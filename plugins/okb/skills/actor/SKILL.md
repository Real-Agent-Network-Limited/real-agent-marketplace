---
name: actor
description: Use when a person's agent, or an autonomous agent, works in the firm's organisational knowledge base (OKB) as one actor. Covers setting up one folder per person, signing in with the actor's own account, and the okb command. Covers calling OKB's database functions, uploading, listing, downloading and reading files, and searching them and deleting one for good, within that actor's permissions.
---

# Actor

This skill lets an agent work in a firm's organisational knowledge base (OKB) as a single actor,
through the okb plugin's tools. OKB is the `okb` schema in the firm's own Supabase project. A
**tool** is an operation the plugin gives the agent, such as `rpc`. A **database function** is an
operation stored in the project's database, such as `okb_get_scopes`, and `rpc` calls one through
Supabase's REST API.

Changes go through the database operator, `@real-agent:database-operator`, or for an administrator
the business analyst, `@business-analyst:business-analyst`. Each asks before each change. A session that is
neither does not make changes itself with these tools.

An **actor** is a person, an agent or an application with access to the project. An actor signs in as a **Supabase
Auth user**: an account with an email address and password. What the actor may do is what OKB
grants that account.

## 1. One folder per person

One folder on the person's computer works in one firm's project as one person. The folder holds an
**actor file**, `.okb-actor.json`, which names the project and the person's email address. It holds no
password and no token.

The folder is the **agent folder**, the person's one folder for their agent.
The person puts files there for the agent, and the agent uploads files directly in it into Storage.
The agent also reads a call's JSON arguments there and writes its result there. It draws and
prints pages there, and reads the files the person gives it.

The okb plugin is normally installed as a dependency of the `real-agent` plugin. On its own, it is
installed with:

```sh
claude plugin install okb@real-agent
```

**The okb command.** A person works without the agent, and sets up a folder, with the `okb` command.
`okb` stands for this, on macOS and Linux:

```sh
node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs
```

On Windows, in PowerShell:

```powershell
node "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\cli\okb.mjs"
```

On macOS and Linux, this line, added to the shell's start-up file, such as `~/.zshrc`, lets the
person type `okb`:

```sh
alias okb="node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs"
```

On Windows, this line, added to the PowerShell profile, does the same:

```powershell
function okb { node "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\cli\okb.mjs" @args }
```

- **Responsible:** the person the agent works for; for an autonomous agent, whoever runs it.
- **Person:** sets up the folder in a command-line application, such as Terminal in macOS or
  PowerShell in Windows. Their own values go in place of the angle brackets:

  ```sh
  okb setup --folder <folder> --email <email> --url <project URL> --key <publishable key>
  ```

  It makes the folder, and sets the folder's agent, the database operator
  unless `--agent <plugin>:<agent>` names another. It installs that agent's plugin from the
  real-agent marketplace, and signs the person in, which writes the actor file. The project URL and
  publishable key come from the project administrator; without `--url` and `--key`, the sign-in asks
  for them. The first time, with a password an administrator created, the person adds
  `--new-password` and then chooses their own. Running it again is safe: each step says what it did,
  or that it was already done.

  A folder that already exists is signed in, and its actor file written, with:

  ```sh
  okb sign-in --folder <folder> --email <email>
  ```

  The folder is never inside a git repository, where its JSON and its uploads could be committed
  and pushed. Claude Code reads its settings when a session starts, so the person then starts a new
  session, opened on the folder.

  **The plugin's settings.** These are used only in a folder with no actor file. They are set with
  `--config <setting>=<value>` on `claude plugin install`, or with `claude`, then `/config`, in the
  okb plugin's row:

  | Setting | Value |
  |---|---|
  | **Project reference** (`project_ref`) | the 20-character code in the project's address, `https://<project reference>.supabase.co` |
  | **Auth user's email** (`auth_email`) | the email address the actor signs in with |
  | **Agent folder** (`agent_folder`) | the full path of the agent's one folder. The person puts files there for the agent, and the agent uploads from it; left unset, none of its uses is allowed |
  | **whisper.cpp program** (`whisper_cli`) | the full path of whisper.cpp's `whisper-cli` program, which transcribes recordings. Left unset, the plugin looks in `%LOCALAPPDATA%\okb\whisper\Release` on Windows, on the command path, and in `/opt/whisper.cpp` |
  | **whisper.cpp model** (`whisper_model`) | the full path of whisper.cpp's `ggml-base.bin` model. Left unset, the plugin looks in the install script's folder, `~/.local/share/okb/whisper` or `%LOCALAPPDATA%\okb\whisper`, then in Homebrew's whisper.cpp folder and in `/opt/whisper.cpp` |

  Claude Code refuses an empty value, and then saves none of the command's settings. The whisper.cpp
  settings apply in every folder.

