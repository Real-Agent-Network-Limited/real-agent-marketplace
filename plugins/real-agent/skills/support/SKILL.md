---
name: support
description: Use when a person has a problem with Real Agent, or asks Real Agent for help. Saves the problem, with what the person did and what they got, as a task in their firm's records assigned to Real Agent. Tells them where to follow its progress. It runs in one of three modes: human only, AI guided or human directed.
---

# Support

A support request is a task in the General scope of the firm's organisational knowledge base (OKB), assigned to Real Agent. OKB is the firm's own Supabase project. The person who raises the request owns it, and Real Agent's staff work on it in the same records. Nothing about the problem is kept anywhere else.

This skill sets the order, the wording and the checks. It uses the `okb:records` and `okb:writing` skills. It belongs to no one agent: any agent can run it. Usually the database operator, `@real-agent:database-operator`, runs it, and it saves through that agent's grants.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as the wording of the description. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Write down the problem

1. **Ask what the person did.** The steps they took, in order: what they typed, which agent or skill they used, and in which folder.
   - **Person:** writes it down in their own words.
   - **The agent:** asks one question at a time, and writes down each answer in the person's words. A problem in this session is already in front of the agent: it gives the person its own account, and asks them to correct it.
2. **Ask what the person got.** The message, the answer or the page, quoted as it came, and what they expected instead.
   - **Person:** copies each message as it came, never retyped.
   - **The agent:** quotes each message from the person, or from this session's tool results, unchanged.
   - Leave out any password, key or token, and any client's personal details. Write "[password left out]" in its place.
3. **Ask when and where.** The date and time, the computer, and whether it happens every time.
   - **Person:** adds them.
   - **The agent:** asks for them, and adds them.

**AI guided:** the agent gives the person the description, and waits for their approval of its wording.

## 2. Find Real Agent

Real Agent's staff work in the firm's records as actors the firm made with the `real_agent` access template. A support request is assigned to one of them.

1. **Find the General scope.**
   - **Person:** runs `okb okb_get_scopes`, and notes General's `scope_id`.
   - **The agent:** calls `okb_get_scopes`, and takes the id of the scope with the code `general`.
2. **Find Real Agent's staff among the people who can read General.**
   - **Person:** runs `okb okb_find_people p_scope_id=<General's id> p_name="Real Agent"`.
   - **The agent:** calls `okb_find_people` with `p_scope_id` General's id and `p_name` "Real Agent", as the `okb:records` skill's section 9 describes.
   - With one person in the answer, the request is assigned to them.
   - With more than one, the agent lists their names and asks which one. Any of them will do.
   - With none, the agent asks the person for the name of their contact at Real Agent, and calls `okb_find_people` with that name. With still none, it tells the person that the firm's administrator adds Real Agent's staff, as the business analyst's setup skill describes, and saves nothing.

**AI guided:** the agent gives the person the name of the Real Agent staff member, and waits for their approval.

## 3. Save the request

The request is one task in General, with these fields:

- The title is "Support:" and the problem in a few words, such as "Support: the board page will not open".
- `activity_kind` is `task`.
- `description` holds three parts, in this order: "What I did:", "What I got:" and "When:", each from section 1.
- `completion_requirements` is "Real Agent says what caused the problem and what it changed, and I confirm it is fixed."
- `assignee_actor_id` is the Real Agent staff member's `actor_id`, from section 2.
- OKB makes the person the request's owner, and saves it as Pending.

1. **Preview the request.**
   - **Person:** runs `okb okb_add_record p_scope=general p_kind=activity p_title="Support: <the problem>" p_reason="Support request for Real Agent" p_fields.activity_kind=task p_fields.description="<description>" p_fields.completion_requirements="<requirements>" p_fields.assignee_actor_id=<actor id> p_preview=true`.
   - **The agent:** calls `okb_add_record` with those fields and `p_preview` true. It shows the person the save, as the `okb:records` skill's section 3 describes. That is the scope, the title, the description, the deliverables and the Real Agent staff member's name, never their id.
2. **Save it once the person agrees.**
   - **Person:** runs the same command without `p_preview`.
   - **The agent:** calls `okb_save_version` with the preview's `request` and `authorisation_id`, unchanged.
   - A refusal for a missing `create` grant in General goes to the database admin, `@real-agent:database-admin`, as the `okb:records` skill's section 3 says.
   - **Evidence:** the saved version's `record_id` and `version_id`.

**AI guided:** the agent gives the person the saved request's title, and waits for their approval before section 4.

## 4. Where to follow its progress

Real Agent's staff find the request among their own tasks. They start it, write what they find, and complete it with a note of what they changed. The person reads each of these in the request's state and its history.

1. **Tell the person where to look.**
   - **Person:** asks their database operator "How is my support request getting on?" Without the agent, runs `okb okb_show_record p_record="<the request's title>"` for its state, or `okb okb_get_progress p_cutoff=null p_observed_at=null p_cursor=null p_limit=100 p_scope_id=<General's id> result_file=progress-1.json` for General's work.
   - **The agent:** tells the person the request's title, and that the database operator answers that question. It reads the request with `okb_get_record` or `okb_get_progress`, as the `okb:records` skill's section 2 describes. It gives the state, the person it is assigned to and the last change.
2. **Read the states to the person.** Pending: Real Agent has not started it. In progress: Real Agent has started it. Paused: it waits on something, named in its blockers. Completed: Real Agent says what it changed, in the completion note. For each change, `okb_get_history` gives who made it, when and why.
   - **Person:** reads the state with `okb okb_show_record`, and its history with `okb okb_get_history p_record_id=<record id>`.
   - **The agent:** reads them with `okb_get_record` and `okb_get_history`, and gives them in plain words.

**AI guided:** the agent gives the person where to follow the request, and waits for them before closing.

## 5. When the person changes something

- **More detail, later:** add it to the request's `description` in a new version. Use `okb_change_record`, as the `okb:records` skill's section 11 describes.
- **The problem went away:** tell Real Agent in the request, with a new version of its description. Leave the state to Real Agent.
- **A second problem:** save it as its own request.
