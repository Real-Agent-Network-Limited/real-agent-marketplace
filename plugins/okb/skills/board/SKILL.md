---
name: board
description: Use when a person wants to see where a plan in OKB stands as a board. Also use for a model of people, roles or sites as a board. Draws one plan as a read-only page, with its parts, its activities by state, its dates and what is overdue. Draws a model, such as an org chart or a contacts list, as rows of cards.
---

# OKB progress board

A **progress board** draws one plan in OKB as a single HTML page, which opens in a browser with no network. A **model board** draws any other model record as rows of cards, as section 2 says.

- The plan is the page's header, with the time OKB was read. Hovering the time shows the save number.
- The plan's purpose statement is under the header, as the `project:purpose` skill writes it. It opens folded to its first line, ending in Show more. Clicking it shows the whole purpose and Show less.
- A timetable strip shows each part of the plan against the plan's dates, with a line at the time OKB was read.
- The board has a column for each state: Pending, In progress, Paused, Completed and Cancelled. Cancelled is folded until clicked.
- Each part of the plan directly under it is a row, in index order. The first column names the part by its index and title, with its dates, its state and its badges. It is headed Plan, Task, or Plan or task. A part that is itself a plan holds a card for every activity under it, in index order. A task holds its own card. An activity with no index comes after every indexed one beside it, by start date then title.
- A plan with two or more parts has a row of tabs between the filters and the board. Each part has a tab, in index order, named by its index and title, and a last tab, All, shows every row. A cancelled part's tab is muted.
- A part's tab shows that part's row only. The arrow keys move between the tabs. A filter applies within the open tab.
- The board opens on the first part in progress. With none, it opens on the first part not completed or cancelled, and with none of those, on the first part.
- Clicking a part's bar in the timetable strip opens its tab and its panel.
- For a plan with two or more parts, the page's outline has a Tabs line after its header. It names each tab and the tab the board opens on. The outline lists every row.
- Each state column shows how many cards the open tab holds.
- The board scrolls within the window, and its headings stay at the top.
- A plan's board and its graph come from one plan model. Both are built from the same progress files, as the `okb:graph` skill's "Draw a plan" says.
- A card shows the activity's kind, its index and title, its dates and its badges. A task's kind is its task type: Task, Deliverable or Blocker. The badges are Overdue with its hours, Due to start, and Blocked with the count. Deliverables gives how many of its deliverable records are completed, out of those pending, in progress, paused or completed. After names each other unfinished activity it waits on. No deliverables marks an activity in progress or paused with no deliverables written and no deliverable record in those four states. An activity waits on an unfinished one while it is in progress, paused or due to start. Each badge is one line, and a long title is cut short.
- Each card and row uses the forecast dates, and the baseline dates where a forecast date is empty. Due to start means pending, with its start before the time OKB was read.
- Every date and time on the board's page and in its outline is in UK time, wherever the page is opened.
- Clicking a card, or a row's first column, opens a panel. It shows the activity's deliverables: each deliverable record with its state, then its completion requirements. It shows both sets of dates, the recorded start and finish, and its previous state. It shows the other activities it depends on, and its blockers by index and state. It shows the activity's owner, and the person a task is assigned to. It shows its record id with a Copy button, its references and its latest version. Each activity it waits on is shown once. Line breaks in the text are kept.
- For an activity not yet completed or cancelled, the panel's Ready to complete? list marks each thing completing needs as done or missing: deliverables written, no open blockers, and supporting evidence linked. The completion note is written when the activity is completed.
- For a completed activity, the panel shows its completion note and its supporting evidence. It shows how many days early or late it finished against the baseline and the forecast.
- The panel ends with the message that asks the agent to move the activity to each state it may move to. Each message names the activity by its record id, and has a Copy button.
- Filters show all cards, the overdue or due to start, or the blocked.

The board is read-only. A person changes a state by asking the agent, or with `okb okb_set_state`, as the `okb:records` skill's section 4 says, and draws the board again.

The scripts beside this skill do the work, with the Python 3 standard library only.

- `plan_model.py` builds the plan model from the progress files: the plan, every activity under it in index order, and the findings.
- `board_page.py` draws the board from the plan model.
- `model_board.py` draws a model board from a model record.
- `page_check.py` writes the page's outline and picture, for the board, the model board, the graph and the state machine page alike.
- `board-shell.html` holds the board's drawing code, and `model-board-shell.html` the model board's.

