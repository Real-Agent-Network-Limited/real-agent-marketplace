// The text of Word, spreadsheet and slide deck files, read from their XML parts. Layouts, formulas,
// images and notes are not read.
import { unzip } from "./unzip.mjs";

/** An Office file holds a few hundred parts; far more, or far larger, is not one to unpack. */
const LIMITS = { entries: 5000, bytes: 500 * 1024 * 1024 };

/** The five predefined XML entities and numeric references. `&amp;` last, so nothing decodes twice. */
const unescapeXml = s => s
  .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
  .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)))
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
  .replace(/&amp;/g, "&");

const attribute = (tag, name) => tag.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1];

/** A part's path, from a relationship's target, relative to the folder of the part that names it. */
function partPath(base, target) {
  if (target.startsWith("/")) return target.slice(1);
  const parts = base.split("/").slice(0, -1);
  for (const one of target.split("/")) {
    if (one === "..") parts.pop();
    else if (one !== ".") parts.push(one);
  }
  return parts.join("/");
}

/** The parts a main part lists, in its own order: `[{ name, path }]`, found through its relationships. */
function listed(files, main, element, nameOf) {
  const xml = files.get(main)?.toString("utf8");
  const rels = files.get(main.replace(/([^/]+)$/, "_rels/$1.rels"))?.toString("utf8");
  if (!xml || !rels) return null;
  const targets = new Map([...rels.matchAll(/<Relationship\b[^>]*>/g)].map(([tag]) => [attribute(tag, "Id"), attribute(tag, "Target")]));
  const out = [];
  for (const [tag] of xml.matchAll(new RegExp(`<${element}\\b[^>]*>`, "g"))) {
    const target = targets.get(attribute(tag, "r:id"));
    if (target) out.push({ name: nameOf(tag, out.length), path: partPath(main, target) });
  }
  return out;
}

/** Parts named `<prefix>N.xml`, in the order of N, when the main part cannot be read. */
function numbered(files, prefix) {
  const pattern = new RegExp(`^${prefix}(\\d+)\\.xml$`);
  return [...files.keys()].filter(one => pattern.test(one)).sort((a, b) => Number(a.match(pattern)[1]) - Number(b.match(pattern)[1]));
}

function docx(files) {
  const xml = files.get("word/document.xml")?.toString("utf8");
  if (xml === undefined) return null;
  const paragraphs = [];
  for (const p of xml.split("</w:p>")) {
    const withBreaks = p.replace(/<w:tab\b[^>]*\/?>/g, "<w:t>\t</w:t>").replace(/<w:br\b[^>]*\/?>/g, "<w:t>\n</w:t>");
    let line = "";
    for (const m of withBreaks.matchAll(/<w:t\b[^>]*>([\s\S]*?)<\/w:t>/g)) line += unescapeXml(m[1]);
    if (line.length > 0) paragraphs.push(line);
  }
  return paragraphs.join("\n");
}

/** OpenDocument text: paragraphs and headings end a line; every other tag is dropped. */
function odText(xml) {
  const withBreaks = xml
    .replace(/<text:line-break\b[^>]*\/?>/g, "\n")
    .replace(/<text:tab\b[^>]*\/?>/g, "\t")
    .replace(/<text:s\b[^>]*\/?>/g, " ")
    .replace(/<\/text:(?:p|h)>/g, "\n");
  return unescapeXml(withBreaks.replace(/<[^>]+>/g, "")).replace(/\n{3,}/g, "\n\n").trim();
}

function odt(files) {
  const xml = files.get("content.xml")?.toString("utf8");
  if (xml === undefined) return null;
  return odText(xml.replace(/^[\s\S]*?<office:text\b[^>]*>/, "").replace(/<\/office:text>[\s\S]*$/, ""));
}

/** Tab-joined cells and newline-joined rows, without trailing empty cells or empty rows. */
const grid = rows => rows.map(cells => { while (cells.length && cells.at(-1) === "") cells.pop(); return cells.join("\t"); }).filter(Boolean).join("\n");

