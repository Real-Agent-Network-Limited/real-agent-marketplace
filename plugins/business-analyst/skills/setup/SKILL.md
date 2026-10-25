---
name: setup
description: Use when a firm's owner types "Set up Real Agent" or "Set up OKB", or asks how setup stands. After one yes, builds the firm's Real Agent knowledge base, OKB, in their new Supabase project, with file search. It deploys the hosted functions through the Supabase connector, exposes the Data API, and makes the scopes and Real Agent's access. It signs the owner in and checks it all works, while the owner only connects Supabase, agrees and chooses a password. It runs in one of three modes: human only, AI guided or human directed.
---

# Real Agent setup

The owner starts this skill by typing "Set up Real Agent". The older phrase, "Set up OKB", starts it too. It is done once per firm, before the first routine interview.

The **owner** owns the firm's Supabase account and becomes the first administrator. Supabase asks a person for three things: creating the account and project, connecting Supabase to Claude, and choosing their own password. The business analyst, `business-analyst:business-analyst`, does everything else, after the owner's one yes. It never needs the Supabase command-line tool.

The business analyst never sees, asks for or types a password, a secret key or a token. The project's publishable key is public: the sign-in needs it, and the business analyst reads it with the connector. The owner types their password into the sign-in's own prompt, which sends it to Supabase alone.

