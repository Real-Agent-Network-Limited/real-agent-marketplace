-- OKB: first administrator, the first scopes, and each later actor.
-- Run after setup.sql, in the SQL Editor as the postgres login. Leave the editor's role
-- selector on postgres: an impersonated user carries an Auth identity, and the actor
-- and provisioning guards refuse any change made with one.
-- Run one step at a time. Replace every <placeholder> first, including names and reasons:
-- an unreplaced id stops the statement, but unreplaced text would be saved as written.
-- Keep the ids each step returns: later steps need them.
-- Every actor change names the administrator who approved it, and the actor history records them.

-- -------------------------------------------------------------------
-- Step 1. The first administrator: a person, accountable to themselves.
-- Before this step, create their Auth user under Authentication > Users > Add user,
-- and copy the new user's id. This works only while there are no actors at all.
-- Returns the administrator's actor id.
-- -------------------------------------------------------------------
select okb_private.provision_first_administrator(
  '<administrator auth user id>'::uuid,
  '<administrator display name>');

-- -------------------------------------------------------------------
-- Step 2. The six scopes every OKB project starts with, each with its private bucket for files:
-- General, for the firm's day-to-day records; Routines, for the routines its interviews write down;
-- Reference, for the glossary and the data dictionary; Plugins, for each release of Real Agent's plugins;
-- Administration, for the setup record and each access record, which only the firm's administrators
-- and Real Agent read; and Guides, for Real Agent's guides, which everyone reads and only Real Agent
-- changes. created_by: the administrator's actor id from step 1. The database creates each
-- private bucket itself, named after the scope's code. Returns the scope ids.
-- -------------------------------------------------------------------
insert into okb.scope(code, display_name, description, created_by)
select x.code, x.display_name, x.description, '<administrator actor id>'::uuid
from (values
  ('general', 'General', 'The firm''s day-to-day records and files.'),
  ('routines', 'Routines', 'The firm''s routines, as its interviews write them down, and their designs.'),
  ('reference', 'Reference', 'The glossary of the firm''s words, and the data dictionary of where each fact is kept.'),
  ('plugins', 'Plugins', 'Each release of the firm''s plugins, which each person''s okb sync installs.'),
  ('administration', 'Administration', 'The setup record and each access record: who set the project up, each actor made, each grant given and why. Read only by the firm''s administrators and Real Agent.'),
  ('guides', 'Guides', 'Real Agent''s guides to installing, updating, printing, support and leaving, which everyone reads and only Real Agent changes.')
) as x(code, display_name, description)
where not exists(select 1 from okb.scope s where s.code = x.code)
returning code, scope_id;

-- 2b. Any later scope. A workflow plugin's own scope, for its releases, is plugins_ and the plugin's name,
-- each hyphen an underscore, such as plugins_appraisal; Real Agent's actor then needs a grant there with
-- read, create, edit and delete, from 3d, before it publishes the plugin.
-- code: lower case letters, digits and underscores, starting with a letter (at most 63).
insert into okb.scope(code, display_name, description, created_by)
values ('<scope_code>', '<scope display name>', '<what this scope covers>', '<administrator actor id>'::uuid)
returning scope_id;

-- -------------------------------------------------------------------
-- Step 3. Each later actor, then their grant.
-- Before this step, create the actor's Auth user as in step 1 and copy its id.
-- -------------------------------------------------------------------

-- 3a. An agent, accountable to a named person: that person's actor id.
-- Returns the agent's actor id.
select okb_private.provision_actor(
  '<approving administrator actor id>'::uuid,
  '<agent auth user id>'::uuid,
  '<agent display name>',
  'agent',
  '<accountable person actor id>'::uuid,
  'restricted',                                                   -- or 'administrator'
  false);                                                         -- true: every save needs a person's approval

-- 3b. A person, who is accountable to themselves. Returns their actor id.
select okb_private.provision_actor(
  '<approving administrator actor id>'::uuid,
  '<person auth user id>'::uuid,
  '<person display name>',
  'human',
  null,
  'restricted',                                                   -- or 'administrator'
  false);

-- 3c. An application, such as the order management system, accountable to a named person:
-- that person's actor id. An application is always 'restricted' and never waits for a
-- person's approval: the database refuses any other values. Returns the application's actor id.
select okb_private.provision_actor(
  '<approving administrator actor id>'::uuid,
  '<application auth user id>'::uuid,
  '<application display name>',
  'application',
  '<accountable person actor id>'::uuid,
  'restricted',
  false);

