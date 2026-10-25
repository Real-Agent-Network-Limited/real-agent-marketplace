---
name: approve
description: Use when a person approves, or asks for changes to, a workflow model in OKB, in their own session. A workflow is made of routines, and is a current state or a proposed design. Draws the model's exact version, and takes its routines one at a time, one question per reply. Saves one decision per routine as the person, linked to that version, then says what happens next. It runs in one of three modes: human only, AI guided or human directed.
---

# Approve

A person approves one exact version of a model record in the firm's OKB. The model is a **workflow**: how a whole piece of the firm's work runs, such as taking a market appraisal through to a signed agreement. A workflow is made of **routines**. A routine is one part of the workflow that starts from one trigger and ends in one outcome. Each routine is approved on its own, with its own decision record. The model is one of two kinds:

- **A current state**, a model whose `model_kind` is `observed_current`: how the firm works today. Approving a routine confirms the firm works this way. Real Agent designs the new way of working from the approved routines.
- **A proposed design**, a model whose `model_kind` is `proposed_target`: how the firm will work. Approving a routine tells Real Agent to build it, for £100 plus VAT, then £10 a month plus VAT to keep it up to date. Nothing is built without its approval.

Each approval is a decision record, saved by the person who approves, signed in as themselves, so the audit log names them. It names its routine in its title and its fields. It links to the exact model version with `supports`. A request for changes to a routine is a decision too. It links to the version with `describes`, and holds the person's words.

This skill belongs to no one agent. The person's own agent runs it in the session where the person asks, and never sends them to another session or another agent to approve. Every call goes through the okb plugin's `rpc` tool, as the `okb:records` skill says. Every save follows that skill's section 3: preview first, and save only what the person agrees to. Drawing follows the `okb:graph` skill's section 3. Every sentence the person reads follows the `okb:writing` skill.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command in their folder.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as drawing the model again. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead. Nothing replaces the person's own words as the approval of each routine.

## 1. Find the model

1. **Find the model the person means.**
   - **Person:** names the workflow, such as "the current routines" or "the proposed design". Without the agent, runs `okb okb_find_records p_kind=model`, adding `p_title="<words of the title>"` when they know them.
   - **The agent:** calls `okb_find_records` with `p_kind` `model`, and `p_title` when the person's words name the title. It pages with `next_cursor`. It reads each record found with `okb_get_record`. The person's words pick the kind: "current", "today" or "how we work" mean `observed_current`, and "proposed", "design", "new" or "build" mean `proposed_target`. When one model fits, it goes on. When several fit, it lists each one's title, scope and when it was saved, and asks once which they mean. When none fits, it says that the person's Real Agent knowledge base holds no workflow they can read by that name, and stops.
2. **Check the person may approve.**
   - **Person:** runs `okb okb_get_actor` and `okb okb_get_authorisations`.
   - **The agent:** calls `okb_get_actor`. An administrator who is a person may approve in any scope that is not private. Anyone else needs a live grant in the model's scope whose record kinds include `decision` and whose actions include `create` and `decide`, from `okb_get_authorisations`. Without one, it says in one sentence that their role does not let them make decisions in that scope. Their administrator can give them that. Then it stops.

**AI guided:** the agent gives the person the model it found and their right to approve, and waits for their approval.

## 2. Draw the version and list its routines

1. **Read the exact version, and draw it.** Skip the drawing when this session has drawn this version already.
   - **Person:** runs `okb okb_get_record p_record_id=<record id> result_file=approve.json`, then `okb draw_state_machine record_file=approve.json page_file=approve.html`, and opens `approve.html` in a browser.
   - **The agent:** calls `okb_get_record` with `result_file`, a new file in the agent folder named for the record and its version. It notes the `version_id` and `version_number`. It draws the file with `draw_state_machine`, or with `draw_graph` when that refuses, and checks the page as the `okb:board` skill's "Check the page before giving it" says.
