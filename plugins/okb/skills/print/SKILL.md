---
name: print
description: Use when a person asks for the glossary, the data dictionary or an SOP for a routine as a PDF, or asks to print any document or a deck. The agent writes the glossary or data dictionary from OKB's current rows, or an SOP from the routine's approved model version, as an A4 page in the agent folder with the okb plugin's `draw_reference` or `draw_sop` tool. It writes any other document, such as a report, as a page itself. It prints the page with the okb plugin's `print_pdf` tool, to an A4 PDF or a deck's 16:9 slides, and checks the PDF before giving it.
---

# Printing to PDF

A document becomes a PDF in two steps. First it is written as an HTML page in the agent folder, laid out for A4 paper. Then the okb plugin's `print_pdf` tool prints that page to a new PDF beside it, with Google Chrome, Chromium or Microsoft Edge.

- The glossary and the data dictionary are written by the `draw_reference` tool, from the rows `okb_get_reference` returns, as section 1 says.
- An SOP, a standard operating procedure, for one routine is written by the `draw_sop` tool, from the routine's approved model version, as section 2 says.
- Any other document, such as a proposal or a roadmap, is written by the agent as a page, as section 3 says.
- An executive report is written in Markdown, and the okb plugin's `report_page` tool makes its page, as the real-agent-project plugin's `report` skill says. Its deck is a page of slides, which `print_pdf` prints with `size` `slide`.

The scripts beside this skill do the work, with Python 3.

- `reference_page.py` writes the glossary or the data dictionary page, for `draw_reference`.
- `sop_page.py` writes the SOP page, for `draw_sop`.
- `a4.py` holds the A4 page style both pages use.
- `print_pdf.py` prints a page to a PDF, for `print_pdf`. It finds the browser as the `okb:board` skill's `page_check.py` does. `pdf_text.py` reads the printed PDF's text, for its Markdown findings.
- `report_page.py` makes an executive report's page from its Markdown, for `report_page`, with `md_page.py` and the style in `report.css`. `report.css` also styles the report's graphics: the status strip, the flow, the timeline and the red and amber markers.
- `deck.css` is a deck's style: the slide frame, and the report's graphics at slide size. `embed_pictures` with `style` `deck` puts it in the deck's page, so the agent writes the page without it.

`print_pdf`:

- reads the page directly inside the agent folder, and writes the PDF as a new file there;
- opens the page where it is, so a picture beside it prints in place;
- refuses a page that loads a file from anywhere but beside it, or a missing file, and writes nothing;
- refuses a picture file that is not a PNG, JPEG, GIF or WebP picture, and writes nothing;
- refuses a print at any size but A4, portrait or landscape, and writes nothing;
- with `size` `slide`, prints a deck: each `<section class="slide">` is one 16:9 page. It refuses a deck whose pages are not 16:9, or whose page count is not its slides', and writes nothing;
- refuses a print that holds fewer pictures than the PNG, JPEG, GIF and WebP files the page names, and writes nothing;
- returns the PDF's path, its size, its page count, its paper and the pictures it holds;
- gives a finding in `markdown_findings` for each Markdown mark in the printed text, with its page and line. The marks are a heading's "#", "**", a backtick, a line starting "- " and "[text](address)". The check reads the document's prose. Code, in a mono font, is kept apart, and a line starting "- " counts where it starts a block. Where it cannot read a PDF, `markdown_findings` is `null`, and the PDF is checked by eye.

A page holds its pictures with the okb plugin's `embed_pictures` tool. It writes a new page with each picture beside the page inside it. The new page is one file, and shows its pictures wherever it is opened. `report_page` puts a report's pictures inside its page itself. `print_pdf` prints a page with its pictures inside it, and lists each by its file's name.

The agent, such as the database operator, `@real-agent:database-operator`, runs the scripts through the okb plugin's tools. Each tool writes new files directly inside the agent folder, and never replaces a file. The tools need Python 3, as the `okb:graph` skill sets out.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with a text editor, the `okb` command and a PDF reader.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and an **Agent** line.

With the agent, the person's own instruction replaces a rule of this skill, such as the page's style. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Print the glossary or the data dictionary

The glossary lists the firm's terms, its classes and its relationships, each with its meaning and other names; a relationship also names its two classes. The data dictionary lists each record kind with its class and meaning, and each field with its type, whether it is required, the glossary term it holds and the systems it comes from. Each is printed from the current rows in the `reference` scope, at the time it is read.

- **Responsible:** the agent, for the person who asked. The person must be able to read the `reference` scope.