The setup files are in the `okb` folder beside this skill: on macOS, `~/.claude/plugins/marketplaces/real-agent/plugins/business-analyst/skills/setup/okb/`, and on Windows, `$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\business-analyst\skills\setup\okb\`. In this skill, `<okb>` stands for that folder, and `<folder>` for the setup folder, the session's own folder.

- `build.mjs` approves the setup files, sends them to the project, and lists each hosted function's files.
- `functions/okb-setup/` runs each approved setup file in the project, and makes the owner's sign-in. `functions/okb-setup/real-agent.ts` holds Real Agent's staff, its Developer email address and its support address.
- `setup.sql`, `file-search.sql`, `file-search-scopes.sql` and `schedule.sql` build OKB and file search. `first-administrator.sql` makes the administrator, the six scopes and Real Agent's actors.
- `state.sql` reads where a project stands, `reset.sql` takes an unfinished attempt off, `data-api.sql` exposes the `okb` schema, and `health.sql` is the health check.
- `bootstrap.sql` holds the same steps for a person to run by hand, and each later person's grants.
- `tests.sql` and `file-search-tests.sql` are Real Agent's release checks. Setup never runs them in a firm's project.

## Choose the mode

The owner chooses the mode. AI guided is the default.

- **AI guided:** the owner types "Set up Real Agent" and says yes once. The business analyst follows its lines below, and asks nothing more, except the owner's own sign-in.
- **Human directed:** the owner tells the business analyst what to do, step by step. It follows its line for each step the owner directs. A refusal from Supabase, OKB or a tool still stands.
- **Human only:** the owner follows the Person lines below, in the Supabase dashboard and a terminal, without the business analyst.

Each step gives a **Person** line and a **Business analyst agent** line. Nothing replaces the rule that the business analyst handles no password, secret key or token.

## What the owner reads

The owner reads plain sentences only: no code block, table, SQL, command, test output or file name, unless they ask. Each reply holds at most one question.

- **Progress:** one short line per stage, as it ends, such as "Building your Real Agent knowledge base: done."
- **The end:** a summary of three to five lines, as below.
- **A failure:** one plain sentence saying what failed and that Real Agent has been told, then stop. Before the owner's sign-in, Real Agent is told by the owner. The sentence asks them to email Real Agent's support address from `real-agent.ts`, or their Real Agent contact when it is null. After the sign-in, the business analyst saves a support request as the `real-agent:support` skill does, with the database's own message. The owner's yes to setup covers that save.

The owner's messages, in order, in a run with no failure:

- "I found your Supabase project <name>. Shall I set up Real Agent in <name>?"
- The progress lines from section 2, one per step.
- "Last, your own sign-in. I've copied a line for you: in this app's Code tab, open Terminal, paste it and press Return. It asks your name, your email and the password you choose, which goes only to Supabase. Type done here when it says so."
- The progress lines from section 4.
- The summary: "Real Agent is set up in <name>, and you are its administrator. Everything checked out: your knowledge base, file search and your sign-in all work. One thing only you can do: in Supabase, open your organisation's Team page, choose Invite member, and invite <Developer email> as a Developer, so Real Agent can apply updates. A Developer can change the database and read its keys, but not your billing, members or settings, and you can remove it at any time. From your next session, this folder works with your database admin, who adds your staff."

When `real-agent.ts` gives no Developer email, the invitation sentence says Real Agent will send the address. When its staff list is empty, the summary adds "Real Agent will add its own staff and load your guides." On the Free plan, from `get_organization`, it adds "Your Supabase plan is Free, which pauses a project nobody uses for a week; a paid plan keeps it running."

Real Agent's staff load the guides and the Python runtime themselves, as their actor, since only that actor changes the Guides and Plugins scopes. Each staff member's Auth user has a random password nobody is told. They set their own with `bootstrap.sql` step 7, once the owner has invited Real Agent as a Developer.

## Before setup

The owner needs a Supabase account and project, and Supabase connected to Claude.

- **Person:** creates a free account at supabase.com, then a project in it, with the region closest to the firm. Saves the database password Supabase generates in a password manager. In the Claude desktop app, opens the connectors, connects Supabase and chooses the organisation. Then types "Set up Real Agent" in a new Code session on the setup folder.
- **Business analyst agent:** without the Supabase connector's tools, or when `list_projects` gives no project, it tells the owner in two or three sentences: "Before I can set up Real Agent, you need a Supabase project and Supabase connected to Claude. Create a free account and a project at supabase.com, choosing the region nearest you. Then connect Supabase in this app's connectors, and type Set up Real Agent again." Then it stops.

**AI guided:** the business analyst checks this silently, and speaks only when something is missing.

## 1. Find the project and agree

1. **Find the project.**
   - **Person:** opens the project in the Supabase dashboard.
   - **Business analyst agent:** calls `list_projects`. With several projects, its one question is "Which of your Supabase projects is for Real Agent: <name>, <name> or <name>?" With one, it calls `get_project`, and goes on only when its status is `ACTIVE_HEALTHY`. It reads `state.sql` with `Read`, and runs it through `execute_sql`.
2. **Ask once.**
   - **Person:** decides to go ahead.
   - **Business analyst agent:** with `setup_finished` true, says "Real Agent is already set up in <name>." and stops. With `okb_built` false, asks "Shall I set up Real Agent in <name>?" With `okb_built` true and `setup_finished` false, an earlier attempt stopped part way. When `records` and `files` are both 0, it asks "An earlier setup in <name> stopped part way. Shall I clear it and set up Real Agent again?" Otherwise it says "<name> already holds Real Agent records from an earlier setup, so I've stopped. Real Agent needs to look at it." and stops, as "What the owner reads" says for a failure.

The owner's yes covers every step up to their sign-in, and the reset when the question named it.

**AI guided:** after the yes, the business analyst asks nothing until section 3.

## 2. Build

1. **Deploy okb-setup and approve the files.**
   - **Person:** none: in human only mode, the owner pastes each file into the SQL Editor in the next step instead.
   - **Business analyst agent:** calls `get_project_url` and `get_publishable_keys`, and keeps the address and the publishable key. Runs `node "<okb>/build.mjs" functions` with `Bash`. It deploys `okb-setup` first, with `deploy_edge_function`: `entrypoint_path` `index.ts`, `verify_jwt` false, and in `files` each file the listing gives, by its name, with its whole text read with `Read`. Then it runs `node "<okb>/build.mjs" approve --ref <project reference> --folder "<folder>"`, adding `--reset` for a reset, and runs the statement it prints through `execute_sql`. The command writes the owner's sign-in code to the setup folder, and never prints it.
2. **Build OKB and file search.**
   - **Person:** in the dashboard's SQL Editor, runs the whole of `setup.sql`, then `file-search.sql`, then `file-search-scopes.sql`, each in a new query, unchanged. When the editor offers to change a file or turn on Row Level Security, chooses the option that runs it unchanged.
   - **Business analyst agent:** for a reset, runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> reset.sql` first. Then the same command with `setup.sql file-search.sql file-search-scopes.sql`. It prints one line per file, and stops at a failure with the database's message. Tells the owner "Building your Real Agent knowledge base: done."