// Excel's built-in number formats that show a date, a time, or both. Every other built-in is a number.
const BUILT_IN = new Map([
  ...[14, 15, 16, 17, 27, 28, 29, 30, 31, 34, 35, 36, 50, 51, 52, 53, 54, 57, 58].map(id => [id, "date"]),
  ...[18, 19, 20, 21, 32, 33, 45, 47, 55, 56].map(id => [id, "time"]),
  [46, "elapsed h s"],
  [22, "datetime"],
]);

/**
 * For each cell style, by its index, whether its number format shows a date, a time, both, a
 * duration, or none of these. Excel keeps a date as a count of days, and only the style says so. A
 * custom format is read once its quoted text, escaped characters and colours are dropped. A unit in
 * brackets, such as [h] or [mm], makes it a duration, counted in that unit. Otherwise d or y is a
 * date, h or s a time, and m a month unless the format has a time.
 */
function dateStyles(files) {
  const xml = files.get("xl/styles.xml")?.toString("utf8") ?? "";
  const custom = new Map([...xml.matchAll(/<numFmt\b[^>]*>/g)].map(([tag]) => [Number(attribute(tag, "numFmtId")), unescapeXml(attribute(tag, "formatCode") ?? "")]));
  const kind = id => {
    if (BUILT_IN.has(id)) return BUILT_IN.get(id);
    const code = custom.get(id);
    if (code === undefined) return null;
    const section = code.replace(/"[^"]*"/g, "").replace(/\\./g, "").split(";")[0];
    const elapsed = section.match(/\[(h+|m+|s+)\]/i);
    const bare = section.replace(/\[[^\]]*\]/g, "");
    if (elapsed) return `elapsed ${elapsed[1][0].toLowerCase()}${/s/i.test(bare) ? " s" : ""}`;
    const time = /[hs]/i.test(bare);
    const date = /[dy]/i.test(bare) || (!time && /m/i.test(bare));
    return date && time ? "datetime" : date ? "date" : time ? "time" : null;
  };
  const cellXfs = xml.match(/<cellXfs\b[\s\S]*?<\/cellXfs>/)?.[0] ?? "";
  return [...cellXfs.matchAll(/<xf\b[^>]*>/g)].map(([tag]) => kind(Number(attribute(tag, "numFmtId") ?? 0)));
}

/**
 * A duration in days as a running total in its format's largest unit: 36 hours as 36:00, or with
 * seconds 36:00:00; 90 minutes under [mm]:ss as 90:00; and seconds alone as a count.
 */
function elapsedTime(value, kind) {
  const [, unit, seconds] = kind.split(" ");
  const total = Math.round(Math.abs(value) * 86400);
  const two = n => String(n).padStart(2, "0");
  const sign = value < 0 ? "-" : "";
  if (unit === "s") return `${sign}${total}`;
  if (unit === "m") return `${sign}${Math.floor(total / 60)}:${two(total % 60)}`;
  return `${sign}${Math.floor(total / 3600)}:${two(Math.floor(total / 60) % 60)}${seconds ? `:${two(total % 60)}` : ""}`;
}

/**
 * A day count as ISO text, showing what its format shows: the date, the time of day, or both. A
 * duration is a running total. A negative date or time, which Excel cannot show, stays a number.
 */
function serialDate(value, kind, date1904) {
  if (kind.startsWith("elapsed")) return elapsedTime(value, kind);
  if (value < 0) return String(value);
  const seconds = Math.round(value * 86400);
  const at = new Date(Date.UTC(date1904 ? 1904 : 1899, date1904 ? 0 : 11, date1904 ? 1 : 30) + seconds * 1000).toISOString();
  const day = at.slice(0, 10);
  const time = at.slice(11, seconds % 60 === 0 ? 16 : 19);
  return kind === "date" ? day : kind === "time" ? time : `${day} ${time}`;
}

