#!/usr/bin/env node
// Makes the okb check skill's samples in this folder: a two-page PDF, a picture, a recording and a video. The
// other two samples, check.html, a made-up state machine page, and check.progress.json, a plan's progress, are
// kept as they are; the okb plugin's tests check that their own copies match. Run on macOS, which has `say`, with
// ImageMagick, FFmpeg and Poppler:
//   node plugins/okb/skills/check/samples/make.mjs
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SPEECH = "This is the check recording.";
const run = (program, args) => {
  const done = spawnSync(program, args, { encoding: "utf8" });
  if (done.status !== 0) throw new Error(`${program} failed: ${done.stderr}`);
};

/** A PDF with one line of text on each page, in a text layer. */
function pdf(lines) {
  const objects = ["<< /Type /Catalog /Pages 2 0 R >>", `<< /Type /Pages /Kids [${lines.map((_, i) => `${4 + i * 2} 0 R`).join(" ")}] /Count ${lines.length} >>`, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"];
  for (const [i, line] of lines.entries()) {
    const stream = `BT /F1 24 Tf 72 700 Td (${line}) Tj ET`;
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>`, `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
  }
  let out = "%PDF-1.4\n";
  const at = objects.map((body, i) => { const here = out.length; out += `${i + 1} 0 obj\n${body}\nendobj\n`; return here; });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${at.map(one => `${String(one).padStart(10, "0")} 00000 n \n`).join("")}`;
  return Buffer.from(`${out}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`, "latin1");
}

/** A one-page PDF holding a JPEG and nothing else, as a scanner makes: no text layer. */
function scannedPdf(jpeg, width, height) {
  let frame = 2;
  while (!(jpeg[frame + 1] >= 0xc0 && jpeg[frame + 1] <= 0xc3)) frame += 2 + jpeg.readUInt16BE(frame + 2);
  const colours = jpeg[frame + 9] === 1 ? "/DeviceGray" : "/DeviceRGB";
  const draw = `q ${width * 0.36} 0 0 ${height * 0.36} 0 0 cm /Im0 Do Q`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width * 0.36} ${height * 0.36}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`,
    [`<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace ${colours} /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`, jpeg, "\nendstream"],
    `<< /Length ${draw.length} >>\nstream\n${draw}\nendstream`,
  ];
  const parts = [Buffer.from("%PDF-1.4\n", "latin1")];
  let length = parts[0].length;
  const at = objects.map((body, i) => {
    const here = length;
    const chunk = Buffer.concat([`${i + 1} 0 obj\n`, ...[body].flat(), "\nendobj\n"].map(one => Buffer.isBuffer(one) ? one : Buffer.from(one, "latin1")));
    parts.push(chunk);
    length += chunk.length;
    return here;
  });
  parts.push(Buffer.from(`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${at.map(one => `${String(one).padStart(10, "0")} 00000 n \n`).join("")}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${length}\n%%EOF\n`, "latin1"));
  return Buffer.concat(parts);
}

const work = mkdtempSync(join(tmpdir(), "check-samples-"));
try {
  writeFileSync(join(work, "text.pdf"), pdf(["OKB check page one, from its text layer"]));
  run("magick", ["-size", "1700x2200", "xc:white", "-pointsize", "72", "-annotate", "+150+300", "Order total 4250 GBP", "-quality", "70", join(work, "scan.jpg")]);
  writeFileSync(join(work, "scan.pdf"), scannedPdf(readFileSync(join(work, "scan.jpg")), 1700, 2200));
  run("pdfunite", [join(work, "text.pdf"), join(work, "scan.pdf"), join(HERE, "check.pdf")]);

  run("magick", ["-size", "3000x2000", "gradient:navy-orange", "-fill", "white", "-pointsize", "180", "-gravity", "center", "-annotate", "+0+0", "OKB check picture", "-quality", "70", join(HERE, "check.jpg")]);

  run("say", ["-o", join(work, "speech.aiff"), SPEECH]);
  run("ffmpeg", ["-v", "error", "-y", "-i", join(work, "speech.aiff"), "-af", "apad=whole_dur=5", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", join(HERE, "check.wav")]);

  run("ffmpeg", ["-v", "error", "-y",
    "-f", "lavfi", "-i", "color=c=navy:s=1280x720:d=3", "-f", "lavfi", "-i", "color=c=orange:s=1280x720:d=3",
    "-i", join(work, "speech.aiff"),
    "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v];[2:a]apad=whole_dur=6[a]",
    "-map", "[v]", "-map", "[a]", "-t", "6", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "35", "-c:a", "aac", "-b:a", "48k",
    join(HERE, "check.mp4")]);
} finally {
  rmSync(work, { recursive: true, force: true });
}
