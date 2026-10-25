---
name: setup
description: Use when a firm sets up its organisational knowledge base (OKB) in a new Supabase project, or asks about its setup. Covers the Supabase account and project, building OKB and its file search, and the tests. Covers the Data API setting, the first administrator, the six scopes and Real Agent's staff. Covers each person's folder, the setup record in the Administration scope and the Remote Control settings. It runs in one of three modes: human only, AI guided or human directed.
---

# OKB setup

OKB is the firm's organisational knowledge base: the `okb` schema in the firm's own Supabase project. Supabase is the online database service that keeps it. This skill builds OKB on a new, empty project, for a firm whose people have never used Supabase. It is done once per firm, before the first routine interview.

The **owner** is the person at the firm who owns the Supabase account and becomes OKB's first administrator. The owner does every step that creates an account, chooses a password or reads a key, in Supabase's own pages and the sign-in's own prompts. The business analyst, `business-analyst:business-analyst`, does the technical steps with the owner's agreement. It never creates an account, and never sees, asks for or types a password, a key or a token. When one is offered, it refuses it.

The business analyst is the agent of the owner's **setup folder**, so it talks with the owner directly in each Code session on that folder. The owner's own reply in the session, such as "yes", is their agreement or their approval. The business analyst asks for nothing more.

The setup files are in the `okb` folder beside this skill. In the real-agent marketplace's copy on the owner's computer, that is `~/.claude/plugins/marketplaces/real-agent/plugins/business-analyst/skills/setup/okb/` on macOS and Linux. On Windows, it is `$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\business-analyst\skills\setup\okb\`.

- `setup.sql` builds OKB's tables, functions and protections, and holds no data.
- `file-search.sql` builds file search, which finds the passages in a scope's files that answer a question.
- `file-search-scopes.sql` makes file search cover every scope's files.
- `functions/` holds file search's three hosted functions: `file-search`, `file-search-worker` and `file-search-purge`.
- `schedule.sql` runs file search's work every minute.
- `file-search-tests.sql` and `tests.sql` hold the checks of the build.
- `bootstrap.sql` adds the first administrator, the six scopes, and each later person and their grants.
- `setup.sql` also puts OKB's three access templates in the database: `administrator`, `basic` and `real_agent`. `okb_get_access_templates` reads them, and `bootstrap.sql` step 3f gives a person one.
- `upgrades/` and `file-search-upgrades/` hold the numbered upgrades Real Agent applies later.

## Choose the mode

The owner chooses the mode.

- **Human only:** the owner follows the Person lines below, without the business analyst. They do each step in the Supabase dashboard, the Claude desktop app and a terminal.
- **AI guided:** the owner asks the business analyst to guide them. Before each step, the business analyst says what the step does and shows the Person line. It follows its own line with the owner watching, or asks the owner to follow theirs. It stops for the owner's approval at the end of each stage.
- **Human directed:** the owner tells the business analyst what to do. The business analyst follows its lines for each step the owner directs.

Each step below gives a **Person** line and a **Business analyst agent** line.

With the business analyst, the owner's own instruction replaces a rule of this skill, such as the order of two stages. The business analyst names the rule once and does as told. A refusal from Supabase, OKB or a tool still stands, and the business analyst gives it to the owner with what they can do instead. Nothing replaces the rule that the business analyst never creates an account or handles a password, a key or a token.

## Before the first stage

The owner needs a **password manager**, a program that stores passwords safely, and the **Claude desktop app**, signed in.

- **Person:** in the desktop app's **Code** tab, opens the **Terminal**. Runs Real Agent's install script in owner mode, as the public marketplace's README says. On macOS:

  ```sh
  cd ~ && curl -fsSLO https://raw.githubusercontent.com/Real-Agent-Network-Limited/real-agent-marketplace/main/install/install.sh && bash install.sh Real-Agent-Network-Limited/real-agent-marketplace --owner
  ```

  On Windows, in PowerShell:

  ```powershell
  cd ~; Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/Real-Agent-Network-Limited/real-agent-marketplace/main/install/install.ps1 -OutFile install.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 Real-Agent-Network-Limited/real-agent-marketplace --owner
  ```

  The script installs each program the plugins need that is missing, adds the marketplace, and installs the `okb`, `real-agent` and `business-analyst` plugins. It makes the setup folder, `~/okb`, and makes the business analyst its agent. It signs nothing in, since there is no project yet. It ends: "Start a new Code session on" the folder, "and type: Set up OKB".

  The owner quits and reopens the desktop app, starts a new Code session on `~/okb`, and types `Set up OKB`.
- **Business analyst agent:** none before the session. In the session, it starts at stage 1.
- **Evidence:** none. The script's lines stay in the owner's terminal.

**AI guided:** the business analyst starts at stage 1, since the session on the setup folder shows the script has run.

The **setup record** is each stage's status and evidence. It holds no password, key or token. Its home is the **Administration** scope, which stage 5 makes, and which only the firm's administrators and Real Agent's staff read.

Until the owner's folder signs in, in stage 7, OKB has no one to save it as. So the business analyst writes each stage's status and evidence in `setup-record.md` in the setup folder as the stage ends. In stage 7 it saves the record in Administration, and deletes the file, as "The setup record" says. No setup record stays on the owner's computer.

## 1. Account, organisation and project

1. **Create the Supabase account and organisation.**
   - **Person:** signs up at supabase.com, and creates an organisation when asked. Chooses Free or a paid plan; the choice is theirs. Supabase's pricing page gives each plan's price, and says the Free plan pauses a project that is not used for a while.
   - **Business analyst agent:** none in the dashboard. The account and its billing belong to the owner. It reads the plan itself in step 3.
   - **Evidence:** the organisation's name and plan, from `get_organization`.
2. **Create the project.**
   - **Person:** in the dashboard, in that organisation, chooses **New project**, names it, and picks the region closest to the firm. Chooses **Generate a password** for the database password, and saves it in the password manager. Under **Security**, leaves **Enable Data API** ticked and unticks **Automatically expose new tables**. Leaves **Enable automatic RLS** unticked.
   - **Business analyst agent:** none in the dashboard. The project and its password belong to the owner. It checks the project and the two settings itself in step 3.
   - **Evidence:** the project's name, region and status, from `get_project`, and the two settings, from the queries in step 3.
3. **Connect Supabase to Claude.**
   - **Person:** in the Claude desktop app, opens **Supabase** in the connector list and chooses **Connect**. In the browser, signs in to Supabase and chooses the organisation from step 1. Then starts a new Code session on the setup folder, and asks the business analyst to carry on.
   - **Business analyst agent:**
     1. Without the Supabase connector's tools, asks the owner for this step, and stops.
     2. Calls `list_projects`. With no project, asks the owner for step 2, and stops. With several, asks which is OKB's.
     3. Asks the owner one question: "Is <name>, in <region>, the project for OKB?"
     4. Calls `get_project` with its reference. It goes on only when the status is `ACTIVE_HEALTHY`.
     5. Calls `get_organization` with the project's organisation. When its `plan` is not `pro` or higher, it tells the owner the plan it found and that the Free plan pauses a project left unused. It says a paid plan keeps the project running, and that the choice is the owner's, then carries on without waiting. It records the plan in the setup record, with what it told the owner.
     6. Calls `get_project_url` with its reference. It goes on only when the address is `https://<project reference>.supabase.co`.
     7. Checks the two settings from step 2 with `execute_sql`, and asks the owner nothing about them:
        - **Automatically expose new tables** is off when `select defaclacl::text from pg_default_acl where defaclrole = 'postgres'::regrole and defaclnamespace = 'public'::regnamespace and defaclobjtype = 'r';` gives `anon` and `authenticated` no `r`, as in `anon=Dxtm/postgres`.
        - **Enable automatic RLS** is off when `select e.evtname from pg_event_trigger e join pg_proc p on p.oid = e.evtfoid where p.prosrc ilike '%row level security%';` gives no row.

        When either is on, it names the setting, and asks the owner to send the query's result to Real Agent before stage 2.
   - **Evidence:** the project's name, reference, region and status, the organisation's plan, the `get_project_url` result, and the two queries' results.

