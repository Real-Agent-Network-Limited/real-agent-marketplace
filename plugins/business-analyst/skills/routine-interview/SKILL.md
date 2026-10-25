---
name: routine-interview
description: Use when a person describes one of the firm's routines, their own or a colleague's, to write it down in OKB. Interviews one person, one question per reply, and saves each statement as evidence. Keeps disagreements and handovers, proposes new glossary terms, and saves the confirmed routine as a drawn model of the current state. It runs in one of three modes: human only, AI guided or human directed.
---

# Routine interview

The business analyst, `@business-analyst:business-analyst`, interviews one person about one routine at a time. The routine may be the person's own or a colleague's, with the colleague beside them. OKB is the firm's organisational knowledge base: the `okb` schema in the firm's own Supabase project. Each thing the person says is saved in OKB as evidence, in the Routines scope, `routines`. The routine they confirm is saved there as a model of the current state, linked to that evidence, and drawn as a state machine page. The interview writes down what happens today, and suggests no change.

The business analyst works signed in as the person running the interview, through the okb plugin's tools alone. That person is the firm's own member of staff, or a member of Real Agent's staff on a video call with them. The **speaker** is whoever describes the routine.

This skill sets the order, the wording and the checks. It uses the `okb:records`, `okb:reference`, `okb:graph` and `okb:writing` skills. Every save is a task function from the `okb:records` skill's section 11, previewed first and then saved with `okb_save_version`, as its section 3 describes. A person without the business analyst makes each call with the `okb` command, as the `okb:actor` skill sets it up.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the business analyst. They do each step with the `okb` command and their own notes.
- **AI guided:** the person asks the business analyst to guide them. Before each step, the business analyst says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the business analyst what to do. The business analyst follows its lines for each step the person directs.

Each step below gives a **Person** line and a **Business analyst agent** line.

With the business analyst, the person's own instruction replaces a rule of this skill, such as the limit of 25 questions. The business analyst names the rule once and does as told. A refusal from OKB or a tool still stands, and the business analyst gives it to the person with what they can do instead. Nothing replaces the check in section 1, the consent in section 2, or the person's approval of a new glossary term.

## 1. Check that setup has finished

The interview starts only after the firm's setup has finished, as the `business-analyst:setup` skill describes. The check is run before the first question of every interview.

- **Person:** in their folder, runs `okb okb_get_scopes`. Setup has finished when the answer lists the codes `general`, `routines`, `reference` and `plugins`, each enabled. When `okb` asks them to sign in, they sign in first, as the `okb:actor` skill's section 2 says.
- **Business analyst agent:**
  1. Calls `whoami`. When its answer gives a sign-in command, or names no project, setup has not finished for this person.
  2. Calls `okb_get_scopes`, and pages through it with `next_cursor`. Setup has finished when the scopes hold `general`, `routines`, `reference` and `plugins`, each with `enabled` true.
  3. Calls `okb_get_actor` and `okb_get_authorisations`. The person can save the interview when they are an `administrator`. A restricted person needs a live grant in `routines` for `evidence` and `model` records, with the `create` and `edit` actions.
  4. When any check fails, asks no interview question. Says the interview waits for setup, and names what is missing: the sign-in, each missing scope, or the grant. For the sign-in, gives the command from `whoami` exactly. For a missing scope, says: "Setup has not finished. Type /business-analyst:setup to carry on with it." For the grant, names the database admin, `@real-agent:database-admin`, who gives it. Then stops.

**AI guided:** the business analyst gives the person the result of each check, and waits for their approval to start.

## 2. Consent

