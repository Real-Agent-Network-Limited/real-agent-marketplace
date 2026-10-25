---
name: graph
description: Use when a plan or a model record in OKB is to be drawn as a graph page. Also use when a state machine page is to be kept in OKB as a model record. Also use when a person asks how a file search found its answer. A plan's graph is drawn from the same plan model as its board. A state machine page is an HTML page with a graph-data and a state-machine-data JSON block.
---

# OKB graph pages

A **model record** in OKB holds a graph of nodes and edges, in the format the `okb:records` skill's section 3 sets out. This skill draws a model record as a single HTML page, which opens in a browser with no network.

- A **plan's graph page** draws a plan from its progress files, the same plan model its board is drawn from, as section 4 says.
- A **graph page** draws any other model record. The `okb:board` skill's section 2 draws the same record as rows of cards. For an org chart, a contacts list or another structure of people, roles or sites, the agent offers both. The person chooses. Each node is a circle in its group's colour, carrying a short reference. Nodes are grouped by type, or by an attribute the person names. Where nodes carry an `index` attribute, each node's reference is its index, and nodes run in index order. Groups then run in the order of their lowest index, each headed by its name alone. Each link is an arrow with a small sign for its type at its middle, and the key names each sign. A Part of link is a plain arrow. Clicking a node shows its attributes.
- A **search page** shows how a file search found its answer, as section 5 says.
- A **state machine page** draws a routine model as a graph of routines, states, data and rules. It shows the actors and applications each state involves. A **routine model** has only the node types in "The state machine model". It may be made from a state machine page, or written as a payload by the `project:interview`, `project:audit` or `project:design` skill. Its content is in two JSON blocks inside the page, `graph-data` and `state-machine-data`. A state machine page can be kept in OKB as a model record, and drawn again from it.

The scripts beside this skill do the work. They use the Python 3 standard library only.

- `graph_page.py` draws a graph page from any model record.
- `plan_graph.py` draws a plan's graph page from its progress files, with the `okb:board` skill's `plan_model.py`, and writes its outline and picture with that skill's `page_check.py`.
- `page_to_model.py` turns a state machine page into a model record's payload.
- `model_to_page.py` draws a state machine page from a routine model record.
- `state_machine_page.py` holds the state machine page format and the drawing rules.
- `page-shell.html` holds the drawing code both kinds of page use.
- `search_page.py` draws a search page from a file search's result file, with `search-shell.html`.

The agent, such as the database operator, `@real-agent:database-operator`, runs the scripts through the okb plugin's four tools, and saves and reads the record, as the `okb:records` skill says. `draw_graph` runs `graph_page.py` on a record file, or `plan_graph.py` on progress files, `draw_search` runs `search_page.py` on a search's result file, `state_machine_payload` runs `page_to_model.py`, and `draw_state_machine` runs `model_to_page.py`. Each reads one file and writes one new file, both directly inside the agent folder, and never replaces a file. The agent folder is the person's one folder for their agent, where they put files and the agent keeps its work. The JSON passes between the scripts and OKB through these files, unchanged.

The tools need Python 3 on the computer. The okb plugin finds it as `python3`, `python` or `py -3`, whichever first answers with a version such as `Python 3.12.4`. Without it, install it with the command for your system, then quit and reopen the Claude desktop app:

| Program | macOS | Windows | Debian and Ubuntu |
|---|---|---|---|
| Python 3, for graph pages and state machine pages | `xcode-select --install` | `winget install Python.Python.3.13` | `sudo apt install python3` |

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command and a browser.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and an **Agent** line.

With the agent, the person's own instruction replaces a rule of this skill, such as the attribute the nodes are grouped by. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Draw any model

A plan is drawn as section 4 says, from its activities. A model record that copies a plan is never drawn as the plan.

- **Responsible:** the person, who must be able to read the record.
- **Person:** names the record, and, to group its nodes by something other than their type, the attribute to group by. Without the agent, in their agent folder, runs `okb okb_get_record p_record_id=<record id> result_file=record.json`, then `okb draw_graph record_file=record.json page_file=graph.html group_by=<attribute>`, and opens `graph.html` in a browser. `okb_find_records` gives the record id, as the `okb:records` skill's section 2 says.
- **Agent:**
  1. Follows `okb:records` section 2. It finds the record with `okb_find_records`, with `p_kind` `model` and words of the name the person gave, unless the person gave its record id. It calls `okb_get_record` with `result_file` set to a new file in the agent folder, such as `<agent folder>/<name>.record.json`.
  2. Calls `draw_graph` with that file and a new `page_file`, such as `<agent folder>/<name>.html`. Adds `group_by` with the attribute the person named.
  3. Checks the page, as the `okb:board` skill's "Check the page before giving it" says.
  4. Gives the person the page's full path, to open in a browser, and the Checked list. Gives the counts of nodes, links and groups from the tool's result.
- **Evidence:** the record file, the page's path, size and counts from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the page with its Checked list, and waits for their approval.

## 2. State machine page to record