The **project reference** is the 20-character code in the project's web address. Every later call names it.

**AI guided:** the business analyst gives the owner the project it found, and waits for their approval before stage 2.

## 2. Build OKB and file search

The dashboard's **SQL Editor** runs as `postgres`, which these files need. The editor may warn about destructive operations, or offer to turn on Row Level Security. Both are expected. The owner chooses the option that runs the file unchanged, such as **Run query** or **Run without RLS**.

`setup.sql` and `file-search.sql` are long. Pasting them is much quicker than the business analyst writing them out through the connector. The business analyst offers the paste for each. It copies the file to the clipboard, checks the copy, and asks the owner to paste and run it.

On macOS it runs `pbcopy < <file>`, then compares `pbpaste | shasum -a 256` with `shasum -a 256 < <file>`. On Windows it runs `Get-Content -Raw <file> | Set-Clipboard` in PowerShell. On Linux it gives the file's full path, to open, select all and copy.

1. **Run `setup.sql`.**
   - **Person:** opens **SQL Editor** in the dashboard's left sidebar, starts a new query, pastes the whole of `setup.sql` and chooses **Run**.
   - **Business analyst agent:** offers the paste, as above. When the owner prefers to wait, calls `apply_migration` with the name `okb_setup` and the whole of `setup.sql`. Either way, checks the build with `list_tables` for the `okb` schema.
   - **Evidence:** the run's success, and the tables listed.