function xlsx(files) {
  const styles = dateStyles(files);
  const date1904 = /<workbookPr\b[^>]*\bdate1904="(?:1|true)"/.test(files.get("xl/workbook.xml")?.toString("utf8") ?? "");
  const shared = [];
  const strings = files.get("xl/sharedStrings.xml")?.toString("utf8");
  if (strings) {
    for (const si of strings.split("</si>")) {
      if (!si.includes("<si")) continue;
      // Phonetic guides, furigana on CJK workbooks, would be appended to their base word.
      const base = si.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "");
      let s = "";
      for (const m of base.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) s += m[1];
      shared.push(unescapeXml(s));
    }
  }
  const sheets = listed(files, "xl/workbook.xml", "sheet", tag => unescapeXml(attribute(tag, "name") ?? ""))
    ?? numbered(files, "xl/worksheets/sheet").map((path, i) => ({ name: String(i + 1), path }));
  if (sheets.length === 0) return null;
  const out = [];
  for (const sheet of sheets) {
    const xml = files.get(sheet.path)?.toString("utf8") ?? "";
    const rows = [];
    for (const rowXml of xml.split("</row>")) {
      if (!rowXml.includes("<row")) continue;
      const cells = [];
      for (const c of rowXml.matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const [, attrs, body = ""] = c;
        if (/\bt="inlineStr"/.test(attrs)) {
          let s = "";
          for (const m of body.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) s += m[1];
          cells.push(unescapeXml(s));
          continue;
        }
        const v = body.match(/<v\b[^>]*>([\s\S]*?)<\/v>/);
        if (!v) { cells.push(""); continue; }
        if (/\bt="s"/.test(attrs)) cells.push(shared[Number(v[1])] ?? "");
        else if (!/\bt="(?:str|e|b)"/.test(attrs) && styles[Number(attribute(attrs, "s") ?? 0)] && Number.isFinite(Number(v[1]))) cells.push(serialDate(Number(v[1]), styles[Number(attribute(attrs, "s") ?? 0)], date1904));
        else cells.push(unescapeXml(v[1]));
      }
      rows.push(cells);
    }
    out.push(`sheet ${sheet.name}\n${grid(rows)}`);
  }
  return out.join("\n\n");
}

/**
 * An OpenDocument date or time cell's stored value as ISO text, such as `2026-10-06` or `09:30`. A
 * date's time is given only when the cell shows one, as its display text then holds a colon.
 */
function odsDate(type, tag, shown) {
  if (type === "date") {
    const m = attribute(tag, "office:date-value")?.match(/^(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2})(:\d{2})?)?/);
    if (!m) return null;
    if (!m[2] || !shown.includes(":")) return m[1];
    return `${m[1]} ${m[2]}${m[3] && m[3] !== ":00" ? m[3] : ""}`;
  }
  if (type === "time") {
    const m = attribute(tag, "office:time-value")?.match(/^PT(\d+)H(\d+)M(\d+)(?:\.\d+)?S$/);
    if (!m) return null;
    const [h, min, sec] = m.slice(1).map(Number);
    return `${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}${sec ? `:${String(sec).padStart(2, "0")}` : ""}`;
  }
  return null;
}

function ods(files) {
  const xml = files.get("content.xml")?.toString("utf8");
  if (xml === undefined) return null;
  const out = [];
  // The lookahead keeps `<table:table-row>` and `<table:table-cell>` from starting a new table.
  for (const tableXml of xml.split(/(?=<table:table[\s>])/).slice(1)) {
    const name = unescapeXml(attribute(tableXml.slice(0, tableXml.indexOf(">")), "table:name") ?? String(out.length + 1));
    const rows = [];
    for (const rowXml of tableXml.split(/<table:table-row\b/).slice(1)) {
      rows.push(rowXml.split(/<table:(?:covered-)?table-cell\b/).slice(1).map(cell => {
        // A date or time cell's stored value, not its display text, which may be in any locale's order.
        const tag = cell.slice(0, cell.indexOf(">"));
        const stored = odsDate(attribute(tag, "office:value-type"), tag, cell.slice(cell.indexOf(">")).match(/<text:p\b[^>]*>([\s\S]*?)<\/text:p>/)?.[1] ?? "");
        if (stored) return stored;
        let s = "";
        for (const m of cell.matchAll(/<text:p\b[^>]*>([\s\S]*?)<\/text:p>/g)) s += (s ? "\n" : "") + odText(m[1]);
        return s;
      }));
    }
    out.push(`sheet ${name}\n${grid(rows)}`);
  }
  return out.length ? out.join("\n\n") : null;
}