1. **Agree the file names:** the reference file, such as `glossary.json`, the page, such as `glossary.html`, and the PDF, such as `glossary.pdf`. Each is a new file directly inside the agent folder. When a name is taken, add the next number to it.
   - **Person:** names the three files.
   - **Agent:** proposes the names, and waits for the person's agreement.
2. **Read the rows into a file.**
   - **Person:** runs `okb okb_get_reference p_part=glossary result_file=glossary.json` in the agent folder, or `p_part=dictionary` for the data dictionary.
   - **Agent:** calls `okb_get_reference` with `p_part` `glossary` or `dictionary`, and `result_file` set to the reference file's full path.
3. **Write the page.**
   - **Person:** runs `okb draw_reference reference_file=glossary.json page_file=glossary.html`.
   - **Agent:** calls `draw_reference` with `reference_file` and `page_file`, as full paths. The result gives the counts, such as terms, classes and relationships, or record kinds and fields.
4. **Check the outline and the picture.** The outline lists each class, relationship and term, or each record kind and its fields. An empty glossary or dictionary is a finding: it says the glossary holds no terms yet, or the dictionary no record kinds yet.
   - **Person:** reads `glossary.outline.md` and the picture `glossary.png`.
   - **Agent:** checks the page as the `okb:board` skill's "Check the page before giving it" says. With an empty glossary or dictionary, it tells the person, and prints only if they still want it.
5. **Print the page.**
   - **Person:** runs `okb print_pdf page_file=<full path>/glossary.html pdf_file=<full path>/glossary.pdf`.
   - **Agent:** calls `print_pdf` with `page_file` and `pdf_file`, as full paths.
6. **Check the PDF and give it,** as section 4 says. The PDF's paper is A4, and its page count is in the result.
- **Evidence:** the reference file, the page's counts and findings, and the PDF's path, page count and paper.

**AI guided:** the agent gives the person the counts and the outline before printing, and waits for their approval.

## 2. Print an SOP for one routine

An SOP is printed from the routine's approved model version. It holds the routine's purpose, its trigger, each state with who does it, what they do, the tool and the checks, the handovers, the exceptions, the drawn state machine, and the glossary terms it uses.

A routine's **approved model version** is a `proposed_target` model version that a decision record links to with `supports`, where the decision is made: its `decision` text and its `decided_on` date are set. The person can also name the version.

- **Responsible:** the agent, for the person who asked. The person must be able to read the routine's model and the `reference` scope.

1. **Find the approved model version.**
   - **Person:** names the routine, or the model version. Without the agent, they find the model with `okb okb_find_records p_kind=model p_title="<words of the routine's name>"`, and the decisions in its scope with `okb okb_find_records p_kind=decision p_scope_id=<scope id>`. They read each decision with `okb okb_get_record p_record_id=<decision record id>`, and take the one that is made and whose `links` hold a `supports` link to a `proposed_target` version of the model. That link's `target_version_id` is the approved version.
   - **Agent:** follows `okb:records` section 2, as the person's line says. With no made decision supporting a `proposed_target` version, it asks the person to name the version, and does not guess.
2. **Read the approved version into a file.**
   - **Person:** when the approved version is the model's latest, runs `okb okb_get_record p_record_id=<model record id> result_file=<routine>-model.json`. When it is an older version, runs `okb okb_get_history p_record_id=<model record id> result_file=<routine>-model-history-1.json`, reading each next page while the reply has a `next_cursor`, until a page holds the version.
   - **Agent:** calls `okb_get_record` with `result_file` set to a new file in the agent folder. When its `version`'s `version_id` is not the approved one, it calls `okb_get_history` instead, a new `result_file` for each page, until a page holds the approved version, and keeps that page as the model file.
3. **Read the glossary into a file.**
   - **Person:** runs `okb okb_get_reference p_part=glossary result_file=glossary.json`.
   - **Agent:** calls `okb_get_reference` with `p_part` `glossary` and `result_file` set to a new file.
4. **Draw the state machine.** `draw_state_machine` writes the routine's state machine page and, beside it, its picture `<name>.png`. The SOP shows that picture.
   - **Person:** runs `okb draw_state_machine record_file=<routine>-model.json page_file=<routine>-machine.html`. With a history page, they first copy the approved version, unchanged, into a new file of its own, and give that file as `record_file`. `draw_state_machine` takes a version on its own.
   - **Agent:** calls `draw_state_machine` with the model file and a new `page_file`, as the `okb:graph` skill's section 3 says. With a history page, it first copies the approved version, unchanged, into a new file of its own, and gives that file. It checks that the result's `picture_file` is there. With no picture, it tells the person that Google Chrome, Chromium or Microsoft Edge is needed, and stops.