2. **List the routines, from the model's payload.**
   - **Person:** reads the outline beside the page, `approve.outline.md`. Each `## Routine:` heading is one routine, with its id and name, and its states under it.
   - **The agent:** reads the routines from the payload's `graph`:
     - Each node whose `type` is `routine` is a routine. Each node whose `type` is `route_group` is a supporting routine, which the person reads as "<name>, a supporting routine".
     - A routine's id is its `reference` attribute, such as `0.1`, and its name is its `label`. Routines run in the order of the outline's `## Routine:` headings.
     - A routine's states are the nodes with a `part_of` edge to it, in the outline's order. Its trigger is its `start` state, or its first state when it has none. Its outcome is its `end` states, or its last state when it has none.
     - A model with no `routine` or `route_group` node has no routine grouping. The agent takes the whole model as one routine, named by the model's title, with no id.
3. **Find the routines already decided.** A routine is decided when a made decision in the model's scope links to this `version_id` and names the routine in its title.
   - **Person:** runs `okb okb_find_records p_kind=decision p_title="<model title> version <n>"`, and reads each with `okb okb_get_record`.
   - **The agent:** calls `okb_find_records` with `p_kind` `decision` and `p_title` the model's title, and reads each with `okb_get_record`. It keeps those whose `links` hold this `version_id`. Each routine they name is left out of the routines still to decide.

**AI guided:** the agent gives the person the page and the list of routines, and waits for their approval.

## 3. Take each routine in turn

One reply deals with one routine, and asks one question. The first reply also holds the list.

1. **Give the list, with the first routine.**
   - **Person:** reads the page and the list of routines.
   - **The agent:** writes the page's full path, then the list, filled in: "<title>, version <n>, is a workflow of <k> routines. Each routine is approved on its own. The routines are:" with one line per routine, such as "0.1 Booking" or "0.7 Media billing, a supporting routine". For a model with no routine grouping, the list is instead: "<title>, version <n>, has no routines marked in it, so I'll take it as one routine." Routines already decided are named once: "<ids and names> are already decided." Then it adds the sentence for the model's kind:
     - Current state: "Approving a routine confirms this is how you work today."
     - Proposed design: "Approving a routine tells Real Agent to build it. Each routine costs £100 plus VAT to create, then £10 a month plus VAT to keep up to date."
     Then it gives the first routine still to decide, as the next step says.
2. **Show one routine, and ask about it.**
   - **Person:** reads the routine, and says "approve" or names each change, in their own words.
   - **The agent:** writes, filled in: "Routine <i> of <k>: <id> <name>. It starts with: <trigger>. It ends with: <outcome>. Its steps: <each state's name, in order>." For a supporting routine, it adds "It is a supporting routine." For a proposed design, it adds "Building it costs £100 plus VAT, then £10 a month plus VAT to keep it up to date." Then it asks once: "Do you approve routine <id> <name> as it is, or would you like changes?" Each routine has its own question. It never takes silence, a page path, an earlier message, the answer about another routine or someone else's words as the approval. The person's own yes to this question is their agreement to that routine's save.
3. **Take a request to approve them all.**
   - **Person:** says "I approve all of them", or "approve all <k> at once".
   - **The agent:** before the person has seen the list, "I approve the current routines" or "I approve all of them" still goes one routine at a time, as step 2 says. Once the person has seen the list, they may say plainly to approve all <k> at once. Then the agent previews one decision per routine, as section 4 says. It shows them in one message, one line per routine, and asks once: "Shall I save these <k> approvals, one for each routine?" Their yes saves them all, and the agent goes to section 5.

**AI guided:** the agent asks each routine's question, and waits for the person's words.

## 4. Save each routine's decision

