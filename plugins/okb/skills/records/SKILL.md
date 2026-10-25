---
name: records
description: Use when a person, or their agent, works in OKB's records as themselves. Covers scopes and grants, finding and reading records, history, progress, the audit log and sign-ins. Covers saving records, states, assigned tasks, approvals, the task functions, moving records, limited grants, renaming or deleting a scope, private scopes and access templates. Covers the graph of what a scope's files name. Each task names the database function the agent calls, and the `okb` command a person runs.
---

# OKB records

This skill is how a signed-in actor works in the records of OKB, the firm's organisational knowledge base. Changes to OKB are made by the database operator, `@real-agent:database-operator`, or for an administrator by the database admin, `@real-agent:database-admin`. Each follows this skill's rules on asking before each change. A session that is neither calls the database operator for each change. It passes on the person's answer, quoting their words with the change the agent proposed.

Every task is a call to one of OKB's database functions, in the `okb` schema, through the okb plugin's `rpc` tool, as the signed-in person. OKB itself decides what each call may see and change, from the actor's grants. A record the actor may not read is absent, and a change the actor may not make is refused.

A person without the agent makes each call with the `okb` command, as the `okb:actor` skill sets it up. Each step's **Person** line gives the command.

The **records** are activities, decisions, evidence and models, each in a **scope**. A record never changes in place: each change saves a new **version**, and every version stays in the record's history. OKB's work records data model sets the rules each kind follows.

A call looks like this, with the function's own argument names:

```json
{"function": "okb_get_scopes", "schema": "okb", "args": {"p_limit": 100}}
```

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and an **Agent** line.

With the agent, the person's own instruction replaces a rule of this skill, such as the order of the reads. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead. An autonomous agent follows the Agent lines, in human directed mode, with the person accountable for it as the person.

## 1. The actor, their scopes and grants

- **Responsible:** the actor.
- **Person:** asks who they are in OKB, or what they can work on. Without the agent, runs `okb okb_get_actor`, `okb okb_get_scopes` and `okb okb_get_authorisations`.
- **Agent:** calls `okb_get_actor` for the actor's own record. It gives the person their name, and whether they are an `administrator` or `restricted`. The record also holds whether they are a person, an agent or an application, and whether every save needs approval. It holds the person accountable for them. The agent gives these only when the person asks. A person who is an administrator can read and save in every scope that is not private, with no grant. They upload and delete its files too. An agent that is an administrator can read in every scope that is not private and handle its files. In a private scope, an administrator holds only the grants its owner gives, as section 20 describes. It still passes a grant's or an approval's id with every save. Every record deletion needs an approval, whoever makes it. A restricted actor can do only what their grants allow. Then calls `okb_get_scopes` for the scopes the actor may read, and `okb_get_authorisations` for the actor's own grants: each grant's scope, record kinds, actions and expiry. A grant is limited to the actor's own records when its `own_records` is true. A person who is an administrator usually holds none, and needs none. Both return `items`, and a `next_cursor` only when the page is full and there may be more; it is passed back as `p_cursor` for the next page. `okb_get_history` and `okb_get_progress`, in section 2, page the same way.
- **Evidence:** each call's result, quoted.

**AI guided:** the agent gives the person their actor record, scopes and grants, and waits for them before the next step.

## 2. Reading

- **Responsible:** the actor.
- **Person:** names a record, or asks about the work in a scope. Without the agent, runs `okb okb_find_records p_title="<words of the title>"`, then `okb okb_show_record p_record="<title or record id>"`. For a record's versions, runs `okb okb_get_history p_record_id=<record id>`. For a scope's work, runs `okb okb_get_progress p_cutoff=null p_observed_at=null p_cursor=null p_limit=100 p_scope_id=<scope id> result_file=progress-1.json`.
- **Agent:** calls:
  - `okb_find_records` to find a record the person names by its title or kind, with no record id. It lists each record the actor may read once, at its latest version, newest save first: `{"record_id", "kind", "scope_id", "title", "version_id", "version_number", "change_no", "saved_at", "saved_by"}`. It takes `p_kind`, one of `activity`, `decision`, `model` or `evidence`, `p_scope_id`, and `p_title`, words that must all appear in the title, in any case. Each is left out when not needed. Paging passes the answer's `cutoff` as `p_cutoff` and its `next_cursor` as `p_cursor`, while the answer has one. When more than one record fits, the agent lists each one's title, scope and when it was saved, and asks the person which they mean.
  - `okb_get_record` with `p_record_id` for a record's latest version and its links. A null answer means the record does not exist or the actor may not read it; the agent says exactly that, and nothing more. The person may name a file in the agent folder to read the record into, as the `okb:graph` skill does. The call then carries `result_file` with that file's full path. The `rpc` tool never replaces a file already there.
  - `okb_get_history` with `p_record_id` for every version, each with who saved it, when, why, and which fields changed. Paging passes the answer's `cutoff` as `p_cutoff` and its `next_cursor` as `p_cursor`, while the answer has one.
  - `okb_get_assigned` for the tasks assigned to the actor, as section 9 describes.
  - `okb_get_progress` for the activities the actor may read, with counts by state and each activity's dates, blockers and dependencies. For one scope, all five arguments are passed: `p_cutoff`, `p_observed_at`, `p_cursor`, `p_limit` and `p_scope_id`, with null for the ones not needed. Each activity carries its `state`, and its `parent` plan, `{"record_id", "referenced_version_id"}` or null, and its `evidence`: each evidence version its version links to as `supports`, `{"record_id", "referenced_version_id", "current_version_id", "title", "standing", "deleted"}`, or `[]`. Each activity also carries `assignee_name`, and each plan the person who created it, as `creator_actor_id` and `creator_name`. Each activity's `payload` names its owner in `owner_actor_id` and `owner_label`, as section 9 describes. To draw a plan as a board, the agent reads each page into a file with `result_file`, as the `okb:board` skill does.
- **Evidence:** each call's result, quoted.

**AI guided:** the agent gives the person what it read, with the call it made, and waits for them before the next step.

## 3. Saving a version

Every change, including a new record, is a call to `okb_save_version` with `p_request` and `p_authorisation_id`.

The request has exactly these keys, all of them, and no others:

| Key | Value |
|---|---|
| `request_id` | a new UUID for each change; the same one again only to retry a change whose answer was lost |
| `record_id` | a new UUID for a new record; the record's own for a new version |
| `scope_id` | the record's scope, set when it is created. A person who is an administrator can move it, as section 12 describes |
| `kind` | `activity`, `decision`, `evidence` or `model`, which never changes |
| `expected_previous_version_id` | null for a new record; otherwise the `version_id` of the latest version, from `okb_get_record` |
| `title` | the record's title |
| `reason` | why this change is made |
| `payload` | the record's fields, as its kind sets out below |
| `links` | every link this version has, `[]` for none: each `{"target_version_id", "relation"}`, with an optional `locator` and `note` |

A link's `relation` is `supports`, `describes`, `parent` or `depends_on`. It points at an exact version in the same scope. `parent` and `depends_on` join activities only, a `parent` is a plan, and an activity has at most one.

**Authority.** Every actor except a human administrator passes an id as `p_authorisation_id`. It is the id of a grant that covers the change. An actor that needs a person's approval for every save passes the approval's id, from section 5. A human administrator may leave it out.

The grant is found with `okb_get_authorisations`. It is a live grant in the record's scope, whose record kinds include the record's kind, and whose actions include every action the change needs. A new record needs `create`, and any new version needs `edit`. An activity's change of state also needs the action in section 4. A decision that is made or changed needs `decide`.

With no such grant, the agent saves nothing and says which action is missing. An administrator can grant it, or approve this exact change, as section 5 describes.

**Kinds.** Each payload has exactly these fields:

- **activity:**
  - `activity_kind`: `plan` or `task`, fixed once saved.
  - `state`: `pending`, `in_progress`, `paused`, `completed` or `cancelled`. A new activity is `pending`.
  - `owner_actor_id`: the id of the person who owns the activity, as section 9 describes. OKB writes their name into `owner_label`.
  - `description`, `completion_requirements` and `completion_note`.
  - `baseline_start_at`, `baseline_finish_at`, `forecast_start_at` and `forecast_finish_at`. Each is null, or a time with its time zone, such as `YYYY-MM-DDThh:mm:ssZ`. The baseline changes in any state, with the reason in `reason`.
  - `blockers`, each `{"blocker_id", "description"}`, and `external_references`, each `{"label", "reference"}`.
  - It may also carry `index`, one line of at most 20 characters. A task may carry `task_type`: `work`, `deliverable` or `blocker`.
  - A task may also carry `assignee_actor_id`, the id of the person it is assigned to, or null, as section 9 describes.