2. **Run `file-search.sql`, then `file-search-scopes.sql`.**
   - **Person:** runs the whole of each file in a new query, in that order.
   - **Business analyst agent:** offers the paste for `file-search.sql`, or calls `apply_migration` named `file_search`. Runs `file-search-scopes.sql` through `execute_sql`.
   - **Evidence:** each run's success.
3. **Deploy the three hosted functions.**
   - **Person:** opens **Edge Functions** and deploys a new function in the editor, named `file-search-worker`, from `functions/file-search-worker/index.ts`. It adds `text.ts`, `vendor/sheetjs-0.20.3/xlsx.mjs` and `vendor/sheetjs-0.20.3/types/index.d.ts` from that folder, at those paths. Turns JWT verification off. Then deploys `file-search` and `file-search-purge` the same way, each from its own `index.ts`, with JWT verification on.
   - **Business analyst agent:** deploys `file-search-worker` with the Supabase command-line tool, `supabase`, signed in as the owner. In a new folder, it copies `index.ts`, `text.ts` and the `vendor` folder into `supabase/functions/file-search-worker`. There it runs `supabase functions deploy file-search-worker --project-ref <project reference> --no-verify-jwt --use-api`. When the command asks for a sign-in, the owner runs `supabase login` and signs in in the browser. It calls `deploy_edge_function` for `file-search` and `file-search-purge`, each with its `index.ts` and `verify_jwt` on. Then calls `list_edge_functions` to confirm all three, with the worker's `verify_jwt` off.
   - **Evidence:** the three functions as listed, with their JWT setting.
4. **Run `schedule.sql`.**
   - **Person:** opens `schedule.sql` in a text editor, replaces `<project reference>` with the project reference, and runs it.
   - **Business analyst agent:** fills in the project reference, and runs `schedule.sql` through `execute_sql`.
   - **Evidence:** the two checks at its end: the scheduled job, and both secrets by name. Their values are never shown.

If a run reports an error, nothing of that file is kept. The owner keeps the error message for Real Agent, and runs the whole file again once its cause is put right.

**AI guided:** the business analyst gives the owner each run's result, and waits for their approval before the tests.

## 3. Tests

Each test file installs stored checks. Each run always ends with an error message, so that nothing it made is kept. OKB's checks run in four parts, each within the SQL Editor's time limit. `select okb_tests.parts();` gives the parts and each part's suites, and `select okb_tests.run(1);` runs part 1. A run that passed ends `PASS: file search checks passed`, or `PASS: part 1 of 4 passed` and the like. Any other message names the suite and the check that failed, and setup goes no further until every run ends in PASS.