The agent, such as the database operator, `@real-agent:database-operator`, runs the scripts through the okb plugin's `draw_board` tool. The tool reads the progress files or the record file. It writes one new page, all directly inside the agent folder, and never replaces a file. The tools need Python 3, as the `okb:graph` skill sets out.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command and a browser.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and an **Agent** line.

With the agent, the person's own instruction replaces a rule of this skill, such as the files the progress is read into. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Draw a plan's board

- **Responsible:** the person, who must be able to read the plan's scope.
- **Person:** names the plan. Without the agent, in their agent folder:
  1. Finds the plan's record id with `okb okb_find_records p_kind=activity p_title="<words of the plan's title>"`, and its purpose statement as the `project:purpose` skill's section 1 says.
  2. Reads the plan's scope into a file: `okb okb_get_progress p_cutoff=null p_observed_at=null p_cursor=null p_limit=100 p_scope_id=<scope id> result_file=progress-1.json`
  3. While the reply's `summary` has a `next_cursor`, reads the next page into the next file, with the first page's `cutoff` and `observed_at`: `okb okb_get_progress p_cutoff=<cutoff> p_observed_at=<observed_at> p_cursor=<next_cursor> p_limit=100 p_scope_id=<scope id> result_file=progress-2.json`
  4. Draws the board, giving `progress_files` once for each file: `okb draw_board progress_files=progress-1.json page_file=board.html plan_id=<plan record id> purpose="<purpose statement>"`
  5. Opens `board.html` in a browser.
- **Agent:**
  1. Finds the plan's purpose statement with the `project:purpose` skill's section 1. With none, writes and saves one with that skill. The board waits until the person agrees a statement.
  2. Follows `okb:records` section 2, calling `okb_get_progress` with `p_scope_id` set to the plan's scope, `p_limit` 100, and `result_file` set to a new file in the agent folder, such as `<agent folder>/<name>.progress-1.json`.
  3. While the answer's `next_cursor` is not null, calls `okb_get_progress` again with `p_cursor` set to it. Sets `p_cutoff` and `p_observed_at` to the first answer's `cutoff` and `observed_at`, and `result_file` to a new file, such as `<agent folder>/<name>.progress-2.json`.
  4. Calls `draw_board` with every progress file in `progress_files`, and a new `page_file`, such as `<agent folder>/<name>.board.html`. Sets `plan_id` to the plan's record id, and `purpose` to the purpose statement's text.
  5. Checks the page, as "Check the page before giving it" says.
  6. Gives the person the page's full path, to open in a browser, and the Checked list. Gives the plan's title and the counts in each state from the tool's result.
- **Evidence:** the purpose statement's `record_id` and `version_id`, the progress files, the page's path, size and counts from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the plan and its purpose statement before drawing, and waits for their approval.

## 2. Draw a model as a board

A model board draws any other model record, such as an org chart or a contacts list, as rows of cards. The `okb:graph` skill draws the same record as a graph page. The person chooses either drawing. For a structure of people, roles or sites, the agent names both drawings each time it offers one, also before the model is saved. It names them in one line, such as "It can be drawn as a board of cards by reporting level, or as a graph."

- Each node is a card: its label, a second line from its `role` attribute, or its `title` where it has no role, and its `description`.
- The page's header is the model's title and description, with its version.
- The cards fall into rows, in one of two layouts the person names:
  - **group**: one row per value of a node attribute, such as `side` or `team`, in the order the nodes first give them. The attribute's name is matched in any case, with a space, `_` or `-` between words. Nodes without it are in a last row, Ungrouped.
  - **level**: one row per level of a relation, such as reports to. A node with no line of that relation is on the top row, and each card sits under the card it points to. A node outside the relation, such as a site in a reporting chart, is a card above the chart, headed Beside the chart. The levels scroll sideways as one.
- In a grouped row, a node whose type is a place, such as a site or a branch, heads a column. Each card linked to it sits under it. A card linked to neighbouring places spans them. A card linked to places apart sits under each one.
- A node whose type is `gap`, or whose `gap` attribute is true, is a dashed card.
- Clicking a card opens a panel with its attributes, its lines to other nodes, and the evidence behind it. The evidence is the node's own `evidence` or `source` attribute, or else the model's sources, and the count of evidence records linked to the model.
- Below 760 pixels wide, a row's cards stack.