1. **Preview the decision, then save it, as the person.** Each decision is a new record in the model's scope, titled for the model, its version, the routine and the outcome.
   - **Person:** runs `okb okb_add_record p_scope=<scope> p_kind=decision p_title="<model title>, version <n>, routine <id> <name>, approved" p_reason="Approval" p_fields.question="<question>" p_fields.decision="<decision>" p_fields.rationale="<their words>" p_fields.decided_on=<date> p_preview=true`. Then runs it again without `p_preview`, and links it with `okb okb_link p_record="<decision title>" p_target=<model record id> p_relation=supports p_reason="Approval"`. For changes, the title ends "changes asked for", and the relation is `describes`.
   - **The agent:** reads the model again with `okb_get_record`, and checks the version is still its latest. When it is not, it draws the newer version and starts again from section 2. It calls `okb_add_record` with `p_kind` `decision`, `p_reason` "Approval", `p_preview` true, and the title above. A model with no routine grouping leaves out "routine <id> <name>, " from the title. Its `p_fields`:
     - `question`: "Approve routine <id> <name> of <title>, version <n>, <version id>, as how the firm works today?" for a current state. For a proposed design: "Approve routine <id> <name> of <title>, version <n>, <version id>, to build: £100 plus VAT, then £10 a month plus VAT?"
     - `alternatives`: `["Approve this routine", "Ask for changes"]`.
     - `decision`: "Approved: routine <id> <name> is how we work today" for a current state, "Approved: routine <id> <name>, £100 plus VAT, then £10 a month plus VAT" for a proposed design, or "Changes asked for: routine <id> <name>".
     - `rationale`: the person's own words, as they said them. `decided_on`: today's date.
     It sets the preview's `request` `links` to one link to the `version_id`: `supports` for an approval, `describes` for changes. It calls `okb_save_version` with that request and the preview's `authorisation_id`. For changes, it shows the decision first, asks "Shall I save this change request for routine <id> <name>?", and saves it once the person agrees.
2. **Go on to the next routine.**
   - **Person:** reads that the routine is saved, and the next one.
   - **The agent:** says "Saved: routine <id> <name>, approved." or "Saved: your changes to routine <id> <name>." In the same reply, it shows the next routine still to decide and asks its question, as section 3's step 2 says. After the last routine, it goes to section 5. When the person stops part way, it says which routines are still to decide, and that they can carry on in any session.

**AI guided:** the agent shows the person each decision before saving it, and waits for their approval.

## 5. Say what happens next

1. **Tell the person, after the last routine, in one or two sentences.**
   - **Person:** reads what happens next.
   - **The agent:** says one of these, filled in. <a> is the number of routines approved in this version, and <c> the number with changes asked for.
     - A current state, with no proposed design yet: "That was the last of the <k> routines. You approved <a> of them. Real Agent designs the new way of working next, and asks you to approve each of its routines."
     - A current state, with a proposed design already saved: "That was the last of the <k> routines. You approved <a> of them. The proposed design, <title>, is ready for you to approve next, one routine at a time." A proposed design is a `proposed_target` model in the same scope that links to this model with `describes`, or whose title names the same workflow.
     - A proposed design: "That was the last of the <k> routines. You approved <a> of them, for £<a × 100> plus VAT to create, then £<a × 10> a month plus VAT to keep them up to date. Real Agent builds them next."
     - With changes asked for, it adds: "Real Agent revises <the ids and names of those routines>, and asks you to approve the new version."

- **Evidence:** the page's path, the model's `version_id`, each decision's `record_id` and `version_id` with its routine, and the person's words. The audit log, the `okb:records` skill's section 8, lists each save under the person.

**AI guided:** the agent gives the person what happens next, and waits for them.

## Problems

- **`No grant of yours covers ... decide on decision records in ...`:** the person's role does not let them make decisions in that scope. The agent says so in one sentence, and that their administrator can give them that.
- **The previous version is stale:** the model or the decision changed since the preview. The agent reads the model again, draws the newer version, and starts again from section 2.
- **The person names a version that is not the latest:** the agent says a later version exists, draws it, and asks about that one. A later version is unapproved until each of its routines is approved.
- **The person names a routine the model does not hold:** the agent says the workflow has no routine by that name. It gives the list again.