1. **Install the checks.**
   - **Person:** runs the whole of `file-search-tests.sql`, then the whole of `tests.sql`, each in a new query.
   - **Business analyst agent:** offers the paste for `tests.sql`, as stage 2 says. Installs `file-search-tests.sql` with `apply_migration`, named `file_search_checks`.
   - **Evidence:** each run's success.
2. **Run the checks.**
   - **Person:** runs `select file_search.run_checks();` in a new query. Then runs `select okb_tests.run(1);`, `select okb_tests.run(2);`, `select okb_tests.run(3);` and `select okb_tests.run(4);`, each in a new query, in order. Goes on to the next part only once the one before ends with its PASS message.
   - **Business analyst agent:** runs `set local statement_timeout = '120s'; select file_search.run_checks();` as one `execute_sql` call. Then reads `select okb_tests.parts();`, and runs each part as its own `execute_sql` call, in order: `set local statement_timeout = '60s'; select okb_tests.run(1);`, then part 2, and so on. Goes on to the next part only once the one before ends with its PASS message. A run that says another run is in progress is tried again once it has finished.
   - **Evidence:** the message each run ends with, one for file search and one for each part.
3. **Check the glossary and data dictionary are empty.**
   - **Person:** runs `select (select count(*) from okb.glossary_term) + (select count(*) from okb.dictionary_table) + (select count(*) from okb.dictionary_column) + (select count(*) from okb.dictionary_source);`, which gives 0.
   - **Business analyst agent:** runs the same query through `execute_sql`, then calls `get_advisors` for security and performance.
   - **Evidence:** the count, and the advisor results.

**AI guided:** the business analyst gives the owner each PASS message and the count, and waits for their approval.

## 4. Data API

- **Person:** in the dashboard, opens **Data API** and its **Settings** tab. Under **Exposed schemas**, ticks `okb` alone. Leaves `okb_private`, `okb_storage`, `okb_task`, `okb_tests` and `file_search` unticked, and leaves `public` and `graphql_public` as they are. Checks that **Automatically expose new tables** is off, and saves.
- **Business analyst agent:** none in the dashboard. The connector has no tool for this setting, so this is the one setting the owner reads back. Once the owner has saved, it asks one question: "On the Data API settings page, which schemas are ticked under Exposed schemas?" It goes on when the answer is `okb` with `public` and `graphql_public`, or `okb` alone. It checks **Automatically expose new tables** again with stage 1's query, and asks nothing about it.
- **Evidence:** the exposed schemas, as the owner read them, and the query's result.

Once `okb` is exposed, the **Security Advisor** lists each `okb_*` function under "Signed-In Users Can Execute SECURITY DEFINER Function". That is expected: each checks the caller's grants before it reads or changes anything.

**AI guided:** the business analyst gives the owner the saved setting, and waits for their approval.

## 5. First administrator and the six scopes

1. **Create the administrator's Auth user.** An Auth user is a Supabase account with an email address and a password.
   - **Person:** in **Authentication → Users**, chooses **Add user → Create new user**. Enters their own email address and a long password from the password manager. Leaves **Auto confirm user?** on, creates the user, and copies its **User UID**.
   - **Business analyst agent:** none in the dashboard. The password never passes through the business analyst. Once the owner says the user is made, it reads `select id, email, created_at from auth.users order by created_at;` with `execute_sql`. It asks the owner one question: "Is <email> your login, and what name should OKB give you?"
   - **Evidence:** the User UID and email, from the query.
2. **Make the administrator and the scopes.**
   - **Person:** opens `bootstrap.sql` in a text editor. Fills in step 1 with the User UID and their name, and runs it. Copies the actor id it returns into step 2, and runs step 2. Fills in step 3e for themselves, and runs it.
   - **Business analyst agent:** fills in and runs `bootstrap.sql` step 1 through `execute_sql`. Then it runs step 2 with the actor id step 1 returned, and step 3e for the administrator.
   - **Evidence:** the actor id, the six scope ids, and the result of `bootstrap.sql` step 6.

Step 2 makes the six scopes:

- `general`, for the firm's day-to-day records;
- `routines`, for its routines;
- `reference`, for the glossary and the data dictionary;
- `plugins`, for each release of Real Agent's plugins;
- `administration`, for the setup record and each access record: who set the project up, each actor made, each grant given and why. Only the firm's administrators work in it. Real Agent's staff read it, with the `real_agent` template's grant. No other template names it;
- `guides`, for Real Agent's guides: installing and updating, reaching the office computer from a phone, printing, support, removing Real Agent's access and uninstalling. Everyone reads it: the `basic` and `real_agent` templates grant read, and an administrator reads every scope. Only the `real_agent` template changes its files, as with `plugins`.

A workflow plugin's releases go to a scope of its own, `plugins_<workflow>`. The database admin makes it with the `real-agent:add-staff` skill when Real Agent first publishes that workflow, not here.

**AI guided:** the business analyst gives the owner the administrator and the six scopes, and waits for their approval.

## 6. Real Agent's staff

Real Agent's staff work in the project only as the actors the owner makes here, with the `real_agent` template's grants. It is the one template that changes the `plugins` and `guides` scopes' files, and the one that reads the Administration scope. Real Agent gives the owner each staff member's name and email address. Each staff member's actor is named with their name followed by "(Real Agent)", such as "Riley Jones (Real Agent)". The `support` skill finds Real Agent by that name, and the firm sees at a glance which actors are Real Agent's.

1. **Create each staff member's Auth user.**
   - **Person:** creates the Auth user as stage 5 says, with the staff member's email address and a first password from the password manager. Passes the password to them through the password manager's secure share, and copies the User UID.
   - **Business analyst agent:** none in the dashboard. It reads the staff member's User UID with stage 5's query, by the email address Real Agent gave. It takes their name from Real Agent's list. It asks the owner one question: "Have you passed on the first password through the password manager's secure share?"
   - **Evidence:** the User UID, and the owner's answer about the first password.
2. **Make each staff member an actor with the `real_agent` template.**
   - **Person:** fills in and runs `bootstrap.sql` step 3b, then step 3e, then step 3f with the template code `real_agent`.
   - **Business analyst agent:** reads the template through `execute_sql`, with `select grants from okb.access_template where code = 'real_agent';`. It lists each grant for the owner: the scope, the record kinds and the actions. With the owner's agreement, runs the same statements through `execute_sql`, then `bootstrap.sql` step 6. Step 3f answers with each grant it issued.
   - **Evidence:** the staff member's actor id and their name ending "(Real Agent)", each grant's id, and step 6's result, listing them.

3. **Invite Real Agent into the Supabase organisation as a Developer.** Real Agent applies each OKB upgrade, which changes the database's structure. No OKB actor can do that, so Real Agent needs a place in the organisation.
   - **Person:** reads what the Developer role reaches. In the Supabase dashboard, opens the organisation's Team page. Invites the email address Real Agent gives, as a Developer. A Developer can use the SQL Editor, change the database and read the project's keys, including the service key, which passes every OKB grant. A Developer cannot change billing, members or project settings, or delete the project. Real Agent's staff use this access only to apply upgrades. The owner can remove it at any time from the same page; upgrades then stop.
   - **Business analyst agent:** none in the dashboard. It tells the owner, in those words, what the role reaches before the owner invites, and asks them to confirm the invitation once sent.
   - **Evidence:** the invited email address, its role, Developer, and the date.
4. **Load Real Agent's guides and the Python runtime.** The guides go into the Guides scope, so the database operator answers how-to questions from them. The runtime goes into the Plugins scope, for the database operator's code runs. Only Real Agent's actor changes either scope. So a Real Agent staff member runs both, once step 2 has made their actor.
   - **Person:** the Real Agent staff member opens their copy of Real Agent's repository, signed in to this project as their actor. They run these two commands, with the project's reference and their own email address in place of the angle brackets:

     ```sh
     node scripts/load-guides.mjs --project <project reference> --email <staff member's email address>
     node scripts/publish-runtime.mjs --project <project reference> --email <staff member's email address> --cache ~/.cache/real-agent-runtime
     ```

     The first prints a line for each guide it added. The second prints "Published runtime/pyodide-0.28.3 to the Plugins scope".
   - **Business analyst agent:** none, since the owner changes neither scope. It fills in both commands for Real Agent, as the `okb:writing` skill's "Commands run as pasted" says. It gives them to the owner, and asks the owner to confirm when Real Agent says both ran.
   - **Evidence:** each command's output, as Real Agent sends it.