- **decision:** `question`, `alternatives` (a list of text), `decision` (empty while undecided), `rationale` and `decided_on` (a date, `YYYY-MM-DD`, or null while undecided).
- **evidence:** `summary`, `source_reference` (or null), `source_date` (a date, or null), `standing` (`stated`, `observed` or `unverified`) and `limitations`; optionally `file_sha256`, the file's SHA-256 checksum.
  - `source_reference` is a link, plain words or null. A link starts `https://`, in any case, with no `?` part, and may have a `#` part. Any other scheme with `://`, such as `http://`, is refused. Plain words name the source, such as `Vendor call, 10 Oct 11:00`. They start with neither `/` nor `\`, and hold no `..` between slashes. An external reference's `reference` is the same.
- **model:**
  - `model_kind`: `observed_current` or `proposed_target`.
  - `source_version`, `source_status` and `description`.
  - `graph`: `{"format_version": 1, "nodes": [...], "edges": [...]}`. Each node is `{"id", "type", "label", "attributes"}`, and each edge `{"id", "source", "target", "type", "attributes"}`. Every edge's source and target is a node's id.
  - The person may name a file in the agent folder that holds the payload, as the `okb:graph` skill does. The call then carries `file_args` `{"/p_request/payload": "<the file's full path>"}`, and the rest of the request in `args` as usual.
  - A saved version returns its whole payload. A large one is saved with `result_file` too, and the agent reports the ids from the reply's `summary`.

A new version carries the whole record again. The agent reads the latest version first, changes what the person asked for, and saves the rest as it was.

**Deliverables.** An activity's `completion_requirements` are its deliverables: what must exist for it to be completed.

- For a new activity, the agent asks the person for its deliverables, and shows any that the source document states.
- The person may leave them empty. The agent then tells the person the activity can be completed once its deliverables are written, in a new version.
- When the agent builds activities from a document, it takes what the document states. That is each activity's deliverables, dates and `depends_on` links, and nothing more.

**Index, deliverables and blockers.** A plan's board and graph are drawn from its activities, in index order.

- Each activity in a plan carries its `index`, kept apart from its title. A title carries no number.
- A part of the plan is `<n>`, such as `2`. A task is `<part>.<n>`, such as `2.2`. A deliverable is its task's index and a letter, such as `2.2a`. A blocker is its task's index, `-B` and a number, such as `2.2-B1`.
- Each task carries its `task_type`. A deliverable is its own task, with `task_type` `deliverable`, under the same plan as its task, and the task `depends_on` it.
- A blocker is its own task, with `task_type` `blocker`, under the same plan as the task it holds up, and that task `depends_on` it. The task also lists it in `blockers`, with `blocker_id` set to the blocker's own `record_id` and `description` set to its title.
- A blocker is cleared in two saves: the blocker is completed, and the task's next version leaves it out of `blockers`.
- Two activities in one plan never share an index.

- **Responsible:** the actor, and the person accountable for them.
- **Person:** says what to record or change, and approves the save before it is made. Without the agent, runs the task function from section 11 with `p_preview=true`, reads the change, then runs it again without `p_preview`.
- **Agent:**
  1. Calls the task function from section 11 with `p_preview` true. It names the record by its id. Its preview holds the request, with the latest version read and the grant found.
  2. Shows the person what it will save: the scope, the kind, the title, the reason, each field it changes, and the links. For an activity, it shows the deliverables, or "Deliverables: none". It saves only when the person agrees, and nothing they decline.
  3. Calls `okb_save_version` with the preview's `request` and `authorisation_id`, unchanged. A model's payload from a file is a request built as this section describes. When the answer is lost, it retries with the same request, unchanged. When the answer says the previous version is stale, it reads the record again and shows the person the newer version before trying again.
- **Evidence:** the saved version's `version_id` and `version_number`, and the call's result.

**AI guided:** the agent shows the person each save before it is made, and waits for their approval.

## 4. An activity's state

An activity moves between states only these ways, each needing its own action as well as `edit`:

| From | To | Action |
|---|---|---|
| pending | in_progress | `start` |
| in_progress | paused | `hold` |
| paused | in_progress | `start` |
| in_progress | completed | `complete` |
| completed | in_progress | `reopen` |
| pending, in_progress or paused | cancelled | `cancel` |

A person reads them as Pending, In progress, Paused, Completed and Cancelled.

A cancelled activity stays cancelled. Completing an activity needs its completion requirements and a completion note, no blockers, and at least one `supports` link to an evidence version. A save that changes a completed activity's completion requirements must also set its state to `in_progress`, which is the `reopen` action.

- **Responsible:** the actor.
- **Person:** asks for the change. Without the agent, runs `okb okb_set_state p_record="<title or record id>" p_state=<state> p_reason="<why>" p_preview=true`, then the same without `p_preview`. Completing adds `p_note="<completion note>"`.
- **Agent:** saves a new version with the new `state` with `okb_set_state`, as sections 3 and 11 describe.
- **Evidence:** as section 3.

**AI guided:** the agent shows the person each state change before saving, and waits for their approval.

## 5. Approving another actor's change

An administrator can approve an agent's exact change, once, instead of granting it standing permission. In a private scope, its owner approves in place of an administrator, as section 20 describes.

- **Responsible:** the administrator.
- **Person:** an administrator reviews the exact request the other agent will send. Without the agent, the administrator saves the request as `request.json` in their agent folder, and runs `okb okb_approve_change p_issuance_request_id=<new UUID> p_executor_id=<the other actor's id> p_request=@request.json p_expires_at=<time> p_reason="<why>"`.
- **Agent:** working for the administrator, calls `okb_approve_change` with a reason and these arguments. `p_issuance_request_id` is a new UUID, and `p_executor_id` the other actor's id. `p_request` is the exact request, and `p_expires_at` an expiry in the future. The other agent then calls `okb_save_version` with that request, unchanged, and the approval's `authorisation_id`. An approval is used once; any difference in the request is refused.
- **Evidence:** the approval's `authorisation_id`, and the save that used it.

**AI guided:** the agent shows the administrator the exact request before approving it, and waits for their approval.

## 6. Answering a question

- **Responsible:** the actor.
- **Person:** asks a question about OKB, its terms or its work. Without the agent, searches OKB's files with `okb call_function name=file-search body.query="<the question>" result_file=search.json`, and reads each hit's section in `search.json`. To see how a search found its answer, runs the same search with `body.explain=true`, then `okb draw_search search_file=search.json question="<the question>"`, and opens `search.html`.
- **Agent:** answers only from what OKB returns to it in this session:
  - For what one of the firm's words means, it reads the glossary before any file search. It calls `okb_get_reference` with `p_part` `glossary`, as the `okb:reference` skill's section 1 says. The glossary is a table in OKB, not a file, and file search never finds it. A definition comes from the term's row there, matched on its name or one of its other names, in any case. The agent names the glossary as its source.
  - For what OKB's documents say, it searches the files as the `okb:actor` skill's "Search results" describes. It calls `call_function` with the name `file-search`, and the question as `query`. Each search carries `result_file`, a new file in the agent folder named for the search, such as `search-<date>-<time>.json`. The agent reads that file with `read_file` before it answers. If the hits do not answer it, it searches again in other words.
  - A search across every scope returns two lists. `reference_hits` holds the top hits in the reference scope's files, ranked apart from everything else. `hits` holds the top hits from every other scope. The agent reads `reference_hits` first. A search across every scope leaves each person's sessions scope out. The agent searches one only when the person asks about an earlier session, as section 17 says. Real Agent's guides are in the Guides scope, `guides`. Every actor reads it, and only Real Agent's actor changes it. For a how-to question, the agent searches it by name, with `"bucket": "guides"`.
  - For records and the work, it reads them as section 2 describes.
  - A hit found by the graph, with `graph` among its `found`, names the `entities` and `relations` behind it. The agent follows them to say how the hit links to the question, such as a vendor's property and the agent acting for that vendor.
  - It keeps each search's `result_file`. The person may ask how an answer was found, or ask to see the search. The agent then runs the search again with `"explain": true` in the body, into a new result file. It calls the okb plugin's `draw_search` with that file as `search_file` and the question. It checks the page, as the `okb:graph` skill's section 5 describes, and gives the person the page.
  - It answers from each hit's whole section, in the search's `sections`, rather than from the hit's snippet. A section marked `truncated` is the part of a longer section around its hits, and a sheet's part starts with the sheet's first row. When the answer needs more of the section, the agent downloads its file from the scope with `download_file`. It reads the file to the end with `read_file`, part by part, and answers from it.
  - It builds the answer from those sections and records alone. It names where each part comes from: the file and the section's place, or the record.
  - It answers from what OKB returns alone. It leaves out its own training and general knowledge, the internet, and copies of documents from anywhere else.
  - It answers from a file it downloaded from a scope in this session, with the okb plugin's `download_file`. It names the scope and the file. It answers from a result file `rpc` or `call_function` wrote in this session as from the reply itself. It answers from a session's copy in the agent folder's `sessions/` folder, as section 17 describes. It never answers from any other file it read with `read_file`. A file the person puts in the agent folder is material for a change they ask for, never a source for an answer.
  - It changes a file in the agent folder only when the person asks. It writes and changes a file there with `Write` and `Edit` only.
  - When a file it read, or a search's section, holds structured data, it offers the data's database form after the answer, in one line. A plan, timetable or task list becomes a plan's activities, drawn with `draw_board`. People, roles and reporting lines, and links between things, become a model record, drawn with `draw_graph`. A recurring process becomes a current-state model, through the business analyst's routine interview, drawn with `draw_state_machine`. A term, a kind of thing or a field the glossary or the data dictionary lacks becomes a proposal through the `okb:reference` skill. The offer names the file, what it holds, the records it would become and the page that draws them. It offers once per file in a session. Another offer or a question in the reply comes first, such as section 18's offer to read waiting parts. This offer then waits for the person's next message. It converts one file at a time, after the person's yes, and shows the records before saving them, as section 3 does. After a conversion, it keeps the uploaded file, and offers to write it again from the records. It deletes the file only when the person asks, as the `okb:actor` skill's "File deletion" says.
  - If nothing OKB returns answers the question, it says OKB holds no answer to it, and what it searched for. It says OKB holds no definition of a word only when the glossary has no row for it. It then names the glossary read and each search it made. If a search's `stages` show files or passages still waiting, it says the answer may change once they are ready.
