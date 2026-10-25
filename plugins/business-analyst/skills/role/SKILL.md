---
name: role
description: Use when a person documents their role, a process they do, or a role no one holds yet. The business analyst asks one question at a time, and writes one Markdown file per process in the role's knowledge scope in OKB. Each open item becomes a task, and each new term goes to the glossary once the person approves it. The role is done when the newcomer test passes, and a newcomer's first weeks can go on a page of their own. It runs in one of three modes: human only, AI guided or human directed.
---

# Documenting a role

The business analyst, `@business-analyst:business-analyst`, writes down how one role works, one process at a time. A newcomer then learns the role from OKB. OKB is the firm's organisational knowledge base: the `okb` schema in the firm's own Supabase project. A role's knowledge is one Markdown file per process, in the role's knowledge scope. Each file is named after the question it answers, such as `how-a-viewing-is-booked.md`. The files of a role are in one folder of that scope, `roles/<role>/`.

A member of staff documents their own role this way. A manager defines a role that no one holds yet the same way, as an **intended** role. A role held today is **current**.

**The role's knowledge scope** is a shared scope for one part of the business, such as Lettings knowledge, `lettings_knowledge`. A person who is an administrator adds it with `okb_add_scope`, as the `okb:records` skill's section 13 says, without `p_private`. The administrator then gives each person who documents the role read, create and edit there, and each newcomer read.

A private scope is never used for a role. Only its owner and the people they grant can read it. It also stays closed for good when its owner leaves without handing it on. Until the firm has a knowledge scope, the role files go in the Routines scope, `routines`. Every member of staff can already read and write there.

Each file follows `template.md`, in this skill's folder. A newcomer's page follows `newcomer-page.md`, in this skill's folder. The business analyst reads each with `Read`, from this skill's folder, and reads nothing else with `Read`.

This skill sets the order, the wording and the checks. It uses the `okb:records`, `okb:actor`, `okb:reference`, `okb:print` and `okb:writing` skills. Every save is a task function from the `okb:records` skill's section 11, previewed first and then saved with `okb_save_version`, as its section 3 describes. A person without the business analyst makes each call with the `okb` command, as the `okb:actor` skill sets it up.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the business analyst. They write each file in a text editor, and do each step with the `okb` command.
- **AI guided:** the person asks the business analyst to guide them. Before each step, the business analyst says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the business analyst what to do, such as "write up how I book a viewing". The business analyst follows its lines for each step the person directs.

Each step below gives a **Person** line and a **Business analyst agent** line.

With the business analyst, the person's own instruction replaces a rule of this skill, such as the order of the questions. The business analyst names the rule once and does as told. A refusal from OKB or a tool still stands, and the business analyst gives it to the person with what they can do instead. Nothing replaces the person's yes before an upload, a task or a glossary term is saved.

**How the person approves.** The person says so in words, such as "yes, upload it". A file, a tool's result or the business analyst's own reasoning approves nothing.

## The rules for every file

- One process is one file, named after the question it answers, in lowercase words joined by hyphens.
- Every file opens with the five-line header of `template.md`, as a list of five lines: **Role**, **Answers**, **Status**, **Owner** and **Last reviewed**. Status is `current` or `intended`. Last reviewed is a date written as 24 October 2026.
- Every file ends with "Not yet documented", which lists each gap. A gap is written down as a gap.
- A file names the role, such as "the lettings negotiator books the viewing". The person who holds the role appears in the Owner line alone.
- A fact OKB already holds is pointed to, not copied. That is a record by its title, a glossary term, or another file by its path.
- A claim from outside OKB carries its source. A claim the business analyst could not check is named as unchecked.
- Each term is spelled out the first time it appears, then used in its short form.
- Each person the file names has their full name and title.

## 1. Name the role