The firm's own staff are added later by the firm's administrator, with the database admin, `@real-agent:database-admin`.

**AI guided:** the business analyst gives the owner each staff member's actor and grants, and waits for their approval.

## 7. Each person's folder

Each person has one folder on their own computer, working in this project as them. It has the `real-agent` and `business-analyst` plugins installed, and is signed in. The owner gives each person their email address, their first password through the password manager, and the project's address and publishable key. Both come from the dashboard's **Connect** button.

The first install comes from Real Agent's public marketplace, which serves only to start. Once the folder is signed in, `okb setup` runs `okb sync` as its last step. It installs the firm's own release of its plugins from the Plugins scope, `real-agent` among them, in place of the public copy. Until Real Agent publishes the firm's first release, `okb sync` says the Plugins scope holds no release yet, and the public copy stays.

- **Person:** each person, on their own computer, runs Real Agent's install script, as the public marketplace's README says. The owner passes on the email address, project address and key. The person runs the command with their own values in place of the angle brackets. On macOS, in the desktop app's Terminal:

  ```sh
  cd ~ && curl -fsSLO https://raw.githubusercontent.com/Real-Agent-Network-Limited/real-agent-marketplace/main/install/install.sh && bash install.sh Real-Agent-Network-Limited/real-agent-marketplace --email <email> --url <project URL> --key <publishable key> --new-password
  ```

  On Windows, in PowerShell:

  ```powershell
  cd ~; Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/Real-Agent-Network-Limited/real-agent-marketplace/main/install/install.ps1 -OutFile install.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 Real-Agent-Network-Limited/real-agent-marketplace --email <email> --url <project URL> --key <publishable key> --new-password
  ```

  The script installs each program the okb plugin needs that is missing, and prints one line for each. It then adds the marketplace, installs the `okb`, `real-agent` and `business-analyst` plugins, and runs `okb setup` on `~/okb`, or the folder `--folder` names. The script never asks for a password: the sign-in asks at its own prompt.

  Without the script, the person adds the marketplace and installs the plugins by hand:

  ```sh
  claude plugin marketplace add Real-Agent-Network-Limited/real-agent-marketplace
  ```

  ```sh
  claude plugin install real-agent@real-agent
  ```

  ```sh
  claude plugin install business-analyst@real-agent
  ```

  Then sets up their folder, with their own values in place of the angle brackets. On macOS and Linux:

  ```sh
  node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs setup --folder ~/okb --email <email> --url <project URL> --key <publishable key> --new-password
  ```

  On Windows, in PowerShell:

  ```powershell
  node "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\cli\okb.mjs" setup --folder "$env:USERPROFILE\okb" --email <email> --url <project URL> --key <publishable key> --new-password
  ```

  The owner goes first, on the setup folder itself. They leave out `--new-password`, since they chose their own password. They add `--agent business-analyst:business-analyst`, so the business analyst stays the folder's agent until setup has finished. Stage 9 then makes the folder the database admin's.

  Each person types their password into the sign-in's own prompt. With `--new-password`, a new password typed the same as the first keeps the first. `okb setup` then runs `okb sync` in the folder. Each person then starts a new Code session on the folder, and types: who am I?

- **Business analyst agent:** gives each person the commands with their email address and the project URL filled in, from `get_project_url`. It leaves the publishable key for the person to paste, and never asks for it or a password. It asks each person for `okb setup`'s lines from `okb sync` on, and their agent's answer to "who am I?". `okb sync` names the release installed and each plugin's old and new version, or says the Plugins scope holds no release yet.
- **Evidence:** each person's `okb setup` lines, with `okb sync`'s, and their agent's answer, naming them and the project.

**AI guided:** the business analyst gives the owner each person's sign-in, and waits for their approval.