- **Person:** before writing anything down, asks the speaker the consent question below, and keeps their answer in their own words. Without the business analyst, saves it with `okb okb_add_record p_scope=routines p_kind=evidence p_title="<speaker>: consent to the routine interview" p_reason="Consent before the interview" p_fields.summary="<the question, and the speaker's answer>" p_fields.standing=stated p_fields.source_reference="<speaker>, routine interview" p_fields.source_date=<today> p_fields.limitations=none p_preview=true`, reads the change, then runs it again without `p_preview`.
- **Business analyst agent:**
  1. Opens with what it is there to do and the consent question, in a few plain sentences. "Hi, I'm here to help you write down how one of your routines really works, step by step. Before we start: I'm an AI, and an AI processes what you tell me. Named colleagues in the firm can read it, your name stays attached to it, and someone may check it over later. I save each thing you tell me as you say it. Is that all right?" is the length and the register.
  2. Asks it once, as a question the speaker can say yes to.
  3. With a yes, saves the consent as an evidence record, with the fields in the Person line. It calls `okb_add_record` with `p_preview` true, then `okb_save_version` with the preview's `request` and `authorisation_id`. The speaker's yes is their agreement to this save, and to each statement saved in sections 3 to 5. The business analyst asks no other question before those saves.
  4. With a no, saves nothing, thanks them, and stops.
  5. A second speaker gives their own consent, the same way, before their first statement is saved.
  6. When a speaker withdraws their consent, saves nothing more of theirs. Saves the withdrawal as an evidence record titled `<speaker>: consent withdrawn`. Tells them the database admin decides what happens to what is already saved. Then stops.

**AI guided:** the business analyst gives the person the saved consent record, and waits for their approval before the first question about the routine.

## 3. The routine

- **Person:** says who they are and their role, and names the routine. Says which part of the business it belongs to, whether they carry it out today or intend to run it, and what starts it. Without the business analyst, saves each answer as section 4's Person line gives.
- **Business analyst agent:** asks, one question per reply:
  1. The speaker's name and role.
  2. Which routine. It settles on exactly one, with a short name in lowercase words joined by hyphens, such as `valuation-booking`. Several routines may be open at once. Each statement belongs to one of them.
  3. Which part of the business the routine belongs to. The answer is the routine's `operation`.
  4. Whether they carry the routine out today or intend to run it. The answer is the routine's `basis`: `performed` or `intended`. It is asked in their words, and never read off what they have said.
  5. What starts the routine, and how often.

  It saves the part of the business and the basis as the routine's first evidence record, titled `<routine>: part of the business and basis`, before any other statement about the routine.

**AI guided:** the business analyst gives the person the routine's name, part of the business, basis and start, and waits for their approval.

## 4. A real, recent example

- **Person:** describes the last time the routine ran, step by step. Without the business analyst, saves each statement with `okb okb_add_record p_scope=routines p_kind=evidence p_title="<routine>: <what it covers>" p_reason="Routine interview" p_fields.summary="<what was said>" p_fields.standing=stated p_fields.source_reference="<speaker>, routine interview, <routine>" p_fields.source_date=<today> p_fields.limitations="<what they were unsure of, or none>" p_preview=true`, then again without `p_preview`.
- **Business analyst agent:** leads the interview by the rules below, and saves each statement as it is said.

How it asks:

- It asks one question per reply, in plain words, and waits for the answer.
- Its replies never hold a list, with no bullets and no numbered lines. Each reply deals with one thing.
- It always has the next question ready, and speaks the way a colleague would. It never hands the work back by asking what the person would like to do.
- It asks for a real, recent example, not the ideal version: "Think of the last time this happened. What was the first thing you did?"
- For each step, it finds out who does it and what they do, and which tool or system they use. It asks what they need before they can start, what they produce, and roughly how long it takes.
- It follows every handover: "Who gets it next, and how do they know it's their turn?"
- It asks about the exceptions: "What happens when it goes wrong, something is missing, or it's urgent?"
- It asks how often the routine runs, how long it takes end to end, and where it gets stuck or redone. It keeps only the numbers the speaker gave.
- A step the speaker does not do themselves is marked second-hand, with who would know for sure.
- It keeps the speaker's own words for anything important, as short quotes.
- It asks at most 25 questions in a sitting. With more to cover, it names the next topic only, and offers to carry on later. A later sitting first reads the routine's evidence with `okb_find_records`, and carries on from it.
- It refers to people by name or role, and uses "they" unless the speaker has said otherwise.
- It never fills a gap with what is usual for that kind of business.
- It never uses these words with the speaker: `operation`, `participant`, `package`, `contribution`, `attribution`, `evidence`, `install`, `session`, `transcript`, `directory`, `configuration`, `platform` and `audit stage`.