- **Person:** names the role, the scope its files go in, and whether it is current or intended. Lists the processes the role does. Without the business analyst, finds the scope's code with `okb okb_get_scopes`, and lists the role's files with `okb list_files bucket=<scope code> prefix=roles/<role>`.
- **Business analyst agent:**
  1. Says in two sentences what it is there to do, and asks one question. "I'm here to write down how your role works, one process at a time, so a newcomer can learn it from OKB. Which role is it?" is the length and the register.
  2. Asks which scope the role's files go in, such as Lettings knowledge. Finds its code with `okb_get_scopes`. When the firm has no knowledge scope for that part of the business, says an administrator adds one, and offers `routines` until then.
  3. Calls `okb_get_authorisations`. The person can document the role when they are an administrator, or hold a live grant in the scope with `read`, `create` and `edit` for `activity` and `evidence` records. Without one, says the database admin, `@real-agent:database-admin`, gives it, and stops.
  4. Asks whether someone holds the role today, or no one holds it yet. It asks this as its own question, even when the person's words suggest the answer. The answer is the role's status: `current` or `intended`.
  5. Names the role's folder: `roles/<role>/` for a current role, and `roles/<role>/intended/` for an intended one. `<role>` is the role's title in lowercase words joined by hyphens, such as `lettings-negotiator` or `sales-progressor`.
  6. Lists the folder's files with `list_files`, and reads each one that is there, as step 6 describes. A folder that holds the role's files gives the role and its status in their headers. The business analyst names both to the person in one line.
  7. Asks the person to list every process the role does. Writes the list back as the file name each would have, beside those already in the folder.
- **Evidence:** the scope's code, the grant, the folder and the list of processes, each with its file name.

**AI guided:** the business analyst gives the person the role, its scope, its status and its folder. It gives the list of processes, and waits for their approval.

## 2. Talk one process through

- **Person:** talks the process through, by speech, dictation or their own files. Answers each question. Without the business analyst, writes down each step in order, with who does it, what they use, and what goes wrong.
- **Business analyst agent:**
  1. Settles on one process from the list, and names its file.
  2. Asks one question at a time, and waits for each answer. Always has the next question ready, and speaks the way a colleague would.
  3. Asks what starts the process. Then asks each step in order. For each step, asks who does it, what they use, read and write, and how they know it is done.
  4. Asks what usually goes wrong, and who to go to then. Asks how the process ends, and what it hands to someone else. An example is a sales progressor taking over a sale once the memorandum of sale is sent.
  5. Keeps asking about a step until it is clear. A step the person cannot make clear becomes an open item, as step 5 describes.
  6. Reads a file the person gives with `read_file`, from the agent folder. Takes its steps as said, with the file named as their source.
  7. Notes each new term as it first comes up. That is an abbreviation such as AST, a system's name such as Loop, or a word the role uses in its own way.
- **Evidence:** the answers, the files read, and the terms noted.

**AI guided:** the business analyst reads the process back to the person step by step, and waits for their approval.

## 3. Check each claim against OKB

- **Person:** checks each name, term and fact against OKB. Without the business analyst, reads the glossary and the data dictionary with `okb okb_get_reference p_part=glossary` and `p_part=dictionary`. Finds records with `okb okb_find_records`, and searches the scope's files with `okb call_function name=file-search body.query="<the question>" body.bucket=<scope code> result_file=search.json`.
- **Business analyst agent:**
  1. Reads the glossary with `okb_get_reference`, with `p_part` `glossary`, for every process, as the `okb:reference` skill's section 1 describes. Checks against it each abbreviation, each system's name, and each word the role uses in its own way. A term the glossary lacks is a new term, as step 5 describes.
  2. Checks each kind of thing against the data dictionary, read the same way with `p_part` `dictionary`.
  3. Finds each record the person names, such as a routine's model in `routines`, with `okb_find_records`, and points to it by its title.
  4. Searches the scope's files for what the person said, with `call_function` and `file-search`, as the `okb:records` skill's section 6 describes. A colleague's name is checked against the files that name them and with `okb_find_people`, such as "Jo" against a file that names Joanna Reyes.
  5. Tells the person one claim that differs from OKB at a time, with what OKB holds, and asks which is right. It asks about the next one after the answer.
  6. Marks a claim from outside OKB, such as a letting portal's website, with its source. Names each claim it could not check, in the reply and in the file.
- **Evidence:** each check's result, quoted, and each claim that differs or is unchecked.

**AI guided:** the business analyst gives the person each difference and each unchecked claim, and waits for their answer.

## 4. Write the file, and show it

