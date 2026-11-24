---
name: setup
description: Use when a firm's owner types "Set up Real Agent" or "Set up OKB", or asks how setup stands. The business analyst takes the owner through making a Supabase account, then gives them one command, okb setup --owner. The command builds the firm's Real Agent knowledge base, OKB, in their Supabase project, with file search. It signs the owner in, checks it all works and makes the settings of Real Agent's connector. It runs in one of three modes: human only, AI guided or human directed.
---

# Real Agent setup

The owner starts this skill by typing "Set up Real Agent". The older phrase, "Set up OKB", starts it too. It is done once per firm, before the first interview about a workflow.

The **owner** owns the firm's Supabase account and becomes the first administrator. Supabase asks a person for three things: creating the account, making an access token, and choosing their own password. The business analyst, `business-analyst:business-analyst`, guides the owner through the account. Then it gives them one command, the setup command, which does every other step on the owner's computer. It never needs the Supabase command-line tool.

The business analyst never holds the Supabase connector or `Bash`. The okb plugin's hook refuses both to it, before, during and after setup. The setup command reaches Supabase through its Management API, with the access token the owner pastes at its own hidden prompt.

The business analyst never sees, asks for or types a password, a secret key or a token. The owner pastes the token and types their password into the command's own prompts. The command sends them to Supabase alone.

