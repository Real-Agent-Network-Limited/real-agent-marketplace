// The okb plugin's page tools: `draw_graph`, `draw_search`, `draw_state_machine` and `state_machine_payload`,
// which run the graph skill's scripts, `draw_board`, which runs the board skill's script, `draw_reference` and
// `draw_sop`, which write the print skill's pages from OKB's rows, `report_page`, which makes an executive
// report's page from its Markdown, `print_pdf`, which runs the print skill's script, and `embed_pictures`,
// which puts a page's pictures inside it, and `create_workbook` and `edit_workbook`, which run the code skill's
// workbook scripts, on files directly inside one folder.
// `check_text` runs the humanizer plugin's checks, copied beside this file, on a text there. `copy_samples` copies
// the check skill's samples into the folder.
// The MCP server and the okb command both make them with createTools.
import { execFile } from "node:child_process";
import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdtempSync, openSync, readdirSync, readFileSync, readSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { check as humanizerCheck } from "./humanizer-checks.mjs";

const SKILLS = fileURLToPath(new URL("../../skills/", import.meta.url));
const HERE = fileURLToPath(new URL(".", import.meta.url));
// The skill folder each script is in.
const SCRIPT_SKILL = { "graph_page.py": "graph", "search_page.py": "graph", "plan_graph.py": "graph", "model_to_page.py": "graph", "page_to_model.py": "graph", "board_page.py": "board", "model_board.py": "board",
  "print_pdf.py": "print", "reference_page.py": "print", "sop_page.py": "print", "report_page.py": "print", "create_workbook.py": "code", "edit_workbook.py": "code" };
// The scripts that write a page's outline and picture beside it, for the agent to check.
const CHECKED = new Set(["graph_page.py", "search_page.py", "plan_graph.py", "board_page.py", "model_board.py", "model_to_page.py", "reference_page.py", "sop_page.py"]);
/** The outline and picture beside a page `<name>.html`: `<name>.outline.md` and `<name>.png`. */
const companionsOf = page => { const stem = String(page).replace(/\.html$/i, ""); return { outline: `${stem}.outline.md`, picture: `${stem}.png` }; };
// Each script's input and output extensions, for its copies in the scratch folder.
const SCRIPT_FILES = { "page_to_model.py": [".html", ".json"], "report_page.py": [".md", ".html"], "edit_workbook.py": [".xlsx", ".xlsx"] };
// A page or record larger than this is refused rather than read.
const MAX_BYTES = 20 * 1024 * 1024;
// A live model's names, number formats and input rules, as create_workbook and edit_workbook take them.
const MODEL = {
  names: {
    type: "array",
    description: "Names for cells or ranges, such as growth_rate for Inputs!B2. A formula can use a name in place of the cells.",
    items: { type: "object", properties: { name: { type: "string" }, ref: { type: "string", description: "A sheet and its cells, such as Inputs!B2 or Inputs!B2:B4." } }, required: ["name", "ref"], additionalProperties: false },
  },
  formats: {
    type: "array",
    description: "Number formats, such as 0.0% or #,##0, each for a cell or a range of cells on a sheet.",
    items: { type: "object", properties: { sheet: { type: "string" }, range: { type: "string", description: "A cell or range, such as B2 or B2:D10." }, format: { type: "string" } }, required: ["sheet", "range", "format"], additionalProperties: false },
  },
  rules: {
    type: "array",
    description: "Input rules, each for a cell or range on a sheet: a list of choices, or a number from min to max. A cell with a rule is an input a person changes.",
    items: {
      type: "object",
      properties: { sheet: { type: "string" }, range: { type: "string" }, list: { type: "array", items: { type: ["string", "number"] } }, min: { type: "number" }, max: { type: "number" } },
      required: ["sheet", "range"],
      additionalProperties: false,
    },
  },
};
const FORMULAS = "A value starting with = is a formula, such as =Inputs!B2*(1+growth_rate), and one starting with '= is the text after the quote. Each formula's brackets, sheets and names are checked first. The workbook recalculates every formula when it opens.";
// A workbook is a live model a person works in. The glossary, the data dictionary and other reference data stay in OKB.
const MODELS_ONLY = "It is for a live model a person works in, such as a forecast, never for the glossary, the data dictionary or other reference data, which stay in OKB.";
// The check skill's samples, which copy_samples copies into the agent folder.
const SAMPLES = join(SKILLS, "check", "samples");
const NO_FOLDER = "No agent folder is set for the okb plugin. The person signs in with okb sign-in --folder, which makes the folder the agent folder, or sets agent_folder in the okb plugin's settings.";

