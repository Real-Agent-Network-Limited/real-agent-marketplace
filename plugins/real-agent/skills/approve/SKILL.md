---
name: approve
description: Use when a person approves, rejects or asks for changes to a model in OKB, in the session they are in. The model is a current state, how the firm works today, or a proposed design for Real Agent to build. Finds the model from the person's words, draws its exact version, and says what approving it means. Saves the decision as the person, linked to that version, then says what happens next. It runs in one of three modes: human only, AI guided or human directed.
---

# Approve

A person approves one exact version of a model record in the firm's OKB. The model is one of two kinds:

- **A current state**, a model whose `model_kind` is `observed_current`: how the firm works today. Approving it confirms the firm works this way. Real Agent designs the new way of working from it.
- **A proposed design**, a model whose `model_kind` is `proposed_target`: how the firm will work. Approving it tells Real Agent to build it, at the price shown. Nothing is built without it.

The approval is a decision record, saved by the person who approves, signed in as themselves, so the audit log names them. It links to the exact model version with `supports`. A request for changes, or a rejection, is a decision too. It links to the version with `describes`, and holds the person's words.

This skill belongs to no one agent. The person's own agent runs it in the session where the person asks, and never sends them to another session or another agent to approve. Every call goes through the okb plugin's `rpc` tool, as the `okb:records` skill says. Every save follows that skill's section 3: preview first, and save only what the person agrees to. Drawing follows the `okb:graph` skill's section 3. Every sentence the person reads follows the `okb:writing` skill.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command in their folder.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as drawing the model again. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead. Nothing replaces the person's own words as the approval.

## 1. Find the model

1. **Find the model the person means.**
   - **Person:** names the model, such as "the current routine" or "the proposed design". Without the agent, runs `okb okb_find_records p_kind=model`, adding `p_title="<words of the title>"` when they know them.
   - **The agent:** calls `okb_find_records` with `p_kind` `model`, and `p_title` when the person's words name the title. It pages with `next_cursor`. It reads each record found with `okb_get_record`. The person's words pick the kind: "current", "today" or "how we work" mean `observed_current`, and "proposed", "design", "new" or "build" mean `proposed_target`. When one model fits, it goes on. When several fit, it lists each one's title, scope and when it was saved, and asks once which they mean. When none fits, it says that the person's Real Agent knowledge base holds no model they can read by that name, and stops.
2. **Check the person may approve.**
   - **Person:** runs `okb okb_get_actor` and `okb okb_get_authorisations`.
   - **The agent:** calls `okb_get_actor`. An administrator who is a person may approve in any scope that is not private. Anyone else needs a live grant in the model's scope whose record kinds include `decision` and whose actions include `create` and `decide`, from `okb_get_authorisations`. Without one, it says in one sentence that their role does not let them make decisions in that scope. Their administrator can give them that. Then it stops.

**AI guided:** the agent gives the person the model it found and their right to approve, and waits for their approval.

## 2. Draw the version

1. **Read the exact version, and draw it.** Skip the drawing when this session has drawn this version already.
   - **Person:** runs `okb okb_get_record p_record_id=<record id> result_file=approve.json`, then `okb draw_state_machine record_file=approve.json page_file=approve.html`, and opens `approve.html` in a browser.
   - **The agent:** calls `okb_get_record` with `result_file`, a new file in the agent folder named for the record and its version. It notes the `version_id` and `version_number`. It counts the routines: the graph's nodes whose `type` is `routine`, or one routine when there are none. It draws the file with `draw_state_machine`, or with `draw_graph` when that refuses, and checks the page as the `okb:board` skill's "Check the page before giving it" says.

**AI guided:** the agent gives the person the page, and waits for their approval.

## 3. Ask for the decision

