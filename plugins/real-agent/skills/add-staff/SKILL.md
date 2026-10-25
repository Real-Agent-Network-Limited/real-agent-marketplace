---
name: add-staff
description: Use when a firm's administrator adds a member of staff to a workflow, or gives one a role in it. Also use when a workflow's plugin first needs its own scope. It makes the person's actor in OKB and a one-time invitation code, and gives them their role's grants from the workflow plugin's access.json. It checks they sign in and see only that role's records, and saves the access record. It runs in one of three modes: human only, AI guided or human directed.
---

# Add staff

Each member of staff works in the firm's organisational knowledge base (OKB) as their own actor, with their own sign-in. OKB is the firm's own Supabase project. In each workflow a person holds one role, such as negotiator or manager. The role sets what they may read and change there. So the audit log names who did what, and each person sees only what their role allows.

This skill adds one person to one workflow. A workflow is one plugin, such as `appraisal`, delivered by Real Agent. Each workflow plugin holds an `access.json` file. It names the workflow's own scope and each role in it, with the role's grants. It also names the roles whose people install the plugin. Section 1 sets out the file.

Each workflow plugin's releases are kept in a scope of their own, `plugins_<workflow>`: the plugin's name, each hyphen an underscore, such as `plugins_appraisal`. Only a person whose grants reach that scope gets the plugin from `okb sync`. Section 2 makes the scope before Real Agent first publishes the workflow.

Each person's access is written down in the **Administration** scope, which only the firm's administrators and Real Agent's staff read. Section 7 saves that access record.

The database admin, `@real-agent:database-admin`, runs this skill with the firm's administrator. It adds a person with one call to the okb plugin's `invite_person` tool, once the administrator has confirmed the person's name, email and role. The tool calls the `okb-invite` hosted function as the administrator.

OKB makes their actor, their grants, the access record and a one-time invitation code, and no email is sent. The administrator gives the person the code. The person runs one command, which asks for the code and a password they choose. The agent never asks for, sees or handles a password or a secret key. Only in human only mode does the administrator use the Supabase dashboard and the SQL Editor, in section 4.

This skill sets the order, the wording and the checks. It uses the `okb:records` skill for every call, and its sections 1, 10, 14 and 16.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step in the Supabase dashboard and with the `okb` command.
- **AI guided:** the person asks the database admin to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the database admin what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a **Database admin agent** line.

With the agent, the person's own instruction replaces a rule of this skill, such as the order of the stages. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. The workflow's roles

The workflow's `access.json` is in its plugin, at the plugin's top folder. Each release in the workflow's plugin scope holds it at `<release>/plugins/<workflow>/access.json`. This example has two roles, and both install the plugin. A negotiator works only on the appraisals they started. A manager sees and decides on every appraisal.

```json
{
  "workflow": "appraisal",
  "scope": { "code": "appraisal", "display_name": "Appraisal", "description": "Each market appraisal, from the vendor's first call to the instruction." },
  "roles": {
    "negotiator": {
      "description": "A negotiator books and carries out appraisals, and sees only the appraisals they started.",
      "grants": [{ "scope": "appraisal", "record_kinds": ["activity", "decision", "model", "evidence"], "actions": ["read", "create", "edit", "start", "complete", "cancel"], "own_records": true }]
    },
    "manager": {
      "description": "The branch manager sees every appraisal, takes one over, and decides on the price advice.",
      "grants": [{ "scope": "appraisal", "record_kinds": ["activity", "decision", "model", "evidence"], "actions": ["read", "create", "edit", "start", "hold", "complete", "reopen", "cancel", "decide"], "own_records": false }]
    }
  },
  "plugin_readers": ["negotiator", "manager"]
}
```

The rules for the file:

- `workflow` is the plugin's name, as its `plugin.json` gives it.
- `scope` is the workflow's own scope: its code, its name and what it holds. The code is lower case letters, digits and underscores. It is never `general`, `routines`, `reference`, `plugins` or `administration`, and never starts `plugins_` or `sessions_`.
- `roles` names each role, in lower case. Each role has a `description` in plain words and its `grants`.
- Each grant names a `scope`, its `record_kinds`, its `actions` and `own_records`, as the access templates do. A role has a grant in the workflow's scope. It may also work in `general`, `routines` or `reference`, and never in `plugins`.
- A grant with `own_records` true carries `read` and no `delete`, as the records skill's section 15 says.
- `plugin_readers` names at least one role whose people install the workflow's plugin. Section 5 gives each person in such a role read of `plugins_<workflow>`.

`publish-plugin.mjs` refuses a workflow plugin whose `access.json` breaks a rule. So the file in a release is one this skill can use.

1. **Find the newest release.**
   - **Person:** in their folder, runs `okb list_files bucket=plugins_<workflow>`. The newest release is the folder with the latest name, such as `20261015-120000-1a2b3c4`, whose own list holds `MANIFEST`. `okb list_files bucket=plugins_<workflow> prefix=<release>` shows it.
   - **Database admin agent:** calls `list_files` with the workflow's plugin scope, `plugins_<workflow>`, as the bucket. It takes the folder with the latest name, and calls `list_files` with that folder as `prefix`. A folder without `MANIFEST` is a release still being published, so it takes the next older one. When the scope is missing or holds no release, it runs section 2 first, and asks Real Agent to publish.
2. **Read the workflow's access.json.**
   - **Person:** runs `okb download_file bucket=plugins_<workflow> path=<release>/plugins/<workflow>/access.json file=access-<workflow>.json`, and opens the file.
   - **Database admin agent:** calls `download_file` with that path, into a new file in the agent folder, and reads it with `read_file`. When the release has no such file, it says the workflow is not in the firm's plugins yet, and stops.
3. **Choose the person and their role.**
   - **Person:** names the member of staff, their work email address, and one role from the file.
   - **Database admin agent:** shows each role's name, its description and its grants in plain words. It asks which person and which role. One person holds one role in each workflow.

**AI guided:** the database admin gives the person the role chosen and its grants, and waits for their approval.

## 2. The workflow's scopes

A workflow has two scopes. Its plugin scope, `plugins_<workflow>`, keeps the plugin's releases. Its own scope, from `access.json`, keeps its records. OKB lets only an administrator add a scope, so Real Agent asks the administrator for the plugin scope before the first publish. `publish-plugin.mjs` refuses until it is there, and prints the two commands of steps 1 and 2.

1. **Add the plugin scope when it is missing.**
   - **Person:** runs `okb okb_get_scopes`, and looks for `plugins_<workflow>`. When it is missing, runs `okb okb_add_scope p_code=plugins_<workflow> p_display_name="Plugins: <workflow>" p_description="Releases of the <workflow> workflow plugin. Read by the roles its access.json names; Real Agent publishes to it." p_reason="The <workflow> workflow plugin's own scope, for its releases."`
   - **Database admin agent:** calls `okb_get_scopes`. When the plugin scope is missing, it shows the code, name and description above. Once the person agrees, it calls `okb_add_scope`. OKB refuses a code named for one of Real Agent's own plugins, such as `plugins_okb`. File search leaves every `plugins_` scope out.
2. **Let Real Agent publish there.**
   - **Person:** runs `okb okb_find_actors p_name="(Real Agent)"` for Real Agent's actor id. Then runs `okb okb_grant_permission p_issuance_request_id="<new UUID>" p_executor_id="<Real Agent's actor id>" p_scope_id="<plugins_<workflow>'s scope id>" p_record_kinds='["evidence"]' p_record_id=null p_actions='["read","create","edit","delete"]' p_expires_at=null p_reason="Real Agent publishes the <workflow> workflow plugin's releases." p_own_records=false`.
   - **Database admin agent:** finds Real Agent's actor by the name ending "(Real Agent)", and checks with `okb_get_authorisations` that it holds no live grant there yet. Once the person agrees, it calls `okb_grant_permission` with those values. The storage rules then let Real Agent's actor alone change the scope's files. The administrator's own authority reads them and changes none.