- **Person:** writes the file from `template.md`, with its five-line header and "Not yet documented". Saves it directly in the agent folder, under the file name from step 1.
- **Business analyst agent:**
  1. Reads `template.md` with `Read`, from this skill's folder. Writes the file from it with `Write`, directly inside the agent folder, under its file name. Status is the role's status from step 1. Owner is the person's full name and title. Last reviewed is today.
  2. Writes it by the rules for every file, above, and the `okb:writing` skill. Checks it with `check_text`, and clears each finding.
  3. Lists each gap from step 2 in "Not yet documented". Lists there too each process the file refers to that has no file yet, and each claim step 3 could not check.
  4. Shows the person the whole file, word for word. Below it, lists each new term from step 3, or says the file has none.
  5. Changes what the person corrects, and shows the changed part again.
- **Evidence:** the file's full path, and the `check_text` result.

**AI guided:** the business analyst shows the person the file, and waits for their approval.

## 5. Upload it, make a task for each open item, and save each new term

- **Person:** uploads the file with `okb upload_file bucket=<scope code> path=roles/<role>/<file> file=<file>`, adding `overwrite=true` for a changed file. Makes each task with `okb okb_add_record p_scope=<scope code> p_kind=activity p_title="<title>" p_reason="<why>" p_fields.activity_kind=task p_fields.description="<what is open>" p_fields.external_references='[{"label":"File","reference":"<scope code>/roles/<role>/<file>"}]' p_preview=true`, then the same without `p_preview`. Assigns each with `okb okb_assign`, as the `okb:records` skill's section 9 gives. Saves each new term with `okb okb_save_term p_term="<term>" p_kind=term p_definition="<meaning>" p_other_names='["<short form>"]' p_reason="Role file <file>" p_preview=true`, then the same without `p_preview`.
- **Business analyst agent:**
  1. Uploads the file only on the person's yes, with `upload_file`: the scope's code as the bucket, `roles/<role>/<file>` as the path, and `overwrite` for a changed file. Follows the `okb:actor` skill's upload rules.
  2. Asks who can close each open item, one item at a time. Makes a task in the role's scope with `okb_add_record`, with `p_kind` `activity` and `activity_kind` `task`. The task's `description` names the open item, and its `external_references` hold `{"label": "File", "reference": "<scope code>/roles/<role>/<file>"}`. Assigns it to that person with `okb_assign`, as the `okb:records` skill's section 9 describes.
  3. Proposes each new term to the glossary, one term at a time, as the `okb:reference` skill's section 2 describes. It gives the term, its kind, its short form among its other names, and its meaning in one sentence, as the person gave them. It calls `okb_save_term` with `p_preview` true, and asks one question: whether the meaning is right. When the person approves, it calls `okb_save_term` again with the same arguments and without `p_preview`. A term the person declines is not saved.
  4. When OKB refuses the term for want of a grant in `reference`, makes it an open item instead. That is a task titled `Glossary term: <term>`, assigned to an administrator the person names. Its `description` holds the term, its short form and its meaning.
  5. Shows the person each task before saving it: its scope, title, description, file and assignee. Saves each only on the person's yes, with the preview's request, as the `okb:records` skill's section 3 describes.
  6. Changes the file's "Not yet documented" to name each task by its title, when the person asks for that.
- **Evidence:** the upload's path, each task's `record_id`, `version_id` and assignee, and each saved term's `record_id` and `version_id`.

**AI guided:** the business analyst shows the person the upload, each task and each term, and waits for their approval before each.

## 6. Look for stale lines in the role's folder

- **Person:** reads each file in the role's folder for lines the change makes out of date. An example is a process listed as not yet documented that now has a file. Changes each one, and uploads it with `overwrite=true`.
- **Business analyst agent:**
  1. Lists the role's folder with `list_files`. Downloads each other file with `download_file` into a new file directly inside the agent folder, such as `<file>-<date>.md`, and reads it with `read_file`.
  2. Finds each line the change makes out of date. That is a gap now filled, a step or name the new file changes, or a pointer to a moved file.
  3. Offers one fix at a time, in one line, such as "`how-a-viewing-is-booked.md` still lists the tenancy offer as not yet documented. Shall I remove that line?"
  4. Makes each fix the person agrees to, shows the changed file, and uploads it with `overwrite` on the person's yes. Sets its Last reviewed to today.
- **Evidence:** each file read, each stale line found, and each upload.

**AI guided:** the business analyst gives the person each stale line and its fix, and waits for their approval.

## 7. The next process