export const TOOLS = [
  {
    name: "draw_graph",
    description: "Draw a graph page. For a plan, give the pages okb_get_progress wrote, as draw_board takes them: the graph is drawn from the same plan model as the board, each part of the plan a group in index order, each activity a node carrying its index. For any other model record, give the file okb_get_record wrote: nodes are grouped by type, or by the attribute named in group_by, and a node's index attribute sets its reference and order. Every path is a full path directly inside the agent folder, and the page is a new file there; nothing is replaced. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before giving the page to the person. Returns the page's path and size, the counts, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        record_file: { type: "string", description: "A model record that is not a plan, as okb_get_record's result_file wrote it." },
        progress_files: { type: "array", items: { type: "string" }, minItems: 1, description: "For a plan: every page of the progress answer, as okb_get_progress's result_file wrote each one." },
        plan_id: { type: "string", description: "With progress_files: the plan's record id. Without it, the graph draws the only plan with no parent." },
        page_file: { type: "string", description: "The new page file, ending in .html." },
        group_by: { type: "string", description: "With record_file: a node attribute to group by. Without it, nodes are grouped by type." },
      },
      required: ["page_file"],
      additionalProperties: false,
    },
  },
  {
    name: "draw_search",
    description: "Draw a page that shows how a file search found its answer, from the search's own result file: best one from a file-search call with explain true. Each hit is a card, the reference hits first, naming the ways that found it with their ranks and its similarity. Its passage shows the question's words marked in yellow, each measured sentence shaded blue by its similarity to the question, and each entity the graph walk reached underlined in green. A green panel plays the graph walk step by step, from its starting points to the hits. Every path is a full path directly inside the agent folder, and the page is a new file there; nothing is replaced. Without page_file, the page is the search file's name ending in .html. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before giving the page to the person. Returns the page's path and size, the counts, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        search_file: { type: "string", description: "The search's result, as file-search's result_file wrote it." },
        question: { type: "string", description: "The question the search was asked, as the page's heading." },
        page_file: { type: "string", description: "The new page file, ending in .html. Without it, the search file's name ending in .html." },
      },
      required: ["search_file", "question"],
      additionalProperties: false,
    },
  },
  {
    name: "draw_board",
    description: "Draw a board. For a plan, give the pages okb_get_progress wrote to files, every page read with the first page's cutoff and observed_at: the plan is the header, with its purpose statement under it, each part of the plan is a row, and each activity is a card in its state's column. For any other model record, such as an org chart or a contacts list, give the file okb_get_record wrote as record_file, with layout and by: each node is a card with its label, role and description, in rows. With layout group, there is one row per value of the node attribute named in by, in the order the nodes first give them; a place, such as a site, heads a column, and the cards linked to it sit under it, a card linked to places apart under each one. With layout level, there is one row per level of the relation named in by, such as reports to: each card sits under the card it points to, the levels scroll sideways as one, and each node outside the relation is a card above them, headed Beside the chart. A gap is a dashed card, and clicking a card shows its lines and evidence. Every path is a full path directly inside the agent folder, and the page is a new file there; nothing is replaced. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before giving the page to the person. Returns the page's path and size, the plan's title and the count of activities in each state, or the model's title and its counts of cards and rows, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        progress_files: { type: "array", items: { type: "string" }, minItems: 1, description: "For a plan: every page of the progress answer, as okb_get_progress's result_file wrote each one." },
        record_file: { type: "string", description: "A model record that is not a plan, as okb_get_record's result_file wrote it." },
        layout: { type: "string", enum: ["group", "level"], description: "With record_file: group, one row per value of a node attribute, or level, one row per level of a relation." },
        by: { type: "string", description: "With record_file: the node attribute to group by, or the relation to draw by level, such as reports to." },
        page_file: { type: "string", description: "The new page file, ending in .html." },
        plan_id: { type: "string", description: "With progress_files: the plan's record id. Without it, the board draws the only plan with no parent." },
        purpose: { type: "string", description: "With progress_files: the plan's purpose statement, the decision text of its purpose record, shown at the top of the board." },
      },
      required: ["page_file"],
      additionalProperties: false,
    },
  },
  {
    name: "draw_state_machine",
    description: "Draw a state machine page from a routine model record that okb_get_record wrote to a file. A routine model's nodes are routines, states, data, rules, actors and applications, whether it was made from a state machine page or written as a payload. Any other model is drawn with draw_graph. Both paths are full paths directly inside the agent folder, and the page is a new file there; nothing is replaced. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before giving the page to the person. Returns the page's path and size, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        record_file: { type: "string", description: "The record file, as okb_get_record's result_file wrote it." },
        page_file: { type: "string", description: "The new page file, ending in .html." },
      },
      required: ["record_file", "page_file"],
      additionalProperties: false,
    },
  },
  {
    name: "state_machine_payload",
    description: "Turn a state machine page into a model record's payload, ready to save with okb_save_version's file_args. Both paths are full paths directly inside the agent folder, and the payload is a new file there; nothing is replaced. Returns the record's title and the counts of each node and edge type, never the payload.",
    inputSchema: {
      type: "object",
      properties: {
        page_file: { type: "string", description: "The page, an HTML file with a graph-data and a state-machine-data JSON block." },
        payload_file: { type: "string", description: "The new payload file, ending in .json." },
        description: { type: "string", description: "What the model describes. Without it, the description names the page." },
      },
      required: ["page_file", "payload_file"],
      additionalProperties: false,
    },
  },
  {
    name: "draw_reference",
    description: "Write the glossary, with its classes and relationships, or the data dictionary, as an A4 page ready for print_pdf, from the rows okb_get_reference returned to a file. Both paths are full paths directly inside the agent folder, and the page is a new file there; nothing is replaced. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before printing the page. Returns the page's path and size, the counts, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        reference_file: { type: "string", description: "okb_get_reference's result for the glossary or the dictionary, as its result_file wrote it." },
        page_file: { type: "string", description: "The new page file, ending in .html." },
      },
      required: ["reference_file", "page_file"],
      additionalProperties: false,
    },
  },
  {
    name: "draw_sop",
    description: "Write a standard operating procedure for one routine, as an A4 page ready for print_pdf, from its approved model version: its purpose, its trigger, each state with who, what, the tool and the checks, the handovers, the exceptions, the drawn state machine and the glossary terms it uses. Every path is a full path directly inside the agent folder, and the page is a new file there; nothing is replaced. Beside the page it writes the page's outline, <name>.outline.md, and, where a Chromium browser is found, its picture, <name>.png. Read both before printing the page. Returns the page's path and size, the counts, outline_file, picture_file and the number of findings, never the page's content.",
    inputSchema: {
      type: "object",
      properties: {
        record_file: { type: "string", description: "The routine's approved model version, as okb_get_record's or okb_get_history's result_file wrote it." },
        version_id: { type: "string", description: "The approved version's id. Needed when record_file is a page of okb_get_history." },
        glossary_file: { type: "string", description: "okb_get_reference's result for the glossary, as its result_file wrote it." },
        picture_file: { type: "string", description: "The picture of the routine's state machine page, the <name>.png draw_state_machine wrote beside it." },
        page_file: { type: "string", description: "The new page file, ending in .html." },
      },
      required: ["record_file", "glossary_file", "picture_file", "page_file"],
      additionalProperties: false,
    },
  },
  {
    name: "report_page",
    description: "Make an executive report's page from its Markdown, as the real-agent-project plugin's report skill describes, for print_pdf to print. Headings, paragraphs, lists, tables, bold, italic, code and links become the page's own, with no Markdown mark left. A figure block of the report skill's section 6, a line starting with <, passes through up to the next blank line. The report's first '# ' heading is its title, and the four header lines are given here. The page has the plain style. Each picture the report names beside it is put inside the page, so the page is one file. Both paths are full paths directly inside the agent folder, and the page is a new file there; nothing is replaced. A picture given with a folder, missing, or not a PNG, JPEG, GIF or WebP picture is refused, and nothing is written. Returns the page's path and size, and the pictures it holds.",
    inputSchema: {
      type: "object",
      properties: {
        markdown_file: { type: "string", description: "The report's Markdown, a .md file in the agent folder." },
        page_file: { type: "string", description: "The new page, ending in .html." },
        prepared_for: { type: "string", description: "The header's Prepared for: the audience the person names." },
        prepared_by: { type: "string", description: "The header's Prepared by: the person who reviews the report and accepts responsibility for it." },
        read_at: { type: "string", description: "The header's Read from OKB line: the date and time of the progress read, such as '21 October 2026, 11:30 UK time'." },
        project_owner: { type: "string", description: "The header's Project owner: the plan's owner." },
      },
      required: ["markdown_file", "page_file", "prepared_for", "prepared_by", "read_at", "project_owner"],
      additionalProperties: false,
    },
  },
  {
    name: "print_pdf",
    description: "Print a page to an A4 PDF, or a deck's page of slides to a PDF of 16:9 pages, with Google Chrome, Chromium or Microsoft Edge, as the print skill describes. The page is an HTML file whose style sets @page { size: A4; }. With size slide, it is a deck whose style is the print skill's deck.css, and each <section class=\"slide\"> prints as one 16:9 page; a deck whose pages are not 16:9, or whose page count is not its slides', is refused. Each picture or other file it loads is a file directly beside it in the agent folder, or a web address. Both paths are full paths directly inside the agent folder, and the PDF is a new file there; nothing is replaced. A page printed at any other size, naming a file that is not beside it, or with a picture missing from the PDF, is refused and nothing is written. Returns the PDF's path and size, its page count, its paper and the pictures it holds, never its content. Its markdown_findings give each Markdown mark in the printed prose, with its page and line: a heading's #, **, a backtick, a line starting - that starts a block, and [text](address). Code, in a mono font, is left out. It is null where the PDF's text cannot be read. A document with a finding is put right and printed again before it is given.",
    inputSchema: {
      type: "object",
      properties: {
        page_file: { type: "string", description: "The page, an HTML file in the agent folder." },
        pdf_file: { type: "string", description: "The new PDF file, ending in .pdf." },
        size: { type: "string", enum: ["A4", "slide"], description: "A4, the default, for a document. slide for a deck: each section.slide prints as one 16:9 page." },
      },
      required: ["page_file", "pdf_file"],
      additionalProperties: false,
    },
  },
  {
    name: "embed_pictures",
    description: "Make a single-file copy of a page, such as a report's deck, as the print skill describes. Each picture the page's <img> elements name directly beside it is put inside the copy, so the copy shows its pictures wherever it goes. print_pdf prints the copy as it prints the page. With style deck, the copy also holds the print skill's deck.css, so a deck's page is written without it. Both paths are full paths directly inside the agent folder, and the copy is a new file there; nothing is replaced. A picture given with a folder, missing, or not a PNG, JPEG, GIF or WebP picture is refused, and nothing is written. Returns the copy's path and size, the pictures it holds, and its style.",
    inputSchema: {
      type: "object",
      properties: {
        page_file: { type: "string", description: "The page, an HTML file in the agent folder, with its pictures beside it." },
        new_file: { type: "string", description: "The new single-file page, ending in .html." },
        style: { type: "string", enum: ["deck"], description: "deck puts the print skill's deck.css in the copy's head, before the page's own style, for a deck's page of slides." },
      },
      required: ["page_file", "new_file"],
      additionalProperties: false,
    },
  },
  {
    name: "create_workbook",
    description: `Create a new Excel workbook, an .xlsx file, from named sheets of rows. ${MODELS_ONLY} Row 1 of each sheet holds its column headings. A value is text, a number, true, false, or null for an empty cell. ${FORMULAS} A live model keeps its inputs on a sheet of their own, each with a rule. Every sheet is checked first; on any problem, nothing is written and every problem is returned. The workbook is a new file directly inside the agent folder, given as a full path; nothing is replaced. edit_workbook can edit it afterwards. Returns the new workbook's path, size and SHA-256, and the rows written on each sheet, never its content.`,
    inputSchema: {
      type: "object",
      properties: {
        new_file: { type: "string", description: "The new workbook file, ending in .xlsx." },
        sheets: {
          type: "array",
          minItems: 1,
          description: "The sheets, in order.",
          items: {
            type: "object",
            properties: {
              name: { type: "string", description: "The sheet's name, 1 to 31 characters." },
              rows: { type: "array", description: "The rows, row 1 first. Each row is a list of values, one for each column.", items: { type: "array" } },
            },
            required: ["name", "rows"],
            additionalProperties: false,
          },
        },
        ...MODEL,
      },
      required: ["new_file", "sheets"],
      additionalProperties: false,
    },
  },
  {
    name: "edit_workbook",
    description: `Add, remove and change rows on named sheets of an Excel workbook, an .xlsx file, into a new workbook. ${MODELS_ONLY} Row 1 of each sheet holds its column headings. Every edit is checked first; on any problem, nothing is written and every problem is returned. Sheets, headings, column widths, frozen panes and styles stay as they are, and a sheet in order by its first column keeps that order. ${FORMULAS} In a workbook with formulas, names or input rules, rows keep their numbers: an added row goes after the last row, and a remove is refused. Both paths are full paths directly inside the agent folder, and the new workbook is a new file there; nothing is replaced. Returns the new workbook's path, size and SHA-256, and the rows added, removed and changed on each sheet, never its content.`,
    inputSchema: {
      type: "object",
      properties: {
        workbook_file: { type: "string", description: "The workbook to edit, an .xlsx file." },
        new_file: { type: "string", description: "The new workbook file, ending in .xlsx." },
        edits: {
          type: "array",
          minItems: 1,
          description: "The edits, applied in order.",
          items: {
            type: "object",
            properties: {
              sheet: { type: "string", description: "The sheet's name." },
              action: { type: "string", enum: ["add", "remove", "change"] },
              match: { type: "object", description: "For remove and change: column headings and values that find exactly one row." },
              row: { type: "object", description: "For add: a value for each heading the new row fills. For change: each heading to set, and its new value." },
            },
            required: ["sheet", "action"],
            additionalProperties: false,
          },
        },
        ...MODEL,
      },
      required: ["workbook_file", "new_file", "edits"],
      additionalProperties: false,
    },
  },
  {
    name: "copy_samples",
    description: "Copy the check skill's sample files, check.html, check.progress.json, check.pdf, check.jpg, check.wav and check.mp4, from the okb plugin into the agent folder, for the check of this computer. A file of a sample's name already in the agent folder is left as it is. Returns copied, the names copied, already, the names already there as the sample, and differs, the names already there with other content.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "check_text",
    description: "Check a text against the plain-English rules that can be checked: no em-dash, no sentence over 25 words, no paragraph over 6 sentences, no inflated or self-narrating words, one name for each thing, and the others the humanizer plugin's translate skill lists. The text is a Markdown or plain text file directly inside the agent folder; nothing is written. Returns each finding with its rule, the words it is about and the line they are on, or no findings.",
    inputSchema: {
      type: "object",
      properties: {
        text_file: { type: "string", description: "The text, a .md or .txt file in the agent folder." },
      },
      required: ["text_file"],
      additionalProperties: false,
    },
  },
];