- **Agent:** none. The folder and the settings belong to the person.
- **Evidence:** `okb setup`'s lines, and the agent's `whoami` result.

The plugin needs Node.js 26 on the computer that runs the agent. `okb setup` stops on another
version, and names the command that installs it.

## 2. Sign-in

Signing in links the agent to the actor's own account, so everything it does is done as that actor.

Signing in gives the plugin two tokens from Supabase, which work like keys. A short-lived token
lets the agent work for a limited time, which the project sets. A long-lived token lets the plugin
get a new pair without the password. The plugin keeps only the long-lived token, in a private file
on the computer: `~/.config/supabase-auth/<project reference>/<email>.json`. Only the person's own
computer account can read that file. The password is never stored.

Before each call, the plugin checks the short-lived token. When it is about to run out, the plugin
sends the long-lived token to Supabase for a new pair. It saves the new long-lived token in the file.

Supabase refuses the long-lived token once the project administrator bans or deletes the account.
The agent's next call then fails with a message giving Supabase's reason and the exact sign-in
command.

A person can check the session without the agent:

- The session file exists while the plugin holds a session. Deleting it ends the session on that
  computer once the current short-lived token runs out.
- The project administrator can see when the account last signed in.
- Running the sign-in again always starts a fresh session.

- **Responsible:** the person themselves; for an autonomous agent, whoever runs it.
- **Person:** in the folder, runs:

  ```sh
  okb sign-in
  ```

  In a folder already signed in, it signs in again as that folder's person, with the project's
  address and key saved at the first sign-in. It asks for the password. Nothing shows while the
  password is typed. `--new-password` replaces a password an administrator created with the person's
  own; a person who set their own password, such as the project's owner, leaves it out.
  `--url <project URL> --key <publishable key>` gives the project's address and key on the command
  line. In a folder not yet signed in, the person runs `okb sign-in --folder <folder> --email <email>`,
  as section 1 describes.
- **Agent:** calls `whoami`. If it responds with a sign-in command, gives the person that command
  exactly, and waits until they say it is done.
- **Evidence:** the command's "Signed in as" line, and the agent's `whoami` result.

## 3. Tools

The agent reads and changes OKB's data, and uploads and lists files, as the actor. The agent
uploads files directly inside the agent folder, where the person puts files for it and it saves its
own. The actor's permissions, and the person's yes before each upload, decide what is uploaded.

| Tool | What it does |
|---|---|
| `whoami` | the signed-in Auth user's id and email address, the project's reference, the agent folder, the newest 50 files directly inside it, newest first, as `agentFiles`, with how many there are as `agentFileCount`, and the schema `rpc` uses when a call names none, `okb` |
| `rpc` | calls a database function, with named arguments. `file_args` places JSON from files directly in the agent folder into the arguments, and `result_file` writes the result to a new file there, replying with a summary of its plain values. A reply of `refused` true is a refusal, given with its `problem` sentence, as a refusal the function raises is, and no result file is written |
| `call_function` | calls one of the project's hosted functions, with a JSON body. `result_file` writes the reply to a new file directly in the agent folder, replying with a summary of its plain values, as `rpc`'s does. A refusal gives the function's own `problem` sentence, and its whole reply as `body` |
| `upload_file` | uploads one file directly inside the agent folder into a Storage bucket. It refuses a hidden file, a link and a file in a folder within it |
| `list_files` | lists one folder of a Storage bucket, as far as the actor may see it |
| `download_file` | downloads one file from a Storage bucket into a new file directly in the agent folder, as "Downloading a file" describes |
| `read_file` | reads one file in the agent folder or in a folder within it, and gives the agent its content, or lists a folder there, as "Reading a file" describes |
| `copy_to_agent_folder` | copies one file from a folder added to the session when it started into a new file directly in the agent folder, for an upload or a page tool, as "A folder added to the session" describes |
| `check_plugins` | at the start of a session: each plugin installed from the real-agent marketplace that is behind the newest release in the Plugins scope, and what the session's folder holds, as "Connect a folder again" describes. It changes nothing |
| `update_plugins` | runs `okb sync` as the person, only when they ask to update their plugins |