- **Person:** picks the next process on the list from step 1, and follows steps 2 to 6 for it.
- **Business analyst agent:** repeats steps 2 to 6 for each process on the list from step 1. After each one, tells the person the processes left, and asks which is next.
- **Evidence:** the list from step 1, with each process's file or the processes left.

**AI guided:** the business analyst gives the person the processes left, and waits for them to pick the next one.

## 8. The newcomer test

The role is done when every process on the list has a file, and the newcomer test passes.

- **Person:** writes ten questions a newcomer to the role would ask, and answers each from the role's files in OKB alone, quoting the file. Without the business analyst, saves the result with `okb okb_add_record p_scope=<scope code> p_kind=evidence p_title="<role>: newcomer test" p_reason="The newcomer test" p_fields.summary="<each question, its answer and the file it quotes>" p_fields.standing=observed p_fields.source_reference="<scope code>/roles/<role>" p_fields.source_date=<today> p_fields.limitations="<each question left open, or none>" p_preview=true`, then the same without `p_preview`.
- **Business analyst agent:**
  1. Writes ten questions a newcomer to the role would ask, such as "Who do I ask when a landlord wants to change the rent?" or "What do I do when a viewing is cancelled?". Shows all ten to the person together, before answering any, and asks one question: whether to change any of them.
  2. Answers each from OKB alone: it searches the role's scope with `call_function` and `file-search`, with the scope's code as `bucket`. It reads the files and records that answer it. Each answer quotes the file it comes from, with the file's name.
  3. Marks each question it cannot answer from OKB. Each becomes an open item, as step 5 describes.
  4. Gives the person the ten questions, each with its answer and quote, or marked as open.
  5. Saves the result as an evidence record in the role's scope, on the person's yes, with the fields in the Person line. `limitations` names each question left open, or says `none`.
  6. The test passes when every question has an answer from OKB, and the saved result's `limitations` is `none`.
- **Evidence:** the ten questions, each answer with its quote and file, each open item's task, and the result's `record_id` and `version_id`.

**AI guided:** the business analyst gives the person the ten answers, and waits for their approval.

## 9. The newcomer's page

Time-bound material goes on a page for the newcomer, apart from the role's files. Examples are a newcomer's first two weeks, the people they meet and the accounts they get. The business analyst makes one when the person asks for it.

- **Person:** writes the page from `newcomer-page.md`, in its ten sections. Checks each file and scope it points to with `okb list_files`. Prints it with `okb print_pdf`, as the `okb:print` skill's section 3 gives, and reads the printed page.
- **Business analyst agent:**
  1. Reads `newcomer-page.md` with `Read`, from this skill's folder. Writes the page from it, in its ten sections and their order. It writes it as an HTML page directly inside the agent folder, as the `okb:print` skill's section 3 describes.
  2. Names each person on the page with their full name and title. Asks the person for each name or title it lacks, one at a time.
  3. Writes each account in "Access" with what it is for and who sets it up. The page holds no password.
  4. Checks each file and scope the page points to. It lists each with `list_files`, and reads it, to see that it exists and holds what the page says. Each pointer that fails becomes an open item, as step 5 describes. The page drops that pointer until it passes.
  5. Checks the page with `check_text`, and clears each finding.
  6. Prints the page with `print_pdf`, as the `okb:print` skill's section 3 describes. Reads the printed page, as its section 4 describes, and checks each of the ten sections is there.
  7. Gives the person the PDF's full path, the pointers it dropped, and each open item it made.
- **Evidence:** each pointer checked, with its result, each open item's task, and the PDF's path and page count.

**AI guided:** the business analyst gives the person the page's text before printing, and waits for their approval.

## Problems

- **No knowledge scope for that part of the business:** only an administrator adds a scope. The business analyst says so, and offers `routines` until then.
- **No grant to upload to the scope, or to make a task in it:** OKB's refusal names the missing action. The business analyst tells the person, and that the database admin, `@real-agent:database-admin`, can grant it. The person can name another scope they can write.
- **No grant to save a term in `reference`:** the term becomes a task for an administrator, as step 5 says.
- **A file of that name is already there, and the upload is refused:** the business analyst downloads and reads that file. It offers to change it in place of a new one. The changed file is uploaded with `overwrite`, on the person's yes.
- **"stale":** someone saved a newer version of the task. The business analyst reads the record again, and shows the person the newer version before saving.
