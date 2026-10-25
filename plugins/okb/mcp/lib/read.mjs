// `read_file`: one file anywhere inside the agent folder, given to the agent in the form it can use,
// or the files and folders in one folder there.
// Text as text, images as images, PDFs, Office files and recordings as their text, and a video as a
// timeline of frames and speech. Each program runs with execFile, never through a shell, on a
// private copy in a scratch folder that is removed after the call.
import { execFile } from "node:child_process";
import { existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, delimiter, dirname, extname, join } from "node:path";
import { folderFile, folderPath } from "./session.mjs";
import { OFFICE, officeText } from "./office.mjs";

const MB = 1024 * 1024;
/** The largest file read_file reads. */
export const READ_LIMIT = 50 * MB;
const IMAGE_LIMIT = 10 * MB;
/** Longest side of an image the agent is given, and the size above which it is recompressed. */
const IMAGE_SIDE = 2000;
const IMAGE_BYTES = 5 * MB;
const TEXT_CHARS = 100_000;
const LINES = 2000;
const PDF_PAGES = 20;
/** A page whose text layer holds fewer characters than this is read by character recognition. */
const PDF_MIN_TEXT = 20;
const VIDEO_SECONDS = 300;
const WHISPER_TIMEOUT = 20 * 60_000;

const TEXT = [".md", ".txt", ".csv", ".tsv", ".json", ".jsonl", ".yaml", ".yml", ".xml", ".html", ".htm"];
const IMAGE_TYPES = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp" };
const OTHER_IMAGE = [".heic", ".heif", ".tif", ".tiff"];
const AUDIO = [".mp3", ".m4a", ".wav", ".aac", ".ogg", ".opus", ".flac"];
const VIDEO = [".mp4", ".mov", ".m4v", ".webm", ".mkv", ".3gp"];
const LEGACY = { ".doc": ".docx", ".xls": ".xlsx", ".ppt": ".pptx" };
const READABLE = [...TEXT, ".ipynb", ...Object.keys(IMAGE_TYPES), ...OTHER_IMAGE, ".pdf", ...OFFICE, ...AUDIO, ...VIDEO];

const SYSTEM = process.platform === "win32" ? "win32" : process.platform === "darwin" ? "darwin" : "linux";

// The apt lines hold for Debian 13 and Ubuntu 24.04, or later.
const OTHER_LINUX = " on Debian 13 or Ubuntu 24.04, or later, or its own package manager on another Linux";

/** Where each system gets each program. */
const INSTALL = {
  poppler: { darwin: "brew install poppler", win32: "winget install oschwartz10612.Poppler", linux: `sudo apt install poppler-utils${OTHER_LINUX}` },
  tesseract: { darwin: "brew install tesseract", win32: "winget install UB-Mannheim.TesseractOCR", linux: `sudo apt install tesseract-ocr${OTHER_LINUX}` },
  ffmpeg: { darwin: "brew install ffmpeg", win32: "winget install Gyan.FFmpeg", linux: `sudo apt install ffmpeg${OTHER_LINUX}` },
  magick: { darwin: "brew install imagemagick", win32: "winget install ImageMagick.ImageMagick", linux: `sudo apt install imagemagick libheif-plugin-libde265${OTHER_LINUX}` },
  whisper: {
    darwin: "Real Agent's install script, install.sh, run again as the install guide gives it, which installs whisper.cpp with Homebrew and downloads its model, ggml-base.bin, to ~/.local/share/okb/whisper",
    win32: "Real Agent's install script, install.ps1, run again as the install guide gives it, which puts whisper.cpp and its model, ggml-base.bin, in %LOCALAPPDATA%\\okb\\whisper",
    linux: "whisper-bin-ubuntu-x64.tar.gz from the newest of whisper.cpp's GitHub releases that lists it, and ggml-base.bin from its Hugging Face models, with their full paths set as whisper_cli and whisper_model in the okb plugin's settings",
  },
};
const PACKAGE = { pdftotext: "poppler", pdftoppm: "poppler", pdfinfo: "poppler", tesseract: "tesseract", ffmpeg: "ffmpeg", ffprobe: "ffmpeg", magick: "magick" };

