// The okb plugin's `run_code` tool: Python or JavaScript, run in a new Node.js process under its permission model. A run
// reads the agent folder and each folder added to the session, which the okb plugin's agent-tools hook names, and writes
// only the new files the call names directly inside the agent folder. Python runs as Pyodide, from the runtime that
// Real Agent's scripts/publish-runtime.mjs publishes to the client's Plugins scope, at runtime/<RUNTIME>. The first
// Python run on a computer downloads it into ~/.cache/okb-runtime, signed in as the person, each file checked against
// the runtime's MANIFEST. The MCP server makes the tool with createCodeTool.
//
// Node.js's permission model, as observed on 24 October 2026 with Node.js 26.11.1, refuses lstat and readdir of a folder
// it was given when another path it was given starts with the folder's name, as ~/real-agent-notes starts with ~/real-agent. Pyodide
// then cannot mount the folder. So the runtime is kept in ~/.cache, apart from the agent folder, ~/real-agent by default, and a
// run whose folders name each other so is refused, naming both.
import { execFile } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = fileURLToPath(new URL(".", import.meta.url));
// The okb plugin's own releases code and sign-in, loaded when a Python run first needs the runtime.
const RELEASES = new URL("../../cli/releases.mjs", import.meta.url);
const SESSION = new URL("../../cli/okb-session.mjs", import.meta.url);

// The runtime: its folder in the Plugins scope's bucket, and the files of it Pyodide loads beside the packages in its lock file.
export const RUNTIME = "pyodide-0.28.3";
const RUNTIME_NAME = "Python 3.13 in Pyodide 0.28.3";
export const RUNTIME_ITEM = `runtime/${RUNTIME}`;
export const WHEELS = ["et_xmlfile-2.0.0-py3-none-any.whl", "openpyxl-3.1.5-py2.py3-none-any.whl"];
// Where a computer keeps its copy of the runtime, below the person's home folder.
export const RUNTIME_HOME = join(".cache", "okb-runtime");
// A run's time limit in seconds, which OKB_RUN_SECONDS shortens for the tests, and the most of its printed output given back.
const RUN_SECONDS = 120;
const runSeconds = () => Math.min(RUN_SECONDS, Number(process.env.OKB_RUN_SECONDS) || RUN_SECONDS);
const MAX_PRINTED = 100 * 1024;
const NO_FOLDER = "No agent folder is set for the okb plugin. The person signs in with okb sign-in --folder, which makes the folder the agent folder, or sets agent_folder in the okb plugin's settings.";

export const TOOL = {
  name: "run_code",
  description: `Run Python or JavaScript, as the code skill describes, for analysis, a model worked out from data, a cleaned or joined data set, or a chart from data. The code reads the agent folder and each folder added to the session when it started. It writes only the new files named in new_files, and changes no file already there. It reaches nothing else on the computer, starts no program, sends no signal and has no network. Python is ${RUNTIME_NAME}: it sees the agent folder as /work, its working folder, and each added folder as /added/<folder name>, and imports numpy, pandas, scipy, matplotlib, openpyxl and the standard library. The first Python run on a computer downloads the runtime from the firm's Plugins scope in OKB, signed in as the person. JavaScript is an ES module on Node.js, with the agent folder's full path in process.env.AGENT_FOLDER, its working folder, and each added folder's in process.env.ADDED_FOLDERS, as a JSON list. A run stops after ${RUN_SECONDS} seconds, and its printed output is cut at 100 KB. A result goes into OKB only with upload_file, after the person's yes. Returns ok, what the code printed as stdout and stderr, made: each of new_files the run wrote, and not_made: each it did not.`,
  inputSchema: {
    type: "object",
    properties: {
      language: { type: "string", enum: ["python", "javascript"] },
      code: { type: "string", description: "The code. It writes each file it makes into the agent folder, and prints what the person needs to see." },
      new_files: { type: "array", items: { type: "string" }, description: "Each file the code writes, as a full path directly inside the agent folder, a new name and not a hidden one. The code may write these alone. Leave it out for code that only prints." },
    },
    required: ["language", "code"],
    additionalProperties: false,
  },
};

const asContent = payload => ({ content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] });
// Windows paths ignore letter case, so there a folder typed in any case is the same folder.
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;