5. **Write the SOP page.**
   - **Person:** runs `okb draw_sop record_file=<routine>-model.json glossary_file=glossary.json picture_file=<routine>-machine.png page_file=<routine>-sop.html`, adding `version_id=<approved version id>` when the model file is a page of `okb_get_history`.
   - **Agent:** calls `draw_sop` with `record_file`, `glossary_file`, `picture_file` and a new `page_file`, as full paths, and `version_id` when `record_file` is a history page.
6. **Check the outline and its findings.** The outline lists the purpose, the trigger, each state with who, the tool and the checks, the handovers, the exceptions, the state machine's picture and the terms the SOP uses. Its findings are:
   - a start or step state with no one named as doing it;
   - a state the model says nothing of, with no description of what is done;
   - a routine with no start state, so the SOP names no trigger.
   - **Person:** reads `<routine>-sop.outline.md`, with its findings at the end, and the picture `<routine>-sop.png`.
   - **Agent:** checks the page as the `okb:board` skill's "Check the page before giving it" says. It gives the person each finding. A finding in the model is put right in a new version of the model, which needs its own approval before it is printed as the SOP.
7. **Print the page.**
   - **Person:** runs `okb print_pdf page_file=<full path>/<routine>-sop.html pdf_file=<full path>/<routine>-sop.pdf`.
   - **Agent:** calls `print_pdf` with `page_file` and `pdf_file`, as full paths.
8. **Check the PDF and give it,** as section 4 says. The result's `pictures` holds the state machine's picture.
- **Evidence:** the decision record's `record_id` and `version_id`, the approved model version's `version_id`, the model and glossary files, the state machine page and its picture, the SOP's outline and findings, and the PDF's path, page count, paper and pictures.

**AI guided:** the agent gives the person the routine, its approved version and the decision that approved it before drawing, and waits for their approval. It gives the outline and findings before printing, and waits again.

Refusals from `draw_sop`:

- "the model file is a page of okb_get_history: name the approved version with version_id": give `version_id`.
- "the model file holds version …, not …": the model file holds a different version. Read the approved one.
- "the model has no states: it is not a routine model": the model is not a routine model. Name the routine's model.
- "the glossary file is not okb_get_reference's result for the glossary": read the glossary with `p_part` `glossary`.
- "picture_file must be the .png draw_state_machine wrote": give the `.png` beside the state machine page.

## 3. Print any other document

- **Responsible:** the agent, for the person who asked.

1. **Agree the file names:** the page, such as `valuation-routine-report.html`, and the PDF, such as `valuation-routine-report.pdf`. Each is a new file directly inside the agent folder. When a name is taken, add the next number to it.
   - **Person:** names the page and the PDF.
   - **Agent:** proposes both names, and waits for the person's agreement.
2. **Write the page** from the page below. Put the document's text in `<main>`. Keep the wording of a document the person already has, such as a Markdown file, word for word. Give each picture by its file name alone, such as `<img src="booking-and-preparation-v2.png" alt="…">`. Each picture is a file directly inside the agent folder. A drawn page is shown by its picture, `<name>.png`, which the drawing tools write.
   - **Person:** writes the page in a text editor, in the agent folder.
   - **Agent:** writes the page with `Write`.
3. **Print the page.**
   - **Person:** runs `okb print_pdf page_file=<full path>.html pdf_file=<full path>.pdf`.
   - **Agent:** calls `print_pdf` with `page_file` and `pdf_file`, as full paths.
4. **Check the PDF and give it,** as section 4 says.

**AI guided:** the agent gives the person the page's text before printing, and waits for their approval.

Start each page from this one. Change the title, and the text in `<main>`.