/** Each system's standard install folders, searched after the command path. */
function standardFolders() {
  if (SYSTEM === "darwin") return ["/opt/homebrew/bin", "/usr/local/bin"];
  if (SYSTEM === "linux") return ["/usr/bin", "/usr/local/bin"];
  const programFiles = process.env.ProgramFiles ?? "C:\\Program Files";
  let magick = [];
  try { magick = readdirSync(programFiles).filter(one => one.startsWith("ImageMagick")).sort().reverse().map(one => join(programFiles, one)); } catch {}
  return [
    join(programFiles, "Tesseract-OCR"),
    ...magick,
    ...(process.env.LOCALAPPDATA ? [join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Links")] : []),
  ];
}

const isFile = path => { try { return statSync(path).isFile(); } catch { return false; } };

/** A folder inside Git for Windows, whose own copies of programs such as pdftotext are older builds. */
const inGitForWindows = folder => /[\\/]Git[\\/](ucrt64|mingw64|mingw32|clang64|usr)[\\/]/i.test(`${folder}\\`);

/**
 * A program's full path, from the command path, then the standard folders, then `extra`. On Windows, a copy inside
 * Git for Windows is taken only when no other is found.
 */
export function findProgram(name, extra = []) {
  const suffixes = SYSTEM === "win32" ? ["", ...(process.env.PATHEXT ?? ".EXE;.CMD;.BAT;.COM").split(";").filter(Boolean)] : [""];
  const all = [...(process.env.PATH ?? "").split(delimiter).filter(Boolean), ...standardFolders(), ...extra];
  const folders = SYSTEM === "win32" ? [...all.filter(f => !inGitForWindows(f)), ...all.filter(inGitForWindows)] : all;
  for (const folder of folders) {
    for (const suffix of suffixes) {
      const path = join(folder, name + suffix);
      if (isFile(path)) return path;
    }
  }
  return null;
}

const missing = (program, why) => ({ ok: false, problem: `${why} needs ${program}, which is not on this computer. It is added with: ${INSTALL[PACKAGE[program] ?? program][SYSTEM]}` });

/** Runs one program, never through a shell: `{ ok, stdout, stderr }`, or `{ ok: false, problem }`. */
function run(program, args, { timeout, why, path, cwd, encoding = "utf8" }) {
  const found = path ?? findProgram(program);
  if (!found) return Promise.resolve(missing(program, why));
  return new Promise(done => {
    execFile(found, args, { timeout, maxBuffer: 64 * MB, windowsHide: true, encoding, cwd }, (err, stdout, stderr) => {
      if (err?.killed) return done({ ok: false, problem: `${program} took longer than ${Math.round(timeout / 1000)} seconds, and was stopped.` });
      if (err) return done({ ok: false, problem: `${program} failed: ${String(stderr || stdout || err.message).trim().split("\n").slice(-3).join(" ")}` });
      done({ ok: true, stdout, stderr: String(stderr) });
    });
  });
}

/** Lines `offset` on, at most `limit` of them, cut at 100,000 characters, with where to go on from. A longer line is given in parts, from its character `from`. */
function page(text, { offset, limit, from, label }) {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/);
  if (lines.at(-1) === "" && lines.length > 1) lines.pop();
  const first = Math.max(1, Math.floor(offset ?? 1));
  if (first > lines.length) return { ok: false, problem: `${label} has ${lines.length} lines, so there is nothing from line ${first}.` };
  const start = Math.max(1, Math.floor(from ?? 1));
  const line = lines[first - 1];
  if (start > 1 || line.length >= TEXT_CHARS) {
    if (start > line.length) return { ok: false, problem: `Line ${first} of ${label} has ${line.length} characters, so there is nothing from character ${start}.` };
    const end = Math.min(line.length, start + TEXT_CHARS - 1);
    let head = `${label}: line ${first}, characters ${start} to ${end} of ${line.length}.`;
    if (end < line.length) head += ` To read on, call read_file again with offset ${first} and from ${end + 1}.`;
    else if (first < lines.length) head += ` To read on, call read_file again with offset ${first + 1}.`;
    return { ok: true, content: [{ type: "text", text: `${head}\n\n${line.slice(start - 1, end)}` }] };
  }
  const most = Math.max(1, Math.floor(limit ?? LINES));
  const kept = [];
  let chars = 0;
  for (const one of lines.slice(first - 1, first - 1 + most)) {
    if (chars + one.length + 1 > TEXT_CHARS) break;
    kept.push(one);
    chars += one.length + 1;
  }
  const last = first + kept.length - 1;
  let head = `${label}: lines ${first} to ${last} of ${lines.length}.`;
  if (last < lines.length) head += ` To read on, call read_file again with offset ${last + 1}.`;
  return { ok: true, content: [{ type: "text", text: `${head}\n\n${kept.join("\n")}` }] };
}

function notebook(body, file) {
  let book;
  try { book = JSON.parse(body.toString("utf8")); } catch (err) { return { ok: false, problem: `${file} is not a notebook: ${err.message}` }; }
  if (!Array.isArray(book?.cells)) return { ok: false, problem: `${file} is not a notebook: it has no cells.` };
  const joined = value => Array.isArray(value) ? value.join("") : String(value ?? "");
  return {
    ok: true,
    text: book.cells.map((cell, i) => {
      const outputs = (cell.outputs ?? []).map(out => {
        if (out.output_type === "stream") return joined(out.text);
        if (out.output_type === "error") return `${out.ename}: ${out.evalue}`;
        return out.data?.["text/plain"] !== undefined ? joined(out.data["text/plain"]) : "";
      }).filter(Boolean);
      return [`cell ${i + 1} (${cell.cell_type})`, joined(cell.source), ...(outputs.length ? ["output:", ...outputs] : [])].join("\n");
    }).join("\n\n"),
  };
}

/**
 * ImageMagick's `identify` or `convert`: `magick`, or version 6's own programs, which Debian and
 * Ubuntu install. Windows has a `convert` of its own, a disk tool, so there only `magick` is used.
 */
function imageMagick(tool) {
  const magick = findProgram("magick");
  if (magick) return { path: magick, first: tool === "identify" ? ["identify"] : [] };
  const six = SYSTEM === "win32" ? null : findProgram(tool);
  return six ? { path: six, first: [] } : null;
}

/** Runs ImageMagick's `identify` or `convert`, or refuses with the line that adds it. */
function runImageMagick(tool, args, why) {
  const found = imageMagick(tool);
  if (!found) return Promise.resolve(missing("magick", why));
  return run("magick", [...found.first, ...args], { timeout: 60_000, why, path: found.path });
}

/** The first frame's width and height, as ImageMagick measures them. */
async function measure(path, why) {
  const out = await runImageMagick("identify", ["-format", "%w,%h\\n", `${path}[0]`], why);
  if (!out.ok) return out;
  const [width, height] = out.stdout.trim().split("\n")[0].split(",").map(Number);
  if (!(width > 0 && height > 0)) return { ok: false, problem: `${why}: ImageMagick could not measure it.` };
  return { ok: true, width, height };
}

/**
 * One image as an MCP image item. An image in a format other than PNG, JPEG, GIF or WebP, with a
 * side over 2,000 pixels, or over 5 MB, is turned upright, cut and converted to JPEG first.
 */
async function imageItem(path, ext, why) {
  const size = await measure(path, why);
  if (!size.ok) return size;
  const longest = Math.max(size.width, size.height);
  const bytes = statSync(path).size;
  if (IMAGE_TYPES[ext] && longest <= IMAGE_SIDE && bytes <= IMAGE_BYTES)
    return { ok: true, item: { type: "image", data: readFileSync(path).toString("base64"), mimeType: IMAGE_TYPES[ext] }, width: size.width, height: size.height, cut: false };
  const out = `${path}.jpg`;
  const made = await runImageMagick("convert", [`${path}[0]`, "-auto-orient", "-resize", `${IMAGE_SIDE}x${IMAGE_SIDE}>`, "-quality", "85", out], why);
  if (!made.ok) return made;
  const scale = Math.min(1, IMAGE_SIDE / longest);
  return { ok: true, item: { type: "image", data: readFileSync(out).toString("base64"), mimeType: "image/jpeg" }, width: Math.round(size.width * scale), height: Math.round(size.height * scale), cut: scale < 1, from: size };
}

async function image(copy, ext, name) {
  const got = await imageItem(copy, ext, `Reading ${name}`);
  if (!got.ok) return got;
  const note = got.cut ? `, cut from ${got.from.width} by ${got.from.height}` : got.item.mimeType === "image/jpeg" && !IMAGE_TYPES[ext] ? ", converted to JPEG" : "";
  return { ok: true, content: [{ type: "text", text: `${name}: an image, ${got.width} by ${got.height} pixels${note}.` }, got.item] };
}

/** `pages` as a list of page numbers: "3", "1-5", or "1-3,7". Every page from 1 to 20 when it is left out. */
function pageList(pages, count) {
  if (pages === undefined || pages === "") return { ok: true, list: Array.from({ length: Math.min(count, PDF_PAGES) }, (_, i) => i + 1) };
  const list = [];
  for (const part of String(pages).split(",")) {
    const m = part.trim().match(/^(\d+)(?:\s*-\s*(\d+))?$/);
    if (!m) return { ok: false, problem: `pages must be a page or a range, such as 3 or 1-5, not ${pages}.` };
    const from = Number(m[1]), to = Number(m[2] ?? m[1]);
    if (from < 1 || to < from) return { ok: false, problem: `pages must be a page or a range, such as 3 or 1-5, not ${pages}.` };
    if (to > count) return { ok: false, problem: `The PDF has ${count} pages, so there is no page ${to}.` };
    for (let n = from; n <= to; n += 1) if (!list.includes(n)) list.push(n);
    if (list.length > PDF_PAGES) return { ok: false, problem: `pages names more than ${PDF_PAGES} pages. Read at most ${PDF_PAGES} pages a call.` };
  }
  return { ok: true, list };
}

async function pdf(copy, name, args) {
  const why = `Reading ${name}`;
  const info = await run("pdfinfo", [copy], { timeout: 60_000, why });
  if (!info.ok) return info;
  const count = Number(info.stdout.match(/^Pages:\s+(\d+)/m)?.[1]);
  if (!(count > 0)) return { ok: false, problem: `${name} has no pages that can be read.` };
  const chosen = pageList(args.pages, count);
  if (!chosen.ok) return chosen;
  const parts = [];
  for (const n of chosen.list) {
    const text = await run("pdftotext", ["-f", String(n), "-l", String(n), "-layout", copy, "-"], { timeout: 60_000, why });
    if (!text.ok) return text;
    if (text.stdout.trim().length >= PDF_MIN_TEXT) { parts.push(`page ${n}\n${text.stdout.replace(/\f/g, "").trimEnd()}`); continue; }
    if (!findProgram("tesseract")) return missing("tesseract", `Page ${n} of ${name} has no text layer. Reading it`);
    const picture = `${copy}-page-${n}`;
    const drawn = await run("pdftoppm", ["-f", String(n), "-l", String(n), "-r", "300", "-png", "-singlefile", copy, picture], { timeout: 60_000, why });
    if (!drawn.ok) return drawn;
    // Named from its own folder: on macOS, Leptonica, which tesseract reads images with, takes a
    // path under /tmp to mean the user's own temporary folder, and finds nothing there.
    const read = await run("tesseract", [`${basename(picture)}.png`, "-"], { timeout: 30_000, why, cwd: dirname(picture) });
    if (!read.ok) return read;
    parts.push(`page ${n} (read by character recognition)\n${read.stdout.replace(/\f/g, "").trimEnd()}`);
  }
  const last = chosen.list.at(-1);
  const rest = args.pages === undefined && count > last ? ` To read on, call read_file again with pages ${last + 1}-${Math.min(count, last + PDF_PAGES)}.` : "";
  const paged = page(parts.join("\n\n"), { offset: args.offset, limit: args.limit, from: args.from, label: `${name}, ${chosen.list.length === 1 ? `page ${last}` : `pages ${chosen.list[0]} to ${last}`} of ${count}` });
  if (paged.ok && rest) paged.content[0].text = paged.content[0].text.replace("\n\n", `${rest}\n\n`);
  return paged;
}

/**
 * Where whisper.cpp's program and model are looked for when the settings name none: the folder Real Agent's install
 * script puts them in, Homebrew's whisper.cpp folders, where a person may have put the model by hand, and a build in
 * /opt. Homebrew's whisper.cpp puts whisper-cli on the command path, and installs no ggml-base.bin.
 */
export function whisperFolders(home = homedir(), localAppData = process.env.LOCALAPPDATA, system = SYSTEM) {
  const own = system === "win32" ? (localAppData ? join(localAppData, "okb", "whisper") : null) : join(home, ".local", "share", "okb", "whisper");
  return {
    cli: [...(own && system === "win32" ? [join(own, "Release")] : []), "/opt/whisper.cpp/build/bin"],
    model: [...(own ? [own] : []), ...["/opt/homebrew", "/usr/local"].flatMap(brew => [join(brew, "share", "whisper-cpp"), join(brew, "share", "whisper.cpp")]), "/opt/whisper.cpp/models"],
  };
}

/** whisper.cpp's program and model: the settings, then the command path and whisperFolders. */
function whisper(settings) {
  const folders = whisperFolders();
  const cli = settings.whisperCli ?? findProgram("whisper-cli", folders.cli);
  const model = settings.whisperModel ?? folders.model.map(one => join(one, "ggml-base.bin")).find(isFile);
  if (!cli || !isFile(cli)) return { ok: false, problem: settings.whisperCli ? `whisper_cli is set to ${settings.whisperCli}, which is not a file.` : null };
  if (!model || !isFile(model)) return { ok: false, problem: settings.whisperModel ? `whisper_model is set to ${settings.whisperModel}, which is not a file.` : null };
  return { ok: true, cli, model };
}

const stamp = seconds => {
  const s = Math.floor(seconds % 60), m = Math.floor((seconds / 60) % 60), h = Math.floor(seconds / 3600);
  const mm = String(m).padStart(2, "0"), ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
};

// whisper.cpp's line, with timestamps left on: `[00:00:00.000 --> 00:00:03.500]   Hello there.`
const SEGMENT = /^\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)$/;
// Its special tokens, such as [_BEG_] and [_TT_50], which never occur in speech.
const SPECIAL = /\[_[A-Z]+(?:_\d+)?_?\]/g;