1. **Say what approving means, and ask.** One message holds the page's full path, the model's title and version, and each routine with its trigger and outcome. It adds one sentence on what approving means, the decision it will save, and one question.
   - **Person:** reads the page, and says "approve" or names each change, in their own words.
   - **The agent:** gives the sentence for the model's kind, filled in:
     - Current state: "Approving it confirms this is how you work today, and Real Agent designs the new way of working from it."
     - Proposed design: "Approving it tells Real Agent to build these <n> routines, for £<n × 100> plus VAT, then £<n × 10> a month plus VAT to keep them up to date."
     It then asks once: "Do you approve this version, or would you like changes?" It never takes silence, a page path, an earlier message or someone else's words as the approval. The person's own yes to this question is their agreement to the save.

**AI guided:** the agent asks the question, and waits for the person's words.

## 4. Save the decision

1. **Preview the decision, then save it, as the person.** Each decision is a new record in the model's scope, titled for the model, its version and the outcome.
   - **Person:** runs `okb okb_add_record p_scope=<scope> p_kind=decision p_title="<model title>, version <n>, approved" p_reason="Approval" p_fields.question="<question>" p_fields.decision="<decision>" p_fields.rationale="<their words>" p_fields.decided_on=<date> p_preview=true`. Then runs it again without `p_preview`, and links it with `okb okb_link p_record="<decision title>" p_target=<model record id> p_relation=supports p_reason="Approval"`. For changes, the title ends "changes asked for", and the relation is `describes`.
   - **The agent:** reads the model again with `okb_get_record`, and checks the version is still its latest. When it is not, it draws the newer version and asks again from section 3. It calls `okb_add_record` with `p_kind` `decision`, `p_reason` "Approval", and `p_preview` true. Its `p_fields`:
     - `question`: "Approve <title>, version <n>, <version id>, as how the firm works today?" for a current state. For a proposed design: "Approve <title>, version <n>, <version id>, as the design to build: <n> routines, £<n × 100> plus VAT, then £<n × 10> a month plus VAT?"
     - `alternatives`: `["Approve this version", "Ask for changes"]`.
     - `decision`: "Approved: this is how we work today" for a current state, "Approved: <n> routines, £<n × 100> plus VAT, then £<n × 10> a month plus VAT" for a proposed design, or "Changes asked for".
     - `rationale`: the person's own words, as they said them. `decided_on`: today's date.
     It sets the preview's `request` `links` to one link to the `version_id`: `supports` for an approval, `describes` for changes. It calls `okb_save_version` with that request and the preview's `authorisation_id`. For changes, it shows the decision first and saves it once the person agrees.

**AI guided:** the agent shows the person the decision before saving it, and waits for their approval.

## 5. Say what happens next

1. **Tell the person, in one or two sentences.**
   - **Person:** reads what happens next.
   - **The agent:** says one of these, filled in:
     - A current state approved, with no proposed design yet: "Saved: you approved how you work today. Real Agent designs the new way of working next, and asks you to approve it."
     - A current state approved, with a proposed design already saved: "Saved: you approved how you work today. The proposed design, <title>, is ready for you to approve next." A proposed design is a `proposed_target` model in the same scope that links to this model with `describes`, or whose title names the same routine.
     - A proposed design approved: "Saved: you approved <title> and its price. Real Agent builds its <n> routines next, for £<n × 100> plus VAT, then £<n × 10> a month plus VAT."
     - Changes asked for: "Saved: your changes to <title>. Real Agent revises it and asks you to approve the new version."

- **Evidence:** the page's path, the model's `version_id`, the decision's `record_id` and `version_id`, and the person's words. The audit log, the `okb:records` skill's section 8, lists the save under the person.

**AI guided:** the agent gives the person what happens next, and waits for them.

## Problems

- **`No grant of yours covers ... decide on decision records in ...`:** the person's role does not let them make decisions in that scope. The agent says so in one sentence, and that their administrator can give them that.
- **The previous version is stale:** the model or the decision changed since the preview. The agent reads the model again, draws the newer version, and asks again from section 3.
- **The person names a version that is not the latest:** the agent says a later version exists, draws it, and asks about that one. A later version is unapproved until its own approval.