// Windows paths ignore letter case, so there a folder typed in any case is the same folder.
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;

// The commands that may run Python 3, in the order tried. On Windows, python3 and python may be
// Microsoft Store shortcuts that run nothing, and py is the Python launcher.
const PYTHONS = [["python3"], ["python"], ["py", "-3"]];
const INSTALL_PYTHON = { win32: "`winget install Python.Python.3.13`", darwin: "`xcode-select --install`" }[process.platform] ?? "`sudo apt install python3` on Debian or Ubuntu, or its own package manager on another Linux";
let pythonFound;

/** The first command whose --version starts "Python 3.", found once and remembered. */
function findPython() {
  pythonFound ??= (async () => {
    for (const command of PYTHONS) {
      const version = await new Promise(done => execFile(command[0], [...command.slice(1), "--version"], { timeout: 10_000 }, (err, stdout, stderr) => done(err ? "" : `${stdout}${stderr}`.trim())));
      if (version.startsWith("Python 3.")) return command;
    }
    return null;
  })();
  return pythonFound;
}

/** Runs one of the skill's scripts with Python 3, never through a shell. */
async function python(script, args) {
  const command = await findPython();
  if (!command) return { ok: false, problem: `Python 3 is not on this computer. Install it with ${INSTALL_PYTHON}, then start a new session.` };
  return new Promise(done => {
    // No bytecode is written beside the scripts, so the installed plugin folder stays as installed.
    const env = { ...process.env, PYTHONDONTWRITEBYTECODE: "1" };
    execFile(command[0], [...command.slice(1), SCRIPT_SKILL[script] ? join(SKILLS, SCRIPT_SKILL[script], script) : join(HERE, script), ...args], { env, timeout: 120_000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) return done({ ok: false, problem: `${script} failed: ${(stderr || stdout || err.message).trim()}` });
      // Python on Windows ends each line with \r\n; the output reads the same on every system.
      done({ ok: true, output: stdout.replaceAll("\r\n", "\n").trim() });
    });
  });
}