/** A recording's speech: `{ ok, segments: [{ start, text }], language }`. */
async function transcribe(copy, name, settings) {
  const why = `Transcribing ${name}`;
  const found = whisper(settings);
  if (!found.ok) return { ok: false, problem: found.problem ?? `${why} needs whisper.cpp, which is not on this computer. It is added with: ${INSTALL.whisper[SYSTEM]}` };
  const wav = `${copy}.16k.wav`;
  const converted = await run("ffmpeg", ["-v", "error", "-i", copy, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "-y", wav], { timeout: 60_000, why });
  if (!converted.ok) return converted;
  const heard = await run("whisper-cli", ["-m", found.model, "-f", wav, "-l", "auto"], { timeout: WHISPER_TIMEOUT, why, path: found.cli });
  if (!heard.ok) return heard;
  const segments = [];
  for (const line of heard.stdout.split("\n")) {
    const m = SEGMENT.exec(line.trim());
    if (!m) continue;
    const text = m[9].replace(SPECIAL, "").replace(/[ \t]{2,}/g, " ").trim();
    if (text) segments.push({ start: ((Number(m[1]) * 60 + Number(m[2])) * 60 + Number(m[3])) + Number(m[4]) / 1000, text });
  }
  return { ok: true, segments, language: heard.stderr.match(/auto-detected language:\s*(\w+)/)?.[1] ?? "unknown" };
}