3. **Check the workflow's own scope is there.**
   - **Person:** looks in `okb okb_get_scopes` for the code `access.json` gives.
   - **Database admin agent:** finds it in the same answer. When it is there, it goes on to section 3.
4. **Add the workflow's own scope when it is missing.**
   - **Person:** runs `okb okb_add_scope p_code="<code>" p_display_name="<name>" p_description="<description>" p_reason="The <workflow> workflow's own scope, from its access.json."`
   - **Database admin agent:** shows the code, name and description from `access.json`. Once the person agrees, it calls `okb_add_scope`, as the records skill's section 13 says.

**AI guided:** the database admin gives the person the workflow's two scopes and Real Agent's grant, and waits for their approval.

## 3. Invite the person

One call adds the person: their actor, their grants and a one-time invitation code. The `okb-invite` hosted function goes on only for an administrator, as OKB itself answers it. It sends no email. An email that already has a sign-in keeps it, and gets no code.

The code is three groups of four letters and digits, such as `K7QM-3XRD-W9PA`. It works once, for 7 days. Five wrong tries lock it. Inviting the same email again replaces an unused code with a new one. OKB keeps only the code's SHA-256, so the code is in the tool's answer once, and nowhere else.

It makes their actor. Real Agent's staff get the name "<name> (Real Agent)". It gives the access template's grants, or a workflow role's grants. It saves the access record in Administration, as the administrator. The person's sessions scope is made when they first sign in.

A workflow role gives the `basic` template's grants and the role's grants from the newest release of the workflow's `access.json`. It also gives read of `plugins_<workflow>` for a role `plugin_readers` names. A person already in OKB keeps their actor, and gets only the grants they lack.

1. **Confirm the name, email and role.**
   - **Person:** decides the person's name, their work email address, and their access template or workflow role.
   - **Database admin agent:** asks for whatever the administrator has not given, one question at a time. For an access template, it reads `okb_get_access_templates` and names the template's grants in plain words. Real Agent is the `real_agent` template, and its name is the staff member's name, such as Support. It then asks once, in one line, such as "Shall I add Sam Lee, sam@firm.example, as basic staff?"
2. **Add them.**
   - **Person:** in their folder, runs `okb invite_person name="<name>" email=<email> template=<template>`, or `workflow=<workflow> role=<role>` in place of the template. It prints the code, its last day, and the person's commands.
   - **Database admin agent:** after the administrator's yes, calls `invite_person` once, with `name`, `email` and either `template` or `workflow` and `role`. Its answer gives `code`, `code_expires_at`, and the person's `command`, `install_command` and `install_command_windows`. The reply is plain sentences, with each command alone in a fenced code block tagged `bash`, as given:
     - With `sign_in` "code": "I've added <name> as <role>. Their one-time invitation code is <code>, and it works until <day>. Please give <first name> the code yourself, in person or by phone. If Real Agent is already on their computer, they run this line in the Terminal:" Then `command`. Then "If not, they run this line instead, which installs Real Agent first:" Then `install_command`. When the administrator says the person uses Windows, the second line is `install_command_windows`, in a block tagged `powershell`.
     - With `sign_in` "existing": "<name> already had a sign-in, so there is no code. Their role is ready. They run this line in the Terminal:" Then `command`.
     - For Real Agent: "I've added Real Agent as <name>. Please email its one-time code to <email>: <code>. It works once, until <day>." With no command: Real Agent's staff know it.
     - `<role>` is the template or role in plain words, such as "basic staff" or "a negotiator in appraisal". `<day>` is `code_expires_at` as a day, such as 1 November 2026.
3. **When it is refused.**
   - **Person:** reads the problem the command prints.
   - **Database admin agent:** gives the problem in one plain sentence, and what the administrator can do. OKB has kept nothing. It never offers the dashboard steps of section 4 instead.