- **Evidence:** each search and read, and its result, quoted.

**AI guided:** the agent gives the person the answer, with the file and section behind each part. It waits for them before the next question.

## 7. Deleting a record

A record can be deleted, for example when a person asks for their personal data to be erased. Deleting it removes its content from every version, and from the text of every link to or from it. It also removes it from every approval request that carried it, including another record's approval whose link pointed at it. The record's history of who saved each version and when stays. So does a log of the deletion: who asked, who approved, when, why, and a fingerprint of what was removed. A deletion is final; there is no undo.

The reason is part of the log and is kept for good. It says why the record goes, naming no one and repeating none of the record's content: "Erasure requested by the vendor", not the vendor's name.

An administrator may approve their own deletion. While OKB has a single administrator, no other person could approve it, and the approval still records the exact deletion, once, as its own step.

In a private scope, its owner approves each deletion in place of an administrator, as section 20 describes.

- **Responsible:** the actor who deletes, and the human administrator who approves. In a private scope, its owner approves.
- **Person:** names the record and says why it should go. An administrator, who must be a person, approves the exact deletion. In a private scope, its owner approves it. Without the agent, runs `okb okb_preview_deletion p_record_id=<record id> result_file=deletion.json`, puts the reason into the request's `reason` in `deletion.json`, and saves the request alone as `request.json`. The administrator, or in a private scope its owner, approves it as section 5 describes, and the person runs `okb okb_delete_record p_request=@request.json p_authorisation_id=<approval id>`.
- **Agent:**
  1. Calls `okb_preview_deletion` with `p_record_id`. The answer shows the record's title, and how many versions, links and approvals would be emptied. It shows the `dependents`, the records whose latest version links to it, and the `request` to approve. The dependents may include records the person cannot read; the agent gives their number, and the ids of those the person can read.
  2. Shows the person all of that, in plain words, and says that the deletion cannot be undone. Waits for their agreement and their reason.
  3. Puts the reason into the request's `reason`, changing nothing else.
  4. Asks for the approval. If the person is an administrator, the agent, working for them, calls `okb_approve_change` with the request, as section 5 describes, naming the person as `p_executor_id`. Otherwise the person asks an administrator, whose own agent approves it. In a private scope, the owner's agent approves it in the same way, and a person who is not the owner asks the owner.
  5. Calls `okb_delete_record` with the request, unchanged, as `p_request`, and the approval's `authorisation_id`. The answer is the deletion's log entry: how many versions, links and approvals were emptied, and the `content_sha256`.
- **Evidence:** the preview, the approval, and the deletion's log entry.

Records that link to a deleted record keep their links, which now point to a deleted record. Only the link's note and locator are emptied. A linking record's own content, such as its summary or description, stays. If it repeats what was deleted, that record needs its own deletion or a new version. An approval not yet used whose request carried the record is emptied too, and the save it approved can no longer be made. A save that links to a deleted record is refused, and needs a new request without that link.

Files are separate: deleting a record, even an evidence record, leaves its files, and deleting a file is its own action, as "Files" describes.

**AI guided:** the agent shows the person the preview, the approval and the deletion, each before it is made. It waits for their approval at each.

## 8. The audit log

OKB keeps a log of what happened in it:
- each save, deletion and move of a record;
- each grant or approval given, and each grant revoked;
- each change to an actor;
- each change to a scope's name or description, and each deletion of a scope;
- each upload, replacement, move and deletion of a file in a scope;
- each sign-in, sign-out and expired session;
- each change OKB refused for want of permission;
- each change to an access template.

An administrator sees every event outside a private scope, including each deletion of a scope, and in a private scope their own. Anyone else sees:
- the saves and deletions of records they may read, and the moves of records they may read in either scope;
- the grants and approvals given to them, and changes to their own actor;
- the file events, and the changes to a scope's name or description, in scopes where they may read;
- the changes OKB refused them;
- each change to an access template.

A private scope's owner also sees each change OKB refused in it.

- **Responsible:** the actor.
- **Person:** asks what happened in OKB over a period. Without the agent, runs `okb okb_get_audit p_from=<start> p_to=<end>`, with each time as `<date>T<time><offset from UTC>`, and passes the answer's `next_cursor` as `p_cursor=<cursor>`.
- **Agent:**
  1. Turns the period into a start and an end, in UK time unless the person names another time zone, and calls `okb_get_audit` with `p_from` and `p_to`. It passes the answer's `next_cursor` back as `p_cursor`, while the answer has one. If there are more than a few pages, it says how many events it has so far and asks before reading on.
  2. Reports the events in time order. Each has its time, who did it, what they did, and to which record, file or person, in the scope it names. `actor_name` is who did it. For a deletion, it also names who approved it and the reason.
     A file event's `attributed_by` says how its actor is known:
     - `sign_in`: the person signed in to the change.
     - `storage_owner`: Storage made the change, and recorded no one signed in. The actor named is the file's owner, as Storage has it, who may be someone other than the one who made this change. The agent says "the file's owner, per Storage", never that they made it. With no actor named, the owner is not an OKB actor; the agent says so.
     - `none` with the `login` `supabase_storage_admin`: Storage made the change, and the person was not recorded; the agent says so.
     - `none` with any other `login`: the change came from outside OKB, such as the Supabase dashboard; the agent says so.

     A `signed_in`, `signed_out` or `session_expired` event names the person or agent as `actor_name`, with the session's `user_agent` and `ip`. `session_expired` is a session Supabase removed after it timed out, with no one signing out.

     A `change_refused` event is a change OKB refused and undid. `actor_name` is who was refused, `function` the function called, `kind` and `record_id` the record where the call named one, and `problem` OKB's message. Its scope is given only to someone who may see the scope.

     An `access_template_changed` event names the template as its subject, with `old_grants` and `new_grants`. A `scope_handed_on` event names the new owner, with `old_owner_name` and `new_owner_name`.
  3. For a record's full history, calls `okb_get_history` with the event's `record_id`, as section 2 describes.
- **Evidence:** each call's result, quoted.

**AI guided:** the agent gives the person the events, and waits for them before reading another page.

## 9. An activity's owner and a task's assignee

Every activity has one owner, the person accountable for it. The owner is an enabled person in OKB who can read activities in the activity's scope.

A save names the owner in `owner_actor_id`, and OKB writes the owner's name into `owner_label`. A save with no owner, or with an owner who is not such a person, is refused. A new activity made with `okb_add_record` is owned by the person the actor answers to, unless `p_fields` names an owner. A blocker or deliverable made with `okb_add_blocker` or `okb_add_deliverable` is owned by its task's owner.

A task can also be assigned to one person: a person in OKB who can read activities in its scope. The assignee is the person doing the task, and the owner the person accountable for it.

**Setting an owner.** Setting or changing an owner is a new version of the activity, as section 3 describes, with `owner_actor_id` set to the person's `actor_id`. It needs `edit`. Owning an activity gives the person no grant.

- **Responsible:** the actor, and the person accountable for them.
- **Person:** names the person who owns the activity. Without the agent, runs `okb okb_set_owner p_record="<activity title or record id>" p_person="<words of their name>" p_reason="<why>" p_preview=true`, then the same without `p_preview`.
- **Agent:**
  1. Calls `okb_find_people` with `p_scope_id`, the activity's scope, and `p_name`, the words of the name the person gave.
  2. When more than one fits, lists their names and asks the person which they mean. When none fits, says so, and that an administrator can add them to OKB or give them read in the scope.
  3. Calls `okb_set_owner` with `p_preview` true and the person's name as `p_person`. Shows the save as section 3 describes, with the owner's name in place of their id, and the name of the owner it replaces.
  4. Saves only when the person agrees, with the preview's request, as section 3 describes.
- **Evidence:** the saved version, and the activity's history, where `owner_actor_id` is among the changed fields.

**Activities without a valid owner.** `okb_find_unowned` with `p_scope_id` lists the activities in the scope that the actor may read and that lack a valid owner. That is an activity whose latest version has no owner, or an owner who is no longer an enabled person who can read the scope. Each item carries `record_id`, `index`, `title`, `activity_kind`, `owner_actor_id` and `owner_label`, the name saved on it, as text.

- **Responsible:** the administrator, after any change to grants.
- **Person:** names the owner of each activity listed.
- **Agent:**
  1. Calls `okb_find_unowned` for each scope the actor may read that holds activities.
  2. For each activity listed, shows its index, title and the name saved in `owner_label`, and the person in `okb_find_people` whose name matches it, if one does.
  3. Asks the person who owns each, and sets each owner with `okb_set_owner`, as "Setting an owner" describes, only with the person's approval.
  4. Calls `okb_find_unowned` again, and reports what it still lists.
