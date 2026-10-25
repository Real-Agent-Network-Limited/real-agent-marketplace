// Text out of a file, and chunks out of the text.
import { extractText, getDocumentProxy } from "npm:unpdf@1.8.1";
// SheetJS 0.20.3, kept in the worker's vendor folder; vendor/sheetjs-0.20.3/SHA256SUMS records its files.
// @deno-types="./vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from "./vendor/sheetjs-0.20.3/xlsx.mjs";
import mammoth from "npm:mammoth@1.12.3";
import { strFromU8, unzipSync } from "npm:fflate@0.8.2";
import { Buffer } from "node:buffer";

/** Never an empty success: a file with no text says so, and one nobody can read says that. */
export type Outcome = "extracted" | "no_text" | "unsupported";
export interface Section { place: string | null; text: string }
export interface Extraction { outcome: Outcome; sections: Section[] }
export interface Chunk { ordinal: number; place: string | null; body: string; section: number }

/** About 300 tokens, well inside the 512 gte-small reads, with room for the overlap. */
export const CHUNK_SIZE = 1200;
export const OVERLAP = 200;

type Kind = "pdf" | "sheet" | "ods" | "word" | "markdown" | "text";

function kindOf(contentType: string | null, name: string): Kind | null {
  const type = (contentType ?? "").split(";")[0].trim().toLowerCase();
  const ext = name.toLowerCase().match(/\.[a-z0-9]+$/)?.[0] ?? "";
  if (type === "application/pdf" || ext === ".pdf") return "pdf";
  if (type === "application/vnd.oasis.opendocument.spreadsheet" || ext === ".ods") return "ods";
  if (type.includes("spreadsheetml") || type === "application/vnd.ms-excel" || ext === ".xlsx" || ext === ".xls") return "sheet";
  if (type.includes("wordprocessingml") || ext === ".docx") return "word";
  if (type === "text/markdown" || ext === ".md") return "markdown";
  if (type.startsWith("text/") || type === "application/json" || [".txt", ".csv", ".tsv", ".json"].includes(ext)) return "text";
  return null;
}

/** The five XML entities, and numeric character references. `&amp;` last, so nothing decodes twice. */
function unescapeXml(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#([0-9]+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/** A cell as CSV writes it: quoted when it holds a comma, a quote or a line break. */
const csvCell = (text: string) => /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;

/** An OpenDocument spreadsheet's sheets, one section each, as CSV rows. Only content.xml is
 * unzipped; each `<table:table>` is a sheet, and each cell's text is its `<text:p>` paragraphs. A
 * cell repeated across columns is written that many times, up to 1,024; trailing empty cells
 * and empty rows are dropped. */
function odsSections(bytes: Uint8Array): Section[] {
  const content = unzipSync(bytes, { filter: (file) => file.name === "content.xml" })["content.xml"];
  if (!content) throw new Error("The file has no content.xml, so it is not an OpenDocument spreadsheet");
  const xml = strFromU8(content);
  const sections: Section[] = [];
  for (const table of xml.split(/<table:table(?=[\s>])/).slice(1)) {
    const name = unescapeXml(table.match(/^[^>]*\btable:name="([^"]*)"/)?.[1] ?? "");
    const rows: string[] = [];
    for (const row of table.split(/<table:table-row\b/).slice(1)) {
      const cells: string[] = [];
      for (const cell of row.split(/<table:(?:covered-)?table-cell\b/).slice(1)) {
        const repeat = Math.min(Number(cell.match(/^[^>]*\btable:number-columns-repeated="(\d+)"/)?.[1] ?? 1), 1024);
        const paragraphs = [...cell.replace(/<text:line-break\b[^>]*\/?>/g, "\n").replace(/<text:tab\b[^>]*\/?>/g, "\t")
          .matchAll(/<text:p\b[^>]*>([\s\S]*?)<\/text:p>/g)].map((m) => unescapeXml(m[1].replace(/<[^>]+>/g, "")));
        const text = csvCell(paragraphs.join("\n"));
        for (let i = 0; i < repeat; i++) cells.push(text);
      }
      while (cells.length && cells[cells.length - 1] === "") cells.pop();
      if (cells.length) rows.push(cells.join(","));
    }
    sections.push({ place: `sheet ${name}`, text: rows.join("\n") });
  }
  return sections;
}

/** A Markdown file's sections, one per heading, `#` or underlined with `===` or `---`, each placed
 * by its heading path. Headings inside fenced code blocks are text. Text before the first heading
 * is a section with no place. */
function markdownSections(text: string): Section[] {
  const sections: Section[] = [];
  const path: string[] = [];
  let place: string | null = null;
  let lines: string[] = [];
  let fence: string | null = null;
  const close = () => { if (lines.join("").trim()) sections.push({ place, text: lines.join("\n") }); lines = []; };
  for (const line of text.replace(/\r\n?/g, "\n").split("\n")) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
    if (marker && (fence === null || marker[0] === fence[0] && marker.length >= fence.length)) fence = fence === null ? marker : null;
    const heading = fence === null && !marker ? line.match(/^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$/) : null;
    const title = lines.at(-1) ?? "";
    const underline = fence === null && !marker && lines.length > 0 && title.trim() !== ""
      && !/^ {0,3}([-*+]|\d+[.)]|>|#)/.test(title) ? line.match(/^ {0,3}(=+|-+)\s*$/) : null;
    const start = (level: number, text: string) => {
      close();
      path.length = level - 1;
      path[level - 1] = text;
      place = path.filter(Boolean).join(" › ");
    };
    if (heading) start(heading[1].length, heading[2]);
    else if (underline) {
      lines.pop();
      start(underline[1][0] === "=" ? 1 : 2, title.trim());
      lines.push(title);
    }
    lines.push(line);
  }
  close();
  return sections;
}