- **Responsible:** the person, who must be able to save a model record in the scope.
- **Person:** puts the page in the agent folder, names it and the scope, and agrees to the save when the agent asks. Without the agent, in their agent folder, runs `okb state_machine_payload page_file=<page>.html payload_file=payload.json description="<what the model describes>"`. Then saves it, with the title the result gives: `okb okb_add_record p_scope=<scope> p_kind=model p_title="<title>" p_reason="<why>" p_fields=@payload.json result_file=saved.json`. Runs each save first with `p_preview=true` and without `result_file`, reads the change, then runs it again without `p_preview`.
- **Agent:**
  1. Calls `state_machine_payload` with the page's full path and a new `payload_file` beside it, such as `<agent folder>/<name>.payload.json`. Adds `description` to say what the model describes; without it, the description names the page. The result gives the record's title and the counts of each node and edge type. A page without the two JSON blocks is refused.
  2. Follows `okb:records` section 3, with the payload from the file. It calls `okb_save_version` with `file_args` `{"/p_request/payload": "<the payload file>"}`, the rest of the request in `args` as usual, and `result_file`. A saved version holds the whole payload, too large to read in full, so the agent reports the `record_id`, `version_id` and `version_number` from the reply's `summary`.
- **Evidence:** the tool's title and counts, and the saved `record_id` and `version_id`.

**AI guided:** the agent gives the person the title and counts from the page before saving, and waits for their approval.

## 3. Record to state machine page

- **Responsible:** the person, who must be able to read the record.
- **Person:** names the record. Without the agent, in their agent folder, runs `okb okb_get_record p_record_id=<record id> result_file=record.json`, then `okb draw_state_machine record_file=record.json page_file=machine.html`, and opens `machine.html` in a browser.
- **Agent:**
  1. Follows `okb:records` section 2. It finds the record with `okb_find_records`, with `p_kind` `model` and words of the name the person gave, unless the person gave its record id. It calls `okb_get_record` with `result_file` set to a new file in the agent folder, such as `<agent folder>/<name>.record.json`. `okb_get_record` returns `{"cutoff", "version", "links"}`, and `model_to_page.py` takes the model from `version`.
  2. Calls `draw_state_machine` with that file and a new `page_file`, such as `<agent folder>/<name>.html`.
  3. Checks the page, as the `okb:board` skill's "Check the page before giving it" says.
  4. Gives the person the page's full path, to open in a browser, and the Checked list.

  The outline lists each routine with its states, then the drawn objects, the transitions, the dependencies and the routes. Its findings are:

  - a state with no transition and in no route;
  - a state in no routine;
  - a routine with no states;
  - a link or route naming a node the page does not draw;
  - two nodes with the same reference.

  A gap or a dead end is part of the routine, and is no finding. A finding in the model is put right with the person, in a new version of the record.

  For a routine model, the agent uses `draw_state_machine`. For any other model, or a model `draw_state_machine` refuses, it uses `draw_graph`, as section 1 says.
- **Evidence:** the record file, the page's path and size from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the page with its Checked list and findings, and waits for their approval.

## 4. Draw a plan

- **Responsible:** the person, who must be able to read the plan's scope.
- **Person:** names the plan. Without the agent, reads the plan's progress into files, as the `okb:board` skill's section 1 says, then runs `okb draw_graph progress_files=progress-1.json plan_id=<plan record id> page_file=plan.html`, and opens `plan.html` in a browser.
- **Agent:**
  1. Reads the plan's progress into files, as the `okb:board` skill's section 1, steps 2 and 3, says. The board and the graph can share one read.
  2. Calls `draw_graph` with every progress file in `progress_files`, `plan_id` set to the plan's record id, and a new `page_file`, such as `<agent folder>/<name>.graph.html`.
  3. Checks the page, as the `okb:board` skill's "Check the page before giving it" says.
  4. Gives the person the page's full path, to open in a browser, and the Checked list. Gives the counts from the tool's result.
- **Evidence:** the progress files, the page's path, size and counts from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the page with its Checked list, and waits for their approval.

The page draws:

- each part of the plan as a group, headed by its title, in index order, after the plan's own group;
- each activity as a node carrying its index, in index order;
- a plan as an ellipse, and a task as a circle;
- a deliverable as a box, and a blocker as a circle with a red border;
- a Part of link from each activity to its parent, and a Waits on link to each activity it depends on.

Clicking a node shows its description, with its line breaks. Then it shows the node's state, dates, deliverables, blockers, what it waits on, its evidence and its record id. It shows each activity's owner, and the person a task is assigned to.

## 5. Draw a search

