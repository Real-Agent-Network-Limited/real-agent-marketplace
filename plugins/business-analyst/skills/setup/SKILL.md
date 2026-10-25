---
name: setup
description: Use when a firm's owner types "Set up Real Agent" or "Set up OKB", or asks how setup stands. Once the owner agrees, it builds the firm's Real Agent knowledge base, OKB, in their new Supabase project, with file search. It deploys the hosted functions through the Supabase connector, exposes the Data API, and makes the scopes and Real Agent's access. It signs the owner in and checks it all works, while the owner only connects Supabase, agrees and chooses a password. It runs in one of three modes: human only, AI guided or human directed.
---

# Real Agent setup

The owner starts this skill by typing "Set up Real Agent". The older phrase, "Set up OKB", starts it too. It is done once per firm, before the first interview about a workflow.

The **owner** owns the firm's Supabase account and becomes the first administrator. Supabase asks a person for three things: creating the account and project, connecting Supabase to Claude, and choosing their own password. The business analyst, `business-analyst:business-analyst`, guides the owner through the first two, and does everything else once the owner agrees. It never needs the Supabase command-line tool.

The business analyst never sees, asks for or types a password, a secret key or a token. The project's publishable key is public: the sign-in needs it, and the business analyst reads it with the connector. The owner types their password into the sign-in's own prompt, which sends it to Supabase alone.

