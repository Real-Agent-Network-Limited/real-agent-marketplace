---
name: code
description: Use when a person asks for analysis, a model, a cleaned or joined data set, or a chart from data. The agent runs Python or JavaScript with the okb plugin's run_code tool, on the agent folder and the folders added to the session. It builds a live Excel model with create_workbook and changes one with edit_workbook. It names each file it made, and uploads one to OKB only with the person's yes. It runs in one of three modes: human only, AI guided or human directed.
---

# Running code on data

The agent, such as the database operator, `@real-agent:database-operator`, runs code with the okb plugin's `run_code` tool. The code reads the files in the agent folder and in each folder added to the session when it started. It writes only the new files each run names, in the agent folder. It reads only the folders the session was started with, never one a call names. It reaches those folders and files alone: no other file, no program, no signal to another program and no network. A folder holding a link stops the run, and the refusal names the link.

- **Python** sees the agent folder as `/work`, its working folder, and each added folder as `/added/<folder name>`. It has pandas, numpy, scipy, matplotlib and openpyxl. The first Python run on a computer downloads Python from the firm's Plugins scope in OKB, signed in as the person, in under a minute. It keeps it in `.cache/okb-runtime` in the person's home folder, and each later run uses that copy. Real Agent publishes it there with `scripts/publish-runtime.mjs`.
- **JavaScript** is a Node.js module. The agent folder's full path is in `process.env.AGENT_FOLDER`, its working folder, and each added folder's is in `process.env.ADDED_FOLDERS`, as a list.

A run stops after 120 seconds, and what it prints is cut at 100 KB.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do the work in a spreadsheet program, such as Excel.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each step.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as which language to use. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## When to run code

The agent runs code for:

- analysis of a data set, such as totals, averages, trends or a comparison;
- a model worked out from data, such as a forecast fitted to past sales;
- a cleaned data set, such as one with duplicates removed and dates in one form;
- two or more files joined into one, such as viewings matched to properties;
- a chart drawn from data.

A live model the person changes, with inputs and formulas, is a workbook, as "Live workbook models" below says. Code works out the figures a live model starts from.

## 1. Find the data

- **Responsible:** the person.
- **Person:** opens the file in a spreadsheet program, and checks its columns and its first rows.
- **The agent:** finds the file in the agent folder, or in a folder added to the session. Runs code that prints the file's columns, its number of rows and its first five rows. Tells the person what the file holds, in one line per column it needs.
- **Evidence:** the columns and rows the run printed.

**AI guided:** the agent gives the person the columns it found, and waits for their approval.

## 2. Agree the result

- **Responsible:** the person.
- **Person:** writes down the result they want, and the name of each file it goes in.
- **The agent:** says what the code will work out. Names each file the run will make in the agent folder, such as `fees-model.xlsx` and `fees-chart.png`. Each name is a new one. Waits for the person's yes before a run that writes a file. Runs code that only prints at once.
- **Evidence:** the person's yes, and the file names.

**AI guided:** the agent gives the person the result and the file names, and waits for their yes.

## 3. Run the code

- **Responsible:** the agent.
- **Person:** works out the result in the spreadsheet program, with formulas, a pivot table or a chart. Saves it as a new file.
- **The agent:** calls `run_code` with `language`, `code`, and `new_files` set to each file step 2 named, as a full path in the agent folder. The code prints each figure the person needs to see, and writes each file it makes in the agent folder. Python saves a chart with matplotlib's `savefig`, and a table with pandas' `to_csv` or `to_excel`.
- **Evidence:** the run's `stdout`, and its `made` files.

When `ok` is false, the agent reads `stderr` and `problem`, puts the code right, and runs it again. After three runs that fail, it tells the person what stopped the run, in one line.

**AI guided:** the agent shows the person the code before it runs, and waits for their approval.

## 4. Give the result

- **Responsible:** the agent.
- **Person:** checks the figures and the chart in the spreadsheet program.
- **The agent:** gives the figures the run printed, and names each file in `made` by its full path. Names each file in `not_made` as one still to make. Asks the person to check the figures.
- **Evidence:** the figures, and each file's full path.

**AI guided:** the agent gives the person the figures and the files, and waits for their approval.

## 5. Upload a result to OKB

- **Responsible:** the person.
- **Person:** uploads the file to its scope in OKB: `okb upload_file bucket=<scope's code> path=<path> file=<file name>`, in the agent folder.
- **The agent:** uploads a file the run made only with the person's yes, in words in the chat. Before the upload, it shows one table: the file, made by the agent, the scope and the path, as the `okb:actor` skill's upload gives it. Then it calls `upload_file`.
- **Evidence:** the upload's result.