const asContent = payload => ({ content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] });

/** The tools on files directly inside `agentFolder`. Returns the tools' list and `callTool`, which answers as MCP content. */
export function createTools({ agentFolder = null }) {
  /** A full path naming a file directly inside the agent folder, and not a hidden one. */
  function place(file) {
    if (!agentFolder) return { ok: false, problem: NO_FOLDER };
    if (!isAbsolute(String(file ?? ""))) return { ok: false, problem: `The file must be given as a full path inside ${agentFolder}.` };
    let root;
    try { root = realpathSync.native(agentFolder); } catch { return { ok: false, problem: `The agent folder ${agentFolder} does not exist.` }; }
    const name = basename(file);
    const parent = resolve(dirname(file));
    if (!samePath(parent, resolve(agentFolder)) && !samePath(parent, root) || name === "" || name === "." || name === ".." || name.startsWith(".")) {
      return { ok: false, problem: `${file} is not a file name directly inside the agent folder, ${agentFolder}.` };
    }
    return { ok: true, path: join(root, name), shown: join(parent, name) };
  }

  /** Reads a file directly inside the agent folder, refusing a link, a folder or an oversized file. */
  function readInside(file) {
    const at = place(file);
    if (!at.ok) return at;
    // Where the open cannot refuse a link itself (Windows has no O_NOFOLLOW), refuse one by name first, as a best effort.
    if (constants.O_NOFOLLOW === undefined) {
      let named;
      try { named = lstatSync(at.path); } catch { return { ok: false, problem: `No such file: ${file}` }; }
      if (named.isSymbolicLink()) return { ok: false, problem: `${file} is a link. Only files directly inside ${agentFolder} can be read.` };
    }
    let fd;
    try { fd = openSync(at.path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0)); }
    catch (err) {
      if (err?.code === "ELOOP" || err?.code === "EMLINK") return { ok: false, problem: `${file} is a link. Only files directly inside ${agentFolder} can be read.` };
      if (err?.code === "ENOENT") return { ok: false, problem: `No such file: ${file}` };
      return { ok: false, problem: `${file} could not be opened: ${err?.message ?? err}` };
    }
    try {
      const stat = fstatSync(fd);
      if (!stat.isFile()) return { ok: false, problem: `${file} is not a file.` };
      if (stat.size > MAX_BYTES) return { ok: false, problem: `${file} is ${stat.size} bytes, over the ${MAX_BYTES}-byte limit.` };
      const body = Buffer.alloc(stat.size);
      let read = 0;
      while (read < stat.size) { const n = readSync(fd, body, read, stat.size - read, read); if (n === 0) break; read += n; }
      return { ok: true, body: body.subarray(0, read) };
    } finally {
      closeSync(fd);
    }
  }

  /** Checks that a new file may be created, before any work is done. */
  function freeInside(file) {
    const at = place(file);
    if (!at.ok) return at;
    try { lstatSync(at.path); return { ok: false, problem: `${file} already exists. Name a new file; nothing is replaced.` }; }
    catch (err) { if (err?.code !== "ENOENT") return { ok: false, problem: `${file} could not be checked: ${err?.message ?? err}` }; }
    return at;
  }

  /** Creates a new file directly inside the agent folder; never replaces one. */
  function writeInside(file, body) {
    const at = place(file);
    if (!at.ok) return at;
    let fd;
    try { fd = openSync(at.path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600); }
    catch (err) {
      if (err?.code === "EEXIST") return { ok: false, problem: `${file} already exists. Name a new file; nothing is replaced.` };
      return { ok: false, problem: `${file} could not be written: ${err?.message ?? err}` };
    }
    try { writeFileSync(fd, body); fsyncSync(fd); } finally { closeSync(fd); }
    return { ok: true, file: at.shown, bytes: body.length };
  }

  /**
   * Copies each input into a scratch folder, runs the script there, and writes its output back. A
   * JSON value given as `data` is written to the scratch folder too, and passed after the output.
   * Each of `beside`, `{ name, body }`, is written beside the output under its own name, as a picture
   * the page names is beside it in the agent folder. `finish`, given the output's bytes, returns
   * `{ ok, body }` to write in their place, or a refusal, and nothing is written.
   */
  async function convert(script, inputFiles, outputFile, extra = [], data, beside = [], finish) {
    const inputs = [].concat(inputFiles);
    if (inputs.length === 0) return { ok: false, problem: "Name at least one input file." };
    const output = freeInside(outputFile);
    if (!output.ok) return output;
    const besides = CHECKED.has(script) ? companionsOf(outputFile) : null;
    if (besides) {
      if (!/\.html$/i.test(String(outputFile))) return { ok: false, problem: "page_file must end in .html." };
      for (const file of [besides.outline, besides.picture]) { const free = freeInside(file); if (!free.ok) return free; }
    }
    const bodies = [];
    for (const file of inputs) {
      const input = readInside(file);
      if (!input.ok) return input;
      bodies.push(input.body);
    }
    const [inputExt, outputExt] = SCRIPT_FILES[script] ?? [".json", ".html"];
    const scratch = mkdtempSync(join(tmpdir(), "okb-page-"));
    try {
      const sources = bodies.map((body, at) => {
        const source = join(scratch, `input-${at + 1}` + inputExt);
        writeFileSync(source, body, { mode: 0o600 });
        return source;
      });
      const target = join(scratch, "output" + outputExt);
      for (const { name, body } of beside) writeFileSync(join(scratch, name), body, { mode: 0o600 });
      if (data !== undefined) {
        const dataFile = join(scratch, "data.json");
        writeFileSync(dataFile, JSON.stringify(data), { mode: 0o600 });
        extra = [dataFile, ...extra];
      }
      // Scratch paths are given back as the agent folder's own paths.
      const named = text => sources.reduce((out, source, at) => out.replaceAll(source, inputs[at]), text.replaceAll(target, outputFile));
      const ran = await python(script, [...sources, target, ...extra]);
      if (!ran.ok) return { ...ran, problem: named(ran.problem) };
      let body = readFileSync(target);
      if (finish) {
        const finished = finish(body);
        if (!finished.ok) return finished;
        body = finished.body;
      }
      const written = writeInside(outputFile, body);
      if (!written.ok) return written;
      const sha256 = data === undefined ? {} : { sha256: createHash("sha256").update(body).digest("hex") };
      const shown = named(ran.output).replaceAll(outputFile, written.file);
      let checked = {};
      if (besides) {
        // The outline is always written; the picture where the script found a browser.
        const made = companionsOf(target);
        const outline = writeInside(besides.outline, readFileSync(made.outline));
        if (!outline.ok) return outline;
        let picture = null;
        try { picture = readFileSync(made.picture); } catch { picture = null; }
        const pictured = picture && picture.length ? writeInside(besides.picture, picture) : null;
        if (pictured && !pictured.ok) return pictured;
        const findings = Number((shown.match(/; (\d+) findings;/) ?? [])[1]);
        checked = { outline_file: outline.file, picture_file: pictured ? pictured.file : null, findings: Number.isFinite(findings) ? findings : null,
          ...(pictured ? {} : { picture_problem: (shown.match(/no picture: ([^;]*)$/) ?? [])[1] ?? "no picture was taken" }) };
      }
      return { ok: true, file: written.file, bytes: written.bytes, ...sha256, ...checked, agentFolder, agentFolderPath: realpathSync.native(agentFolder), output: shown };
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }

  /**
   * The page with each picture an <img> names beside it put inside it, as a data: address, with the file's name in
   * data-file for print_pdf to count. A picture given with a folder, missing, or not a PNG, JPEG, GIF or WebP picture
   * is refused, as print_pdf refuses it. A web address or a data: address stays as it is.
   */
  function embedPictures(html, pageFile) {
    const pictures = new Set(), problems = new Set();
    const page = html.replace(/(<img\b[^>]*?\bsrc\s*=\s*)(["'])([^"']*)\2/gi, (whole, start, quote, src) => {
      let name;
      try { name = decodeURIComponent(src.trim()).split(/[?#]/)[0]; } catch { name = src.trim(); }
      if (/^(https?:|data:)/i.test(name)) return whole;
      if (name === "" || /[\\/]/.test(name) || /^file:/i.test(name) || name.startsWith(".")) { problems.add(`${name} is not a file directly beside the page`); return whole; }
      const file = readInside(join(dirname(String(pageFile)), name));
      if (!file.ok) { problems.add(`${name} is not in the agent folder`); return whole; }
      const head = file.body.subarray(0, 12);
      const type = head.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex")) ? "image/png"
        : head.subarray(0, 3).equals(Buffer.from("ffd8ff", "hex")) ? "image/jpeg"
        : ["GIF87a", "GIF89a"].includes(head.subarray(0, 6).toString("latin1")) ? "image/gif"
        : head.subarray(0, 4).toString("latin1") === "RIFF" && head.subarray(8, 12).toString("latin1") === "WEBP" ? "image/webp" : null;
      if (!type) { problems.add(`${name} is not a PNG, JPEG, GIF or WebP picture`); return whole; }
      pictures.add(name);
      return `${start}${quote}data:${type};base64,${file.body.toString("base64")}${quote} data-file=${quote}${name}${quote}`;
    });
    if (problems.size) return { ok: false, problem: `Nothing was written: the page names pictures it cannot hold: ${[...problems].sort().join("; ")}` };
    return { ok: true, body: Buffer.from(page), pictures: [...pictures].sort() };
  }

  /** Writes a new page from one in the agent folder, holding each picture it names beside it. */
  function embedInPage(pageFile, newFile, style) {
    if (!/\.html?$/i.test(String(pageFile ?? ""))) return { ok: false, problem: "page_file must end in .html." };
    if (style !== undefined && style !== "deck") return { ok: false, problem: "style must be deck, or left out." };
    if (!/\.html$/i.test(String(newFile ?? ""))) return { ok: false, problem: "new_file must end in .html." };
    const page = readInside(pageFile);
    if (!page.ok) return page;
    const free = freeInside(newFile);
    if (!free.ok) return free;
    let html = page.body.toString("utf-8");
    if (style === "deck") {
      // The deck's style goes first in the head, so the page's own style can change it.
      const head = html.match(/<head\b[^>]*>/i);
      if (!head) return { ok: false, problem: "Nothing was written: the page has no <head> to put deck.css in." };
      const css = readFileSync(join(SKILLS, "print", "deck.css"), "utf-8");
      html = html.slice(0, head.index + head[0].length) + `\n<style>\n${css}</style>` + html.slice(head.index + head[0].length);
    }
    const embedded = embedPictures(html, pageFile);
    if (!embedded.ok) return embedded;
    const written = writeInside(newFile, embedded.body);
    if (!written.ok) return written;
    return { ok: true, file: written.file, bytes: written.bytes, pictures: embedded.pictures, ...(style ? { style } : {}), agentFolder, agentFolderPath: realpathSync.native(agentFolder) };
  }

  /**
   * Prints a page where it is, so the files beside it print, into a scratch folder, and writes the
   * PDF back as a new file.
   */
  async function printPdf(pageFile, pdfFile, size = "A4") {
    if (!/\.html?$/i.test(String(pageFile ?? ""))) return { ok: false, problem: "page_file must end in .html." };
    if (!["A4", "slide"].includes(size)) return { ok: false, problem: "size must be A4 or slide." };
    if (!/\.pdf$/i.test(String(pdfFile ?? ""))) return { ok: false, problem: "pdf_file must end in .pdf." };
    const page = readInside(pageFile);
    if (!page.ok) return page;
    const output = freeInside(pdfFile);
    if (!output.ok) return output;
    const scratch = mkdtempSync(join(tmpdir(), "okb-print-"));
    try {
      const target = join(scratch, "output.pdf");
      const ran = await python("print_pdf.py", [place(pageFile).path, target, ...(size === "slide" ? ["--size=slide"] : [])]);
      if (!ran.ok) return { ok: false, problem: ran.problem.replace(/^print_pdf\.py failed: /, "Nothing was written: ") };
      const written = writeInside(pdfFile, readFileSync(target));
      if (!written.ok) return written;
      const { pages, paper, pictures, markdown } = JSON.parse(ran.output);
      return { ok: true, file: written.file, bytes: written.bytes, pages, paper, pictures, markdown_findings: markdown, agentFolder, agentFolderPath: realpathSync.native(agentFolder) };
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }

  /** Runs the humanizer checks on a text, and gives each finding the line its words are on, or 0. */
  function checkText(textFile) {
    if (!/\.(md|txt)$/i.test(String(textFile ?? ""))) return { ok: false, problem: "text_file must end in .md or .txt." };
    const read = readInside(textFile);
    if (!read.ok) return read;
    const text = read.body.toString("utf-8").replaceAll("\r\n", "\n");
    const lines = text.split("\n");
    const findings = humanizerCheck(text).map(({ rule, at }) => {
      const words = String(at).replace(/^\d+ sentences: /, "");
      let line = 0;
      // An em-dash finding gives advice, not words, and a short word is found by itself.
      const short = rule === "em-dash" ? /[\u2014\u2013]/ : words.length <= 8 ? new RegExp(`\\b${words.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i") : null;
      if (short) return { rule, at, line: lines.findIndex(l => short.test(l)) + 1 };
      for (const size of [70, 50, 30]) {
        const probe = words.slice(0, size);
        const found = probe.length > 8 ? lines.flatMap((l, i) => (l.includes(probe) ? [i + 1] : [])) : [];
        if (found.length === 1 || (found.length && size === 30)) { line = found[0]; break; }
      }
      return { rule, at, line };
    });
    return { ok: true, file: place(textFile).shown, findings };
  }

  /** Writes a new workbook from `sheets` in a scratch folder, then creates it in the agent folder. */
  async function createWorkbook(newFile, sheets, model = {}) {
    const free = freeInside(newFile);
    if (!free.ok) return free;
    const scratch = mkdtempSync(join(tmpdir(), "okb-workbook-"));
    try {
      const target = join(scratch, "output.xlsx"), dataFile = join(scratch, "sheets.json");
      writeFileSync(dataFile, JSON.stringify({ sheets, ...model }), { mode: 0o600 });
      const ran = await python("create_workbook.py", [target, dataFile]);
      if (!ran.ok) return { ok: false, problem: ran.problem.replace(/^create_workbook\.py failed: /, "Nothing was written. ") };
      const body = readFileSync(target);
      const written = writeInside(newFile, body);
      if (!written.ok) return written;
      return { ok: true, file: written.file, bytes: written.bytes, sha256: createHash("sha256").update(body).digest("hex"), sheets: JSON.parse(ran.output).sheets,
        agentFolder, agentFolderPath: realpathSync.native(agentFolder) };
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }

  /** Copies each check.* sample into the agent folder, leaving a file already there, and naming one that differs. */
  function copySamples() {
    if (!agentFolder) return { ok: false, problem: NO_FOLDER };
    const copied = [], already = [], differs = [];
    for (const name of readdirSync(SAMPLES).filter(name => /^check\./.test(name)).sort()) {
      const sample = readFileSync(join(SAMPLES, name));
      const written = writeInside(join(agentFolder, name), sample);
      if (written.ok) { copied.push(name); continue; }
      if (!written.problem.endsWith("already exists. Name a new file; nothing is replaced.")) return written;
      // A file of the same name is kept; one that is not this release's sample is named, so the check runs on no old copy.
      const there = readInside(join(agentFolder, name));
      (there.ok && there.body.equals(sample) ? already : differs).push(name);
    }
    return { ok: true, copied, already, differs, agentFolder, agentFolderPath: realpathSync.native(agentFolder) };
  }

  async function callTool(name, args = {}) {
    try {
      if (name === "draw_graph") {
        const fromRecord = args.record_file !== undefined, fromProgress = args.progress_files !== undefined;
        if (fromRecord === fromProgress) return asContent({ ok: false, problem: "Give record_file for a model record, or progress_files for a plan, and not both." });
        if (fromProgress) {
          if (!Array.isArray(args.progress_files)) return asContent({ ok: false, problem: "progress_files must be a list of file paths." });
          if (args.group_by !== undefined) return asContent({ ok: false, problem: "A plan's graph is grouped by the parts of the plan; group_by is for a model record." });
          const extra = args.plan_id === undefined ? [] : [`--plan-id=${String(args.plan_id)}`];
          return asContent(await convert("plan_graph.py", args.progress_files.map(String), args.page_file, extra));
        }
        if (args.plan_id !== undefined) return asContent({ ok: false, problem: "plan_id goes with progress_files." });
        const extra = args.group_by === undefined ? [] : [`--group-by=${String(args.group_by)}`];
        return asContent(await convert("graph_page.py", args.record_file, args.page_file, extra));
      }
      if (name === "draw_search") {
        if (!String(args.question ?? "").trim()) return asContent({ ok: false, problem: "Give the question the search was asked." });
        const page = args.page_file ?? String(args.search_file ?? "").replace(/(\.json)?$/i, ".html");
        return asContent(await convert("search_page.py", args.search_file, page, [`--question=${String(args.question)}`]));
      }
      if (name === "draw_board") {
        const fromRecord = args.record_file !== undefined, fromProgress = args.progress_files !== undefined;
        if (fromRecord === fromProgress) return asContent({ ok: false, problem: "Give record_file for a model record, or progress_files for a plan, and not both." });
        if (fromRecord) {
          for (const key of ["plan_id", "purpose"]) if (args[key] !== undefined) return asContent({ ok: false, problem: `${key} goes with progress_files.` });
          if (args.layout !== "group" && args.layout !== "level") return asContent({ ok: false, problem: "layout must be group or level." });
          if (!String(args.by ?? "").trim()) return asContent({ ok: false, problem: "Name in by the node attribute to group by, or the relation to draw by level." });
          return asContent(await convert("model_board.py", args.record_file, args.page_file, [`--layout=${args.layout}`, `--by=${String(args.by)}`]));
        }
        if (args.layout !== undefined || args.by !== undefined) return asContent({ ok: false, problem: "layout and by go with record_file." });
        if (!Array.isArray(args.progress_files)) return asContent({ ok: false, problem: "progress_files must be a list of file paths." });
        const extra = [`--purpose=${String(args.purpose ?? "")}`];
        if (args.plan_id !== undefined) extra.push(`--plan-id=${String(args.plan_id)}`);
        return asContent(await convert("board_page.py", args.progress_files.map(String), args.page_file, extra));
      }
      if (name === "draw_state_machine") return asContent(await convert("model_to_page.py", args.record_file, args.page_file));
      if (name === "state_machine_payload") {
        // One argument, so a description starting with "-" is not taken for an option.
        const extra = args.description === undefined ? [] : [`--description=${String(args.description)}`];
        return asContent(await convert("page_to_model.py", args.page_file, args.payload_file, extra));
      }
      if (name === "draw_reference") return asContent(await convert("reference_page.py", args.reference_file, args.page_file));
      if (name === "draw_sop") {
        const picture = place(args.picture_file);
        if (!picture.ok) return asContent(picture);
        if (!/\.(png|jpe?g)$/i.test(String(args.picture_file))) return asContent({ ok: false, problem: "picture_file must be the .png draw_state_machine wrote." });
        const read = readInside(args.picture_file);
        if (!read.ok) return asContent(read);
        const extra = [`--picture=${basename(picture.path)}`, ...(args.version_id === undefined ? [] : [`--version-id=${String(args.version_id)}`])];
        return asContent(await convert("sop_page.py", [args.record_file, args.glossary_file], args.page_file, extra, undefined, [{ name: basename(picture.path), body: read.body }]));
      }
      if (name === "report_page") {
        if (!/\.md$/i.test(String(args.markdown_file ?? ""))) return asContent({ ok: false, problem: "markdown_file must end in .md." });
        if (!/\.html$/i.test(String(args.page_file ?? ""))) return asContent({ ok: false, problem: "page_file must end in .html." });
        for (const key of ["prepared_for", "prepared_by", "read_at", "project_owner"])
          if (!String(args[key] ?? "").trim()) return asContent({ ok: false, problem: `${key} is needed for the report's header.` });
        let pictures = [];
        const made = await convert("report_page.py", args.markdown_file, args.page_file, [`--for=${args.prepared_for}`, `--by=${args.prepared_by}`,
          `--read-at=${args.read_at}`, `--owner=${args.project_owner}`], undefined, [],
          body => { const embedded = embedPictures(body.toString("utf-8"), args.page_file); pictures = embedded.pictures ?? []; return embedded; });
        if (!made.ok) return asContent({ ...made, problem: made.problem.replace(/^report_page\.py failed: /, "Nothing was written: ") });
        const { output, ...rest } = made;
        return asContent({ ...rest, pictures });
      }
      if (name === "print_pdf") return asContent(await printPdf(args.page_file, args.pdf_file, args.size ?? "A4"));
      if (name === "embed_pictures") return asContent(embedInPage(args.page_file, args.new_file, args.style));
      if (name === "check_text") return asContent(checkText(args.text_file));
      if (name === "create_workbook") {
        if (!Array.isArray(args.sheets) || args.sheets.length === 0) return asContent({ ok: false, problem: "sheets must be a list of at least one sheet." });
        if (!String(args.new_file ?? "").toLowerCase().endsWith(".xlsx")) return asContent({ ok: false, problem: "new_file must end in .xlsx." });
        return asContent(await createWorkbook(args.new_file, args.sheets, { names: args.names, formats: args.formats, rules: args.rules }));
      }
      if (name === "edit_workbook") {
        if (!Array.isArray(args.edits) || args.edits.length === 0) return asContent({ ok: false, problem: "edits must be a list of at least one edit." });
        if (!String(args.new_file ?? "").toLowerCase().endsWith(".xlsx")) return asContent({ ok: false, problem: "new_file must end in .xlsx." });
        const edited = await convert("edit_workbook.py", args.workbook_file, args.new_file, [], { edits: args.edits, names: args.names, formats: args.formats, rules: args.rules });
        if (!edited.ok) return asContent({ ...edited, problem: edited.problem.replace(/^edit_workbook\.py failed: /, "Nothing was written. ") });
        const { output, ...rest } = edited;
        return asContent({ ...rest, sheets: JSON.parse(output).sheets });
      }
      if (name === "copy_samples") return asContent(copySamples());
      return asContent({ ok: false, problem: `No such tool: ${name}` });
    } catch (err) {
      return asContent({ ok: false, problem: `${name} failed: ${err instanceof Error ? err.message : String(err)}` });
    }
  }

  return { TOOLS, callTool };
}