- **Evidence:** each call's result, quoted, and each saved version.

**Assigning a task.** Assigning, reassigning and removing an assignee is a new version of the task, as section 3 describes, with `assignee_actor_id` set to the person's `actor_id`, or null. It needs `edit`, or `create` for a new task. Being assigned a task gives the person no grant.

- **Responsible:** the actor, and the person accountable for them.
- **Person:** names the person the task is for. Without the agent, runs `okb okb_assign p_record="<task title or record id>" p_person="<words of their name>" p_reason="<why>" p_preview=true`, then the same without `p_preview`. `okb okb_find_people p_scope_id=<scope id>` lists the people a task in the scope can be assigned to.
- **Agent:**
  1. Calls `okb_find_people` with `p_scope_id`, the task's scope, and `p_name`, the words of the name the person gave. It lists the people a task in that scope can be assigned to, `{"actor_id", "display_name"}`, and none when the actor cannot read the scope.
  2. When more than one fits, lists their names and asks the person which they mean. When none fits, says so, and that an administrator can give that person read in the scope.
  3. Calls `okb_assign` with `p_preview` true and the person's name as `p_person`, and shows the save as section 3 describes, with the assignee's name, never their id. A reassignment also names the person the task moves from.
  4. Saves only when the person agrees, with the preview's request, as section 3 describes.
- **Evidence:** the saved version, and the task's history, where `assignee_actor_id` is among the changed fields.

**The tasks assigned to the actor.** `okb_get_assigned` lists the tasks assigned to the actor that they may read, at their latest version, soonest finish first. It leaves out completed and cancelled tasks unless `p_include_closed` is true. Each item carries `record_id`, `scope_id`, `scope_name`, `title`, `version_id`, `version_number`, `index`, `state`, `description`, `completion_requirements`, `baseline_finish_at`, `forecast_finish_at`, `overdue_seconds`, `blockers`, `parent` (`{"record_id", "title"}` or null) and `unfinished_dependencies`, a count. Paging passes the answer's `cutoff` as `p_cutoff` and its `next_cursor` as `p_cursor`, while the answer has one.

- **Responsible:** the actor.
- **Person:** asks what is theirs to do. Without the agent, runs `okb okb_get_assigned`.
- **Agent:** calls `okb_get_assigned`, and reads a task the person picks with `okb_get_record`.
- **Evidence:** each call's result, quoted.

**AI guided:** the agent shows the person each assignment before saving it, and waits for their approval.

## 10. Who has signed in

`okb_get_sign_ins` lists each person and agent with an OKB login, latest activity first. It needs an administrator. Anyone else is refused with `Administrator required`.

Each item carries `actor_id`, `actor_name`, `actor_kind`, `authority_class`, `enabled`, `email`, `login_created_at`, `last_sign_in_at`, `last_active_at`, `open_sessions` and `latest_session` (`{"signed_in_at", "user_agent", "ip"}` or null). `last_sign_in_at` changes only when the person signs in again. `last_active_at` is the latest time a session was renewed, which happens about once an hour while it is in use.

- **Responsible:** an administrator.
- **Person:** asks who has used OKB, or when someone last used it. Without the agent, an administrator runs `okb okb_get_sign_ins`.
- **Agent:**
  1. Calls `okb_get_sign_ins` with no arguments: `{"function": "okb_get_sign_ins", "schema": "okb", "args": {}}`.
  2. Shows each actor's name, kind, last activity and last sign-in in UK time, and their open sessions. An actor with no sign-in is shown as never signed in.
  3. For sign-ins and sign-outs over a period, reads the audit log, as section 8 describes.
- **Evidence:** the call's result, quoted.

**AI guided:** the agent gives the person each actor's sign-ins, and waits for them before the next step.

## 11. Task functions

Each task function makes one change to a record and saves it with `okb_save_version`, as section 3 describes.

- A record is named by its record id, or by its exact title in any case, among the records the actor may read. A title that fits more than one is refused, with each one's title, scope, last save and id.
- A scope is named by its id, its code or its name.
- A record keeps its other fields and its links, unless the function changes them.
- The grant is the actor's live grant that covers the change, soonest expiry first. A person who is an administrator needs none.
- `p_preview` true saves nothing, and returns `request`, `authorisation_id` and `actions`: the exact request and grant the save would use. Without it, the function saves, and returns the saved version.
- An actor whose every save needs a person's approval gets the preview, and is refused the save. An administrator approves the preview's request, as section 5 describes.

| Function | Arguments | The change |
|---|---|---|
| `okb_show_record` | `p_record` | None. It reads the latest version, its scope's name, and each link with the title and index of its target's latest version. |
| `okb_add_record` | `p_scope`, `p_kind`, `p_title`, `p_reason`, `p_fields`, `p_parent` | A new record. A field not given is empty, and a new task's `task_type` is `work`. `p_parent` names its plan. |
| `okb_change_record` | `p_record`, `p_reason`, `p_fields`, `p_title` | The fields given, and the title when one is given. |
| `okb_set_state` | `p_record`, `p_state`, `p_reason`, `p_note` | An activity's state, as section 4 sets out. `p_note` is the completion note. |
| `okb_link` | `p_record`, `p_target`, `p_relation`, `p_reason`, `p_note`, `p_locator` | A link to the target's latest version. It replaces the record's link of that relation to the same record, and a `parent` replaces the parent. |
| `okb_unlink` | `p_record`, `p_target`, `p_relation`, `p_reason` | The record's link of that relation to the target, removed. |
| `okb_assign` | `p_record`, `p_person`, `p_reason` | A task's assignee, by words of their name, as section 9 describes. Null removes the assignee. |
| `okb_set_owner` | `p_record`, `p_person`, `p_reason` | An activity's owner, by words of their name, as section 9 describes. |
| `okb_add_blocker` | `p_task`, `p_title`, `p_requirements`, `p_reason` | A blocker under the task's plan, at the task's index with `-B` and the next number. `p_requirements` is what clears it. The task depends on it and lists it in `blockers`. |
| `okb_add_deliverable` | `p_task`, `p_title`, `p_requirements`, `p_reason` | A deliverable under the task's plan, at the task's index and the next letter. The task depends on it. |
| `okb_clear_blocker` | `p_blocker`, `p_note`, `p_evidence`, `p_reason` | The blocker started if pending or paused, then completed with the note and a `supports` link to the evidence record `p_evidence`, and taken out of each task's `blockers`. |

`okb_add_blocker`, `okb_add_deliverable` and `okb_clear_blocker` make their saves together, all or none. Their preview lists the saves, with no requests. An actor whose every save needs an approval makes each save with the single-save functions instead. The evidence that a blocker is cleared is saved first, as an evidence record.

- **Responsible:** the actor, and the person accountable for them.
- **Person:** names the record and the change. Without the agent, runs the function with `p_preview=true`, reads the change, then runs it again without `p_preview`. Each argument is `<argument>=<value>`, and each field `p_fields.<field>=<value>`:
  - `okb okb_add_record p_scope=<scope> p_kind=<kind> p_title="<title>" p_reason="<why>" p_fields.<field>="<value>" p_parent="<plan>" p_preview=true`
  - `okb okb_change_record p_record="<record>" p_reason="<why>" p_fields.<field>="<value>" p_preview=true`
  - `okb okb_link p_record="<record>" p_target="<target record>" p_relation=<relation> p_reason="<why>" p_preview=true`
  - `okb okb_add_blocker p_task="<task>" p_title="<blocker title>" p_requirements="<what clears it>" p_reason="<why>" p_preview=true`
  - `okb okb_clear_blocker p_blocker="<blocker>" p_note="<how it was cleared>" p_evidence="<evidence record>" p_reason="<why>" p_preview=true`
- **Agent:** calls the function with `p_preview` true, and shows the person the change as section 3 describes. When the person agrees, calls `okb_save_version` with the preview's `request` and `authorisation_id`, unchanged. A function that makes several saves, it calls once without `p_preview`, after the person agrees.
- **Evidence:** the preview, and the saved version.

**AI guided:** the agent shows the person each preview before the save, and waits for their approval.

## 12. Moving records to another scope

A person who is an administrator can move a set of records from one scope to another. A private scope's owner moves records into and out of it, as section 20 describes. Each record keeps its id, its versions, its links and its history. Its scope changes, and the move is logged.

- Every record in a move is in the same scope.
- Every link to or from a record in the move is from or to another record in the move. Each link between a record in the move and a record outside it is named in `outside_links`, and the move is refused. Add it to the move, or save a version without the link.
- `refused` names each record that is deleted, holds a glossary term or a record kind of the data dictionary, or is named by a live grant or an unused approval. The move is then refused. An administrator revokes such a grant first, with `okb_revoke_authorisation`.
- `losing_access` lists each person and agent who can read a record in the old scope and cannot read it in the new one. `gaining_access` lists the reverse. Each entry names the records.
- The move is refused if anything in the preview has changed. Preview it again.
- Files stay in their scope. A record that names a file in the old scope keeps that name.