The setup files are in the `okb` folder beside this skill: on macOS, `~/.claude/plugins/marketplaces/real-agent/plugins/business-analyst/skills/setup/okb/`, and on Windows, `$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\business-analyst\skills\setup\okb\`. In this skill, `<okb>` stands for that folder, and `<folder>` for the setup folder, the session's own folder.

- `build.mjs` approves the setup files, sends them to the project, and lists each hosted function's files.
- `functions/okb-setup/` runs each approved setup file in the project, and makes the owner's sign-in. `functions/okb-setup/real-agent.ts` holds Real Agent's staff, the address their codes are sent to, and Real Agent's support address.
- `functions/okb-invite/` stays deployed after setup. The business analyst adds each later person with one call to it, for an administrator, which makes their actor and a one-time invitation code.
- `functions/okb-join/` stays deployed too, with JWT verification off. A person spends their code there, and chooses their own password.
- `functions/okb-upgrade/` stays deployed too. Real Agent's own actor applies each new upgrade there, signed by Real Agent, so the owner never invites Real Agent into their Supabase organisation.
- `setup.sql`, `file-search.sql`, `file-search-scopes.sql` and `schedule.sql` build OKB and file search. `first-administrator.sql` makes the administrator, the six scopes, Real Agent's actors with their invitation codes, and the open tasks setup leaves.
- `state.sql` reads where a project stands, `reset.sql` takes an unfinished attempt off, `data-api.sql` exposes the `okb` schema, and `health.sql` is the health check.
- `bootstrap.sql` holds the same steps for a person to run by hand, and each later person's grants.
- `tests.sql` and `file-search-tests.sql` are Real Agent's release checks. Setup never runs them in a firm's project.

## Choose the mode

The owner chooses the mode. AI guided is the default.

- **AI guided:** the owner types "Set up Real Agent" and agrees once. The business analyst follows its lines below, and asks nothing more, except the owner's own sign-in.
- **Human directed:** the owner tells the business analyst what to do, step by step. It follows its line for each step the owner directs. A refusal from Supabase, OKB or a tool still stands.
- **Human only:** the owner follows the Person lines below, in the Supabase dashboard and a terminal, without the business analyst.

Each step gives a **Person** line and a **Business analyst agent** line. Nothing replaces the rule that the business analyst handles no password, secret key or token.

## What the owner reads

The owner reads plain sentences only: no code block, table, SQL, command, test output or file name, unless they ask. The one exception is the sign-in command in section 3, the only command the owner ever sees. Each reply holds at most one question. A sentence the owner reads has no semicolon, and says nothing about what the owner or Real Agent does not need to do. Between the messages below, the business analyst writes nothing: no remark on a tool's result, such as what a command printed or did not print.

- **Progress:** one short line per stage, as it ends, such as "Building your Real Agent knowledge base: done."
- **Progress list:** a list of steps has exactly four, in the owner's words. They are "Confirm your project", "Build your knowledge base", "Your sign-in" and "Final checks".
- **The end:** a summary of two to six lines, as below.
- **A failure:** one plain sentence saying what failed and that Real Agent has been told, then stop. Before the owner's sign-in, Real Agent is told by the owner. The sentence asks them to email Real Agent's support address from `real-agent.ts`, or their Real Agent contact when it is null. After the sign-in, the business analyst saves a support request as the `real-agent:support` skill does, with the database's own message. The owner's agreement to setup covers that save.

The owner's messages, in order, in a run with no failure:

- "I found your Supabase project <name>. Shall I set up Real Agent in <name>? Setup also gives Real Agent its own account in your knowledge base. We use it to design, build and update your agents. It can read and change your general records, workflows and glossary, and every change it makes is in your audit log." With no project yet, this is instead "Shall I create a Supabase project called <organisation name> in London, and set up Real Agent in it? On your Free plan it costs nothing. Setup also gives Real Agent its own account in your knowledge base. We use it to design, build and update your agents. It can read and change your general records, workflows and glossary, and every change it makes is in your audit log.", then "Creating your project. This takes a few minutes."
- The progress lines from section 2, one per step.
- "This makes your own account in your knowledge base and signs you in. Click Run on the line below. It asks your name, your email and a password you choose. The password goes only to Supabase. When it says you're signed in, type done here." Below it comes the sign-in command, alone, in one fenced code block tagged `bash`. The Claude desktop app gives that block a Run button, which runs it in the app's Terminal, where its password prompt works.
- The progress lines from section 4.
- The summary: "Real Agent is set up in <name>, and you are its administrator. I stay with you in this folder, to add your staff and remind you of anything still open. Real Agent now has its own account in your knowledge base, as you agreed. I can show you what it can reach and what it has changed, and can remove it at any time."

When `node "<okb>/build.mjs" real-agent-code --folder "<folder>"` prints a line, Real Agent's website did not take that code. For each line, the summary adds, after its first sentence, "Please email this one-time code to <Real Agent email>, so Real Agent can sign in: <code>. It works once, until <day>." When it prints nothing, every code reached Real Agent, and the summary says nothing about a code. When `real-agent.ts` gives no staff, the summary adds "I'll add Real Agent once Real Agent gives you its email address." On the Free plan, from `get_organization`, it adds "Your Supabase plan is Free, which pauses a project nobody uses for a week. A paid plan keeps it running."

Real Agent's staff load the guides and the Python runtime themselves, as their actor, since only that actor changes the Guides and Plugins scopes. At the owner's sign-in, `okb-setup` makes a one-time invitation code for each of them, and sends no email. It sends each code to Real Agent's website, `ACCESS_URL` in `real-agent.ts`, with the project's address, the email the code is for and its last day. The owner's agreement to setup covers that send. `first-administrator.sql` makes each one's actor, with the `real_agent` template's grants and no sign-in yet. Real Agent's staff member spends the code with the okb command's `sign-in --join`, and chooses their own password.

Real Agent applies each later upgrade itself, as its own actor, through `okb-upgrade`, which runs only an upgrade Real Agent signed. The owner gives Real Agent no role in their Supabase organisation.

Setup saves each loose end as an open task in Administration, assigned to the owner: "Send Real Agent its invitation code (<email>)" for a code the website did not take. The business analyst raises the first one still open at the start of each session. It completes the code's task once Real Agent's actor has signed in. When the code is lost or runs out, the business analyst adds Real Agent again, which makes a new code. With no staff in `real-agent.ts`, the task is "Add Real Agent as a user", which the business analyst's `okb-invite` call completes.

## Before setup

The owner needs a Supabase account, with Supabase connected to Claude. The business analyst creates the project itself. When the Supabase connector's tools are missing, it takes the owner through the two steps below. It sends one step per reply, and waits for the owner to say it is done before the next. It skips a step already done.

Each of these replies is the step's message as written below, and nothing else. The business analyst judges only by what the connector shows now. It never mentions an earlier session, a project it cannot see, or another organisation.

1. **The account.**
   - **Person:** creates a Supabase account.
   - **Business analyst agent:** says "First, create a free Supabase account at [supabase.com](https://supabase.com). Tell me when you have."
2. **The connector.**
   - **Person:** connects Supabase to Claude.
   - **Business analyst agent:** says "Next, connect Supabase to Claude in this app's connectors, and choose your business's Supabase organisation. Tell me when it's connected."

After step 2 the business analyst calls `list_projects` itself. When the connector's tools are not in the session, it says "Supabase is connected, but this session started before it. Start a new Code session on this folder, and type Set up Real Agent again." Then it stops. Otherwise it goes straight on to section 1.

**AI guided:** the business analyst checks this silently, and speaks only when a step is missing.

## 1. Find or create the project, and agree

1. **Find the project.**
   - **Person:** opens the project in the Supabase dashboard.
   - **Business analyst agent:** calls `list_projects`. With several projects, its one question is "Which of your Supabase projects is for Real Agent: <name>, <name> or <name>?" With one, it calls `get_project`, and goes on only when its status is `ACTIVE_HEALTHY`. It reads `state.sql` with `Read`, and runs it through `execute_sql`. With none, it creates one, as step 3 says.
2. **Ask once.**
   - **Person:** decides to go ahead.
   - **Business analyst agent:** with `setup_finished` true, says "Real Agent is already set up in <name>." and stops. With `okb_built` false, asks "Shall I set up Real Agent in <name>? Setup also gives Real Agent its own account in your knowledge base. We use it to design, build and update your agents. It can read and change your general records, workflows and glossary, and every change it makes is in your audit log." With `okb_built` true and `setup_finished` false, an earlier attempt stopped part way. When `records` and `files` are both 0, it asks "An earlier setup in <name> stopped part way. Shall I clear it and set up Real Agent again?" Otherwise it says "<name> already holds Real Agent records from an earlier setup, so I've stopped. Real Agent needs to look at it." and stops, as "What the owner reads" says for a failure.
3. **Create the project, when there is none.**
   - **Person:** creates a project in the Supabase dashboard, in the London region. They leave automatic table exposure off, and save the database password in a password manager.
   - **Business analyst agent:** calls `list_organizations`. With several, its one question is "Which of your Supabase organisations is for your business: <name> or <name>?" It calls `get_cost` for a project in that organisation, and asks once: "Shall I create a Supabase project called <organisation name> in London, and set up Real Agent in it? <cost sentence> Setup also gives Real Agent its own account in your knowledge base. We use it to design, build and update your agents. It can read and change your general records, workflows and glossary, and every change it makes is in your audit log." The cost sentence is "On your Free plan it costs nothing." for a quote of 0, and otherwise "Supabase charges <amount> a <month or hour> for it." When the owner names another project name or region, it uses theirs. Once the owner agrees, it calls `confirm_cost` with the quoted amount, 0 included, then `create_project` in `eu-west-2`, or the region the owner named, with that confirmation. Between these calls it writes nothing to the owner. It says "Creating your project. This takes a few minutes." and calls `get_project` until the status is `ACTIVE_HEALTHY`. Then it runs `state.sql` as step 1 does, and goes straight on to section 2, with no second question. Supabase may refuse, for example when the organisation already has its two free projects. Then it gives Supabase's own reason in one plain sentence, and stops.

The owner's agreement covers every step up to their sign-in, and the reset when the question named it. When the business analyst created the project, the agreement to create it covers setup too.

**AI guided:** once the owner agrees, the business analyst asks nothing until section 3.

## 2. Build

1. **Deploy okb-setup and approve the files.**
   - **Person:** none: in human only mode, the owner pastes each file into the SQL Editor in the next step instead.
   - **Business analyst agent:** calls `get_project_url` and `get_publishable_keys`, and keeps the address and the publishable key. Runs `node "<okb>/build.mjs" functions` with `Bash`. It deploys `okb-setup` first, with `deploy_edge_function`: `entrypoint_path` `index.ts`, `verify_jwt` false, and in `files` each file the listing gives, by its name, with its whole text read with `Read`. Then it runs `node "<okb>/build.mjs" approve --ref <project reference> --folder "<folder>"`, adding `--reset` for a reset, and runs the statement it prints through `execute_sql`. The command writes the owner's sign-in code to the setup folder, and never prints it.
2. **Build OKB and file search.**
   - **Person:** in the dashboard's SQL Editor, runs the whole of `setup.sql`, then `file-search.sql`, then `file-search-scopes.sql`, each in a new query, unchanged. When the editor offers to change a file or turn on Row Level Security, chooses the option that runs it unchanged.
   - **Business analyst agent:** for a reset, runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> reset.sql` first. Then the same command with `setup.sql file-search.sql file-search-scopes.sql`. It prints one line per file, and stops at a failure with the database's message. Tells the owner "Building your Real Agent knowledge base: done."