/** A slide with no text may be a picture, which is not read. */
const NO_TEXT = "(no text; any pictures on it are not read)";

function pptx(files) {
  const slides = listed(files, "ppt/presentation.xml", "p:sldId", (_, i) => i + 1)
    ?? numbered(files, "ppt/slides/slide").map((path, i) => ({ name: i + 1, path }));
  if (slides.length === 0) return null;
  return slides.map(slide => {
    const xml = files.get(slide.path)?.toString("utf8") ?? "";
    const lines = [];
    for (const p of xml.split("</a:p>")) {
      let line = "";
      for (const m of p.replace(/<a:br\b[^>]*\/?>/g, "<a:t>\n</a:t>").matchAll(/<a:t\b[^>]*>([\s\S]*?)<\/a:t>/g)) line += unescapeXml(m[1]);
      if (line.trim()) lines.push(line);
    }
    return `slide ${slide.name}\n${lines.length ? lines.join("\n") : NO_TEXT}`;
  }).join("\n\n");
}

function odp(files) {
  const xml = files.get("content.xml")?.toString("utf8");
  if (xml === undefined) return null;
  const pages = xml.split(/<draw:page\b/).slice(1).map(one => one.slice(one.indexOf(">") + 1).split("</draw:page>")[0]);
  if (pages.length === 0) return null;
  return pages.map((page, i) => `slide ${i + 1}\n${odText(page) || NO_TEXT}`).join("\n\n");
}

// An RTF group whose whole span is dropped: ignorable `{\*…}`, the font, colour, style and list
// tables, the document's details, and picture data. None carries body text. Headers, footers and
// footnotes do, and are kept.
const RTF_DROP = /^\\(?:\*|fonttbl|colortbl|stylesheet|listtable|info|pict)\b/;

/** Every non-content group and everything nested in it, dropped by a brace-balanced scan. */
function stripRtfGroups(s) {
  let out = "";
  for (let i = 0; i < s.length; i += 1) {
    const ch = s[i];
    if (ch === "\\" && i + 1 < s.length) { out += ch + s[i + 1]; i += 1; continue; }
    if (ch === "{" && RTF_DROP.test(s.slice(i + 1, i + 40))) {
      let depth = 1, j = i + 1;
      for (; j < s.length && depth > 0; j += 1) {
        if (s[j] === "\\") { j += 1; continue; }
        if (s[j] === "{") depth += 1;
        else if (s[j] === "}") depth -= 1;
      }
      i = j - 1;
      continue;
    }
    out += ch;
  }
  return out;
}

function rtf(bytes) {
  let s = stripRtfGroups(bytes.toString("latin1"));
  // A control word's one trailing space ends it, and is not text.
  s = s.replace(/\\par[d]?\b ?/g, "\n").replace(/\\line\b ?/g, "\n").replace(/\\tab\b ?/g, "\t");
  s = s.replace(/\\'([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
  s = s.replace(/\\u(-?\d+)\??/g, (_, n) => String.fromCharCode((Number(n) + 65536) % 65536));
  s = s.replace(/\\[a-zA-Z]+-?\d* ?/g, "");
  s = s.replace(/\\([{}\\])/g, "$1").replace(/[{}]/g, "");
  return s.replace(/[ \t]{2,}/g, " ").replace(/\n{3,}/g, "\n\n").trim();
}

const ZIPPED = { ".docx": docx, ".odt": odt, ".xlsx": xlsx, ".ods": ods, ".pptx": pptx, ".odp": odp };
export const OFFICE = [...Object.keys(ZIPPED), ".rtf"];

/** An Office file's text, by its extension: `{ ok, text }`, or `{ ok: false, problem }`. */
export function officeText(ext, bytes, file) {
  if (ext === ".rtf") return { ok: true, text: rtf(bytes) };
  const unzipped = unzip(bytes, LIMITS);
  if (unzipped.refused) return { ok: false, problem: `${file} could not be opened as a ${ext} file: ${unzipped.refused}.` };
  const text = ZIPPED[ext](unzipped.files);
  if (text === null) return { ok: false, problem: `${file} is not a ${ext} file: its text part is missing.` };
  return { ok: true, text };
}