The plugin's page tools draw and print pages in the agent folder from what OKB returns. The
`okb:board`, `okb:graph`, `okb:print`, `okb:reference` and `okb:writing` skills cover them.
In a folder with no one signed in, the plugin serves only its page tools, `run_code` and `check_plugins`.

- **Responsible:** the actor, and the person accountable for them.
- **Person:** shares a file in the chat, or puts it in the agent folder. Each scope's files are in
  its own bucket, named after the scope's code, and OKB decides who may use each one. Without the
  agent, the person runs each tool with the `okb` command. In the folder that holds the file,
  `okb upload_file bucket=<bucket> path=<path in the bucket> file=<file>` uploads it.
  `okb list_files bucket=<bucket> prefix=<folder>` lists a folder.
- **Agent:** calls the tools as the actor. A refusal from OKB, or from Storage, is the actor's
  permissions at work, and should be reported as it came. `rpc` calls a function in the `okb`
  schema when the call names no schema. Uploads read files directly in the agent folder, not in a
  folder within it. The agent uploads a file from where it is. A file the person shares in the chat
  is saved directly in the agent folder first, as it is, never retyped. Before uploading, the agent
  lists every file in one table: the file, where it came from, the scope and the path. Where it came
  from is one of: given by the person, made by the agent, or downloaded from a scope, with that
  scope's name. It lists only files the person named or asked for, and uploads them all after the
  person's one yes, in words in the chat. The agent uploads only files the person has given it or
  asked it to make, never one it found elsewhere on the computer. Uploads replace an existing file
  only when asked with `overwrite`. The agent then names the parts waiting to be read for the graph.
  It reads them after the person's yes, as the `okb:records` skill's section 18 describes. It calls `okb_get_unextracted` and `okb_save_extraction`. It reads in the person's own
  Claude subscription. `list_files` on a bucket that does not exist returns an empty list. A long
  result is cut short, and says so; a file over the plugin's size limit is refused, with the limit
  named.
- **Evidence:** each tool's result, quoted.

## A folder added to the session

The person can add a folder of their own to a session when they start it, such as their Downloads
folder. Claude Code writes the folders added at the start in the session's transcript, and the okb
plugin's hook reads them there. A folder added during a session is read in a new session.

The database operator and the business analyst read such a folder, read only. They find its files with
`Glob` and `Grep`, each given the folder's full path as `path`, and read a file with `Read`. They
write and change files in the agent folder alone. The agent copies a file into the agent folder with
`copy_to_agent_folder`, after the person's agreement. It then uploads the copy, or works on it with
a page tool.

- **Responsible:** the person who adds the folder.
- **Person:** adds the folder when they start the session, and names the file they want.
- **The agent:** names the folder in its first reply that uses it. It copies a file in only after the
  person's yes, and uploads it from the agent folder as section 3 describes.
- **Evidence:** the `copy_to_agent_folder` result, with the new file's path and SHA-256.

**AI guided:** the agent names the file it would copy and the new file's path, and waits for the
person's yes.

## Connect a folder again

A folder made with `okb setup` holds an actor file, `.okb-actor.json`, naming its person, and a
`.claude/settings.json` naming its agent. A reinstall can remove either, and the folder's own files
stay. A folder missing either is disconnected, and its sessions stop uploading. The same `okb setup`
command connects it again. `check_plugins` gives the folder as `sessionFolder` at the start of each
session.

1. **Name the folder and what it is missing.**
   - **Person:** asks why the folder's sessions are not uploading, or says the folder is not connected.
   - **The agent:** reads `sessionFolder` from `check_plugins`. When `connected` is false and
     `madeBySetup` is true, it names the folder by its full path, and says in one line what is
     missing: the sign-in, the agent, or both. When `uploadProblems` holds lines, it names the
     problem and its fix in one line.
2. **Fill in the folder, the email and the agent.**
   - **Person:** answers only what the agent asks.
   - **The agent:** reads `sessionFolder.reconnect`. It holds the folder's full path, the email and the
     agent, and where each came from:
     - The email: the account the folder's earlier sessions signed in as, or else the okb plugin's
       settings.
     - The agent: the folder's agent setting, or the agent of its earlier sessions, or else the agent
       the folder's name points to: the business analyst for a name with "admin" in it, and the
       database operator otherwise.
   - The agent names the email and the agent with where each came from, in one line. When `command`
     is null, it asks for the email before it gives the command.
