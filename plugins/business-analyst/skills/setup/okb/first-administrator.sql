-- OKB: the firm's first administrator, the six scopes and Real Agent's staff, from the Auth users the okb-setup
-- hosted function made at the owner's first sign-in, as okb_setup.person lists them. Run once, as postgres, through
-- okb-setup or the SQL Editor, after the owner has signed in. It holds no name, email or id of its own.
-- It does what bootstrap.sql's steps 1, 2, 3b, 3e and 3f do, filled in from okb_setup.person: the owner becomes
-- the first administrator, with their sessions scope; the six scopes are made in their name; and each of Real Agent's
-- staff becomes an actor named "<name> (Real Agent)", with their sessions scope and the real_agent template's grants,
-- each approved by the owner. One transaction: a failure keeps nothing.
do $$
declare
 o record;
 p record;
 admin_id uuid;
 person_id uuid;
begin
 select * into o from okb_setup.person where role = 'owner';
 if o.auth_user_id is null then
  raise exception 'The owner has not signed in yet: okb_setup.person names no owner' using errcode = '22023';
 end if;
 if exists(select 1 from okb.actor) then
  raise exception 'OKB already has actors: the first administrator is made' using errcode = '23505';
 end if;

 -- Step 1. The first administrator.
 admin_id := okb_private.provision_first_administrator(o.auth_user_id, o.name);

 -- Step 2. The six scopes, as bootstrap.sql's step 2 makes them.
 insert into okb.scope(code, display_name, description, created_by)
 select x.code, x.display_name, x.description, admin_id
 from (values
   ('general', 'General', 'The firm''s day-to-day records and files.'),
   ('routines', 'Routines', 'The firm''s routines, as its interviews write them down, and their designs.'),
   ('reference', 'Reference', 'The glossary of the firm''s words, and the data dictionary of where each fact is kept.'),
   ('plugins', 'Plugins', 'Each release of the firm''s plugins, which each person''s okb sync installs.'),
   ('administration', 'Administration', 'The setup record and each access record: who set the project up, each actor made, each grant given and why. Read only by the firm''s administrators and Real Agent.'),
   ('guides', 'Guides', 'Real Agent''s guides to installing, updating, printing, support and leaving, which everyone reads and only Real Agent changes.')
 ) as x(code, display_name, description)
 where not exists(select 1 from okb.scope s where s.code = x.code);

 -- Step 3b for each of Real Agent's staff, then step 3e for every person, then step 3f for Real Agent's staff.
 for p in select * from okb_setup.person order by role = 'real_agent', name loop
  if p.role = 'owner' then
   person_id := admin_id;
  else
   person_id := okb_private.provision_actor(admin_id, p.auth_user_id, p.name || ' (Real Agent)', 'human', null, 'restricted', false);
  end if;
  insert into okb.scope(code, display_name, description, created_by)
  values ('sessions_' || replace(p.auth_user_id::text, '-', ''),
   case when p.role = 'owner' then p.name else p.name || ' (Real Agent)' end || '''s sessions',
   'The text of each session ' || case when p.role = 'owner' then p.name else p.name || ' (Real Agent)' end || ' has had with their agent.',
   admin_id);
  perform okb_private.provision_grant(
   admin_id,
   gen_random_uuid(),
   person_id,
   (select s.scope_id from okb.scope s where s.code = 'sessions_' || replace(p.auth_user_id::text, '-', '')),
   array['evidence'],
   null::uuid,
   array['read','create','edit','delete'],
   null::timestamptz,
   'Their agent keeps the text of each session with them here.');
  if p.role = 'real_agent' then
   perform okb_private.apply_access_template(admin_id, person_id, 'real_agent');
  end if;
 end loop;
end $$;