- **Responsible:** the person who is an administrator, or, in a private scope, its owner.
- **Person:** names the records, the scope to move them to, and the reason. Without the agent, in Terminal, runs the preview, reads `move.json`, then runs the move:

  ```sh
  okb okb_preview_move p_records='["<title or record id>","<title or record id>"]' p_to_scope="<scope name>" p_reason="<why>" result_file=move.json
  ```

  ```sh
  okb okb_move_records p_request=@move.json
  ```

  On Windows, in PowerShell, puts the list of records in a file first:

  ```powershell
  Set-Content records.json '["<title or record id>","<title or record id>"]'
  okb okb_preview_move p_records=@records.json p_to_scope="<scope name>" p_reason="<why>" result_file=move.json
  ```

- **Agent:**
  1. Asks for the reason, then calls `okb_preview_move` with `p_records`, a list of titles or record ids, `p_to_scope` and `p_reason`.
  2. Shows the person the records, the two scopes, `outside_links`, `refused`, `losing_access` and `gaining_access`, in plain words. When `outside_links` or `refused` is not empty, says what to add, link or revoke, and previews again.
  3. Waits for the person's agreement.
  4. Calls `okb_move_records` with the preview, unchanged, as `p_request`. The answer names each record moved, the two scopes, the time and the reason.
- **Evidence:** the preview, and the move's answer. The audit log, section 8, lists each record moved as `record_moved`.

**AI guided:** the agent shows the person the preview before the move, and waits for their approval.

## 13. Adding a scope

A person who is an administrator can add a scope. The database makes its private bucket for files, and the audit log shows it as `scope_created`, with who added it, when and why.

- The code is lower case letters, digits and underscores, starting with a letter, at most 63 characters. It never changes.
- A code or name used by another scope as its name or its code is refused, in any case.
- A name, a description of what the scope covers and a reason are required.
- A scope can be made private, for the owner the administrator names, as section 20 describes.

- **Responsible:** the person who is an administrator.
- **Person:** gives the code, the name, what the scope covers and the reason. Without the agent, in Terminal or PowerShell, runs:

  ```sh
  okb okb_add_scope p_code="<code>" p_display_name="<name>" p_description="<what it covers>" p_reason="<why>"
  ```

- **Agent:** shows the person the code, name and description, and calls `okb_add_scope` once they agree. The answer names the scope's id and code, its name and description, who added it, when and why. No one holds a grant in the new scope until one is given.
- **Evidence:** the new scope in `okb_get_scopes`, and its `scope_created` entry in `okb_get_audit`.

## 14. Renaming a scope

A person who is an administrator can change a scope's name, its description, or both. A private scope's owner changes its own. The scope keeps its id, its code and its files, and its records and grants stay with it. Each change is logged.

- The scope is named by its id, its code or its current name, in any case.
- A new name used by another scope as its name or its code is refused, in any case.
- A reason is required. A call that changes nothing is refused.

- **Responsible:** the person who is an administrator, or, in a private scope, its owner.
- **Person:** names the scope, the new name or description, and the reason. Without the agent, in Terminal or PowerShell, runs this command. For a new description, adds `p_description="<new description>"`:

  ```sh
  okb okb_rename_scope p_scope="<scope name>" p_display_name="<new name>" p_reason="<why>"
  ```

- **Agent:**
  1. Asks for the reason, then shows the person the scope's current name and description, from `okb_get_scopes`, beside the new ones.
  2. Waits for the person's agreement.
  3. Calls `okb_rename_scope` with `p_scope`, `p_display_name`, `p_description` where it changes, and `p_reason`. The answer names the scope's id and code, its old and new name and description, the time and the reason.
- **Evidence:** the answer. The audit log, section 8, lists each field changed as `scope_renamed`, with `field`, `old_value` and `new_value`.

**AI guided:** the agent shows the person the old and new name and description before the change, and waits for their approval.

## 15. A grant limited to a person's own records

A person who is an administrator can limit a grant to the holder's own records. The holder reads, creates, edits, starts and cancels only the records that the holder, or an agent working for the holder, created. A record created by anyone else is absent from the holder's lists, progress, audit log and assigned tasks, and a change to it is refused.

- A limited grant carries `read`, and any of `create`, `edit`, `start`, `hold`, `complete`, `reopen`, `cancel` and `decide`.
- A limited grant carries no `delete`, covers no single record, and gives no access to the scope's files.
- A link from a record to a record the holder cannot read is refused.
- A person can hold a limited grant and a grant without the limit in the same scope. Each grant applies by its own actions and its own reach.
- `okb_get_authorisations` shows `own_records` on each grant.

- **Responsible:** the person who is an administrator.
- **Person:** names the person or agent, the scope, the record kinds, the actions and the reason. Without the agent, in Terminal or PowerShell, runs this command, with a new UUID for `p_issuance_request_id`:

  ```sh
  okb okb_grant_permission p_issuance_request_id="<new UUID>" p_executor_id="<actor id>" p_scope_id="<scope id>" p_record_kinds='["activity"]' p_record_id=null p_actions='["read","create","edit","start","cancel"]' p_expires_at=null p_reason="<why>" p_own_records=true
  ```

- **Agent:**
  1. Asks for the person, the scope, the record kinds, the actions and the reason. Shows the person the grant in plain words, naming the limit.
  2. Waits for the person's agreement.
  3. Calls `okb_grant_permission` with `p_own_records` true, and a new UUID as `p_issuance_request_id`. The answer shows `own_records` true.
- **Evidence:** the answer. The audit log, section 8, lists the grant as `grant_issued`, with `own_records`.

**AI guided:** the agent shows the person the grant before it is given, and waits for their approval.

## 16. Deleting an empty scope

A person who is an administrator can delete a scope that holds no record and no file. A private scope's owner deletes their own. The call deletes the scope's grants and its place for files with it. The log of its files, moves and renames stays.

- The scope is named by its id, its code or its name, in any case.
- A scope that holds a record is refused, including a scope whose records were all deleted. Move its records to another scope first, as section 12 describes.
- A scope that holds a file is refused. Delete its files first, as the Files section describes.
- The scopes `general`, `routines`, `reference`, `plugins`, `administration` and `guides` are refused.
- A reason is required.

- **Responsible:** the person who is an administrator, or, in a private scope, its owner.
- **Person:** names the scope and the reason. Without the agent, in Terminal or PowerShell, runs this command:

  ```sh
  okb okb_delete_scope p_scope="<scope name>" p_reason="<why>"
  ```

- **Agent:**
  1. Asks for the reason, then shows the person the scope's name and description, and its grants from `okb_get_authorisations`.
  2. Waits for the person's agreement to delete the scope and those grants.
  3. Calls `okb_delete_scope` with `p_scope` and `p_reason`. The answer names the scope's id, code and name, the number of grants removed, the time and the reason.
- **Evidence:** the answer. The audit log, section 8, lists the deletion as `scope_deleted`, with the scope's id as `deleted_scope_id`, its `code`, and the `grants_removed`.

**AI guided:** the agent shows the person the scope and its grants before the deletion, and waits for their approval.

## 17. Earlier sessions

The okb plugin's hooks copy each session in the agent folder into its `sessions/` folder, as Markdown with what the person and the agent wrote. They upload each copy into the person's sessions scope. Its code is `sessions_` and their Auth user ID with its hyphens removed, such as `sessions_3f2a9c0e4b1d4e7a9f6c2b8d1e5a7c3f`. Its name is the person's name and "'s sessions". The person alone holds a grant there, with `read`, `create`, `edit` and `delete`.

- **Responsible:** the actor.
- **Person:** asks what was said or agreed in an earlier session. Without the agent, runs `okb okb_get_scopes` for their sessions scope's code. The code starts `sessions_`, and the scope's name is their own. Searches the sessions with `okb call_function name=file-search body.query="<the question>" body.bucket=<sessions scope code> result_file=search.json`, and reads each hit's section in `search.json`. Opens the session's copy in `sessions/` in the agent folder to read it whole. Removes a session's copy from OKB with `okb call_function name=file-search-purge body.bucket=<sessions scope code> body.file=<file name>`.
- **Agent:**
  1. Acts when the person refers to an earlier session, or asks what was said before. Finds the person's sessions scope. Calls `okb_get_actor` for their actor id, then `okb_get_authorisations` with that id as `p_executor_id`, and `okb_get_scopes`. It is the scope whose code starts `sessions_` where a grant of theirs gives `create`.
  2. Calls `call_function` with the name `file-search`, the question as `query`, and the scope's code as `bucket`. A search across every scope leaves sessions scopes out. So the agent names the sessions scope's code as `bucket`, only when the person asks about an earlier session. Reads the result file with `read_file`, as section 6 describes.
  3. Reads a session's copy in `sessions/` with `read_file` for its whole text, or for a session too new to be found by search.
  4. Answers with each session's title and date, and quotes what was said. A decision or a change found there is checked against the records, as section 2 describes, before it is given as standing.
- **Evidence:** each search and read, and its result, quoted.

**AI guided:** the agent gives the person what was said, with the session's title and date. It waits for them before the next question.

## 18. A file's graph