3. **Run the command in the Terminal.**
   - **Person:** runs the command in Terminal on macOS and Linux, or in PowerShell on Windows. They
     type the password into the sign-in's own prompt. Then they start a new Code session on the
     folder, and type `who am I?`.
   - **The agent:** gives `sessionFolder.reconnect.command` as it is, in a code block, for the system
     `shell` names. It runs as pasted. With an answer from the person, such as another email or
     agent, it gives the command again with that value.

**AI guided:** the agent gives the person the command, and waits for them to say it has run.

## Reading a file

A person can give the agent a file to work from, such as a valuation report to build records from.
They put it in the agent folder, or in a folder within it, and the agent reads it with `read_file`.
Given a folder, `read_file` lists its folders and files, with each file's size. The agent reads only
files and folders inside the agent folder that are not hidden and are not links. It reads nothing
else on the computer this way, and writes nothing.

| Type | Files | What the agent is given |
|---|---|---|
| Text | `.md` `.txt` `.csv` `.tsv` `.json` `.jsonl` `.yaml` `.yml` `.xml` `.html` `.htm` | the text, up to 2,000 lines a call |
| Notebook | `.ipynb` | each cell's source and text output, in order |
| Picture | `.png` `.jpg` `.jpeg` `.gif` `.webp` `.heic` `.heif` `.tif` `.tiff` | the picture, with its longest side cut to 2,000 pixels |
| PDF | `.pdf` | each page's text, up to 20 pages a call. A page with no text, such as a scan, is read by character recognition, and says so |
| Word and similar | `.docx` `.odt` `.rtf` | the text |
| Spreadsheet | `.xlsx` `.ods` | each sheet's cells, under the sheet's name. Dates read as `YYYY-MM-DD`, times as `HH:MM`, and a duration as its total hours, such as `36:00` |
| Slide deck | `.pptx` `.odp` | each slide's text, by slide number |
| Recording | `.mp3` `.m4a` `.wav` `.aac` `.ogg` `.opus` `.flac` | what was said, with the time each part starts, and the language |
| Video | `.mp4` `.mov` `.m4v` `.webm` `.mkv` `.3gp` | still pictures every few seconds and at each change of scene, with what was said at their times |

- A file over 50 MB is refused, and so is a picture over 10 MB and a video over 5 minutes.
  A recording has no length limit, but its transcription stops after 20 minutes of work.
- A long text is given in parts of up to 100,000 characters. Each part says where the next one
  starts, with `offset`, and with `from` inside a line longer than one part. A long PDF is read 20 pages at a time, chosen with `pages`.
- Older `.doc`, `.xls` and `.ppt` files are refused. The person saves them in the newer format.
- Office files give their text only, not their layout, formulas, pictures or notes. When the person
  asks about those, the agent says so.
- The recording stays on the computer; nothing is sent to be transcribed.

PDFs, pictures, recordings and videos need programs on the computer. A PDF needs Poppler, and
Tesseract for a page with no text. A picture needs ImageMagick. A recording needs FFmpeg and
whisper.cpp. A video needs FFmpeg, and whisper.cpp for its speech. When one is missing, the agent is
told, with the line that adds it.

| Program | macOS | Windows | Debian and Ubuntu |
|---|---|---|---|
| `pdftotext`, `pdftoppm`, `pdfinfo` | `brew install poppler` | `winget install oschwartz10612.Poppler` | `sudo apt install poppler-utils` |
| `tesseract` | `brew install tesseract` | `winget install UB-Mannheim.TesseractOCR` | `sudo apt install tesseract-ocr` |
| `ffmpeg`, `ffprobe` | `brew install ffmpeg` | `winget install Gyan.FFmpeg` | `sudo apt install ffmpeg` |
| `magick`, or `convert` and `identify` on Debian and Ubuntu | `brew install imagemagick` | `winget install ImageMagick.ImageMagick` | `sudo apt install imagemagick libheif-plugin-libde265` |
| `whisper-cli` and its model | Real Agent's install script: `brew install whisper-cpp`, and `ggml-base.bin` in `~/.local/share/okb/whisper` | Real Agent's install script: whisper.cpp's `whisper-bin-x64.zip` and `ggml-base.bin` in `%LOCALAPPDATA%\okb\whisper` | whisper.cpp's `whisper-bin-ubuntu-x64.tar.gz`, and `ggml-base.bin` from its Hugging Face models |