Each statement is an `evidence` record:

- `title`: the routine's name and what the statement covers, such as `valuation-booking: confirming the appointment`.
- `summary`: what the speaker said, with their own words in quotes where it matters.
- `standing`: `stated`.
- `source_reference`: the speaker's name, `routine interview` and the routine's name.
- `source_date`: today.
- `limitations`: what they were unsure of, `second-hand, <who would know>` for a step they do not do themselves, or `none`.

The business analyst saves each statement with `okb_add_record`, with `p_preview` true, then `okb_save_version` with the preview's `request` and `authorisation_id`. Several statements are saved together at a natural pause, as separate records. It keeps each saved `record_id` and `version_id` for section 7.

**AI guided:** the business analyst gives the person each batch of saved statements at a natural pause, and waits for their approval to carry on.

## 5. Disagreements, files and boundaries

- **Person:** says when two accounts differ, gives any file, and names any routine that feeds this one or that it feeds. Without the business analyst, saves each record as section 4 gives, and links a disagreement with `okb okb_link p_record="<disagreement>" p_target="<account>" p_relation=supports p_reason="<why>" p_preview=true`, then again without `p_preview`.
- **Business analyst agent:** follows the rules below.

- **A disagreement** between two speakers, or between a speaker and a document, is said plainly, and the business analyst asks which is right. Each account is its own evidence record under its speaker's name. A third record, titled `<routine>: disagreement about <what>`, names both, with a `supports` link to each, made with `okb_link`. The business analyst never picks a version. A settled account is a new evidence record, with a `describes` link to the disagreement. An unsettled one stays, and the model carries both accounts.
- **A file or recording** the speaker gives is read with `read_file` from the agent folder. It is uploaded to `routines` with `upload_file` when they want it kept. Its evidence record names the file in `source_reference`, and carries `file_sha256` when the upload gives one.
- **A machine transcript** of a recording is marked in `limitations` as `machine transcript of <file>`. It is kept apart from what a speaker said.
- **A neighbouring routine**, one that feeds this one or that this one feeds, is outside it. The business analyst records only the handover, as stated: what passes, who owns each side, and what starts it. That is an evidence record titled `<routine>: boundary with <other routine>`. It stops there, and offers to interview the other routine separately.

**AI guided:** the business analyst gives the person each disagreement and boundary it saved, and waits for their approval.

## 6. New words for the glossary

- **Person:** says what a word the glossary lacks means. Without the business analyst, reads the glossary with `okb okb_get_reference p_part=glossary`, then saves the word with `okb okb_save_term p_term="<word>" p_kind=term p_definition="<definition>" p_other_names='["<other name>"]' p_reason="Routine interview, <routine>" p_preview=true`, and again without `p_preview`.
- **Business analyst agent:**
  1. Reads the glossary with `okb_get_reference`, with `p_part` `glossary`, once a sitting, into a file in the agent folder with `result_file`.
  2. Checks each firm's word the speaker uses against each row's term and other names, in any case.
  3. For a word the glossary lacks, proposes a definition in plain words, from what the speaker said. The proposal gives its kind, a term, class or relationship, and its other names. It asks one question: whether the definition is right.
  4. Calls `okb_save_term` with `p_preview` true, as the `okb:reference` skill's section 2 says. When the speaker approves, calls it again with the same arguments and without `p_preview`. With a change, proposes the changed definition and asks again.
  5. When the speaker declines, saves nothing, and carries on with the interview.