```html
<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<title>Booking and preparation: report</title>
<style>
  @page {
    size: A4;
    margin: 20mm 18mm 22mm;
    @bottom-center { content: counter(page) " of " counter(pages); font: 8pt "Helvetica Neue", Arial, sans-serif; color: #8f8d86; }
  }
  html { font: 10pt/1.5 "Helvetica Neue", Arial, sans-serif; color: #313131; }
  body { margin: 0; }
  h1 { font-size: 18pt; font-weight: 600; line-height: 1.2; margin: 0 0 6mm; }
  h2 { font-size: 12pt; font-weight: 600; line-height: 1.3; margin: 8mm 0 3mm; }
  h3 { font-size: 10.5pt; font-weight: 600; line-height: 1.3; margin: 5mm 0 2mm; }
  h1, h2, h3 { break-after: avoid; }
  strong, b { font-weight: 600; }
  code, pre { font-family: "IBM Plex Mono", ui-monospace, Menlo, monospace; font-size: 0.9em; }
  p, li { orphans: 3; widows: 3; }
  blockquote { margin: 4mm 0; padding: 2mm 5mm; border-left: 0.5pt solid rgba(31,30,29,.24); color: #5f5e5a; }
  table { width: 100%; border-collapse: collapse; font-size: 9pt; margin: 3mm 0; }
  th, td { border: 0.5pt solid rgba(31,30,29,.24); padding: 1.5mm 2mm; text-align: left; vertical-align: top; }
  th { background: #f0eee6; font-weight: 600; }
  tr, figure, blockquote { break-inside: avoid; }
  figure { margin: 4mm 0; }
  figure img { display: block; max-width: 100%; max-height: 220mm; margin: 0 auto; }
  figcaption { font-size: 8.5pt; color: #5f5e5a; margin-top: 2mm; }
  .page-break { break-before: page; }
  @media print { th { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
</style>
</head>
<body>
<main>
  <h1>Booking and preparation: report</h1>
  <p><strong>To:</strong> the branch manager<br><strong>From:</strong> the negotiator</p>
  <h2>1. Purpose</h2>
  <p>…</p>
  <figure>
    <img src="booking-and-preparation-v2.png" alt="Current state: booking and preparing a market appraisal">
    <figcaption>Figure 1: Current state: booking and preparing a market appraisal</figcaption>
  </figure>
</main>
</body>
</html>
```

- Keep `@page { size: A4; }`. For a wide table or drawing, use `size: A4 landscape;`.
- Let the text flow from page to page. Give a section `class="page-break"` to start it on a new page.
- Number the pages with the `@bottom-center` box.
- Keep each table, picture and quotation whole on one page with `break-inside: avoid`, as the page does. A table longer than a page breaks between its rows.
- Give each tinted cell or band `print-color-adjust: exact` under `@media print`. The browser prints it white otherwise.
- Give each picture a caption in `<figcaption>`, and the same text in its `alt`.

## 4. Check the PDF before giving it

1. **Read the PDF.**
   - **Person:** opens the PDF in a PDF reader.
   - **Agent:** reads it with `read_file`, which gives the PDF's text, page by page.
2. **Check the pages and the paper.** The result's `paper` is A4, portrait or landscape, or a deck's 16:9 slide, and its page count matches the PDF.
   - **Person:** reads the page count and the paper in the result of `okb print_pdf`.
   - **Agent:** checks the result's page count and paper.
3. **Check the sections.** Every heading and section of the document is there, in order, with its wording.
   - **Person:** reads each heading against the document.
   - **Agent:** checks each heading against the page's text.
4. **Clear the Markdown findings.** Each finding in `print_pdf`'s `markdown_findings` is a Markdown mark on the printed page. Put each one right in the page, and print a new PDF, until there is none.
   - **Person:** reads `markdown_findings` in the result of `okb print_pdf`.
   - **The agent:** reads `markdown_findings` in the result of `print_pdf`.
5. **Check the pictures.** `print_pdf`'s `pictures` names each picture the document shows, such as an SOP's state machine.
   - **Person:** reads the `pictures` list in the result of `okb print_pdf`, and finds each picture in the PDF.
   - **Agent:** checks the `pictures` list against the page's pictures.
6. **Give the result:** the PDF's path, its page count and the pictures it holds.
   - **Person:** notes the PDF's path, its page count and its pictures.
   - **Agent:** tells the person the PDF's path, its page count and the pictures it holds.

On a refusal from `print_pdf`, put the page right and print it again.

- "is not a file directly beside the page": a picture is given with a folder. Ask the person to move the picture directly into the agent folder, and give its name alone.
- "is not a PNG, JPEG, GIF or WebP picture" or "pictures the page names": a picture file is empty or damaged. Draw it again, or ask the person for a good copy.
- "not A4": put `@page { size: A4; }` back in the page's style.
- "not 16:9": put `deck.css` back in the deck's style, and print with `size` `slide`.
- "pages for its … slides": a slide's content runs past its 16:9 page. Cut its lines, or scale its figure down, and print again.

**AI guided:** the agent gives the person the result of each check, and waits for their approval before the PDF goes out.