3. **Deploy file search's hosted functions.**
   - **Person:** opens **Edge Functions** and deploys each function in the editor. `file-search-worker` takes its `index.ts` and `text.ts`, with JWT verification off. `file-search` and `file-search-purge` each take their `index.ts`, with it on.
   - **Business analyst agent:** deploys `file-search-worker`, `file-search` and `file-search-purge` as the listing gives them, in that order, each with `deploy_edge_function`, its `verify_jwt` setting and each of its files. Then runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> schedule.sql`, which fills in the project reference itself. Tells the owner "Setting up file search: done."
4. **Expose the Data API.** Supabase's Data API serves the `okb` schema, through which each person's agent works.
   - **Person:** runs `data-api.sql` in the SQL Editor, or ticks `okb` under the Data API's **Exposed schemas** and saves.
   - **Business analyst agent:** runs `data-api.sql`'s text through `execute_sql`. It goes on when the setting it reads back names `okb`. Supabase's own documentation gives this statement for exposing a schema. Once it is set, the dashboard's Exposed schemas list no longer manages the setting.

**AI guided:** the business analyst gives the owner one progress line per step, as "What the owner reads" says.

## 3. The owner's sign-in

The owner's Auth user is their Supabase sign-in. The `okb-setup` hosted function makes it with Supabase Auth's own admin API, from the name, email and password the owner types. The function goes on only with the sign-in code in the setup folder, and only while OKB has no actor. The business analyst never sees the password.

- **Person:** in the desktop app's **Code** tab, opens **Terminal**, pastes the line the business analyst copied and presses Return. Types their name, their email and the password they choose, twice. When it says so, types "done" in the session. In human only mode, the owner instead creates their Auth user under **Authentication**, **Users**, **Add user**. They run `bootstrap.sql` steps 1, 2 and 3e for themselves. Then they run `okb setup --folder <folder> --email <email> --url <project URL> --key <publishable key> --agent business-analyst:business-analyst`.
- **Business analyst agent:** copies this command to the clipboard, with `pbcopy` on macOS or `Set-Clipboard` on Windows: `node "<marketplace>/plugins/okb/cli/okb.mjs" sign-in --owner --url <project URL> --key <publishable key> --folder "<folder>"`, where `<marketplace>` is the real-agent marketplace's copy, `~/.claude/plugins/marketplaces/real-agent`. It sends the owner the sign-in message "What the owner reads" gives, and waits. It shows the command only when the copy fails or the owner asks.

**AI guided:** this is the one step the owner does in the middle of setup. The business analyst sends one message for it.

## 4. Finish

1. **Make the administrator and the scopes.**
   - **Person:** none beyond section 3: in human only mode, `bootstrap.sql` made them.
   - **Business analyst agent:** once the owner types "done", runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> first-administrator.sql`. It makes the owner the first administrator, the six scopes and the owner's sessions scope. It makes each of Real Agent's staff in `real-agent.ts` an actor named "<name> (Real Agent)", with the `real_agent` template's grants, approved by the owner. Tells the owner "Making you the administrator: done."
2. **Check that it works.**
   - **Person:** runs `health.sql` in the SQL Editor, and sees `ok` true.
   - **Business analyst agent:** runs `health.sql`'s text through `execute_sql`, and goes on when `ok` is true. Calls `list_edge_functions`, and goes on when the four functions are there, with `verify_jwt` off for `file-search-worker` and `okb-setup` alone. In the setup folder, with `Bash`, runs `node "<marketplace>/plugins/okb/cli/okb.mjs" okb_get_scopes`, which must list `general`, `routines`, `reference` and `plugins`. Then `node "<marketplace>/plugins/okb/cli/okb.mjs" call_function name=file-search "body.query=setup check"`, which must answer with `hits`. Tells the owner "Checking everything works: done."
3. **Save the setup record, and hand the folder over.**
   - **Person:** runs `okb okb_add_record` in the setup folder, as the agent's line gives it.
   - **Business analyst agent:** with the same command, runs `okb_add_record` with `p_scope=administration`, `p_kind=evidence` and `p_title=Real Agent setup`. Its `p_reason` is "The setup skill's record of who set the project up, and how." Its `p_fields` hold a `summary` of what was built and what the health check found, `source_reference` "The setup skill", today's `source_date`, `standing` "observed" and `limitations` "Written down by the business analyst during setup." Nothing is saved on the owner's computer. It runs `drop schema okb_setup cascade;` through `execute_sql`. Then it runs `node "<marketplace>/plugins/okb/cli/okb.mjs" setup --folder "<folder>" --email <owner's email> --agent real-agent:database-admin`, which makes the folder the database admin's.

**AI guided:** the business analyst ends with the summary below, and asks nothing.

## Status requests

Setup has finished when `general`, `routines`, `reference` and `plugins` are there, the check the `business-analyst:routine-interview` skill's section 1 makes before an interview. The business analyst runs `state.sql`, and `health.sql` once `setup_finished` is true. It answers in one sentence: not started, stopped part way, or set up and working. It adds the next step and who does it.

## Problems

- **The sign-in says its code has run out:** the business analyst runs section 2's approve step again, without `--reset`. Then it copies the sign-in line again.
- **A password, key or token is pasted in:** the business analyst does not use it. The owner changes it in Supabase.
- **The health check fails:** a failure, as "What the owner reads" says.