- **Responsible:** the person, who must be able to read the record.
- **Person:** names the model, the layout and the attribute or relation. Without the agent, in their agent folder:
  1. Finds the record id with `okb okb_find_records p_kind=model p_title="<words of the model's title>"`.
  2. Reads the record into a file: `okb okb_get_record p_record_id=<record id> result_file=record.json`
  3. Draws the board: `okb draw_board record_file=record.json layout=group by=<attribute> page_file=board.html`, or `layout=level by="<relation>"` for a level board.
  4. Opens `board.html` in a browser.
- **Agent:**
  1. Follows `okb:records` section 2. It finds the record with `okb_find_records`, with `p_kind` `model` and words of the name the person gave, unless the person gave its record id. It calls `okb_get_record` with `result_file` set to a new file in the agent folder, such as `<agent folder>/<name>.record.json`.
  2. Reads the record's node attributes and edge types from the file. For reporting lines, it offers `level` by the relation that holds them, such as reports to. For a structure by side, team or site, it offers `group` by that attribute. With no attribute to group by, it offers `level`. Or it asks which attribute to add to the model, as the `okb:records` skill's section 3 describes.
  3. Calls `draw_board` with the file as `record_file`, the `layout`, `by`, and a new `page_file`, such as `<agent folder>/<name>.board.html`.
  4. Checks the page, as "Check the page before giving it" says.
  5. Gives the person the page's full path, to open in a browser, and the Checked list. Gives the counts of cards and rows from the tool's result.
- **Evidence:** the record file, the page's path, size and counts from the tool's result, and the Checked list.

**AI guided:** the agent gives the person the layout and the attribute or relation before drawing, and waits for their approval.

## Check the page before giving it

Each drawing tool writes two files beside the page `<name>.html`. `<name>.outline.md` is the page's text in the order the page draws it, then its findings. `<name>.png` is a picture of the page's first screen, taken where Google Chrome, Chromium or Microsoft Edge is on the computer. The tool's result gives `outline_file`, `picture_file` and `findings`, the number of findings.

The board's and the graph's findings come from the plan model:

- An activity with no index, or two activities that share one.
- An activity with no description.
- A task that still lists a blocker that is completed or cancelled.
- A blocker that no task lists, and a deliverable or blocker that no task waits on.
- An activity that finishes before a child, or before a deliverable it waits on, as the `okb:records` skill's "Finish order" describes. The finding names both activities and both finishes. A cancelled activity, and one with no finish, is left out.

A model board's outline gives one line per row, with its count of cards and the places that head its columns. It then gives one line per card: its label, role and row, and the cards it sits under. A place or a gap is marked. Its findings are:

- Nodes that carry no value of the attribute grouped by, which the Ungrouped row holds.
- A node with more than one line of the relation drawn by level. Its card sits under the first.
- Lines of the relation that loop back. The node where the loop closes is on the top row.

- **Responsible:** the agent.
- **Person:** reads the page after the agent has checked it. Without the agent, reads the findings at the end of `<name>.outline.md`, and the picture `<name>.png`, before opening the page.
- **Agent:**
  1. Before drawing, lists every ask the person made of the page in the conversation, in their words, such as "grouped by sprint" or "each deliverable as its own item".
  2. After drawing, reads `outline_file` with `read_file`, and `picture_file` where there is one.
  3. Marks each ask against the outline line that meets it, quoted.
  4. Puts right each finding and each ask that is not met. A record is changed with the person's agreement, as the `okb:records` skill's section 3 describes. A tool's argument is changed directly. Then draws again, as a new page, and checks again.
  5. Gives the person the page once every ask is met and the findings are 0. The reply gives the page's full path, then a Checked list: each ask, and the outline line that meets it. An ask it cannot meet, it names, with the cause. With no picture, the reply says so, and why.
- **Evidence:** the outline, the picture, and the Checked list.

**AI guided:** the agent gives the person the Checked list with the page, and waits for their approval.

## What the tool refuses

- A call with both `record_file` and `progress_files`, or neither.
- A model board with no `layout` of `group` or `level`, or no `by`.
- `layout` or `by` with progress files, and `plan_id` or `purpose` with a record file.
- A model board grouped by an attribute no node carries, or drawn by level of a relation no line has. The refusal for a relation names the model's relations.
- A board with no purpose statement.
- Progress files from different reads. Every page carries the first page's save number and time.
- More than one plan with no parent, and no plan named. The refusal lists each plan's title and record id.
- A plan with more than 500 activities under it, and a model with more than 500 nodes.
- A page file, or its outline or picture, that already exists.
- A page file whose name does not end in `.html`.