The setup files are in the `okb` folder beside this skill: on macOS, `~/.claude/plugins/marketplaces/real-agent/plugins/business-analyst/skills/setup/okb/`, and on Windows, `$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\business-analyst\skills\setup\okb\`. The setup command runs them. In this skill, `<okb>` stands for that folder, and `<folder>` for the setup folder, the session's own folder.

- `build.mjs` approves the setup files, sends them to the project, and lists each hosted function's files.
- `functions/okb-setup/` runs each approved setup file in the project, and makes the owner's sign-in. `functions/okb-setup/real-agent.ts` holds Real Agent's staff, the address their codes are sent to, and Real Agent's support address.
- `functions/okb-invite/` stays deployed after setup. The business analyst adds each later person with one call to it, for an administrator, which makes their actor and a one-time invitation code.
- `functions/okb-join/` stays deployed too, with JWT verification off. A person spends their code there, and chooses their own password.
- `functions/password-reset/` stays deployed too. It gives an administrator a reset code for a person who has lost their password. The person sets a new password with it on Real Agent's sign-in page.
- `functions/okb-upgrade/` stays deployed too. Real Agent's own actor applies each new upgrade there, signed by Real Agent, so the owner never invites Real Agent into their Supabase organisation.
- `setup.sql`, `file-search.sql`, `file-search-scopes.sql` and `schedule.sql` build OKB and file search. `first-administrator.sql` makes the administrator, the six scopes, Real Agent's actors with their invitation codes, and the open tasks setup leaves.
- `state.sql` reads where a project stands, `reset.sql` takes an unfinished attempt off, `data-api.sql` exposes the `okb` schema, and `health.sql` is the health check.
- `bootstrap.sql` holds the same steps for a person to run by hand, and each later person's grants.
- `tests.sql` and `file-search-tests.sql` are Real Agent's release checks. Setup never runs them in a firm's project.

## Choose the mode

The owner chooses the mode. AI guided is the default.

- **AI guided:** the owner types "Set up Real Agent". The business analyst follows its lines below: the account step when it is needed, then the setup command. It asks nothing more.
- **Human directed:** the owner tells the business analyst what to do, step by step. It gives the same setup command for the build. A refusal from Supabase, OKB or the command still stands.
- **Human only:** the owner follows the Person lines below, in the Supabase dashboard and a terminal, with `bootstrap.sql`, without the business analyst.

Each step gives a **Person** line and a **Business analyst agent** line. Nothing replaces the rule that the business analyst handles no password, secret key or token.

## What the owner reads

The owner reads plain sentences only: no code block, table, SQL, command, test output or file name, unless they ask. Each reply holds at most one question. A sentence the owner reads has no semicolon, and says nothing about what the owner or Real Agent does not need to do. Between the messages below, the business analyst writes nothing.

The one exception in setup is the setup command, in section 1. It goes below its message, alone in one fenced code block tagged `bash`. The Claude desktop app gives that block a Run button, which runs it in the app's Terminal, where its hidden prompts work.

- **A failure:** one plain sentence saying what failed and that Real Agent has been told, then stop. Before the owner's sign-in, Real Agent is told by the owner. The sentence asks them to email Real Agent's support address from `real-agent.ts`, or their Real Agent contact when it is null. After the sign-in, the business analyst saves a support request as the `real-agent:support` skill does, with the command's own line. The owner's agreement to setup covers that save.

The owner's messages, in order, in a run with no failure:

- The account step from "Before setup", when the owner has no Supabase account yet.
- The setup command's message, one line each, in this order:
  - "This sets up Real Agent in your Supabase project."
  - "Setup also gives Real Agent its own account in your knowledge base. We use it to design, build and update your agents. It can read and change your general records, workflows and glossary, and every change it makes is in your audit log. We are also sent your firm's name and your name and email, so we know the account is yours."
  - "1. Make a Supabase access token at [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens). Name it, choose the shortest expiry, choose Organization under Resource access, and keep Full access. Delete it on that page once setup is done."
  - "2. Click Run on the line below, and paste the token when it asks."
  - "3. Answer its questions: your firm's name, your Supabase project, and your name, email and a password you choose."
  - "4. When it says so, start a new Code session on this folder, and type done there."
- The summary, once the business analyst has checked the scopes in section 4: "Real Agent is set up, and you are its administrator. I stay with you in this folder, to add your staff and remind you of anything still open. Real Agent now has its own account in your knowledge base, as you agreed. I can show you what it can reach and what it has changed, and can remove it at any time."

The setup command prints its own lines in the Terminal, and the owner reads them there. It prints one progress line per stage as it ends, such as "Building your Real Agent knowledge base: done." Its stages, in order, are "Creating your project in London", "Waiting for your project to be ready", "Keeping your short name, <slug>, with Real Agent", "Building your Real Agent knowledge base", "Setting up file search", "Turning on the Data API", "Making you the administrator", "Checking everything works" and "Saving the setup record". The first is for a new project only. The wait starts with "Waiting for your project to be ready. This can take a few minutes." Then it prints the five lines of Real Agent's connector's settings, public sign-up off among them, and its summary.

The summary starts "Real Agent is set up in <project>, and you are its administrator." It ends with the one step left and "Start a new Code session on <folder>, and type done there." The session that gave the command started before the owner's sign-in, so its okb plugin cannot see that sign-in.

When Real Agent's connector did not take Real Agent's invitation code, the command's summary gives it: "Real Agent's connector did not take its invitation code. Please email it to <Real Agent email>, so Real Agent can sign in: <code>." On the Free plan, it adds "Your Supabase plan is Free, which pauses a project nobody uses for a week. A paid plan keeps it running."

Real Agent's staff load the guides and the Python runtime themselves, as their actor, since only that actor changes the Guides and Plugins scopes. At the owner's sign-in, `okb-setup` makes a one-time invitation code for each of them, and sends no email. It sends each code to Real Agent's connector, `ACCESS_URL` in `real-agent.ts`. With it go the project's address, the email the code is for, its last day and the firm's short name. The owner's agreement to setup covers that send.

`first-administrator.sql` makes each one's actor, with the `real_agent` template's grants and no sign-in yet. Real Agent's staff member spends the code with the okb command's `sign-in --join`, and chooses their own password.

Real Agent applies each later upgrade itself, as its own actor, through `okb-upgrade`, which runs only an upgrade Real Agent signed. The owner gives Real Agent no role in their Supabase organisation.

Setup saves each loose end as an open task in Administration, assigned to the owner: "Send Real Agent its invitation code (<email>)" for a code the connector did not take. The business analyst raises the first one still open at the start of each session. It completes the code's task once Real Agent's actor has signed in. When the code is lost or runs out, the business analyst adds Real Agent again, which makes a new code. With no staff in `real-agent.ts`, the task is "Add Real Agent as a user", which the business analyst's `okb-invite` call completes. The setup command also saves "Connect Real Agent's connector", and section 5 completes it.

## Before setup

The owner needs a Supabase account. The setup command finds or creates the project itself, so the owner never fills in Supabase's project form.

1. **The account.**
   - **Person:** creates a Supabase account.
   - **Business analyst agent:** says "First, create a free Supabase account at [supabase.com](https://supabase.com). Tell me when you have." It skips this step when the owner says they have an account. Then it goes straight on to section 1.

**AI guided:** the business analyst sends the account step only when the owner has no account, and waits for them to say it is done.

## 1. The setup command

1. **Give the command.**
   - **Person:** makes a Supabase access token as the message says, and clicks **Run** on the command the business analyst shows in the chat. Pastes the token, then answers the command's questions. They are the firm's name, the Supabase organisation and project, and their name, email and chosen password, twice. In human only mode, the owner instead follows the Person lines of sections 2 to 4, in the Supabase dashboard.
   - **Business analyst agent:** sends the setup command's message "What the owner reads" gives. Below it goes the command, alone in a single fenced code block tagged `bash`. Its `<marketplace>` is the real-agent marketplace's copy, `~/.claude/plugins/marketplaces/real-agent`, and `<folder>` is the session's folder from `check_plugins`. It writes both in full, so the block runs as it is. Then it waits. It never runs the command itself, and never asks for the token.

     ```bash
     node "<marketplace>/plugins/okb/cli/okb.mjs" setup --owner --folder "<folder>"
     ```

2. **What the command does.**
   - **Person:** none beyond the answers in step 1.
   - **Business analyst agent:** none: the command does each step below, in this order, and prints its progress lines.
     - It checks the token, and uses the one Supabase organisation, or asks which by number.
     - It lists the organisation's projects and asks which, or offers a new one. A new one is named after the firm, in London. On a paid plan, it creates one only after the owner types yes.
     - It reads a project picked from the list with `state.sql` before it saves anything. One already set up, or holding records or files, gets "<project> already holds a knowledge base. Choose another project, or a new one.", and the list is asked again.
     - On a run after a stop, it reads `state.sql` again. A project already set up goes straight to the connector's settings. An attempt with no records or files is cleared once the owner types yes. A project that already holds records stops the command.
     - It keeps the firm's short name, its slug, with Real Agent's connector. It deploys the hosted functions and runs the setup files, as section 2 gives them.
     - It signs the owner in, runs `first-administrator.sql`, the health check and the scopes check, and saves the setup record and the open task.
     - It makes the five settings of Real Agent's connector with the slug, and prints the summary.

3. **When the command stops.**
   - **Person:** clicks **Run** again. The command carries on from where it stopped, with the same project and slug.
   - **Business analyst agent:** when the owner says the command stopped, it asks them to click Run on the same command again. When a key line says to run it again in 20 minutes, it tells the owner that time, and has them click Run then. When a line says Supabase refused the token, the owner makes a new token and runs it again. A project that already holds Real Agent records, or a second stop at the same step, is a failure, as "What the owner reads" says.

**AI guided:** the business analyst sends the setup command's message once, and asks nothing else until the owner types done.

## 2. Build

The setup command does each step of this section. Its lines are for a person working by hand.

1. **Create the project.**
   - **Person:** creates a project in the Supabase dashboard, in the London region. They leave automatic table exposure off, and save the database password in a password manager.
   - **Business analyst agent:** none: the setup command does it.
2. **Build OKB and file search.**
   - **Person:** in the dashboard's SQL Editor, runs the whole of `setup.sql`, then `file-search.sql`, then `file-search-scopes.sql`, each in a new query, unchanged. When the editor offers to change a file or turn on Row Level Security, chooses the option that runs it unchanged.
   - **Business analyst agent:** none: the setup command does it.
3. **Deploy the hosted functions.**
   - **Person:** opens **Edge Functions** and deploys each function in the editor. `file-search-worker` takes its `index.ts`, its `text.ts`, and `vendor/sheetjs-0.20.3/xlsx.mjs` and `vendor/sheetjs-0.20.3/types/index.d.ts` at those paths, with JWT verification off. `file-search`, `file-search-purge`, `okb-invite` and `password-reset` each take their `index.ts`, with it on. `okb-join` takes its `index.ts`, with it off. `okb-upgrade` takes its `index.ts` and `upgrade-key.ts`, with it on. `graph-reader` takes its `index.ts` and `prompt.ts`, with it off. It stays off until an administrator adds the firm's own Anthropic API key, as the business analyst describes. Then runs `schedule.sql`, with the project reference in place of its placeholder.
   - **Business analyst agent:** none: the setup command does it.
4. **Expose the Data API.** Supabase's Data API serves the `okb` schema, through which each person's agent works.
   - **Person:** runs `data-api.sql` in the SQL Editor, or ticks `okb` under the Data API's **Exposed schemas** and saves.
   - **Business analyst agent:** none: the setup command does it.

**AI guided:** the business analyst writes nothing during this section. The setup command prints its own progress.

## 3. The owner's sign-in

The owner's Auth user is their Supabase sign-in. The `okb-setup` hosted function makes it with Supabase Auth's own admin API, from the name, email and password the owner types into the setup command. The business analyst never sees the password.

- **Person:** types their name, their email and the password they choose, twice, when the setup command asks. In human only mode, the owner instead creates their Auth user under **Authentication**, **Users**, **Add user**. They run `bootstrap.sql` steps 1, 2 and 3e for themselves. Then they run `okb setup --folder <folder> --email <email> --url <project URL> --key <publishable key> --agent business-analyst:business-analyst`.
- **Business analyst agent:** none: the setup command asks for it.

**AI guided:** the business analyst writes nothing during the sign-in.

## 4. Finish

1. **Check that it works.**
   - **Person:** runs `health.sql` in the SQL Editor, and sees `ok` true. Under **Edge Functions**, sees the nine functions, with JWT verification off for `okb-setup`, `file-search-worker`, `okb-join` and `graph-reader` alone.
   - **Business analyst agent:** when the owner types done in a new session, signed in as them, it calls `okb_get_scopes`. It must list `general`, `routines`, `reference` and `plugins`. Then it gives the summary "What the owner reads" gives. When done arrives in a session whose okb plugin has no sign-in, with only `check_plugins` and the page tools, it says "Start a new Code session on this folder, and type done there."
2. **Save the setup record.**
   - **Person:** in human only mode, runs `okb okb_add_record` in the setup folder, with the fields below.
   - **Business analyst agent:** none: the setup command saves it with `okb_add_record`, as the owner. It saves it with `p_scope=administration`, `p_kind=evidence` and `p_title=Real Agent setup`. Its `p_fields` hold a `summary` that says "whose short name is <slug>", and `source_reference` "okb setup --owner". Nothing is saved on the owner's computer. It saves the open task "Connect Real Agent's connector" the same way, and drops `okb_setup`.

3. **Real Agent's connector.**
   - **Person:** once Real Agent confirms the firm, the Owner of the firm's Claude organisation adds Real Agent's connector at `https://mcp.realagent.network/<slug>`.
   - **Business analyst agent:** while `okb_get_assigned` lists the open task "Connect Real Agent's connector", it reads the setup record with `okb_find_records` and `okb_show_record`. The slug is what follows the exact phrase "whose short name is " in its `summary`, up to the full stop. When a Real Agent connector's `show_home` is in the session, it completes the task as the `real-agent:outstanding` skill's step 3 does, then calls `show_home`. With more than one Real Agent connector, it calls each one's `show_home` until one's answer names this firm's project, and uses that one. The project is `https://<projectRef>.supabase.co`, with `projectRef` from the okb plugin's `whoami`. When none does, it says Real Agent's connector for this firm is not connected yet, and gives the address as below. Otherwise it says, once in the session, "Once Real Agent confirms your firm, the Owner of your Claude organisation adds Real Agent's connector at the address below." Below it, alone in a fenced code block with no language tag, goes `https://mcp.realagent.network/<slug>`, with the slug written in. It never asks the owner for the address. A summary without the phrase is a firm set up before the command, which section 5 covers.