/** The first link under folder, links to folders and Windows junctions among them, or null. Node.js's permission model
 * follows a link inside a folder it may read to the file it points to, anywhere. */
export function firstLink(folder) {
  const folders = [folder];
  while (folders.length) {
    let entries;
    try { entries = readdirSync(folders.pop(), { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      const path = join(entry.parentPath, entry.name);
      if (entry.isSymbolicLink()) return path;
      if (entry.isDirectory()) folders.push(path);
    }
  }
  return null;
}

/** The first two paths of which one starts with the other's name but is not inside it, as ~/real-agent-notes and ~/real-agent, or null. */
export function clashing(paths) {
  for (const one of paths) for (const other of paths)
    if (one !== other && other.startsWith(one) && other[one.length] !== sep) return [one, other];
  return null;
}

// The files and folders below the person's home that hold their keys, sign-ins and settings: SSH and GnuPG keys, cloud,
// container and package tool settings, Git's saved passwords, Claude Code's own, macOS's Library, and the okb plugin's
// saved sign-ins in ~/.config/supabase-auth. A run never reads a folder that is one, is inside one or holds one.
export const PRIVATE = [".ssh", ".config", join(".config", "supabase-auth"), ".claude", ".aws", ".gnupg", "Library", ".kube", ".docker",
  ".netrc", ".npmrc", ".pypirc", ".git-credentials"];

/** A folder path with one separator at its end, so "/" stays "/". */
const withSep = path => path.endsWith(sep) ? path : path + sep;
/** Whether path is root or inside it. */
export const within = (path, root) => path === root || path.startsWith(withSep(root));
const realOr = path => { try { return realpathSync.native(path); } catch { return resolve(path); } };

/** Why a run may not read folder, a real path, or null: it is the filesystem's root, the home folder or a folder holding
 * it, or it is, is inside or holds one of the person's private files and folders. */
export function refusedFolder(folder, home = homedir()) {
  const own = realOr(home);
  if (within(own, folder)) return `${folder} is ${folder === own ? "the home folder" : "a folder that holds the home folder"}, and a run never reads it.`;
  for (const name of PRIVATE) {
    const root = realOr(join(home, name));
    if (within(folder, root) || within(root, folder))
      return `${folder} is or holds ${root}, which keeps the person's keys, sign-ins or settings, and a run never reads it.`;
  }
  return null;
}

// The folders added to a session when it started, as the agent-tools hook reads them from the session's transcript before
// each run_code call, kept for the session's folder in a folder of the person's own, ~/.cache/okb/run-folders. run_code
// reads them, never a call's own list. The folder and the file are refused unless each is the person's own, holds no link
// and lets no one else read or write it: then a run reads no added folder. A list older than FOLDERS_FRESH_MS is no
// session's current one, and gives none. On Windows, which keeps no such owner and mode, only the link check applies.
const FOLDERS_FRESH_MS = 120_000;
export const RUN_FOLDERS = join(".cache", "okb", "run-folders");
const POSIX = typeof process.getuid === "function";

/** The person's run-folders folder, as a real path, made with mode 700 where it is missing, or null where it is not safe. */
function runFoldersDir(home, make) {
  let root;
  try { root = realpathSync.native(home); } catch { return null; }
  const dir = join(root, RUN_FOLDERS);
  if (make) { try { mkdirSync(dir, { recursive: true, mode: 0o700 }); } catch { return null; } }
  return ownedPrivately(dir, "dir") && realOr(dir) === dir ? dir : null;
}

/** Whether path is a file or folder of the person's own, not a link, that no one else may read or write. */
function ownedPrivately(path, kind) {
  let st;
  try { st = lstatSync(path); } catch { return false; }
  if (st.isSymbolicLink() || (kind === "dir" ? !st.isDirectory() : !st.isFile())) return false;
  return !POSIX || (st.uid === process.getuid() && (st.mode & 0o077) === 0);
}

const foldersFile = (dir, sessionFolder) => join(dir, `${createHash("sha256").update(realOr(String(sessionFolder))).digest("hex").slice(0, 32)}.json`);

/** Saves the session's added folders for its folder, for run_code to read: a new file, mode 600, renamed into place. */
export function saveSessionFolders(sessionFolder, folders, home = homedir()) {
  const dir = runFoldersDir(home, true);
  if (!dir) return false;
  const file = foldersFile(dir, sessionFolder), part = `${file}.${process.pid}.${randomBytes(6).toString("hex")}`;
  try {
    writeFileSync(part, JSON.stringify({ at: Date.now(), folders }), { flag: "wx", mode: 0o600 });
    renameSync(part, file);
    return true;
  } catch { rmSync(part, { force: true }); return false; }
}

/** The session's added folders, as the hook saved them for the session's folder just now, or none. */
export function sessionFolders(sessionFolder, home = homedir(), now = Date.now()) {
  if (!sessionFolder) return [];
  const dir = runFoldersDir(home, false);
  if (!dir) return [];
  const file = foldersFile(dir, sessionFolder);
  if (!ownedPrivately(file, "file")) return [];
  try {
    const { at, folders } = JSON.parse(readFileSync(file, "utf8"));
    return now - at <= FOLDERS_FRESH_MS && Array.isArray(folders) ? folders.filter(f => typeof f === "string" && isAbsolute(f)) : [];
  } catch { return []; }
}

/** Text cut to MAX_PRINTED bytes, with a line saying so. */
const cut = text => Buffer.byteLength(text) <= MAX_PRINTED ? text : `${Buffer.from(text).subarray(0, MAX_PRINTED).toString("utf8")}\n[cut at 100 KB]`;

/**
 * The run_code tool for one person: `ref` and `email` name their sign-in, which the runtime's download uses, and
 * `agentFolder` is the one folder a run writes in. `home` is where ~/okb-runtime is. Returns `{ TOOLS, callTool }`.
 */
export function createCodeTool({ ref = null, email = null, agentFolder = null, sessionFolder = null, home = homedir() }) {
  /** A full path naming a new file directly inside the agent folder, not a hidden one, and not already there. */
  function freeInside(file) {
    if (!isAbsolute(String(file ?? ""))) return { ok: false, problem: `The file must be given as a full path inside ${agentFolder}.` };
    let root;
    try { root = realpathSync.native(agentFolder); } catch { return { ok: false, problem: `The agent folder ${agentFolder} does not exist.` }; }
    const name = basename(file), parent = resolve(dirname(file));
    if (!samePath(parent, resolve(agentFolder)) && !samePath(parent, root) || name === "" || name === "." || name === ".." || name.startsWith("."))
      return { ok: false, problem: `${file} is not a file name directly inside the agent folder, ${agentFolder}.` };
    const path = join(root, name);
    try { lstatSync(path); return { ok: false, problem: `${file} already exists. Name a new file; nothing is replaced.` }; }
    catch (err) { if (err?.code !== "ENOENT") return { ok: false, problem: `${file} could not be checked: ${err?.message ?? err}` }; }
    return { ok: true, path, shown: join(parent, name) };
  }

  /**
   * The runtime in ~/okb-runtime: the copy there once its MANIFEST and every file it lists are there, or else a new
   * download of it from the Plugins scope, signed in as the person, each file checked against the MANIFEST. A download
   * goes into a folder of its own, renamed into place once it matches.
   */
  async function runtime() {
    const store = join(home, RUNTIME_HOME), folder = join(store, RUNTIME);
    const { downloadFile, manifestEntries, sha256, RELEASES_BUCKET } = await import(RELEASES.href);
    try {
      const listed = manifestEntries(readFileSync(join(folder, "MANIFEST"), "utf8"));
      // The permission model compares real paths, so a home reached through a link, as /var is /private/var on macOS, is given as its real path.
      if (listed.every(({ path }) => existsSync(join(folder, ...path.split("/"))))) return { ok: true, folder: realpathSync.native(folder), downloaded: false };
    } catch { /* no copy yet */ }
    if (!ref || !email) return { ok: false, problem: "The Python runtime could not be downloaded: no one is signed in for this folder. The person signs in with okb sign-in --folder, as the actor skill describes, then asks again." };
    const { openAccess } = await import(SESSION.href);
    const session = await openAccess({ project: ref, email, home });
    if (!session.ok) return { ok: false, problem: `The Python runtime could not be downloaded: ${session.problem}` };
    const got = await downloadFile(session.access, RELEASES_BUCKET, `${RUNTIME_ITEM}/MANIFEST`);
    if (!got.ok) return { ok: false, problem: `The Python runtime in the Plugins scope, ${RUNTIME_ITEM}, could not be downloaded: ${got.missing ? "it is not there. Real Agent publishes it with scripts/publish-runtime.mjs" : got.problem}.` };
    let entries;
    try { entries = manifestEntries(got.body.toString("utf8")); } catch (err) { return { ok: false, problem: `The Python runtime's MANIFEST is unreadable: ${err.message}` }; }
    mkdirSync(store, { recursive: true });
    const staging = mkdtempSync(join(store, `.${RUNTIME}-`));
    try {
      const problems = [];
      for (const { path, hash } of entries) {
        const file = await downloadFile(session.access, RELEASES_BUCKET, `${RUNTIME_ITEM}/${path}`);
        if (!file.ok) { problems.push(`./${path} ${file.missing ? "missing" : `could not be downloaded: ${file.problem}`}`); continue; }
        if (sha256(file.body) !== hash) { problems.push(`./${path} changed`); continue; }
        const at = join(staging, ...path.split("/"));
        mkdirSync(dirname(at), { recursive: true });
        writeFileSync(at, file.body);
      }
      if (problems.length) return { ok: false, problem: `The Python runtime in the Plugins scope, ${RUNTIME_ITEM}, could not be downloaded: ${problems.slice(0, 3).join("; ")}.` };
      writeFileSync(join(staging, "MANIFEST"), got.body);
      rmSync(folder, { recursive: true, force: true });
      renameSync(staging, folder);
      return { ok: true, folder: realpathSync.native(folder), downloaded: true };
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }

  /**
   * Runs code in a new Node.js process with the permission model, started through execFile, never a shell, in a new
   * folder holding the code and its runner. It reads that folder, the runtime for Python, the agent folder and each added
   * folder: no network, child process, worker, addon or WASI. It writes only the new files the call names, each directly
   * inside the agent folder and not hidden, so a run changes no file there, such as the session's .claude settings or its
   * actor file.
   */
  async function runCode({ language, code, new_files: files = [] }) {
    // The folders the session was started with, never any the call names.
    const given = sessionFolders(sessionFolder, home);
    if (!agentFolder) return { ok: false, problem: NO_FOLDER };
    // Node.js's permission model refuses the network from version 25; on an older one the code could reach it.
    if (Number(process.versions.node.split(".")[0]) < 25) return { ok: false, problem: `run_code needs Node.js 25 or later, and this is Node.js ${process.versions.node}. Update Node.js, then start a new session.` };
    if (language !== "python" && language !== "javascript") return { ok: false, problem: "language must be python or javascript." };
    if (typeof code !== "string" || !code.trim()) return { ok: false, problem: "Give the code to run." };
    if (!Array.isArray(files)) return { ok: false, problem: "new_files must be a list of full paths directly inside the agent folder." };
    const writes = [];
    for (const file of files.map(String)) {
      // Node.js reads * in a permission path as any name.
      if (basename(file).includes("*")) return { ok: false, problem: `${file} holds a *. Name each new file without one.` };
      const free = freeInside(file);
      if (!free.ok) return free;
      if (!writes.some(w => samePath(w.path, free.path))) writes.push(free);
    }
    let work;
    try { work = realpathSync.native(agentFolder); } catch { return { ok: false, problem: `The agent folder ${agentFolder} does not exist.` }; }
    const added = [];
    for (const folder of Array.isArray(given) ? given : []) {
      let path;
      try { path = realpathSync.native(String(folder)); } catch { continue; }
      if (!isAbsolute(String(folder)) || !statSync(path).isDirectory()) continue;
      let name = basename(path) || "folder";
      for (let n = 2; added.some(a => a.name === name); n++) name = `${basename(path)}-${n}`;
      added.push({ name, path });
    }
    for (const folder of [work, ...added.map(a => a.path)]) {
      const refused = refusedFolder(folder, home);
      if (refused) return { ok: false, problem: `${refused} Run the code on a folder that holds none of the person's keys, sign-ins or settings.` };
    }
    for (const folder of [work, ...added.map(a => a.path)]) {
      const link = firstLink(folder);
      if (link) return { ok: false, problem: `${link} is a link, and a run would read what it points to. Move it out of ${folder}, or replace it with the file itself, then run the code again.` };
    }
    const python = language === "python";
    const found = python ? await runtime() : null;
    if (found && !found.ok) return found;
    const scratch = realpathSync.native(mkdtempSync(join(tmpdir(), "okb-run-")));
    try {
      let entry;
      const runner = readFileSync(join(HERE, "run-python.mjs"), "utf8");
      if (python) {
        writeFileSync(join(scratch, "code.py"), code, { mode: 0o600 });
        writeFileSync(join(scratch, "run.json"), JSON.stringify({ runtime: found.folder, work, added, wheels: WHEELS }), { mode: 0o600 });
        writeFileSync(join(scratch, "run-python.mjs"), runner, { mode: 0o600 });
        entry = join(scratch, "run-python.mjs");
      } else {
        // JavaScript gets the runner's refusal of signals alone, before its code loads.
        writeFileSync(join(scratch, "code.mjs"), code, { mode: 0o600 });
        writeFileSync(join(scratch, "run.mjs"), `${runner.match(/^const refuse = [^\n]*\nfor \(const name of [^\n]*\n/m)[0]}process.chdir(process.env.AGENT_FOLDER);\nawait import("./code.mjs");\n`, { mode: 0o600 });
        entry = join(scratch, "run.mjs");
      }
      const reads = [scratch, ...(python ? [found.folder] : []), work, ...added.map(a => a.path)];
      const clash = clashing(reads);
      if (clash) return { ok: false, problem: `${clash[0]} and ${clash[1]} start with the same name, and Node.js then refuses the run ${clash[0]} itself. Rename one of the two folders, or start a new session without the folder added, then run the code again.` };
      const args = ["--permission", ...reads.map(path => `--allow-fs-read=${path}`), ...writes.map(w => `--allow-fs-write=${w.path}`), entry];
      const env = { AGENT_FOLDER: work, ADDED_FOLDERS: JSON.stringify(added.map(a => a.path)), ...(process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}) };
      const ran = await new Promise(done => execFile(process.execPath, args, { cwd: scratch, env, timeout: runSeconds() * 1000, killSignal: "SIGKILL", maxBuffer: 16 * 1024 * 1024, windowsHide: true },
        (err, stdout, stderr) => done({ err, stdout: String(stdout).replaceAll("\r\n", "\n"), stderr: String(stderr).replaceAll("\r\n", "\n") })));
      const isFile = path => { try { return lstatSync(path).isFile(); } catch { return false; } };
      const made = writes.filter(w => isFile(w.path)).map(w => w.shown), notMade = writes.filter(w => !isFile(w.path)).map(w => w.shown);
      // Write access to a path reaches below it too, so a folder the code made at a named path goes, with all it holds.
      const folders = writes.filter(w => { try { return !lstatSync(w.path).isFile(); } catch { return false; } }).map(w => w.shown);
      for (const w of writes) if (folders.includes(w.shown)) rmSync(w.path, { recursive: true, force: true });
      const stopped = ran.err?.killed && ran.err?.signal === "SIGKILL";
      const result = { ok: !ran.err, language, stdout: cut(ran.stdout), stderr: cut(ran.stderr), made, not_made: notMade, agentFolder, agentFolderPath: work,
        ...(python ? { work: "/work", added: added.map(a => ({ folder: a.path, as: `/added/${a.name}` })), runtimeDownloaded: found.downloaded } : { added: added.map(a => a.path) }) };
      if (folders.length) return { ...result, ok: false, problem: `The code made a folder in place of ${folders.join(", ")}. It was deleted, with what it held. Write each named file as a file.` };
      if (stopped) return { ...result, ok: false, problem: `The run stopped after ${runSeconds()} seconds.` };
      if (ran.err?.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER") return { ...result, ok: false, problem: "The run stopped: it printed over 16 MB." };
      return ran.err ? { ...result, problem: `The code stopped with exit code ${ran.err.code}. stderr says why.` } : result;
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }

  async function callTool(name, args = {}) {
    try {
      if (name === "run_code") return asContent(await runCode(args ?? {}));
      return asContent({ ok: false, problem: `No such tool: ${name}` });
    } catch (err) {
      return asContent({ ok: false, problem: `${name} failed: ${err instanceof Error ? err.message : String(err)}` });
    }
  }

  return { TOOLS: [TOOL], callTool };
}