The last column is for Debian 13 and Ubuntu 24.04, or later. Another Linux has the same programs in its own package manager.

The install script puts whisper.cpp where the plugin finds it. On Linux, the person saves the full
paths of `whisper-cli` and `ggml-base.bin` as the whisper.cpp settings in section 1. A program added with `winget install` is found only from a new
PowerShell window and a new session.

- **Responsible:** the person who gives the agent the file.
- **Person:** puts the file directly in the agent folder, and asks for what is to be made from it.
  Without the agent, opens the file in its own program.
- **Agent:** calls `read_file` with the file's full path. It reads the file only for what the
  person asked. A refusal is reported as it came, with the line that adds a missing program.
- **Evidence:** the `read_file` result.

## Downloading a file

The agent downloads a file from a Storage bucket with `download_file`, as the actor. OKB's storage
rules decide which files the actor may download. The file goes into a new file directly in the agent
folder, and the reply gives its full path, size, type and SHA-256. The agent can then read it with
`read_file`, and the person can open it there.

- A name already in the agent folder is refused before anything is downloaded. The agent names a new
  file.
- A file over 50 MB is refused, and nothing is kept.

- **Responsible:** the person who asks for the file.
- **Person:** asks for the file by its bucket and path, and opens it in the agent folder. Without the
  agent, runs `okb download_file bucket=<bucket> path=<path> file=<new file>` in the agent folder.
- **Agent:** calls `download_file` with the bucket, the path and the full path of a new file directly
  in the agent folder. Tells the person where the file is. A refusal is reported as it came.
- **Evidence:** the `download_file` result.

## Search results

In a project with file search set up, an agent searches the files the actor may open by calling `call_function` with the name `file-search`. It takes `{"query": "...", "bucket": "<bucket>", "limit": 1-50, "explain": true}`, of which only `query` is needed. A search's reply holds each hit's whole section, and is often too long for the agent to be shown. The agent gives each search a `result_file`, a new file in the agent folder, and reads it with `read_file`. The search returns:

- `hits`: each with its `bucket`, `file`, `place`, `snippet`, `found`, `fusion_score`, and `section`. `found` lists the ways that found it: `words`, `meaning` and `graph`. `section` is the position in `sections` of the section it falls in. `place` is a Markdown file's heading path, a page or a sheet, where the file has one. `ranks` gives the hit's rank in each of `words`, `meaning` and `graph`, null for a way that did not find it. `similarity` is its similarity to the question, 0 to 1, where the meaning search found it, and `graph_weight` its weight where the graph found it;
- `reference_hits`: the top hits from the buckets the project ranks apart, ranked on their own, in a search that names no bucket. They have the same shape as `hits`. In OKB, the reference scope's bucket is ranked apart, so these are the hits in the files kept in the reference scope. The glossary itself is a table, not a file, and is read with `okb_get_reference`, as the `okb:reference` skill says. Each list holds up to the search's `limit`. A search that names a bucket returns an empty `reference_hits`. A search that names no bucket leaves out the buckets searched only by name. In OKB, those are each person's sessions scope. Real Agent's guides are in the Guides scope's bucket, `guides`, which every actor reads. A search across every scope finds them among `hits`. A search naming `guides` finds them alone;
- `graph` in a hit's `found`: the graph search found it. The hit then names its `entities` and `relations`. These are the things the hit's part names, and the links between them, that the search reached from the question. Each has its `steps` from the things nearest the question, and the part's own `description` of it;
- `sections`: each section a hit in either list falls in, whole and once. The reference hits' sections come first, each in the order of its best hit. Each has its `bucket`, `file`, `place`, `text` and `truncated`. A section is a Markdown file's part under a heading, a PDF's page, a sheet, or the whole of any other file. `truncated` is true when the section was longer than a search returns, 8,000 characters. Its `text` is then the part of the section around its hits. A sheet's part starts with the sheet's first row, its column names, and holds whole rows. Any other part holds whole paragraphs. Such a section also has `start` and `end`, the part's place in the section, and `length`, the section's own. Its `before` and `after` count the characters left out on each side. The section's `text` is the passage to answer from; a hit's `snippet` shows where in it the search matched;
- `stages`: how many chunks each search found, how many were merged and returned, and how many files and chunks are still waiting for, or have failed, their text or their vector. `graph_seeds` lists the things nearest the question that the graph search started from, each with its `entity_id`. `graph_walk` lists each link the graph search walked, in order. Each gives `from` and `from_name`, the thing it was walked from, and `relation` and its `keywords`. It gives `to` and `to_name`, the thing it reached, and its `step` and `weight`. Each of a hit's `entities` has its `entity_id` too. `awaiting_extraction` counts the parts waiting for an agent to read them for the graph. The agent names them and offers to read them, as the `okb:records` skill's section 18 says. `awaiting_entity_vector` counts the things still waiting for their vector. `unsupported` and `no_text` count the files search cannot read. `unreadable` lists up to 20 of them the actor may open, each with its `bucket`, `file`, `state` and `error`. The `error` is the reason to tell the person. As `failed_worker_runs`, how many of the worker's runs went wrong in the last day and left work unfinished. A file or chunk such a run took is still waiting, or it took none. A run drops out once its work is done. `worker_problems` lists those runs, newest first. Each has its `job`, `called_at`, `answered_at`, `status`, `problem` and `files`. `files` holds each file the run took that the actor may open, with its `bucket` and `file`. `in_flight` is true for the file the run was at when it stopped;
- `degraded`: why the semantic search did not run, or empty when both ran;
- with `"explain": true`, `chunk` on each hit: its own part in its section's `text`, as `start` and `end`, in characters from 0. It is null where the section's part leaves it out. Each section's `marked` is its `text` with each of the question's words between the characters U+E000 and U+E001, null for a question with no words to search. Each hit also has `sentences`: the sentences of its own part that have their vectors. A person's sessions scope keeps no sentence vectors, so its hits have none. Each sentence has its `start` and `end` in its section's `text`, and its `similarity` to the question, 0 to 1. `explain_ms` is the time the measuring took, and `stages`' `awaiting_sentence_vector` counts the sentences still waiting for their vectors. The okb plugin's `draw_search` draws the result as a page, as the `okb:graph` skill's section 5 says.