**AI guided:** the business analyst ends with the summary, then follows step 3.

## 5. Real Agent's connector

The connector draws Real Agent's cards, such as the home card, in Claude. It is at `https://mcp.realagent.network/<slug>`, the firm's short name, which Real Agent's operator confirms. Each person connects it once in Claude and signs in as themselves, so their grants hold.

The connector needs five settings in the project, and its address added to the firm's Claude organisation. The setup command makes the five settings. A firm set up before it makes them in step 3. Any step the owner says is done is skipped.

1. **Save the open task, if none is open.**
   - **Person:** none.
   - **Business analyst agent:** calls `okb_get_assigned`. When it lists an open task titled "Connect Real Agent's connector" in Administration, it goes on to step 2. Otherwise it saves one with `okb_add_record`, with `p_scope=administration`, `p_kind=activity` and `p_title="Connect Real Agent's connector"`. Its `p_reason` is "An open task setup left for the administrator." Its `p_fields` make it a task for the owner, due in 7 days, as `first-administrator.sql` does. The description is "Make Real Agent's connector's settings in Supabase, and add Real Agent's connector to Claude, once Real Agent gives its address." The completion requirement is "The owner's home card shows in Claude."
2. **Wait for the address.**
   - **Person:** hears that the firm is confirmed, with the address, and tells the analyst.
   - **Business analyst agent:** for a firm the setup command set up, section 4's step 3 takes this step's place. Otherwise it raises the task each session until done, as "Open tasks from setup" says. When the owner gives the address, it checks it is `https://mcp.realagent.network/` and one slug, which is lower-case words and numbers joined by hyphens. With any other, it says "That isn't the address of Real Agent's connector. Please check it with Real Agent." and stops. It reads the setup record, the evidence titled "Real Agent setup" in Administration, with `okb_find_records` and `okb_show_record`. When its `source_reference` is "okb setup --owner" and its `summary` says "whose short name is <slug>" with this slug, it goes on to step 4. Otherwise it goes on to step 3.