async function audio(copy, name, args, settings) {
  const heard = await transcribe(copy, name, settings);
  if (!heard.ok) return heard;
  if (heard.segments.length === 0) return { ok: true, content: [{ type: "text", text: `${name}: no speech was found in it.` }] };
  return page(heard.segments.map(one => `[${stamp(one.start)}] ${one.text}`).join("\n"), { ...args, label: `${name}, a transcript in language ${heard.language}` });
}

/** The video's length, whether it has sound, and its picture's size, from ffprobe. */
async function probe(copy, why) {
  const out = await run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-show_entries", "stream=codec_type,width,height", "-of", "json", copy], { timeout: 30_000, why });
  if (!out.ok) return out;
  let parsed;
  try { parsed = JSON.parse(out.stdout); } catch { return { ok: false, problem: `${why}: ffprobe gave no answer that could be read.` }; }
  const seconds = Number(parsed.format?.duration);
  const streams = parsed.streams ?? [];
  const picture = streams.find(one => one.codec_type === "video");
  if (!(seconds > 0)) return { ok: false, problem: `${why}: its length could not be found.` };
  return { ok: true, seconds, hasAudio: streams.some(one => one.codec_type === "audio"), picture: picture ? { width: picture.width, height: picture.height } : null };
}

/** Frame times: one every 4 seconds and one at each scene cut, half a second apart, 3 to 24 of them. */
export function frameTimes(seconds, cuts) {
  const round = n => Math.round(n * 1000) / 1000;
  const every = [];
  for (let t = 0; t < seconds; t += 4) every.push(round(t));
  const sorted = [...every, ...cuts.filter(t => t >= 0 && t < seconds)].sort((a, b) => a - b);
  const merged = [];
  for (const t of sorted) if (merged.length === 0 || t - merged.at(-1) >= 0.5) merged.push(round(t));
  if (merged.length < 3) return Array.from({ length: 3 }, (_, i) => round((i * seconds) / 3));
  if (merged.length > 24) return Array.from({ length: 24 }, (_, i) => merged[Math.round((i * (merged.length - 1)) / 23)]);
  return merged;
}