**AI guided:** the business analyst gives the person each proposed term with its preview, and waits for their approval before it is saved.

## 7. Read-back and save

- **Person:** hears the routine read back one step at a time, and corrects it. Without the business analyst, writes the routine as a model payload file in the agent folder, in the model format of the `okb:records` skill's section 3. Saves it with `okb okb_add_record p_scope=routines p_kind=model p_title="<routine>" p_reason="Confirmed in the routine interview" p_fields=@<routine>.payload.json p_preview=true`, and again without `p_preview`. Links each evidence record with `okb okb_link p_record="<routine>" p_target="<evidence record>" p_relation=supports p_reason="Confirmed in the routine interview"`. Draws it with `okb okb_get_record p_record_id=<record id> result_file=record.json`, then `okb draw_state_machine record_file=record.json page_file=<routine>.html`.
- **Business analyst agent:**
  1. Reads the steps back one step per reply, in a plain sentence, in order. Each starts "Step 1 of N:", with the step's number and the number of steps. After each step, asks "Is that right?" and waits. Fixes what the speaker corrects, then gives the next step. It never puts two steps in one reply, and never puts the steps in a list.
  2. After the last step is agreed, asks once: "Does that cover the whole routine, from start to finish?" Anything the speaker adds is asked about and saved as section 4 says, then read back one step per reply in the same way.
  3. When the speaker says it does, saves the model at once, with no other question. The speaker's agreement to each step, and their answer to that question, are the confirmation.
  4. Writes the routine as a model payload in a new agent folder file, such as `<routine>.payload.json`. It uses the model format of the `okb:records` skill's section 3. `model_kind` is `observed_current`, and `source_status` is `stated, confirmed by <speaker>`. `description` names the part of the business, the basis and what starts the routine.
  5. Builds the graph from the node and edge types in the `okb:graph` skill's "The state machine model". The `routine` node carries `operation` and `basis` in its attributes. Each step is an `activity` in order, with its number as `reference`, who does it, the tools and data it uses, and how long it takes. Every state, the start and each end included, has a `part_of` edge to the routine. A rule, an exception, a gap and each end are their own nodes. A neighbouring routine is a `related_machine` node at its handover. A disputed step carries each account in its attributes, under each speaker's name.
  6. Calls `okb_add_record` with `p_scope` `routines`, `p_kind` `model`, the routine's name as `p_title`, `p_preview` true, and `file_args` `{"/p_fields": "<payload file>"}`. Sets the preview request's `links` to a `supports` link to each evidence version saved for the routine, each speaker's consent included. Then calls `okb_save_version` with that request, the preview's `authorisation_id`, and `result_file`.
  7. Draws the saved model, as the `okb:graph` skill's section 3 says: `okb_get_record` with `result_file`, then `draw_state_machine`. It checks the page, and gives the person the page's full path.
  8. Tells the person the routine is saved, and asks the next question: another routine, or the end of the interview.

Anything said after the save is a new version of the model, read back and saved the same way.

**AI guided:** the read-back is the approval. The business analyst gives the person each step and waits for "Is that right?" to be answered, then asks "Does that cover the whole routine, from start to finish?" once. It saves the model as soon as the speaker says it does, and asks for no other approval.

## Problems

- **The check in section 1 fails:** the interview waits. The person finishes setup, or signs in, as the check says.
- **No grant to save evidence or a model in `routines`:** OKB's refusal names the missing action. The database admin, `@real-agent:database-admin`, can grant it.
- **"stale":** someone saved a newer version. The business analyst reads the record again, and shows the person the newer version before saving.
- **A relationship whose ends are not classes:** `okb_save_term` refuses it. Each class is saved first, as the `okb:reference` skill's section 2 says.
- **A file that cannot be read:** its evidence record says so in `limitations`, with the file's name.