3. **Make the connector's settings.**
   - **Person:** clicks **Run** on the command the business analyst shows in the chat. Makes a Supabase access token at the address the command gives, as it says, and pastes it at its prompt. When the command prints five lines that each say done, deletes the token on that page, and types "done" in the session. In human only mode, they run the same command, or follow the steps below.
   - **Business analyst agent:** says "This makes the five settings Real Agent's connector needs in your Supabase project. Click Run on the line below. It asks for a Supabase access token, and tells you where to make one. Name it, choose the shortest expiry, choose Organization under Resource access, and keep Full access. Delete it on that page once every line says done. Then type done here." Below it goes the command, alone in a single fenced code block tagged `bash`. The command is `node "<marketplace>/plugins/okb/cli/okb.mjs" connector-settings --url <project URL> --slug <slug>`. Its `<marketplace>` is as in section 1, and the project URL is `https://<projectRef>.supabase.co`, with `projectRef` from the okb plugin's `whoami`. It writes in real values. Before it shows the command, it reads the project's public signing keys with `WebFetch`, at `https://<projectRef>.supabase.co/auth/v1/.well-known/jwks.json`. A key with `alg` `ES256` or `RS256` there means the key is done already, so step 1 below is skipped. The command still runs, for the four auth settings. Then it waits. It never runs the command itself, and never asks for the token.
   - **When the command stops:** a key line that says to run it again gives the time. The business analyst tells the owner that time, and has them click Run then. When a line says Supabase refused the token, the owner makes a new token and runs it again. Step 4 waits until a run's lines all say done. When another line says failed, it gives the owner the four steps below instead, one per reply. Then it goes on to step 4.

   By hand, in the Supabase dashboard:

   1. **Sign tokens with an asymmetric key.**
      - **Person:** in **Project Settings → JWT Keys**, checks that the project signs its tokens with an asymmetric key, and switches to one if not.
      - **Business analyst agent:** skips this step, saying nothing, when the command's key line said done or already done. It skips it too when the keys read before the command showed one. After the command has run, it never reads `jwks.json` to mark this step done, as that list holds a standby key too. Otherwise it says "First, in your Supabase project, open Project Settings, then JWT Keys. If the project still uses the legacy JWT secret, switch to the new asymmetric signing keys. Tell me when it's done."
   2. **Turn on the OAuth server.**
      - **Person:** opens **Authentication → OAuth Server**. They turn on **Enable the Supabase OAuth Server** and **Allow Dynamic OAuth Apps**, set **Authorization Path** to `/oauth/consent`, and click **Save changes**.
      - **Business analyst agent:** says "Next, open Authentication, then OAuth Server. Turn on Enable the Supabase OAuth Server, set Authorization Path to /oauth/consent, turn on Allow Dynamic OAuth Apps, and click Save changes. Leave the Site URL there as it is. Tell me when it's saved."
   3. **Set the Site URL.**
      - **Person:** in **Authentication → URL Configuration**, sets the Site URL to `https://mcp.realagent.network/<slug>/sign-in/`, with the slash at the end, and saves.
      - **Business analyst agent:** says, with the slug written in, "Next, open Authentication, then URL Configuration. Set the Site URL to the address below, with the slash at the end, and save. Tell me when it's done." Below it, alone in a fenced code block with no language tag, goes `https://mcp.realagent.network/<slug>/sign-in/`.
   4. **Turn off public sign-up.**
      - **Person:** in **Authentication → Sign In / Providers**, turns off **Allow new users to sign up**, and saves.
      - **Business analyst agent:** says "Next, in Authentication, open Sign In / Providers, turn off Allow new users to sign up, and save. Tell me when it's done."