## File deletion

A file deleted from its bucket drops out of search at once, but its text and embeddings stay in the database, where no user's search can reach them. They go only when the file is purged.

An agent removes a file for good by calling `call_function` with the name `file-search-purge` and a body of `{"bucket": "<bucket>", "file": "<the file's path>"}`. Storage deletes the file only if OKB's rules let the signed-in user delete it; only then are the file's text and embeddings deleted too. The answer says how many chunks went, or why Storage kept the file.

A purged file's versions stay, marked `purged`, as the record that it was indexed.

Without the agent, the person purges a file with `okb call_function name=file-search-purge body.bucket=<bucket> body.file=<path>`. A search is `okb call_function name=file-search body.query="<the question>" result_file=search.json`.

## Passwords

An agent should never ask for a password in chat, and never accept one that is offered. Anything
pasted into a conversation is kept in its transcript. If a password arrives anyway, the agent should
say plainly that it is now in the conversation record and that it is not using it. The person
should then change it. The agent should never repeat it back.

## Problems

- **The plugin has only its page tools and `check_plugins`:** no one is signed in for this folder.
  The folder has no actor file, and the plugin's settings name no person. A folder `okb setup` made
  is connected again as "Connect a folder again" describes. Any other folder is set up with `okb
  setup`, as section 1 describes, and the person starts a new session.
- **The plugin does not start, naming `.okb-actor.json`:** the actor file cannot be used. The person
  deletes it and signs in again with `--folder`.
- **`whoami` gives a sign-in command:** the session has ended, because the session file was deleted,
  it expired, or the password changed. The agent gives the person the command exactly; nothing in
  OKB is lost.
- **`whoami` names someone else, or another project:** the session was opened on another folder, or
  the actor file names another person. The person opens the session on their own folder, or signs
  it in again with `okb sign-in --folder <folder> --email <email>`, and starts a new session.
- **Sign-in refuses the email or password:** the person checks both; if they still fail, the
  project administrator resets the password, and the next sign-in adds `--new-password`.
- **An upload is refused as outside the agent folder:** the person moves the file directly into the
  agent folder. A file in a folder added to the session is copied in with `copy_to_agent_folder`. A
  file in an `uploads` folder an earlier setup made is moved up into the folder itself; `okb sync`
  names such a folder once.
- **A new computer, or the plugins removed:** the person installs the okb plugin again and runs
  `okb setup`, as section 1 describes. A session belongs to one computer.
- **A tool fails:** the cause is the session, the project, or the request itself, and the agent
  should say which.
- **Everything fails at once:** the project may be paused. The person should check with the
  project administrator.