**AI guided:** the database admin gives the person the name, email and role it will add, and waits for their approval.

## 4. By hand, in human only mode

The administrator may add a person without the agent. The easiest way is section 3's Person line, the `okb invite_person` command, which gives the code. This section is the other way, with no code: the Supabase dashboard and the SQL Editor.

The database makes an actor by hand only from the SQL Editor, as the `postgres` login, with steps 3b and 3e of `bootstrap.sql`. That file is in the business analyst plugin's setup skill, in its `okb` folder. The database admin never gives these steps. It uses section 3.

1. **Make the person's Auth user.**
   - **Person:** in the Supabase dashboard, opens **Authentication**, then **Users**, then **Add user**, then **Create new user**. Types the person's email address and a first password from the firm's password manager, and ticks **Auto Confirm User**. Then opens the new user and copies its user ID. Shares the first password through the password manager, never by email or chat.
   - **Database admin agent:** none: it uses section 3.
2. **Make the actor.**
   - **Person:** copies steps 3b and 3e from `bootstrap.sql`. Replaces `<approving administrator actor id>` with their own actor id from `okb okb_get_actor`, `<person auth user id>` with the user ID, and `<person display name>` with the person's name. In the SQL Editor, with the role selector on `postgres`, runs step 3b. Puts the actor id it returns in place of `<person actor id>` in step 3e, and runs it.
   - **Database admin agent:** none: it uses section 3.
3. **Give the template.**
   - **Person:** runs `okb okb_apply_access_template p_person=<actor id> p_template=basic`. Then follows section 5 for a workflow role, and section 7 for the access record.
   - **Database admin agent:** none: it uses section 3.

**AI guided:** none: in AI guided mode, the database admin uses section 3.

## 5. The role's grants

Section 3 gives a new person their role. This section changes the role of someone already in the workflow, and is the human only route.

1. **Read the person's grants.**
   - **Person:** runs `okb okb_get_authorisations p_executor_id=<actor id>`.
   - **Database admin agent:** calls `okb_get_authorisations` with `p_executor_id`. It lists any grant the person holds in the workflow's scope. A grant there from another role of the workflow is revoked once the administrator agrees, with `okb_revoke_authorisation` and the reason "Their role in the <workflow> workflow is now <role>."
2. **Give each grant of the role.**
   - **Person:** for each grant of the role, runs `okb okb_grant_permission p_issuance_request_id="<new UUID>" p_executor_id="<actor id>" p_scope_id="<scope id>" p_record_kinds='<record_kinds>' p_record_id=null p_actions='<actions>' p_expires_at=null p_reason="The <role> role in the <workflow> workflow, from its access.json." p_own_records=<own_records>`.
   - **Database admin agent:** shows each grant in plain words. It names the scope, what the person may do, and any limit to their own records. Once the administrator agrees, it calls `okb_grant_permission` for each grant the person does not hold yet. It passes a new UUID as `p_issuance_request_id`, and the scope's id from `okb_get_scopes`.
3. **Give read of the plugin scope, for a role `plugin_readers` names.**
   - **Person:** runs `okb okb_grant_permission p_issuance_request_id="<new UUID>" p_executor_id="<actor id>" p_scope_id="<plugins_<workflow>'s scope id>" p_record_kinds='["evidence"]' p_record_id=null p_actions='["read"]' p_expires_at=null p_reason="The <role> role in the <workflow> workflow reads its plugin, from its access.json." p_own_records=false`.
   - **Database admin agent:** checks that `plugin_readers` names the role, and that the person holds no live read grant in `plugins_<workflow>`. It gives the grant once the administrator agrees. When the role is not named, the person gets none, and `okb sync` leaves the plugin out for them.
4. **Check the grants.**
   - **Person:** runs `okb okb_get_authorisations p_executor_id=<actor id>` again.
   - **Database admin agent:** calls `okb_get_authorisations` again. It checks that each grant of the role is there, with the scope, record kinds, actions and `own_records` of `access.json`. It checks the plugin scope's read when `plugin_readers` names the role. It reports any difference.