OKB keeps the things each file names, such as vendors, buyers, properties and agents, and how they relate. Each thing is of a class in the firm's glossary, and each relation is one of the glossary's relationships. A search follows those links. The agent reads each new part of a file once, in the person's Claude subscription, and saves what it finds. OKB calls no language model. The agent reads a part only in a scope where the person may read, and saves it only where they may also create.

The agent names a part no agent has read yet as "waiting to be read for the graph". It names a part still waiting for its text or its vector as one OKB is still preparing. It reads parts only after the person says yes.

- **Responsible:** the actor who uploads the file, or any reader of the scope who asks.
- **Person:** uploads a file, or asks for a scope's waiting parts to be read. Without the agent, runs `okb okb_get_unextracted p_scope="<scope name>" p_limit=20 result_file=waiting.json` and reads each part's text in `waiting.json`, with the `classes` and `relationships` it lists. Writes the part's entities and relations as section 19 describes, saves them as `entities.json` and `relations.json`, and runs `okb okb_save_extraction p_chunk=<chunk id> p_entities=@entities.json p_relations=@relations.json`. Adds `p_replace=true` to correct a part they saved.
- **Agent:**
  1. After each `upload_file` the person agreed to, calls `okb_get_unextracted` with the file's scope as `p_scope`. While its `awaiting_text` is above 0, tells the person OKB is still preparing the file, and calls it again at the person's next message. Once `awaiting_text` is 0, names the parts from `waiting` and offers to read them, such as "Your 3 files have 24 parts waiting to be read for the graph. Shall I read them now?" Reads them only after the person's yes.
  2. A file search's `stages.awaiting_extraction` above 0, or `okb_get_unextracted`'s `waiting` above 0, shows parts waiting. Says so in one line, with one offer. After a search in one scope, it names the scope, such as "The General scope has 17 parts waiting to be read for the graph. Shall I read them now?" After a search across every scope, it gives the total and asks which scope to read, such as "412 parts in your scopes are waiting to be read for the graph. Which scope shall I read?" Calls `okb_get_unextracted` for the scope the person names. Offers once per scope in a session, and once in a session for a search across every scope.
  3. Reads up to 20 parts after the person's yes. Above 20, its own upload's included, the offer gives the count first, and asks before reading any.
  4. Takes the glossary's classes and relationships from the answer's `classes` and `relationships`, as section 19 describes. When `classes` is empty, tells the person the glossary has no classes yet, so nothing can be saved, and offers to propose classes through the `okb:reference` skill.
  5. For each part in `chunks`, follows section 19, and saves the part with `okb_save_extraction`. Calls `okb_get_unextracted` again for the next page while `waiting` is above 0 and the person agreed to that many.
  6. Asked to read a scope's waiting parts, does steps 3 to 5 for the scope.
  7. Reports how many parts it saved, and the entities and relations each save gave.
  8. For each file it read that holds a plan, a table or a list, offers the file's database form, as section 6 says.
  9. Asked to correct a part's entities and relations, reads the part again and saves them with `p_replace` true. The actor who saved them, or an administrator, may replace them.
- **Evidence:** each call's result, quoted.

**AI guided:** the agent shows the person each part's entities and relations before it saves them, and waits for their approval.

## 19. Reading a part for its graph

The agent follows this section to read one part of a file in OKB. It writes down the things the part names, and how they relate. Section 18 says when it reads a part.

These rules are adapted from EdgeQuake's entity extraction instructions, `edgequake/crates/edgequake-pipeline/src/prompts/entity_extraction.rs` and `prompts/parser/tuple_parser.rs`, Copyright 2024-2026 Raphaël MANSUY, under the Apache License 2.0. EdgeQuake ported them from LightRAG, Copyright (c) 2025 LightRAG Team, under the MIT License. The okb plugin's `NOTICE` file and `LICENSES` folder hold both notices and licences. The changes are these: the types and relation names come from the firm's glossary, the output is the JSON that `okb_save_extraction` takes, and the limits are OKB's.

- **Responsible:** the actor whose agent reads the part.
- **Person:** reads the part's text in `waiting.json`, and writes its entities and relations by the rules below, as `entities.json` and `relations.json`.
- **Agent:** takes the classes and relationships from `okb_get_unextracted`, then reads each part by the rules below, and saves it as section 18 describes.
- **Evidence:** each save's result, quoted.

**AI guided:** the agent shows the person each part's entities and relations before it saves them, and waits for their approval.

**Types and relationships:**

- `okb_get_unextracted` lists the glossary's classes as `classes`, and its relationships as `relationships`, each `{"relationship", "from_class", "to_class"}`.
- An entity's type is exactly one of those classes, written as the glossary writes it, such as `vendor`, `property` or `agent`.
- A relation's name is exactly one of those relationships, such as `owns`, from a `vendor` to a `property`. It goes from an entity of its `from_class` to an entity of its `to_class`.
- There is no other type and no other relation name. A thing that fits no class is left out, and so is a relation that fits no relationship.
- When a part names something that matters and fits no class, or a relation that fits no relationship, the agent may propose a new class or relationship to the person, through the `okb:reference` skill. It is saved only when the person approves. The agent then reads the part again, with the new class or relationship. Until the person decides, the agent leaves that part unsaved.

**Each part.** Read the part's `text` alone. Use nothing from other parts, other files or the agent's own knowledge.

**Entities:**

- Find each clearly named and meaningful thing in the text that is of one of the classes.
- Give each one:
   - `name`: its readable name as the text gives it, of 1 to 200 characters. Write a name in title case where the text's case carries no meaning. A code such as a postcode, a UPRN or a property reference keeps its exact form. Use the same name for the same thing every time.
   - `type`: one of the classes, of 1 to 100 characters.
   - `description`: what this part says of it, in one to three sentences, in the third person, of 1 to 2,000 characters. Use only what the text says. A thing the text names and says nothing more of takes one sentence on where it appears, such as "Oak Cottage is listed in the valuation sheet's table.".
- Use no internal identifier as a name: no UUID, no hash and no record id. Put such an identifier in the description when the text gives one.
- Give each thing once in a part. Two things in one part take two different names.

**Relations:**

- Find each direct, clearly stated relation between two of the entities in this part that is one of the relationships.
- Split a statement about three or more things into relations between pairs. "J. Smith and K. Smith own Oak Cottage" gives two relations: J. Smith to Oak Cottage, and K. Smith to Oak Cottage.
- Give each relation:
   - `source` and `target`: the names of two entities in this part, written exactly as in their entities. The source is of the relationship's `from_class`, and the target of its `to_class`.
   - `relationship`: one of the relationships listed, written as the glossary writes it.
   - `keywords`: optional, one to five short words or phrases for the relation, such as `freehold` or `sole agency`. OKB keeps the relationship's name among them.
   - `description`: what the text says of the relation, in one or two sentences, in the third person, of 1 to 2,000 characters.
- A relation goes one way, from its source to its target. Give each pair once for each relationship.
- Give a relation only between two entities given in this part.

**Order and limits:**

- Give the entities first, then the relations. Put the things that take part in relations first, and the most important relations first.
- Give at most 100 entities and 200 relations for one part. Give fewer when the part names fewer.
- Write names, keywords and descriptions in English. Keep a proper name in its own language.

**The save:**

Save the part with `okb_save_extraction`. In this example, the glossary has the classes `vendor`, `property` and `agent`, and the relationships `owns`, from a vendor to a property, and `acts for`, from an agent to a vendor:

```json
{"function": "okb_save_extraction", "schema": "okb", "args": {
  "p_chunk": "<the part's chunk_id>",
  "p_entities": [
    {"name": "J. Smith", "type": "vendor", "description": "J. Smith is selling Oak Cottage."},
    {"name": "Oak Cottage", "type": "property", "description": "Oak Cottage is owned by J. Smith and is to be sold."},
    {"name": "Harbour Estates", "type": "agent", "description": "Harbour Estates is instructed to sell Oak Cottage for J. Smith."}
  ],
  "p_relations": [
    {"source": "J. Smith", "target": "Oak Cottage", "relationship": "owns", "keywords": ["freehold"], "description": "J. Smith owns Oak Cottage freehold."},
    {"source": "Harbour Estates", "target": "J. Smith", "relationship": "acts for", "keywords": ["sole agency"], "description": "Harbour Estates acts for J. Smith on a sole agency."}
  ]
}}
```

A part with nothing to save is saved with two empty lists, and counts as read.

OKB refuses an entity whose type is not a class, a relation whose `relationship` is not a relationship in the glossary, and a relation whose ends' classes are not the relationship's `from_class` and `to_class`. It merges an entity with one already saved of the same name and type, in any case and spacing. It keeps each part's description beside the others.

## 20. Private scopes

A scope can be private. It belongs to its **owner**, the person an administrator made it for. Only a person who is an administrator adds a scope, private or not. Only the owner, and the people and agents the owner grants, read or change anything in it. A scope is private from when it is made, and stays private.

An administrator sees each private scope's name and its owner. Its records, files, search hits and audit events reach its owner and the people they grant.