### The setup record

Once the owner's folder is signed in, the setup record moves into OKB.

- **Person:** in a new Code session on the setup folder, types `Save the setup record`. Without the business analyst, runs `okb okb_add_record` in that folder for each stage, as the agent's line gives it, then deletes `setup-record.md`.
- **Business analyst agent:** calls `whoami`, and goes on only when it names the owner. For each stage of `setup-record.md`, it calls `okb_add_record` with `p_scope` `administration` and `p_kind` `evidence`. The title is "OKB setup, stage <n>: <stage name>". Its `summary` is the stage's status and evidence in a few sentences. Its `source_reference` is "The setup record, stage <n>", and its `source_date` the day the stage ended. Its `standing` is "observed". Its `limitations` are "Written down by the business analyst during setup, from what the owner did and read back." It then reads each record back with `okb_show_record`, and deletes `setup-record.md` once every stage is saved. From here on, it saves each later stage's evidence in the same way, with no file.
- **Evidence:** each record's id, and that `setup-record.md` is gone.

The firm's administrators read the setup record with `okb okb_find_records p_scope_id=<administration's scope id> p_kind=evidence`. Real Agent's staff read it the same way. A member of staff with the `basic` template sees none of it.

## 8. Remote Control

Remote Control lets a person carry on a session from the Claude mobile app while the office computer runs it.

- **Person:** on each office computer, in the Claude desktop app's settings, opens **Remote Control**. Turns on "Connect new sessions to Remote Control" and "Keep this computer awake for Remote Control".
- **Business analyst agent:** none. It asks each person to confirm both settings are on.
- **Evidence:** each person's confirmation.

**AI guided:** the business analyst gives the owner the list of computers with both settings on, and waits for their approval.

## 9. Check that setup has finished

Setup has finished when a signed-in person's `okb_get_scopes` lists `general`, `routines`, `reference` and `plugins`. The routine interview runs the same check before its first question, as the `business-analyst:routine-interview` skill's section 1 says.

- **Person:** in their own folder from stage 7, starts a new Code session, and types `Is setup finished?`. Without the business analyst, runs `okb okb_get_scopes` in that folder. Once setup has finished, makes the folder the database admin's by running `okb setup` again with `--agent real-agent:database-admin`. On macOS and Linux:

  ```sh
  node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs setup --folder ~/okb --email <email> --agent real-agent:database-admin
  ```

  On Windows, in PowerShell:

  ```powershell
  node "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\cli\okb.mjs" setup --folder "$env:USERPROFILE\okb" --email <email> --agent real-agent:database-admin
  ```

  The folder is already signed in, so it asks for no password.
- **Business analyst agent:** in the owner's folder, calls `whoami`, then `okb_get_scopes`, and gives the owner the codes it found. It saves the result as the setup record's last record, in Administration. Then it gives the owner the `okb setup` command above, with their email filled in. It says that a new Code session on the folder then goes to the database admin.
- **Evidence:** the `okb_get_scopes` answer, quoted.

**AI guided:** the business analyst gives the owner the setup record, and waits for their approval to close setup.

## Status requests

The business analyst gives the setup record, with one line per stage and its status, then the next step and who does it. Before stage 7 it reads `setup-record.md`, and after it, the Administration scope's records. When the owner asks what they can do themselves, it answers from each step's **Person** line.

## Problems

- **The editor offers to change the file:** the owner runs it unchanged, as stage 2 says.
- **A check ends in anything but PASS:** setup stops there. The owner sends the message to Real Agent.
- **No Supabase tools in the session:** the owner connects Supabase, as stage 1's step 3 says, and starts a new Code session.
- **"The real_agent access template names scopes this OKB lacks" in `bootstrap.sql` step 3f:** stage 5's step 2 has not run, or ran before it made `administration`. The owner runs it first.
- **A person has lost their password:** the owner gives them a new first password with `bootstrap.sql` step 7, in the SQL Editor. The step also ends their saved sign-ins. The business analyst never sees the password.
- **A password, key or token is pasted in:** the business analyst does not use it. The owner changes it in Supabase.