**AI guided:** the database admin gives the person the role's grants as OKB holds them, and waits for their approval.

## 6. The person signs in

1. **Set up the person's folder.**
   - **Person:** the member of staff runs the line the administrator gave them on their own computer. With Real Agent installed, it is `okb setup` with `--join`. Without it, it is Real Agent's install script, from the public marketplace's README, which runs `okb setup --join` itself. Each takes their email, and the project's address and publishable key. The sign-in asks for the code, and a password they choose, twice. A person made by hand in section 4 leaves out `--join` and adds `--new-password`, to replace their first password. The setup's last step is `okb sync`. It installs the firm's own release of its plugins, and adds the workflow's plugin to their copy when their role reads its plugin scope. They install it with the command `okb sync` gives.
   - **Database admin agent:** gave the administrator the person's lines in section 3, with every value filled in. When the code is lost or has run out, it adds the person again, as section 3 says, which gives a new code.
2. **Check what the person sees.**
   - **Person:** the member of staff, in their folder, runs `okb okb_get_authorisations` and `okb okb_find_records p_scope_id=<scope id>`, and sends both results to the administrator.
   - **Database admin agent:** calls `okb_get_sign_ins`. It checks that the person has signed in, by their `last_sign_in_at`. It reads the person's two results. Their grants are the role's and the `basic` template's, as `okb_get_access_templates` gives it. In a role limited to its own records, each record they see is one they created.
3. **Tell the person what they may do.**
   - **Person:** reads the role's description back to the member of staff.
   - **Database admin agent:** writes the person a short note by the writing skill. It names the workflow, their role, what they may read and change, and the agent they call with `@`.

**AI guided:** the database admin gives the person what the member of staff saw, and waits for their approval.

## 7. The access record

Each person's access is saved as evidence in the Administration scope. It names who was added, to which workflow and role, each grant given and why, and who approved it. Only the firm's administrators and Real Agent's staff read it.

`okb-invite` saves the access record for each person section 3 adds, and gives its id as `access_record_id`. The database admin reads it back with `okb_show_record`, and saves none of its own for that person.

1. **Save the access record.**
   - **Person:** runs `okb okb_add_record p_scope=administration p_kind=evidence p_title="Access for <person's name>: <role> in <workflow>" p_reason="Records the access given to <person's name>." p_fields='{"summary":"<who approved it> gave <person's name> the <role> role in the <workflow> workflow: <each grant, in plain words>.","source_reference":"okb_get_authorisations for <actor id>","source_date":"<today>","standing":"observed","limitations":"Written by the add-staff skill as the grants were given."}'`.
   - **Database admin agent:** writes the summary from what section 5 checked, by the writing skill, and shows it to the administrator. Once they agree, it calls `okb_add_record` with those values, and reads it back with `okb_show_record`. Signed in as the administrator, it needs no grant in Administration.
2. **Record each later change the same way.**
   - **Person:** runs the same `okb okb_add_record` for a new role, a grant revoked or an actor disabled. The summary gives the change and its reason.
   - **Database admin agent:** saves an access record of its own for each such change, once the administrator agrees, and reads it back.

**AI guided:** the database admin gives the person the access record's id, and waits for their approval.

## When the person changes something

- **Real Agent's staff:** setup made Real Agent's actor and its code. When that code is lost or has run out, or Real Agent names another member of staff, use section 3 with the `real_agent` template. The name is the staff member's own, such as Support, with the email Real Agent gives.
- **Another role for someone already in the workflow:** run section 5 with the new role. The grants of the old role in the workflow's scope are revoked first.
- **A person leaving the firm:** this skill adds people. Disable their actor with step 5 of `bootstrap.sql`, as the records skill's "Problems with moves, scopes and grants" names it, and revoke their grants.
- **A role missing from access.json:** Real Agent adds it to the workflow's plugin and publishes a new release. Ask Real Agent with the `real-agent:support` skill.
