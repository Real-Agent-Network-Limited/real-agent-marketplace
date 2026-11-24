---
name: outstanding
description: Use when a person asks "What is outstanding?", asks for a status update, or greets the agent. Shows the person's open tasks on the home card where the Real Agent connector is connected, and as a short list where it is not. It runs in one of three modes: human only, AI guided or human directed.
---

# Outstanding

Outstanding shows a person what is theirs to do. The tasks are the open tasks assigned to the person in their firm's Real Agent knowledge base, soonest finish first. Technically the knowledge base is OKB, the firm's organisational knowledge base, in the firm's own Supabase project. A task is open until it is completed or cancelled.

This skill sets the order, the wording and the checks. It uses the `okb:records` and `okb:writing` skills. It belongs to no one agent: any agent can run it. Usually the database operator, `@real-agent:database-operator`, runs it.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

## 1. Show what is open

1. **See the tasks.**
   - **Person:** runs `okb okb_get_assigned`. The answer's `items` are their open tasks, each with its `title`, `scope_name`, `state`, `forecast_finish_at` and `baseline_finish_at`, and `overdue_seconds` when it is late.
   - **The agent:** where the session has the Real Agent connector, it first closes the connector's task, as step 3 says. So the card never shows that task open. Then it calls `show_home` with no arguments, then ends the turn with no question. The card reads the person's tasks itself. It shows their name, the day and how many are open. Each task has its scope, its due day and a tag: Overdue, Due today, In progress, Paused or Pending. With none, it says "No open tasks." When `show_home` is refused, the agent's whole reply is the connector's own sentence, as it is. It adds no lead-in such as "was refused, with this message", and no comment after it. The line that the firm's subscription is not active is one such refusal. Where the session has no connector, the agent calls `okb_get_assigned`, and follows each `next_cursor` until the answer has none.
2. **Say what is outstanding.**
   - **Person:** reads the list.
   - **The agent:** with the card shown, says nothing about its contents. Without the card, gives one line for each task: its title, its scope and its due day, with late ones first and "overdue" beside them. With none, it says "You have no open tasks." It names no task the answer does not hold, and offers nothing the person did not ask for.
3. **Close the connector's task.**
   - **Person:** once their home card shows, completes their open task "Connect Real Agent's connector" in Administration, with the reason "The owner's home card showed."
   - **The agent:** before it calls `show_home`, calls `okb_get_assigned`. When the person's open tasks include "Connect Real Agent's connector" in Administration, it completes that task as the person, the way the business analyst's "Open tasks from setup" does. It saves an evidence record in Administration with `okb_add_record`, whose summary is "The owner's home card showed." and whose `standing` is "observed". It links that record to the task with `okb_link` and `supports`. Then it calls `okb_set_state` with `in_progress`, then with `completed`, each with the reason "The owner's home card showed.", and a completion note. It says nothing about the task, then or later in the session, and never asks for the connector's address.

**AI guided:** the agent shows the person the list, and asks what they want to open first.