export async function extractSections(bytes: Uint8Array, contentType: string | null, name: string): Promise<Extraction> {
  const kind = kindOf(contentType, name);
  if (!kind) return { outcome: "unsupported", sections: [] };
  let sections: Section[];
  if (kind === "pdf") {
    const { text } = await extractText(await getDocumentProxy(bytes), { mergePages: false });
    sections = (text as string[]).map((page, i) => ({ place: `page ${i + 1}`, text: page }));
  } else if (kind === "sheet") {
    const book = XLSX.read(bytes, { type: "array" });
    sections = book.SheetNames.map((sheet) => ({
      place: `sheet ${sheet}`,
      text: XLSX.utils.sheet_to_csv(book.Sheets[sheet], { blankrows: false }),
    }));
  } else if (kind === "ods") {
    sections = odsSections(bytes);
  } else if (kind === "word") {
    const { value } = await mammoth.extractRawText({ buffer: Buffer.from(bytes) });
    sections = [{ place: null, text: value }];
  } else if (kind === "markdown") {
    sections = markdownSections(new TextDecoder().decode(bytes));
  } else {
    sections = [{ place: null, text: new TextDecoder().decode(bytes) }];
  }
  sections = sections.filter((s) => s.text.trim() !== "");
  return { outcome: sections.length ? "extracted" : "no_text", sections };
}

/** The last `n` characters, starting at a word. */
function tail(text: string, n: number): string {
  if (text.length <= n) return text;
  const from = text.length - n;
  const space = text.indexOf(" ", from);
  return text.slice(space === -1 ? from : space + 1);
}

/** A paragraph longer than a chunk, cut into overlapping pieces at spaces where it can be. */
function cut(paragraph: string, size: number, overlap: number): string[] {
  const pieces: string[] = [];
  let start = 0;
  while (start < paragraph.length) {
    let end = Math.min(start + size, paragraph.length);
    if (end < paragraph.length) {
      const space = paragraph.lastIndexOf(" ", end);
      if (space > start + size / 2) end = space;
    }
    pieces.push(paragraph.slice(start, end).trim());
    if (end >= paragraph.length) break;
    start = Math.max(end - overlap, start + 1);
  }
  return pieces.filter(Boolean);
}

/** Chunks of at most `size` characters, joined at paragraph ends, each overlapping the one before
 * within its section. No chunk crosses a section; each names its section by position. */
export function splitChunks(sections: Section[], size = CHUNK_SIZE, overlap = OVERLAP): Chunk[] {
  const out: Chunk[] = [];
  for (const [index, section] of sections.entries()) {
    const text = section.text.replace(/\r\n?/g, "\n").replace(/[ \t]+/g, " ").trim();
    const paragraphs = text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
    let current = "";
    let fresh = false;
    const push = (body: string) => out.push({ ordinal: out.length, place: section.place, body: body.trim(), section: index });
    const flush = () => {
      if (fresh) push(current);
      current = tail(current, overlap);
      fresh = false;
    };
    for (const paragraph of paragraphs) {
      if (paragraph.length > size) {
        // Its pieces already overlap each other, so they become chunks as they are.
        flush();
        const pieces = cut(paragraph, size, overlap);
        pieces.forEach(push);
        current = tail(pieces[pieces.length - 1], overlap);
        continue;
      }
      if (current.length + 2 + paragraph.length > size) {
        flush();
        // The overlap is dropped when keeping it would take the chunk past the size.
        if (current.length + 2 + paragraph.length > size) current = "";
      }
      current = current ? `${current}\n\n${paragraph}` : paragraph;
      fresh = true;
    }
    if (fresh) push(current);
  }
  return out;
}