- The owner holds a full grant in it from when it is made.
- The owner gives and ends every grant in it. The owner approves each change and each deletion in it that needs an approval, in place of an administrator.
- The owner renames it, and deletes it when it is empty. The owner moves records between it and another private scope they own. A move between it and a scope that is not private needs an owner who is also an administrator.
- The owner hands it to another person, who holds read in the whole scope first. Each grant the old owner gave there then ends, their own among them. The new owner holds a full grant, and gives the others again.
- A private scope whose owner leaves without handing it on stays closed for good.
- A Supabase organisation owner, or anyone with the database password, can still read the database itself.
- The codes `general`, `routines`, `reference` and `plugins`, and any code starting `plugins_` or `sessions_`, are kept for OKB's own scopes, and none is private.

- **Responsible:** the person who is an administrator, for making it; the owner, for everything after.
- **Person:** asks an administrator for a private scope, naming it, a short code for it and what it holds. Without the agent, the administrator runs this command:

  ```sh
  okb okb_add_scope p_code="<code>" p_display_name="<name>" p_description="<what it holds>" p_reason="<why>" p_private=true p_owner="<words of the owner's name>"
  ```

  The owner, to grant someone in it, runs `okb okb_find_actors p_name="<words of their name>"`, then `okb okb_grant_permission` with their `actor_id`, as section 15 shows, with `p_own_records=false`. To hand it on, runs this command:

  ```sh
  okb okb_hand_on_scope p_scope="<scope name>" p_person="<words of their name>" p_reason="<why>"
  ```

- **Agent:**
  1. Working for a person who is not an administrator, says that an administrator adds the scope, and what to ask them for. Working for an administrator, asks for the owner, the name, a code, the description and the reason. Shows the person the scope, its owner, and that it is private, and waits for their agreement. Calls `okb_add_scope` with `p_private` true and `p_owner` naming the owner. The answer names the scope, its owner, and the owner's grant as `owner_grant_id`.
  2. To grant someone in it, finds the person, or an agent of the owner's own, with `okb_find_actors`, by words of their name. When more than one fits, asks which one. Shows the person the grant in plain words, and waits for their agreement. Calls `okb_grant_permission` with a new UUID as `p_issuance_request_id`. Ends a grant with `okb_revoke_authorisation`, after the person agrees. `okb_get_authorisations` with no person named lists the owner's own grants and every grant in their private scopes. With a person named, it lists that person's grants there.
  3. To approve a change or a deletion in it, works as section 5 or section 7 describes, with the owner in place of the administrator.
  4. To hand it on, shows the person who will own it, and that each grant they gave there ends, their own among them. Waits for their agreement, and calls `okb_hand_on_scope` with the reason. The answer names the old and new owner.
- **Evidence:** each answer. The audit log, section 8, lists a handing on as `scope_handed_on`.

`okb_get_scopes` gives each scope's `is_private`, `owner_actor_id` and `owner_name`, in section 1's call too. An administrator sees each private scope with its name and owner, and a null `description`.

**AI guided:** the agent shows the person each change before it is made, and waits for their approval.

## 21. Access templates

An **access template** is a named set of grants, which OKB holds. Each of its grants names a scope by its code, its record kinds, its actions and whether it is limited to the person's own records. OKB starts with three. `administrator` is the client's administrator, with administrator authority and no grant. `basic` is a member of staff. `real_agent` is Real Agent's staff, and the one template that changes the `plugins` scope's files.

- Every signed-in actor reads the templates.
- Only a person who is an administrator gives a person a template, or changes one. Each change gives a reason, and the audit log, section 8, lists it as `access_template_changed`.
- A template names shared scopes only, never a private or sessions scope.
- In the SQL Editor, `bootstrap.sql` step 3f gives a person a template in one statement.

- **Responsible:** the person who is an administrator.
- **Person:** reads the templates with `okb okb_get_access_templates`. Gives a person one with `okb okb_apply_access_template p_person=<actor id> p_template=<code>`. Changes one with `okb okb_save_access_template p_code=<code> p_grants=@<grants file> p_reason="<why>"`, and adds one with `p_description` and `p_authority_class` too.
- **Database admin agent:**
  1. Calls `okb_get_access_templates`, and shows each template's grants in plain words. It names each scope, what the person may do there, and any limit to their own records.
  2. To give a person a template, shows the person and the template's grants, and waits for their agreement. Calls `okb_apply_access_template` with the person's actor id as `p_person` and the template's code as `p_template`. The answer lists each grant it `issued`, and `already_held` counts those the person held. A second call issues nothing more.
  3. To change a template, shows the old and new grants side by side, and waits for the person's agreement. Calls `okb_save_access_template` with the reason. The answer gives the `old` and `new` template.
- **Evidence:** each answer, and the `access_template_changed` entry in `okb_get_audit`.

**AI guided:** the agent shows the person each change before it is made, and waits for their approval.

## Files

Each scope's files are in its own private bucket, named after the scope's code. The okb plugin's `upload_file`, `list_files` and `download_file` upload, list and download them. The `okb:actor` skill's "Search results" and "File deletion" sections cover searching them and deleting one for good. Sections 18 and 19 cover the graph of their parts.

## Problems with records

OKB's refusals are its rules at work, and the agent reports each one as it came, with its message:

- **`Invalid text field: <field>`:** the field is not text, or is over its limit. A `title` holds 500 characters, and a model node's `label` 500. An activity's `index` holds 20. An `owner_label`, and an external reference's `label`, hold 200. A `source_reference`, a link's `locator`, and an external reference's `reference` hold 2,000. A node's or edge's `id` and `type` hold 100. Every other text field holds 4,000. The agent shortens the field, or moves detail into a model's node attributes, and shows the person the change before saving again.
- **`source_reference: <rule>` or `external_references.reference: <rule>`:** the value breaks the rule named, from section 3. The agent removes the `?` part, the leading slash or the `..`. For another scheme, it asks the person for the `https://` link. It shows the person the change before saving again.
- **`Administrator required`:** the call is for administrators only, such as `okb_get_sign_ins`. The agent says that an administrator's own agent can answer it.
- **`Scope or record unavailable`, or a null record:** the actor has no read grant there, or the record does not exist.
- **`Supply the id of a grant or approval that covers this change`:** the save left out the authority's id. An actor that needs a person's approval for every save passes the approval's id, as section 5 describes. Any other actor passes its grant's, as section 3 describes.
- **`Authority unavailable` or `Action outside authority scope`:** the grant given does not cover this change: its scope, record kinds or actions, or it has expired or been revoked. A deletion also needs a grant that includes delete for the record's kind, unless the actor is an administrator.
- **`Exact human-issued approval required`:** every save by this actor needs an approval issued by a person, as section 5 describes. An administrator asks a person to approve it.
- **`Approval already used or does not match exact request`:** an approval covers one save of one exact request. The agent asks the administrator for a new approval of the request as it now stands.
- **`Completion requires requirements, note, no blockers and supporting evidence`:** the activity needs its completion requirements, a completion note, no open blockers, and a `supports` link to an evidence version. The agent says which of these is missing.
- **`Record deletion needs an approval` or `Record deletion needs a human administrator's approval`:** every deletion needs an approval of its exact request from an administrator who is a person, as section 7 describes.
- **`The records that link to this record have changed; preview the deletion again`:** another record has linked to it, or stopped, since the preview. The agent previews again and asks for a new approval.
- **`Deletion retry unavailable or different`:** the request's id was already used, by another actor or for another record. The agent previews again, which gives a new request.
- **`A deletion request has operation delete`:** the request is not the one the preview gave. The agent uses the preview's `request` with only its reason filled in.
- **`The record was deleted`:** the record has already been deleted; it can be read as deleted, but not saved to or deleted again.
- **`Link target unavailable`:** a link points at a version the actor cannot read, or at a record that has been deleted. The agent removes that link, or links to a version it can read.
- **`Assignee is not a person who can read this scope`:** the assignee is an agent or an application, is not enabled, or holds no grant to read activities in the task's scope. The agent finds the person again with `okb_find_people`, or tells the person that an administrator can give them read in the scope.
- **`Only a task has an assignee`:** a plan was given an assignee. A plan has an owner, as section 9 describes.
- **`Owner is not a person who can read this scope`:** the activity has no `owner_actor_id`. Or its owner is an agent or an application, is disabled, or holds no grant to read activities in its scope. The agent finds the person with `okb_find_people`, and sets them with `okb_set_owner`. Or it tells the person that an administrator can add them to OKB, or give them read in the scope.
- **`invalid input syntax for type uuid`:** an `assignee_actor_id` or `owner_actor_id` is not an actor's id. The agent takes the id from `okb_find_people`.
- **`An activity index is one line`, `Only a task has a task type` or `Task types are work, deliverable and blocker`:** the index holds a line break, a plan was given a task type, or the task type is another word. The agent corrects it as the person agrees.
- **`More than one record has the title "<title>"`:** a task function's record fits more than one record. The person names it by one of the record ids listed.
- **`Record unavailable: no record you can read has the title "<title>"`:** no record the actor may read has that exact title. The agent finds it with `okb_find_records` and words of the title, and names it by its record id.
- **`Scope unavailable: no scope has the id, code or name "<scope>"`:** the scope is named another way. `okb_get_scopes` lists each scope's id, code and name.
- **`No grant of yours covers <actions> on <kind> records in <scope>. An administrator can grant it, or approve this exact change`:** the actor holds no grant for the change, as section 3's **Authority** describes. An administrator can grant it, or approve the preview's request.
- **`Every save by this actor needs a person's approval. Save the preview's request with an approval, as the okb:records skill's section 5 describes`:** the actor saves only with an approval. An administrator approves the preview's request, as section 5 describes.
- **`No person who can read <scope> has a name with "<words>". An administrator can give them read in the scope` or `More than one person fits "<words>": <names>`:** `okb_assign` or `okb_set_owner` found no person, or more than one. The person gives more of the name, or an administrator gives that person read in the scope.
- **`The record has no <relation> link to that record`:** `okb_unlink` found no such link to remove.
- **`Name a task`, `Name a blocker` or `The task has deliverables a to z`:** a blocker or deliverable function was given another kind of record, or the task has no letter left.
- **`Give the blocker's requirements: what clears it`, `Give the completion note: how the blocker was cleared` or `Name the evidence that the blocker is cleared`:** `okb_add_blocker` or `okb_clear_blocker` was given no requirements, no note, or a record that is not evidence.
- **`The fields are a JSON object`:** `p_fields` is not an object of field names and values.
- **`Previous version is stale`:** someone saved a newer version; the agent reads it again, as section 3 describes.
- **`This record was changed by another save. Read it again, then save again.`:** another save of the same record finished first. The agent reads the record again, shows the person what changed, and saves again once they agree.
- **`canceling statement due to statement timeout`:** the call ran past OKB's time limit, and nothing was saved. The agent reports it to the person as it came, and tries once more only when the person asks.
- **`A period needs a start before its end` or `Invalid audit cursor`:** the audit log's period is reversed, or the cursor is not one it gave. The agent sets the period again, and passes back only the `next_cursor` it was given.
- **`Missing or unknown JSON fields`:** the request or payload lacks a key, or has an extra one. The agent compares it with section 3's keys and the kind's fields, and shows the person the change before saving again.
- **`The entity "<name>" has the type "<type>", which is not a class in the glossary. An entity's type is one of the classes okb_get_unextracted lists`:** an entity's type is not a glossary class. The agent uses one of the classes listed, or leaves the thing out, as section 19 describes.
- **`The relation from "<source>" to "<target>" names "<name>", which is not a relationship in the glossary. A relation names one of the relationships okb_get_unextracted lists`:** a relation's `relationship` is not a glossary relationship. The agent uses one of the relationships listed, or leaves the relation out.
- **`The relationship "<name>" goes from a <class> to a <class>, and "<source>" is a <class> and "<target>" a <class>`:** the relation's ends are the wrong way round, or of other classes. The agent swaps the source and target, or leaves the relation out.
- **`Chunk unavailable: no chunk with the id "<id>" in a scope you may read` or `Saving a chunk's entities and relations needs create permission in its scope`:** the actor may not read the part's scope, or may read it and not create there. An administrator can grant it.
- **`Only the actor who saved this chunk's entities and relations, or an administrator, may replace them: <name>`:** another actor saved the part. The agent tells the person who, and that they or an administrator can correct it.
- **`File search's graph is not set up yet: ask the administrator to run file-search.sql`:** the project's file search is not set up. The agent tells the person to ask their administrator.