- **Responsible:** the person, who asked the question.
- **Person:** asks how an answer was found. Without the agent, in their agent folder, runs `okb call_function name=file-search body.query="<the question>" body.explain=true result_file=search.json`, then `okb draw_search search_file=search.json question="<the question>"`, and opens `search.html` in a browser.
- **The agent:**
  1. Runs the search again, as the `okb:records` skill's section 6 says, with `"explain": true` in the body and a new `result_file`, such as `<agent folder>/search-<date>-<time>.json`.
  2. Calls `draw_search` with that file as `search_file` and the question. Without `page_file`, the page is the search file's name ending in `.html`.
  3. Checks the page, as the `okb:board` skill's "Check the page before giving it" says. The picture starts from the first card with shaded sentences. A finding that the search was not explained means step 1 ran without `explain`.
  4. Gives the person the page's full path, to open in a browser, and the Checked list.
- **Evidence:** the search's result file, the page's path, size and counts from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the page with its Checked list, and waits for their approval.

The page draws:

- the question, and how many hits the words, meaning and graph searches each found, and how many were merged;
- a card for each hit, the reference hits first. It names the file, its place and its fusion score, with a badge for each way that found it and its rank. The meaning badge shows the hit's similarity to the question as a bar and a number;
- the hit's passage. Each of the question's words is marked in yellow, as with a marker pen. Each measured sentence is shaded blue, darker the nearer its meaning is to the question's, with its similarity on hover. A thin rule in the margin marks the hit's own lines. Each entity the graph walk reached is underlined in green;
- the graph walk, in a green panel: the starting points, then each step's entities, in columns. Play draws the starting points, sized by their similarity, then each step's relations in turn, one step every 1.2 seconds. A card lights when an entity it names is reached. Replay plays it again. Clicking an entity lights the cards that name it. With reduced motion set in the person's display settings, Play shows the last step at once.

File search stores a vector for each sentence of each file, after the file's other vectors, in every scope but a person's sessions scope. A hit whose sentences are still waiting for their vectors has no shading. A hit whose passage lies outside the part of the section returned says so on its card.

## What a state machine record keeps, and what is not

Kept, so the page's two data blocks come back byte for byte:

- every node and its details, and every drawn edge;
- the routines and their colours;
- the routes, and the order of their states;
- the applications list, and each state's actors, applications and data;
- the page's mode and stored status. Where a page differs from the drawing rules, the difference is kept on its node, under `page_overrides`.

Not kept:

- The page's summary line. The drawn page counts what it draws instead, and ends "Drawn from OKB."
- Wording the record has no field for, such as an approval label like "AWAITING APPROVAL".
- The page's own drawing code. The drawn page uses `page-shell.html`.

## The state machine model

Besides the page's own node types (`routine`, `route_group`, `start`, `activity`, `end`, `dead_end`, `gap`, `data`, `rule`, `related_machine` and `object`), the graph has:

- one `state_machine` node, holding the page's mode and format. A model written as a payload may leave it out. Its page then takes its mode from `model_kind`, and each state lists the actors, applications and data it links to;
- an `actor` or `application` node for each actor and application a state links to;
- a `route` node for each route, with its key and outcome.

Its edges are:

- the page's `flow`, `sequence`, `consequence` and `dependency` edges, with their labels;
- `part_of`, from a node to its routine;
- `performed_by`, `occurs_in`, `reads_from` and `writes_to`, from a state to what it links to;
- `in_route`, from each state to each route it is in, in the route's order;
- `listed_in`, from a state to an application in the page's applications list.

## Problems

- **"has no … block":** the page is not a state machine page. Nothing is written.
- **"has node types a state machine page cannot draw":** the model is not a routine model. It is drawn with `draw_graph`, as section 1 says.
- **"over the 500-node limit":** the model is too large for one graph page. Nothing is written.
- **"would not give the page back unchanged":** the page holds something the model cannot keep. Nothing is written; keep the page as a file instead.
- **"does not exist, or you may not read it"** or **"was deleted":** `okb_get_record` found no model to draw.
- **"too near OKB's limit":** OKB refuses a save request over 262,144 bytes, and the request holds the payload with its ids, title, reason and links. The script keeps a payload to 261,120 bytes. Nothing is written.
- **"Save request exceeds 256 KiB":** OKB refused the save, because the request's title, reason or links made it too long. Shorten them, and save again.
- **"already exists":** the record, payload or page file, or a page's outline or picture, is already there. The agent names a new file; nothing is replaced.
- **"Give record_file for a model record, or progress_files for a plan, and not both":** `draw_graph` takes one of the two.
- **"grouped by the parts of the plan":** a plan's graph takes no `group_by`.
- **"is outside the agent folder", "in a folder within"** or **"is not a file name directly inside the agent folder":** every file the agent reads or writes here is directly inside the agent folder. The person moves the page there first.
- **"No agent folder is set":** the folder the person signed in with `okb sign-in --folder` is the agent folder. In a folder with no actor file, the person sets `agent_folder` to a folder of its own in the okb plugin's settings.
- **"the file does not hold a file search's result":** `search_file` is not the result file of a `file-search` call. The agent searches again with `result_file`.
- **"Give the question the search was asked":** `draw_search` needs the question, as the page's heading.
- **"Python 3 is not on this computer":** the person installs it with the line the refusal gives. It is their system's line in the table at the start of this skill.
