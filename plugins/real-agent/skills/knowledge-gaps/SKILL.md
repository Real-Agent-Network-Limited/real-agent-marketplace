---
name: knowledge-gaps
description: Use when the person agrees to log a question the knowledge base could not answer as a knowledge gap. Also use when a person says "log this as a knowledge gap", or asks to assign, move or close a gap. Saves each gap as a task under the plan "Knowledge gaps" in General, assigned to the person who can get the answer. It runs in one of three modes: human only, AI guided or human directed.
---

# Knowledge gaps

A knowledge gap is a question an agent could not answer from the firm's organisational knowledge base (OKB). Each gap is a task under one plan in General, titled "Knowledge gaps". The task says what was asked, what was searched, what came back and who may know. It is assigned to the person who can get the answer, and completed once the answer is saved in OKB.

Setup makes the plan, owned by the firm's owner. This skill uses the `okb:records` and `okb:writing` skills. It belongs to no one agent: any agent can run it.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as the wording of the description. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## The offer

The agent may tell the person that OKB holds no answer to a question. It then adds one line offering to log the question as a knowledge gap, which everyone in General can read. It offers once per question. It goes on with this skill after the person's yes. It also goes on when the person asks in their own words, such as "log this as a knowledge gap".

## 1. Find the log

1. **Find the plan.**
   - **Person:** runs `okb okb_get_scopes`, notes General's `scope_id`, then runs `okb okb_find_records p_kind=activity p_scope_id=<General's id> p_title="Knowledge gaps"`.
   - **The agent:** calls `okb_get_scopes`, takes the id of the scope with the code `general`, and calls `okb_find_records` with `p_kind` `activity`, that scope's id and `p_title` "Knowledge gaps". It takes the plan whose title is "Knowledge gaps".
2. **When there is no plan.** A project set up before the log came in has none.
   - **Person:** asks an administrator to make it.
   - **The agent:** says so in one line. For an administrator, it offers to make the plan. It calls `okb_add_record` in General with the title "Knowledge gaps" and `activity_kind` `plan`. It shows and saves it as the `okb:records` skill's section 3 describes. For anyone else, it names their administrator and stops.
3. **Read the gaps already logged.**
   - **Person:** runs `okb okb_get_progress p_cutoff=null p_observed_at=null p_cursor=null p_limit=100 p_scope_id=<General's id> result_file=progress-1.json`.
   - **The agent:** calls `okb_get_progress` for General, every page while the answer has a `next_cursor`, and keeps the tasks whose parent is the plan. The next gap's `index` is `1.<n>`, one above the highest `1.` index there, or `1.1` for the first. When the same question is already logged and open, it names that gap and saves no second one.

**AI guided:** the agent names the plan and the next index, and waits for the person before section 2.

## 2. Log a gap

1. **Ask who can get the answer.**
   - **Person:** names the person who knows, or who can find out.
   - **The agent:** asks once. It finds that person with `okb_find_people`, with General's id and the words of the name, as the `okb:records` skill's section 9 describes. With more than one, it lists the names and asks which. With none, it says an administrator can add them, and offers to assign the gap to the plan's owner instead.
2. **Preview the gap.** The gap is one task under the plan, with these fields:
   - The title is the question in a few words, with no number, such as "When the office closes for Christmas".
   - `activity_kind` is `task`, and `index` is the next number from section 1.
   - `description` holds four lines. "Asked:" gives the question, the person's name and the date. "Searched:" gives each search and read the agent made, and each outside source it looked in. "Returned:" gives what came back, or "Nothing that answers it". "Who may know:" gives the person's own words.
   - `completion_requirements` names the answer that closes it, and where it is saved, such as "The closing dates, saved as an evidence record in General".
   - `assignee_actor_id` is the person from step 1.
   - **Person:** runs `okb okb_add_record p_scope=general p_kind=activity p_title="<the question>" p_reason="A question the knowledge base could not answer" p_fields.activity_kind=task p_fields.index=1.<n> p_fields.description="<four lines>" p_fields.completion_requirements="<the answer and where it goes>" p_fields.assignee_actor_id=<actor id> p_parent="Knowledge gaps" p_preview=true`.
   - **The agent:** calls `okb_add_record` with those fields, `p_parent` "Knowledge gaps" and `p_preview` true. It shows the save as the `okb:records` skill's section 3 describes, with the assignee's name, never their id.
3. **Save it once the person agrees.**
   - **Person:** runs the same command without `p_preview`.
   - **The agent:** calls `okb_save_version` with the preview's `request` and `authorisation_id`, unchanged. It tells the person the gap's index and title, and that it is now in the assignee's tasks.
   - **Evidence:** the saved version's `record_id` and `version_id`.

**AI guided:** the agent shows the gap and its assignee, and saves it when the person agrees.

## 3. Assign or move a gap

The person names a gap by its index, such as "assign 1.2 to Sam".

- **Person:** runs `okb okb_assign p_record="<the gap's title>" p_person="<words of the name>" p_reason="<why>" p_preview=true`, then the same without `p_preview`.
- **The agent:** finds the gap by its index under the plan, as section 1, step 3 does. It calls `okb_assign` with `p_preview` true, shows both names, and saves once the person agrees, as the `okb:records` skill's section 9 describes.
- **Evidence:** the saved version, and the gap's history, where `assignee_actor_id` changed.

**AI guided:** the agent shows both names, and moves the gap when the person agrees.

## 4. Close a gap

A gap closes once its answer is in OKB.

1. **Save the answer.**
   - **Person:** uploads a file that holds it, or saves an evidence record that states it.
   - **The agent:** saves the answer as an evidence record in General, or uploads its file, as the `okb:records` and `okb:actor` skills describe. It shows the save first. An answer taken from an outside source keeps its link in `source_reference`.
2. **Complete the task.**
   - **Person:** runs `okb okb_link p_record="<the gap's title>" p_target="<the evidence record>" p_relation=supports p_reason="The answer" p_preview=true`, then `okb okb_set_state p_record="<the gap's title>" p_state=completed p_reason="Answered" p_note="<where the answer is>" p_preview=true`, each then without `p_preview`.
   - **The agent:** links the gap to the evidence with `okb_link` and `supports`, starts it if it is Pending, then completes it with `okb_set_state`. The completion note names where the answer is. Each save is shown first, as the `okb:records` skill's section 4 describes.
   - **Evidence:** the evidence record, and the completed version.

**AI guided:** the agent shows each save, and closes the gap when the person agrees.

## Problems

- **Two gaps saved at once share an index:** read the progress again, and offer the next number.
- **No `create` grant in General:** the person cannot log a gap. The agent names the plan's owner, who can log it for them.
- **Completing is refused:** the gap needs its completion requirements, a completion note, a `supports` link to an evidence record and the `complete` grant. The `okb:records` skill's section 4 gives each rule. The plan's owner or an administrator can complete it.