**AI guided:** the agent gives the person the file and the scope, and waits for their yes.

## Live workbook models

A live model is an Excel workbook a person works in: they change its inputs, and its formulas work out the rest when it opens. A fee calculator or a three-year forecast is one. The agent makes one with the okb plugin's `create_workbook` tool, and changes one with `edit_workbook`. Each writes a new workbook in the agent folder, and never replaces one.

The scripts beside this skill do the work, with Python 3. `create_workbook.py` makes a workbook, and `edit_workbook.py` changes one. Both use `workbook_model.py` for formulas, names, number formats and input rules.

A workbook is for a model a person works in, never for the glossary, the data dictionary or other reference data. Those stay in OKB, as the `okb:reference` skill keeps them.

1. **Agree the model.**
   - **Person:** writes down each input, each figure the model works out, and the workbook's name.
   - **The agent:** names the inputs, the figures and the new workbook, such as `fees-model.xlsx`, and waits for the person's yes.
2. **Build it.**
   - **Person:** builds the workbook in a spreadsheet program, with an Inputs sheet.
   - **The agent:** calls `create_workbook` with `new_file`, the sheets and their rows, and the model's `names`, `formats` and `rules`. The inputs go on a sheet of their own, named `Inputs`, each with its input rule and its name, such as `fee_rate` for `Inputs!B2`. Every other figure is a formula that uses the names, such as `=fee_rate*sale_price`, with its number format. Each formula's brackets, sheets and names are checked first. On any problem, nothing is written, and every problem is returned; the agent puts each one right and calls it again.
   - **Evidence:** the result's `file`, `sha256` and rows on each sheet.
3. **Change it.**
   - **Person:** changes the input or the row in the spreadsheet program, and saves it as a new file.
   - **The agent:** calls `edit_workbook` with the workbook as `workbook_file`, a new name as `new_file`, and the edits. Each edit is `{"sheet": "Inputs", "action": "change", "match": {"Input": "Fee rate"}, "row": {"Value": 0.02}}`, or an add with `row`. A workbook with formulas, names or rules keeps its row numbers: an added row goes after the last row, and a remove is refused.
   - **Evidence:** the result's rows added, removed and changed on each sheet.
4. **Check it.**
   - **Person:** opens the workbook, and checks each figure.
   - **The agent:** reads the workbook's inputs with `read_file`, and each formula with a run of openpyxl's `load_workbook`. A formula's cell stays empty until a spreadsheet program works it out. The agent gives the person each input and formula, and asks them to open the workbook in Excel and check the figures.

**AI guided:** the agent gives the person the inputs and the figures, and waits for their approval.

## Each refusal, and what the person does

- **"Access to this API has been restricted":** the code reached outside its folders, wrote an added folder, or used the network, a program or a signal. The agent tells the person, in one line, what the code tried and that the run refuses it. To use a file from elsewhere, the person adds its folder to a new session.
- **"PermissionError":** the code wrote a file outside `new_files`, an existing file, or an added folder. The agent names the file in `new_files`, with a new name in the agent folder, and runs the code again.
- **"The run stopped after 120 seconds":** the agent runs the code on a part of the data first, then on the rest in parts.
- **"is a link, and a run would read what it points to":** a folder the code reads holds a link. The person moves the link out of the folder, or replaces it with the file itself. The agent then runs the code again.
- **"The code made a folder in place of":** the code made a folder with a name `new_files` gives. The folder is deleted. The agent writes each named file as a file, and runs the code again.
- **"The Python runtime could not be downloaded":** the refusal says why. The person's sign-in ended, OKB was out of reach, or the firm's Plugins scope holds no runtime yet. The person signs in again, or raises it with Real Agent with the `real-agent:support` skill.
- **"a run never reads it":** a folder added to the session is the home folder or a folder holding it. Or it holds the person's keys, sign-ins or settings, such as `.ssh` or `.config`. The person starts a new session with a folder that holds only the data, such as `Downloads`.
- **"start with the same name":** two folders the run reads start with the same name, such as `okb` and `okb-notes`. Node.js then refuses the run the shorter one. The person renames one of them, or starts a new session without the added folder. The agent then runs the code again.
- **"needs Node.js 25 or later":** the computer's Node.js is older. The person updates it, as the refusal says, and starts a new session.
- **"Nothing was written.":** a workbook's sheet, formula, name, format or rule broke a rule, and each problem is listed. The agent puts each one right, and calls the tool again.