/** A frame's longest side cut to 2,000 pixels, keeping its shape; a smaller frame is left as it is. */
const FRAME_SCALE = `scale=w='min(${IMAGE_SIDE},iw)':h='min(${IMAGE_SIDE},ih)':force_original_aspect_ratio=decrease`;

async function video(copy, name, settings) {
  const why = `Reading ${name}`;
  const probed = await probe(copy, why);
  if (!probed.ok) return probed;
  if (!probed.picture) return audio(copy, name, {}, settings);
  if (probed.seconds > VIDEO_SECONDS) return { ok: false, problem: `${name} is ${stamp(probed.seconds)} long. Videos over ${VIDEO_SECONDS / 60} minutes are not read.` };

  const scenes = await run("ffmpeg", ["-v", "error", "-i", copy, "-vf", "select='gt(scene,0.3)',metadata=print:file=-", "-an", "-f", "null", "-"], { timeout: 120_000, why });
  if (!scenes.ok) return scenes;
  const cuts = [...`${scenes.stdout}\n${scenes.stderr}`.matchAll(/pts_time:([0-9]+(?:\.[0-9]+)?)/g)].map(m => Number(m[1]));
  const frames = [];
  for (const [i, t] of frameTimes(probed.seconds, cuts).entries()) {
    const out = `${copy}-frame-${i + 1}.jpg`;
    // Cut to 2,000 pixels by ffmpeg itself, so a video needs no ImageMagick.
    const taken = await run("ffmpeg", ["-v", "error", "-ss", String(t), "-i", copy, "-frames:v", "1", "-vf", FRAME_SCALE, "-q:v", "4", "-y", out], { timeout: 120_000, why });
    if (!taken.ok) return taken;
    if (!existsSync(out)) continue;
    frames.push({ t, n: frames.length + 1, item: { type: "image", data: readFileSync(out).toString("base64"), mimeType: "image/jpeg" } });
  }
  if (frames.length === 0) return { ok: false, problem: `${why}: no frame could be taken from it.` };

  const heard = probed.hasAudio ? await transcribe(copy, name, settings) : null;
  if (heard && !heard.ok) return heard;
  const speech = heard?.segments ?? [];
  const sound = !probed.hasAudio ? "It has no sound track, so it is frames only." : speech.length === 0 ? "No speech was found in it." : `Its speech is in language ${heard.language}.`;
  const events = [
    ...speech.map(one => ({ t: one.start, rank: 0, line: `[${stamp(one.start)}] "${one.text}"` })),
    ...frames.map(one => ({ t: one.t, rank: 1, line: `[${stamp(one.t)}] frame ${one.n}`, item: one.item })),
  ].sort((a, b) => a.t - b.t || a.rank - b.rank);

  const content = [];
  let lines = [`${name}: a video, ${stamp(probed.seconds)} long, as ${frames.length} frames and the speech at their times. ${sound}`, ""];
  for (const event of events) {
    lines.push(event.line);
    if (!event.item) continue;
    content.push({ type: "text", text: lines.join("\n") }, event.item);
    lines = [];
  }
  if (lines.length) content.push({ type: "text", text: lines.join("\n") });
  return { ok: true, content };
}

