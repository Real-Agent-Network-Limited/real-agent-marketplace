---
name: getting-started
description: Use when a new member of staff asks to get started, or for training or the next lesson. Teaches nine lessons in order, in the person's own folder and their firm's own records, from checking the computer to printing an SOP. Saves each lesson the person finishes as an evidence record. It runs in one of three modes: human only, AI guided or human directed.
---

# Getting started

Getting started teaches a new member of staff to work with Real Agent, in their own folder and in their firm's organisational knowledge base (OKB). OKB is the firm's own Supabase project: its records, its files, its glossary and its data dictionary. Every lesson uses the person's own records, so nothing is a demonstration. The firm's first session is a training call with Real Agent, and this skill can be run any time after it.

The lessons run in this order:

1. Checking your computer.
2. Claude desktop, and where to find the database operator.
3. A session in your folder, carried on from your phone.
4. Calling a workflow agent with `@`.
5. A question about your records.
6. Finding and uploading a file.
7. The first install, and updating with `plugins`.
8. A routine in each of the three modes.
9. Printing the glossary and an SOP.

Each lesson the person finishes is saved as an evidence record in the General scope, as section 1 describes. The person can stop after any lesson and carry on in a later session.

This skill sets the order, the wording and the checks. It uses the `okb:check`, `okb:records`, `okb:actor`, `okb:print` and `okb:writing` skills. It belongs to no one agent: any agent can run it. Usually the database operator, `@real-agent:database-operator`, runs it, and it saves through that agent's grants.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step in Claude desktop, on their phone and with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as the order of the lessons. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Before the first lesson

1. **Check who the person is.** The lessons need a folder that is signed in as the person.
   - **Person:** in their folder, in Terminal or PowerShell, runs `okb okb_get_actor`.
   - **The agent:** calls `whoami`, then `okb_get_actor`, as the `okb:actor` skill's section 2 describes. With no one signed in, it gives the person the sign-in from that skill, and stops until they say it is done.
