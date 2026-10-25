// Run with: deno test --allow-read --allow-env --allow-net --allow-sys --allow-import text-checks.ts
// Named so node --test, run in the business-analyst plugin, leaves this Deno file alone.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { PDFDocument, StandardFonts } from "npm:pdf-lib@1.17.1";
// SheetJS 0.20.3, kept in the worker's vendor folder; vendor/sheetjs-0.20.3/SHA256SUMS records its files.
// @deno-types="./vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from "./vendor/sheetjs-0.20.3/xlsx.mjs";
import { Document, Packer, Paragraph } from "npm:docx@9.7.2";
import { extractSections, OVERLAP, CHUNK_SIZE, splitChunks } from "./text.ts";

async function pdfOf(pages: string[]): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  for (const line of pages) {
    const page = pdf.addPage();
    if (line) page.drawText(line, { x: 50, y: 700, size: 12, font });
  }
  return await pdf.save();
}

Deno.test("a PDF's text is taken page by page, each chunk naming its page", async () => {
  const got = await extractSections(await pdfOf(["Wholesale price list for spring bedding.", "Delivery charges apply to orders under fifty pounds."]), "application/pdf", "prices.pdf");

  assertEquals(got.outcome, "extracted");
  assertEquals(splitChunks(got.sections), [
    { ordinal: 0, place: "page 1", body: "Wholesale price list for spring bedding.", section: 0 },
    { ordinal: 1, place: "page 2", body: "Delivery charges apply to orders under fifty pounds.", section: 1 },
  ]);
});

Deno.test("a PDF with no text is recorded as having none, not as an empty success", async () => {
  assertEquals(await extractSections(await pdfOf([""]), "application/pdf", "scan.pdf"), { outcome: "no_text", sections: [] });
});

Deno.test("a spreadsheet's sheets are taken as rows, each naming its sheet", async () => {
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet([["SKU", "Name", "Price"], ["DV-100", "Duvet, king", 89]]), "Prices");
  const bytes = new Uint8Array(XLSX.write(book, { type: "array", bookType: "xlsx" }));

  const got = await extractSections(bytes, null, "prices.xlsx");

  assertEquals(got, { outcome: "extracted", sections: [{ place: "sheet Prices", text: 'SKU,Name,Price\nDV-100,"Duvet, king",89' }] });
});

Deno.test("a Word document's text is taken, and text files as they are", async () => {
  const doc = new Document({ sections: [{ children: [new Paragraph("Customer master notes."), new Paragraph("Second paragraph.")] }] });
  const word = await extractSections(new Uint8Array(await Packer.toBuffer(doc)), null, "notes.docx");
  const text = await extractSections(new TextEncoder().encode("Plain text file."), "text/plain", "notes.txt");

  assertEquals(splitChunks(word.sections).map((p) => p.body), ["Customer master notes.\n\nSecond paragraph."]);
  assertEquals(text, { outcome: "extracted", sections: [{ place: null, text: "Plain text file." }] });
});

Deno.test("a file of any other kind is unsupported", async () => {
  assertEquals(await extractSections(new Uint8Array([137, 80, 78, 71]), "image/png", "photo.png"), { outcome: "unsupported", sections: [] });
});

Deno.test("paragraphs join into chunks of at most the chunk size, each starting with the end of the one before", () => {
  const text = Array.from({ length: 30 }, (_, i) => `Paragraph ${i} ${"word ".repeat(30)}`).join("\n\n");

  const chunks = splitChunks([{ place: "page 1", text }]);

  assert(chunks.length > 1);
  for (const [i, chunk] of chunks.entries()) {
    assert(chunk.body.length <= CHUNK_SIZE, `chunk ${i} is ${chunk.body.length} characters`);
    assertEquals(chunk.ordinal, i);
    if (i > 0) assert(chunks[i - 1].body.endsWith(chunk.body.split("\n\n")[0]), `chunk ${i} does not overlap the one before`);
  }
});

Deno.test("a paragraph longer than a chunk is cut into overlapping chunks, none over the size", () => {
  const chunks = splitChunks([{ place: null, text: "x".repeat(3000) }]);

  assertEquals(chunks.map((p) => p.body.length), [1200, 1200, 1000]);
  assertEquals(chunks[1].body.slice(0, OVERLAP), chunks[0].body.slice(-OVERLAP));
});