/** The most entries a folder's listing gives. */
const ENTRIES = 1000;

/**
 * The files and folders in one folder inside the agent folder, or the agent folder itself: each
 * folder with a trailing slash, each file with its size. Hidden ones and links are left out.
 */
function listing(found, file) {
  let entries;
  try { entries = readdirSync(found.path, { withFileTypes: true }); }
  catch (err) { return { ok: false, problem: `${file} could not be listed: ${err?.message ?? err}` }; }
  const shown = entries
    .filter(entry => !entry.name.startsWith(".") && (entry.isDirectory() || entry.isFile()))
    .sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name));
  const lines = shown.slice(0, ENTRIES).map(entry => {
    if (entry.isDirectory()) return `${entry.name}/`;
    let size = "";
    try { size = ` (${lstatSync(join(found.path, entry.name)).size} bytes)`; } catch {}
    return `${entry.name}${size}`;
  });
  const folders = shown.filter(entry => entry.isDirectory()).length;
  const more = shown.length > ENTRIES ? ` The first ${ENTRIES} are shown.` : "";
  const head = `${file}: a folder, with ${folders} folder${folders === 1 ? "" : "s"} and ${shown.length - folders} file${shown.length - folders === 1 ? "" : "s"}.${more} Call read_file with the full path of one to read it.`;
  return { ok: true, content: [{ type: "text", text: [head, "", ...lines].join("\n") }] };
}