3. **Deploy file search's hosted functions.**
   - **Person:** opens **Edge Functions** and deploys each function in the editor. `file-search-worker` takes its `index.ts` and `text.ts`, with JWT verification off. `file-search`, `file-search-purge` and `okb-invite` each take their `index.ts`, with it on. `okb-join` takes its `index.ts`, with it off. `okb-upgrade` takes its `index.ts` and `upgrade-key.ts`, with it on.
   - **Business analyst agent:** deploys the other six functions as the listing gives them, in its order. Each goes with `deploy_edge_function`, its `verify_jwt` setting and each of its files. Then runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> schedule.sql`, which fills in the project reference itself. Tells the owner "Setting up file search: done."
4. **Expose the Data API.** Supabase's Data API serves the `okb` schema, through which each person's agent works.
   - **Person:** runs `data-api.sql` in the SQL Editor, or ticks `okb` under the Data API's **Exposed schemas** and saves.
   - **Business analyst agent:** runs `data-api.sql`'s text through `execute_sql`. It goes on when the setting it reads back names `okb`. Supabase's own documentation gives this statement for exposing a schema. Once it is set, the dashboard's Exposed schemas list no longer manages the setting.

**AI guided:** the business analyst gives the owner one progress line per step, as "What the owner reads" says.

## 3. The owner's sign-in

The owner's Auth user is their Supabase sign-in. The `okb-setup` hosted function makes it with Supabase Auth's own admin API, from the name, email and password the owner types. The function goes on only with the sign-in code in the setup folder, and only while OKB has no actor. The business analyst never sees the password.

- **Person:** clicks **Run** on the command the business analyst shows in the chat, which runs it in the desktop app's Terminal. Types their name, their email and the password they choose, twice. When it says so, types "done" in the session. In human only mode, the owner instead creates their Auth user under **Authentication**, **Users**, **Add user**. They run `bootstrap.sql` steps 1, 2 and 3e for themselves. Then they run `okb setup --folder <folder> --email <email> --url <project URL> --key <publishable key> --agent business-analyst:business-analyst`.
- **Business analyst agent:** sends the owner the sign-in message "What the owner reads" gives. Below it goes the command, alone in a single fenced code block tagged `bash`. The command is `node "<marketplace>/plugins/okb/cli/okb.mjs" sign-in --owner --url <project URL> --key <publishable key> --folder "<folder>"`. Its `<marketplace>` is the real-agent marketplace's copy, `~/.claude/plugins/marketplaces/real-agent`. It writes in the real address, key and folder, so the block runs as it is. Then it waits. It never runs the command itself.

**AI guided:** this is the one step the owner does in the middle of setup. The business analyst sends one message for it.

## 4. Finish

1. **Make the administrator and the scopes.**
   - **Person:** none beyond section 3: in human only mode, `bootstrap.sql` made them.
   - **Business analyst agent:** once the owner types "done", runs `node "<okb>/build.mjs" run --url <project URL> --key <publishable key> first-administrator.sql`. It makes the owner the first administrator, the six scopes and the owner's sessions scope. It makes each of Real Agent's staff an actor named "<name> (Real Agent)", with the `real_agent` template's grants, approved by the owner, and their open invitation. It saves each open task, as the owner. Tells the owner "Making you the administrator: done."
2. **Check that it works.**
   - **Person:** runs `health.sql` in the SQL Editor, and sees `ok` true.
   - **Business analyst agent:** runs `health.sql`'s text through `execute_sql`, and goes on when `ok` is true. Calls `list_edge_functions`, and goes on when the seven functions are there, with `verify_jwt` off for `file-search-worker`, `okb-setup` and `okb-join` alone. In the setup folder, with `Bash`, runs `node "<marketplace>/plugins/okb/cli/okb.mjs" okb_get_scopes`, which must list `general`, `routines`, `reference` and `plugins`. Then `node "<marketplace>/plugins/okb/cli/okb.mjs" call_function name=file-search "body.query=setup check"`, which must answer with `hits`. Tells the owner "Checking everything works: done."
3. **Save the setup record, and hand the folder over.**
   - **Person:** runs `okb okb_add_record` in the setup folder, as the agent's line gives it.
   - **Business analyst agent:** with the same command, runs `okb_add_record` with `p_scope=administration`, `p_kind=evidence` and `p_title=Real Agent setup`. Its `p_reason` is "The setup skill's record of who set the project up, and how." Its `p_fields` hold a `summary` of what was built and what the health check found, `source_reference` "The setup skill", today's `source_date`, `standing` "observed" and `limitations` "Written down by the business analyst during setup." Nothing is saved on the owner's computer. It runs `node "<okb>/build.mjs" real-agent-code --folder "<folder>"` with `Bash`. It prints each code Real Agent's website did not take, for the summary, and deletes the file the sign-in kept them in. It runs `drop schema okb_setup cascade;` through `execute_sql`. Then it runs `node "<marketplace>/plugins/okb/cli/okb.mjs" setup --folder "<folder>" --email <owner's email> --agent business-analyst:business-analyst`, which keeps the folder the business analyst's and ends setup in it. From then on the okb plugin's hook holds the business analyst in this folder to the okb plugin's tools: no Supabase connector and no `Bash`.

**AI guided:** the business analyst ends with the summary below, and asks nothing.

## Status requests

Setup has finished when `general`, `routines`, `reference` and `plugins` are there, the check the `business-analyst:routine-interview` skill's section 1 makes before an interview. In a folder whose setup is under way, or with no sign-in yet, the business analyst runs `state.sql`, and `health.sql` once `setup_finished` is true. In a folder setup has finished, it has no Supabase connector, and calls `okb_get_scopes` instead. It answers in one sentence: not started, stopped part way, or set up and working. It adds the next step and who does it.

## Problems

- **The sign-in says its code has run out:** the business analyst runs section 2's approve step again, without `--reset`. Then it shows the sign-in command again, the same way.
- **A password, key or token is pasted in:** the business analyst does not use it. The owner changes it in Supabase.
- **The health check fails:** a failure, as "What the owner reads" says.