2. **Find the lessons already finished.** Each one is an evidence record whose title starts "Getting started," and the person's name.
   - **Person:** runs `okb okb_get_scopes` for the General scope's id, then `okb okb_find_records p_kind=evidence p_scope_id=<General's id> p_title="Getting started <their name>"`.
   - **The agent:** calls `okb_get_scopes`, then `okb_find_records` with `p_kind` `evidence`, `p_scope_id` General's id and `p_title` "Getting started" and the person's name. It tells the person which lessons are done, and offers the first one that is not.
3. **Save each finished lesson.** At the end of each lesson, the person and the agent save one evidence record in General, with these fields:
   - The title is "Getting started, <name>: lesson <n>, <the lesson's name>", such as "Getting started, Alex Learner: lesson 5, a question about the records".
   - `summary` says what the person did and what they got, in a sentence or two. It quotes an answer or a message as it came.
   - `source_reference` is "Getting started, lesson <n>, <name>". `source_date` is today's date.
   - `standing` is `observed` when the agent read the result itself in this session, such as a tool's answer. It is `stated` when only the person reports it, such as what their phone showed.
   - `limitations` names any part of the lesson the person could not do, and why, or "none".
   - **Person:** runs `okb okb_add_record p_scope=general p_kind=evidence p_title="<title>" p_reason="Getting started lesson finished" p_fields.summary="<summary>" p_fields.source_reference="<source>" p_fields.source_date=<today> p_fields.standing=<standing> p_fields.limitations="<limitations>" p_preview=true`. They read the preview, then run the same command without `p_preview`.
   - **The agent:** calls `okb_add_record` with those fields and `p_preview` true, and shows the person the record, as the `okb:records` skill's section 3 describes. Once they agree, it calls `okb_save_version` with the preview's `request` and `authorisation_id`, unchanged. A refusal for a missing grant goes to the database admin, as that section says.
   - **Evidence:** the saved version's `version_id`.

**AI guided:** the agent gives the person the lessons done and the next one, and waits for their approval to begin it.

## 2. Lesson 1: Checking your computer

The database operator's own tools run on the person's computer. Python 3 draws its pages, and a browser takes their pictures and prints PDFs. Poppler, Tesseract, ImageMagick, FFmpeg and whisper.cpp read PDFs, scans, pictures, recordings and videos. The check uses each one on a sample file from the okb plugin, so a missing program is found before a later lesson needs it.

1. **Run the check.**
   - **Person:** types "Check this computer." Without the agent, follows the `okb:check` skill's Person lines.
   - **The agent:** follows the `okb:check` skill. It copies the samples with `copy_samples`, and uses each tool on its sample. It reports one line per program: working, missing, or checked only once another is installed.
2. **Install what is missing.**
   - **Person:** runs the install command the report gives for each missing program, quits and reopens Claude desktop, and asks for the check again.
   - **The agent:** gives the install command from each refusal, for the person's system. With every program working, it says so in one line.
3. **Save the lesson,** with the report's lines quoted, and `limitations` naming each program still missing.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 2.

## 3. Lesson 2: Claude desktop, and where to find the database operator

Claude desktop is Anthropic's app for the Mac and Windows. Its Code tab runs Claude Code: the person types a request, and an agent carries it out in a folder on the computer. The person's folder holds their sign-in to OKB, and its agent is the database operator.

1. **Open the folder in Claude desktop.**
   - **Person:** opens Claude desktop, picks the Code tab, and picks their folder, such as `okb` in their home folder.
   - **The agent:** gives the person the folder's full path, from `whoami`'s `agentFolderPath`.
2. **Meet the database operator.** It works in OKB as the person, within their own grants, and shows each change before saving it.
   - **Person:** types "Who am I?" in a new session.
   - **The agent:** answers as the database operator does: the person's name, the project and whether they are restricted to their grants.
   - In another folder, or in a session whose agent is not the database operator, the person types `@real-agent:database-operator` before the message.
3. **Save the lesson,** as section 1, step 3 says, with the answer the person got.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 3.

## 4. Lesson 3: A session in your folder, carried on from your phone

Each person starts a session in Claude desktop, on their office computer, in their folder. Remote Control lets them carry it on from the Claude app on their phone, while the office computer runs it. The firm's setup turned on "Connect new sessions to Remote Control" and "Keep this computer awake for Remote Control" on each office computer.

1. **Check both settings.**
   - **Person:** in Claude desktop's settings, opens Remote Control, and checks both settings are on.
   - **The agent:** none. It asks the person whether both are on. If one is off, the person turns it on, or asks the firm's administrator.
2. **Start a session in the folder, on the office computer.**
   - **Person:** starts a new Code session on their folder, and types "What is assigned to me?"
   - **The agent:** answers in that session, as lesson 5 describes.
3. **Carry it on from the phone.**
   - **Person:** opens the Claude app on their phone, signed in to the same Claude account. They open the session the office computer runs, and type "Thank you, that is all."
   - **The agent:** none. It asks the person what the phone showed, and whether the reply arrived in the same session on the office computer.
   - Starting a new session from the phone is a newer Claude feature that Real Agent has not yet tested. Until it has, the person starts each session on the office computer.
4. **Save the lesson,** with `standing` `stated`, since only the person can report what the phone showed.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 4.

## 5. Lesson 4: Calling a workflow agent with @

Each of the firm's workflows is one plugin with one agent, and each routine in it is one skill. The person calls an agent by typing `@` and its name, such as `@appraisal:appraisal`. Every folder has the business analyst, `@business-analyst:business-analyst`, which writes down the firm's routines.

1. **List the agents in the folder.**
   - **Person:** types `@` in a session, and reads the list Claude desktop offers.
   - **The agent:** asks the person which agents the list shows. It names the database operator, the database admin, the business analyst and each workflow agent among them.
2. **Call the business analyst with a question it answers without changing anything.**
   - **Person:** types `@business-analyst:business-analyst Is setup finished?`
   - **The agent:** none. The business analyst answers, from the setup skill's section 9. The agent asks the person for the answer.
3. **Save the lesson,** with the business analyst's answer quoted.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 5.

## 6. Lesson 5: A question about your records

The database operator answers only from what OKB returns: the firm's records and the passages its file search finds. If OKB holds no answer, it says so.

1. **Ask about the tasks assigned to the person.**
   - **Person:** types "What is assigned to me?" Without the agent, runs `okb okb_get_assigned`.
   - **The agent:** calls `okb_get_assigned`, as the `okb:records` skill's section 9 describes, and gives each task with its scope and finish date.
2. **Ask about a record the person knows.** A plan, a decision or a routine they have worked on will do.
   - **Person:** types a question such as "What does the record called Valuations say?" Without the agent, runs `okb okb_find_records p_title="<words of the title>"`, then `okb okb_show_record p_record="<record id>"`.
   - **The agent:** finds and reads the record with `okb_find_records` and `okb_get_record`, as the `okb:records` skill's section 2 describes. It names the record each part of the answer comes from.
3. **Save the lesson,** with the question and the answer quoted.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 6.

## 7. Lesson 6: Finding and uploading a file

Each scope keeps its files in a bucket of its own, named after the scope's code. The person uploads a file from their own folder, and OKB's file search finds it by the words and meaning of what it says.

1. **Choose a file the firm is happy to keep in General.** A price list or a branch leaflet will do. A file with a client's personal details will not.
   - **Person:** copies the file into their folder, directly, not into a folder within it.
   - **The agent:** asks the person for the file's name, and checks it is in `agentFiles` from `whoami`.
2. **Upload it.**
   - **Person:** in their folder, runs `okb upload_file bucket=general path=getting-started/<file name> file=<file name>`.
   - **The agent:** shows the person one table with the file, where it came from, the scope and the path. Once they agree, it calls `upload_file` as the `okb:actor` skill's section 3 describes. It then offers to read the file's parts waiting to be read for the graph, as that section says.
3. **Find it again.**
   - **Person:** runs `okb list_files bucket=general prefix=getting-started`, then `okb call_function name=file-search body.query="<words from the file>" result_file=search.json`, and reads `search.json`.
   - **The agent:** calls `list_files`, then searches with `call_function`, as the `okb:actor` skill's "Search results" describes. It gives the person the hit's file and section. If the search says the file is still waiting, the agent says so and searches again later.
4. **Save the lesson,** with the file's path and the search's hit.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 7.

## 8. Lesson 7: The first install, and updating with plugins

The first install comes from Real Agent's public marketplace. The person added it, installed the `real-agent` plugin, and signed in with `okb setup`, as the business analyst's setup skill describes. The last step of `okb setup` was `okb sync`. It installed the firm's own release of its plugins from the Plugins scope, in place of the public copy. After that, each update comes from the firm's own Supabase project. Real Agent publishes each release of the firm's plugins to the Plugins scope, and the `real-agent:plugins` skill installs it.

1. **See what is installed.**
   - **Person:** in Terminal or PowerShell, runs `claude plugin list`, and reads each plugin's version.
   - **The agent:** asks the person for the list, and names the `real-agent`, `okb` and `business-analyst` plugins and their versions.
2. **Update the plugins.** `okb sync` downloads the newest release from the Plugins scope and checks each file against the release's list. A release that fails the check is passed over for the next older one. It then updates each plugin installed from it, and prints each plugin's old and new version.
   - **Person:** in their folder, runs `okb sync`, and reads each plugin's line.
   - **The agent:** follows the `real-agent:plugins` skill with the person. It gives them each plugin's old and new version, and the release their copy is now at.
3. **Start a new session.** The new versions load in a new session.
   - **Person:** starts a new Code session on their folder.
   - **The agent:** tells the person to start a new Code session on their folder after this lesson is saved.
4. **Save the lesson,** with each plugin's old and new version and the release, from `okb sync`'s lines.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 8.

## 9. Lesson 8: A routine in each of the three modes

Every routine skill runs in three modes. In human only, the person does each step themselves, with the `okb` command. In AI guided, the agent leads the steps in order, and stops for the person's approval at each stage. In human directed, the person says what to do, and the agent does it.

The lesson uses one of the firm's routines, from a workflow agent the folder has. A firm with no workflow agent yet uses the `okb:records` skill's list of the tasks assigned to the person. It changes nothing.

1. **Choose the routine.**
   - **Person:** names a routine they do, or takes the list of their tasks.
   - **The agent:** lists the routines of the workflow agents the person named in lesson 4, and agrees one with them.
2. **Run it in human only.**
   - **Person:** follows the routine's Person lines with the `okb` command. For the list of tasks, runs `okb okb_get_assigned`.
   - **The agent:** none. It asks the person what they got.
3. **Run it in AI guided.**
   - **Person:** types "Guide me through" and the routine's name, such as "Guide me through what is assigned to me."
   - **The agent:** follows the routine's lines in AI guided mode. It says what each step does, shows its Person line, and waits at the end of each stage.
4. **Run it in human directed.**
   - **Person:** types an instruction, such as "List my tasks, soonest finish first."
   - **The agent:** does as told, and names once any rule of the routine the instruction departs from.
5. **Save the lesson,** with what each mode gave.
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lesson, and waits for their approval before lesson 9.

## 10. Lesson 9: Printing the glossary and an SOP

The glossary says what the firm's words mean. An SOP, a standard operating procedure, sets out one routine from its approved design. The database operator prints either as an A4 PDF in the person's folder.

1. **Print the glossary.**
   - **Person:** types "Print the glossary as a PDF." Without the agent, follows the `okb:print` skill's section 1.
   - **The agent:** follows the `okb:print` skill's section 1, and gives the person the PDF's path and page count. An empty glossary prints with a note that it holds no terms yet.
2. **Print an SOP for one routine.** It needs a routine whose design the firm has approved.
   - **Person:** types "Print the SOP for" and the routine's name. Without the agent, follows the `okb:print` skill's section 2.
   - **The agent:** follows the `okb:print` skill's section 2. With no approved routine, it says so, and prints nothing.
3. **Save the lesson,** with each PDF's name and page count. With no approved routine yet, `limitations` says "No routine is approved yet, so no SOP was printed".
   - **Person:** saves the lesson as section 1 says.
   - **The agent:** saves the lesson as section 1 says.

**AI guided:** the agent gives the person the saved lessons, all nine, and waits for their approval to close getting started.

## 11. When the person changes something

- **A lesson out of order:** run it, and save it under its own number.
- **A lesson done again:** save a new version of its evidence record, rather than a second record. Use `okb_change_record`, as the `okb:records` skill's section 11 describes.
- **A problem during a lesson:** offer the `real-agent:support` skill, which saves the problem for Real Agent. Save the lesson once it is done.