/**
 * Reads one file anywhere inside the agent folder, or lists a folder there: `{ ok: true, content }`,
 * MCP content items, or `{ ok: false, problem }`. Nothing is written in the agent folder.
 */
export async function readAgentFile(folder, args, settings = {}) {
  const file = args.file;
  const found = folderPath(folder, file, { kind: "agent", nested: true });
  if (!found.ok) return found;
  let named;
  try { named = lstatSync(found.path); } catch { return { ok: false, problem: `No such file or folder: ${file}` }; }
  if (named.isDirectory() && !named.isSymbolicLink()) return listing(found, file);
  const source = folderFile(folder, file, { kind: "agent", limit: READ_LIMIT, nested: true });
  if (!source.ok) return source;
  const name = source.name;
  const ext = extname(name).toLowerCase();
  if (LEGACY[ext]) return { ok: false, problem: `${name} is in the older ${ext} format, which is not read. Save it as ${LEGACY[ext]} and read that.` };
  if (!READABLE.includes(ext)) return { ok: false, problem: `${ext ? `${ext} files are` : `${name} has no extension, so it is`} not read. read_file reads ${READABLE.join(" ")}.` };
  if ((IMAGE_TYPES[ext] || OTHER_IMAGE.includes(ext)) && source.body.length > IMAGE_LIMIT) return { ok: false, problem: `${name} is over ${IMAGE_LIMIT / MB} MB, the largest image read_file reads.` };

  if (TEXT.includes(ext)) return page(new TextDecoder("utf-8").decode(source.body), { ...args, label: name });
  if (ext === ".ipynb") { const book = notebook(source.body, name); return book.ok ? page(book.text, { ...args, label: name }) : book; }
  if (OFFICE.includes(ext)) { const office = officeText(ext, source.body, name); return office.ok ? page(office.text, { ...args, label: name }) : office; }

  const scratch = mkdtempSync(join(tmpdir(), "supabase-read-"));
  const copy = join(scratch, `file${ext}`);
  try {
    writeFileSync(copy, source.body, { mode: 0o600 });
    const read = IMAGE_TYPES[ext] || OTHER_IMAGE.includes(ext) ? await image(copy, ext, name)
      : ext === ".pdf" ? await pdf(copy, name, args)
      : AUDIO.includes(ext) ? await audio(copy, name, args, settings)
      : await video(copy, name, settings);
    // A program's message names the private copy; the person knows the file by its own name.
    if (!read.ok) return { ...read, problem: read.problem.replaceAll(copy, file).replaceAll(scratch, basename(scratch)) };
    return read;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