4. **Add the connector to Claude.**
   - **Person:** the Owner of the firm's Claude organisation adds a custom connector named Real Agent under **Organization settings → Connectors**, with the URL `https://mcp.realagent.network/<slug>`.
   - **Business analyst agent:** says, with the slug written in, "Next, in Claude, open Organization settings, then Connectors, and add a custom connector called Real Agent with the URL below. Only an Owner of your Claude organisation can do this. Tell me when it's added." Below it, alone in a fenced code block with no language tag, goes `https://mcp.realagent.network/<slug>`.
5. **Connect and check.**
   - **Person:** in Claude, opens Customize, then Connectors, and connects Real Agent. On the sign-in page, signs in with their knowledge base email and password, and presses Allow. Then starts a new Code session on this folder and asks "What is outstanding?" for the home card.
   - **Business analyst agent:** says "Last, in Claude, open Customize, then Connectors, and connect Real Agent. Sign in with your knowledge base email and password, and press Allow. Then start a new Code session on this folder, and ask me what is outstanding. Your home card should show." When the home card shows, it completes the task, as its "Open tasks from setup" says, with the reason "The owner's home card showed." When the sign-in is turned away, it takes the owner through step 3 first, then step 5.

Every person connects it the same way, as the guide "Connecting Real Agent's connector" says.

**AI guided:** the business analyst gives the owner one step per reply, and asks nothing else.

## Status requests

Setup has finished when `general`, `routines`, `reference` and `plugins` are there, the check the `business-analyst:routine-interview` skill's section 1 makes before an interview. In a folder with no sign-in yet, setup has not started or stopped part way, and the setup command carries on from where it stopped. Once the owner is signed in, the business analyst calls `okb_get_scopes`. It answers in one sentence: not started or stopped part way, or set up and working. It adds the next step and who does it. Once setup has finished, Real Agent's connector is set up when the task "Connect Real Agent's connector" is completed.

## Problems

- **The sign-in failed or its code ran out:** the owner clicks Run on the setup command again. It first says the earlier setup stopped part way, and asks the owner to type yes to clear it. Then it builds again and asks for the sign-in again.
- **A password, key or token is pasted in the chat:** the business analyst does not use it. The owner changes it in Supabase.
- **The connector turns away every person's sign-in:** a project still on the legacy JWT secret publishes no signing keys. Section 5's step 3, by hand, switches it to an asymmetric key.
- **The health check fails:** a failure, as "What the owner reads" says.