-- 3d. The grant, approved by a named, enabled administrator. Returns the grant as JSON.
-- gen_random_uuid() makes every run a new grant. For a safe retry, put a fixed uuid there
-- instead: rerunning with the same id and arguments returns the existing grant, and
-- changed arguments are refused.
select okb_private.provision_grant(
  '<approving administrator actor id>'::uuid,                     -- approver
  gen_random_uuid(),                                              -- issuance request id
  '<actor id>'::uuid,                                             -- the actor from 3a, 3b or 3c
  (select scope_id from okb.scope where code = '<scope_code>'),
  array['activity','decision','model','evidence'],                -- record kinds
  null::uuid,                                                     -- one record, or null for the whole scope
  array['read','create','edit','start','hold','complete','reopen','cancel','decide'],  -- add 'delete' to let the actor delete the scope's files, and its records with an approval
  null::timestamptz,                                              -- expiry, or null for none
  '<reason for this grant>');

-- 3e. Each person's sessions scope, where their agent keeps the text of every session with them.
-- Run it for each person from 3b, and for the first administrator from step 1. A person who already
-- holds a grant in a scope whose code starts sessions_, such as sessions_alex, has their sessions scope.
-- code: sessions_ and the person's Auth user id with its hyphens removed, such as
-- sessions_3f2a9c0e4b1d4e7a9f6c2b8d1e5a7c3f. The statement makes it from the person's actor id.
-- created_by: the approving administrator's actor id. The person alone holds a grant there,
-- with 'delete' so they can remove a session's file. The grant finds the scope only while nobody
-- holds a grant there. Returns the grant as JSON.
insert into okb.scope(code, display_name, description, created_by)
select 'sessions_' || replace(auth_user_id::text, '-', ''), '<person display name>''s sessions',
  'The text of each session <person display name> has had with their agent.', '<approving administrator actor id>'::uuid
from okb.actor where actor_id = '<person actor id>'::uuid
returning scope_id;
select okb_private.provision_grant(
  '<approving administrator actor id>'::uuid,
  gen_random_uuid(),
  '<person actor id>'::uuid,                                      -- the person from 3b, or the first administrator
  (select s.scope_id from okb.scope s join okb.actor a on s.code = 'sessions_' || replace(a.auth_user_id::text, '-', '')
    where a.actor_id = '<person actor id>'::uuid
    and not exists(select 1 from okb.authorisation z where z.scope_id = s.scope_id)),
  array['evidence'],
  null::uuid,
  array['read','create','edit','delete'],
  null::timestamptz,
  'Their agent keeps the text of each session with them here.');

-- 3f. The grants of an access template, which OKB holds, for a person from 3b, after 3e. Replace
-- <template code> with the template's code: basic for a member of staff, or real_agent for Real
-- Agent's staff, which also reads the Administration scope. A person made from the administrator template is made with 'administrator' in 3b
-- and needs no grant here. It issues each grant of the template the person does not hold yet, and
-- returns each grant it issued, so it can be run again. A scope the template names and the database
-- lacks stops it, naming the scope.
select okb_private.apply_access_template('<approving administrator actor id>'::uuid, '<person actor id>'::uuid, '<template code>');

-- -------------------------------------------------------------------
-- Step 4. Revoking a grant, approved by a named, enabled administrator.
-- -------------------------------------------------------------------
select okb_private.provision_revocation(
  '<approving administrator actor id>'::uuid,
  '<grant id>'::uuid,
  '<reason for the revocation>');

-- -------------------------------------------------------------------
-- Step 5. Disabling an actor, or enabling them again, approved by a named, enabled administrator.
-- -------------------------------------------------------------------
select okb_private.provision_actor_enabled(
  '<approving administrator actor id>'::uuid,
  '<actor id>'::uuid,
  false);                                                         -- true to enable again

-- -------------------------------------------------------------------
-- Step 6. Checking the result.
-- -------------------------------------------------------------------
select actor_id, display_name, actor_kind, authority_class, enabled, auth_user_id from okb.actor;
select code, display_name, enabled from okb.scope;
select authorisation_id, executor_actor_id, issued_by_actor_id, scope_id, allowed_actions, expires_at, revoked_at
from okb.authorisation order by issued_at;
select actor_id, field, old_value, new_value, changed_at, changed_by_actor_id from okb.actor_change order by change_id;

-- -------------------------------------------------------------------
-- Step 7. A new first password for a person who has lost theirs.
-- Generate a long password in the password manager, and put it and the person's email address in
-- place. It sets the password and ends the person's saved sign-ins, so each of their folders signs
-- in again. Check it shows users_reset 1. Pass the password on through the password manager's
-- secure share, or face to face. The person signs in again with okb setup and --new-password, and
-- chooses a new one. Leave the dashboard's Send password recovery and Send magic link unused.
-- -------------------------------------------------------------------
with u as (
  update auth.users
  set encrypted_password = extensions.crypt('<new password>', extensions.gen_salt('bf')),
      updated_at = now()
  where email = '<email address>'
  returning id
), s as (
  delete from auth.sessions where user_id in (select id from u) returning 1
)
select (select count(*) from u) as users_reset, (select count(*) from s) as sessions_ended;