Deno.test("paragraphs near the chunk size never carry an overlap that takes a chunk past it", () => {
  const paragraph = (i: number) => `Paragraph ${i} ` + "word ".repeat(218);
  const text = Array.from({ length: 6 }, (_, i) => paragraph(i)).join("\n\n");

  const chunks = splitChunks([{ place: null, text }]);

  assertEquals(chunks.length, 6);
  for (const chunk of chunks) assert(chunk.body.length <= CHUNK_SIZE, `a chunk is ${chunk.body.length} characters`);
});

Deno.test("a Markdown file is split at its headings, each section placed by its heading path", async () => {
  const text = "Opening words.\n\n# Guide\n\nAbout it.\n\n## Seeing rows\n\n1. Open the editor.\n2. Choose the schema.\n\n## Logs\n\nOpen the logs.\n";

  const got = await extractSections(new TextEncoder().encode(text), null, "guide.md");

  assertEquals(got.sections.map((s) => s.place), [null, "Guide", "Guide › Seeing rows", "Guide › Logs"]);
  assertEquals(got.sections[2].text, "## Seeing rows\n\n1. Open the editor.\n2. Choose the schema.\n");
});

Deno.test("a heading inside a fenced code block stays in its section", async () => {
  const text = "## Shell\n\n```sh\n# a comment, not a heading\necho hi\n```\n\n## Next\n\nMore.";

  const got = await extractSections(new TextEncoder().encode(text), "text/markdown", "notes");

  assertEquals(got.sections.map((s) => s.place), ["Shell", "Next"]);
  assert(got.sections[0].text.includes("# a comment, not a heading"));
});

Deno.test("no chunk crosses a section, and each names its section", () => {
  const long = (n: number) => Array.from({ length: n }, (_, i) => `Step ${i} ${"word ".repeat(40)}`).join("\n\n");
  const sections = [{ place: "A", text: long(8) }, { place: "B", text: "Short section." }, { place: "C", text: long(8) }];

  const chunks = splitChunks(sections);

  assertEquals([...new Set(chunks.map((c) => c.section))], [0, 1, 2]);
  assertEquals(chunks.filter((c) => c.section === 1).map((c) => c.body), ["Short section."]);
  for (const c of chunks) assert(sections[c.section].text.replace(/[ \t]+/g, " ").includes(c.body.split("\n\n")[0]), `chunk ${c.ordinal} is outside its section`);
});

Deno.test("headings underlined with === or --- split a Markdown file too", async () => {
  const text = "Guide\n=====\n\nAbout it.\n\nSeeing rows\n-----------\n\n1. Open the editor.\n\nA rule after a blank line\n\n---\n\nstays in its section.";

  const got = await extractSections(new TextEncoder().encode(text), null, "guide.md");

  assertEquals(got.sections.map((s) => s.place), ["Guide", "Guide › Seeing rows"]);
  assert(got.sections[1].text.startsWith("Seeing rows\n-----------"));
  assert(got.sections[1].text.includes("stays in its section."));
});

function odsOf(sheets: Record<string, unknown[][]>): Uint8Array {
  const book = XLSX.utils.book_new();
  for (const [name, rows] of Object.entries(sheets)) XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(rows), name);
  return new Uint8Array(XLSX.write(book, { type: "array", bookType: "ods" }));
}

Deno.test("an OpenDocument spreadsheet's sheets are taken as CSV rows, each naming its sheet, in order", async () => {
  const bytes = odsOf({ Bible: [["SKU", "Name"], ["TEMP-P-006", "Duvet, king"]], Stock: [["SKU", "On hand"], ["TEMP-P-006", 12]] });

  const got = await extractSections(bytes, "application/vnd.oasis.opendocument.spreadsheet", "bible.ods");

  assertEquals(got, { outcome: "extracted", sections: [
    { place: "sheet Bible", text: 'SKU,Name\nTEMP-P-006,"Duvet, king"' },
    { place: "sheet Stock", text: "SKU,On hand\nTEMP-P-006,12" },
  ] });
});

Deno.test("an OpenDocument spreadsheet sent with no useful content type is read by its extension", async () => {
  const got = await extractSections(odsOf({ Only: [["A", "B"]] }), "application/octet-stream", "sku-uploads.ods");

  assertEquals(got, { outcome: "extracted", sections: [{ place: "sheet Only", text: "A,B" }] });
});

Deno.test("a file of a type OKB does not read is unsupported", async () => {
  assertEquals(await extractSections(new Uint8Array([1, 2, 3]), "application/x-iwork-pages-sffpages", "notes.pages"), { outcome: "unsupported", sections: [] });
});