## Problems with moves, scopes and grants

The agent reports each of these as it came, with its message:

- **`Only a person who is an administrator moves records`:** the actor is an agent, or a person who is not an administrator. The agent says that an administrator's own agent can move them.
- **`Every record in a move is in the same scope. These are in <scopes>`, or `The records are already in <scope>`:** the records named are in more than one scope, or in the scope named. The agent names one scope's records, or another scope.
- **`Give the reason for the move, as p_reason when previewing it`:** the preview was made without a reason. The agent asks for it and previews again.
- **`A record outside the move links to or from one in it. Add it to the move, or save a version without the link`, or `The preview refuses the move: <records and reasons>`:** the preview's `outside_links` or `refused` was not empty. The agent shows the person each one, as section 12 describes, and previews again once they are dealt with.
- **`The move has changed; preview it again`:** a record, a link or someone's access changed since the preview. The agent previews again, shows the person what is different, and moves only when they agree again.
- **`Only a person who is an administrator renames a scope`:** the actor is an agent, or a person who is not an administrator. The agent says that an administrator's own agent can rename it.
- **`Give the reason for the change, as p_reason`, or `Give the new name, as p_display_name, or the new description, as p_description`:** the call lacks a reason, or changes neither the name nor the description. The agent asks for what is missing and calls again.
- **`The scope <name> already has that name and description`:** the new name and description are the scope's own. The agent tells the person, and changes nothing.
- **`Only a person who is an administrator deletes a scope`:** the actor is an agent, or a person who is not an administrator. The agent says that an administrator's own agent can delete it.
- **`Give the reason for the deletion, as p_reason`:** the call lacks a reason. The agent asks for it and calls again.
- **`The scope <name> holds <n> records, <k> of them deleted; a scope is deleted only when it holds none`:** the scope holds records. The agent offers to move the live ones, as section 12 describes. A record that was deleted stays in the scope.
- **`The scope holds <n> files; delete them first`:** the scope's files are not all deleted. The agent lists the files, and deletes them only when the person agrees.
- **`The scope <name> is part of OKB's setup and is not deleted`:** the scope is `general`, `routines`, `reference`, `plugins`, `administration` or `guides`. The agent says so.
- **`Another scope has the name or code "<name>": <scope> (code <code>)`:** another scope holds that name, or has it as its code, in any case. The agent shows the person that scope, and asks for another name.
- **`A scope's name is at most 200 characters`, or `A scope's description is at most 4000 characters`:** the new name or description is over its limit. The agent shortens it with the person, and calls again.
- **`A grant limited to own records covers no single record`:** the grant named a record with `p_record_id`. The agent leaves `p_record_id` null and calls again.
- **`A grant limited to own records does not carry delete`, or `A grant limited to own records carries read`:** the grant's actions hold `delete`, or lack `read`. The agent takes `delete` out, or puts `read` in, with the person, and calls again.
- **`Only a person who is an administrator adds a scope`:** the actor is an agent, or a person who is not an administrator. The agent says that an administrator's own agent can add it.
- **`The code <code> is kept for OKB's own scopes`:** a private scope was asked for with one of OKB's own codes. The agent asks for another code.
- **`No enabled person has a name with "<words>"`, or `More than one person fits "<words>": <names>`, from `okb_add_scope`:** the owner named was found nowhere, or more than once. The agent asks for more of the owner's name, and calls again.
- **`Only the scope's owner gives grants in a private scope`, `Only the scope's owner ends grants in a private scope`, `Only the scope's owner approves changes in a private scope`, `Only the scope's owner renames a private scope`, `Only the scope's owner deletes a private scope`, or `Only the scope's owner hands it on`:** the scope is private, and the actor is not its owner. The agent names the owner, from `okb_get_scopes`, and says that the owner can do it.
- **`Record deletion in a private scope needs its owner's approval`:** the approval came from someone other than the scope's owner. The owner approves the deletion, as section 20 describes.
- **`Only the owner of a private scope moves records into or out of it, and only an administrator moves them elsewhere`:** the actor does not own a private scope of the two, or is not an administrator where one is not private. The agent says who can make the move.
- **`No other person who can read <scope> has a name with "<words>". Give them read in the scope first, with okb_grant_permission`:** the person to hand the scope to holds no read in the whole scope. The owner grants them read first, as section 20 describes.
- **`Only an administrator, or the owner of a private scope, finds people to grant`:** the actor owns no private scope and is not an administrator.
- **`Only a person who is an administrator applies an access template`, or `Only a person who is an administrator changes an access template`:** the actor is an agent, or a person who is not an administrator. The agent says that an administrator's own agent can do it.
- **`There is no access template <code>`:** the code names no template. The agent lists the templates with `okb_get_access_templates`, and asks which one.
- **`The <code> access template names scopes this OKB lacks: <scopes>`:** a scope the template names is missing. An administrator adds it first, as section 13 describes.
- **`Only the real_agent template changes the plugins scope; the <code> template only reads it`:** a change gave another template more than read in `plugins`. The agent keeps that grant to read.
- **`Only the real_agent template changes the guides scope; the <code> template only reads it`:** a change gave another template more than read in `guides`, the Guides scope, where Real Agent's guides are kept. The agent keeps that grant to read.
- **Any other message:** it names the field or rule that the request broke.

## Finish order

An activity's finish is its forecast finish, or its baseline finish where the forecast is null. Each activity finishes on or after each of its children. It also finishes on or after each deliverable it waits on through a `depends_on` link. So a task finishes on or after its deliverables, a sprint on or after its tasks, and a project on or after its sprints. A cancelled activity, and one with no finish, is left out. OKB refuses a save that breaks this.

A change that moves a parent and its children later saves the parent first. A change that moves them earlier saves the children first. Each finish change carries its own reason.

## Problems with finish dates

- **`This finish cannot be saved: <activity> finishes <time>, before its <task, sprint, plan, blocker or deliverable> <index>, which finishes <time>.`:** the save leaves an activity finishing before a child, or before a deliverable it waits on, as "Finish order" describes. The message names each such pair. The agent shows the person each pair, and asks which finish moves. To move a parent and its children later, it saves the parent first. To move them earlier, it saves the children first. Each save carries its own reason.
