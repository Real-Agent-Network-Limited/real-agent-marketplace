-- 0002-administration-and-plugin-scopes
-- base: 2052799
-- Two of plan 1's decisions for a project built before them. The Administration scope, administration, keeps
-- the setup record and each access record: who set the project up, each actor made, each grant given and why.
-- The client's administrators work in it with their authority, and Real Agent's staff read it with the
-- real_agent template's new grant; no other template names it. The scope is made in an enabled administrator's
-- name; a project with no administrator yet gets it at bootstrap.sql's step 2. The real_agent template gains
-- its read grant there, unless an administrator has changed the template. Each person made from it gets the
-- grant when the template is applied to them again.
-- Each scope whose code starts plugins_ keeps one workflow plugin's releases, and its files change only with
-- an actor's own grant there, as the plugins scope's do: an administrator's authority alone reads them.
-- A workflow plugin's scope never takes the name of one of Real Agent's own plugins, plugins_real_agent, plugins_okb,
-- plugins_business_analyst or plugins_project: okb sync takes those plugins only from the plugins scope. A project
-- that holds such a scope stops this upgrade, naming the constraint; delete that scope, then run it again.
-- Safe to run twice. Run as the postgres login.

-- The plugins scope's storage rules, for each workflow plugin's scope too.
drop policy if exists "OKB: plugins files only with a plugins grant (upload)" on storage.objects;
drop policy if exists "OKB: plugins files only with a plugins grant (replace)" on storage.objects;
drop policy if exists "OKB: plugins files only with a plugins grant (delete)" on storage.objects;
create policy "OKB: plugins files only with a plugins grant (upload)" on storage.objects as restrictive
 for insert to authenticated with check ((bucket_id<>'plugins' and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('create')));
create policy "OKB: plugins files only with a plugins grant (replace)" on storage.objects as restrictive
 for update to authenticated using ((bucket_id<>'plugins' and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('edit')))
 with check ((bucket_id<>'plugins' and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('edit')));
create policy "OKB: plugins files only with a plugins grant (delete)" on storage.objects as restrictive
 for delete to authenticated using ((bucket_id<>'plugins' and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('delete')));

-- No scope takes the name of one of Real Agent's own plugins' scopes.
set role okb_owner;
alter table okb.scope drop constraint if exists scope_code_not_own_plugin;
alter table okb.scope add constraint scope_code_not_own_plugin check (code not in ('plugins_real_agent','plugins_okb','plugins_business_analyst','plugins_project'));
reset role;
-- okb_add_scope refuses such a code with a sentence of its own.
set role okb_owner;
grant create on schema okb_private to okb_writer;
reset role;
set role okb_writer;
create or replace function okb_private.add_scope(p_code text, p_display_name text, p_description text, p_reason text default null,
 p_private boolean default false, p_owner text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; c text:=btrim(coalesce(p_code,'')); n text:=btrim(coalesce(p_display_name,'')); d text:=btrim(coalesce(p_description,''));
 private boolean:=coalesce(p_private,false); o uuid; people jsonb; clash okb.scope;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator adds a scope' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for the change, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 if not private and p_owner is not null then raise exception 'Only a private scope has an owner' using errcode='22023'; end if;
 if c !~ '^[a-z][a-z0-9_]{0,62}$' then
  raise exception 'A scope''s code is lower case letters, digits and underscores, starting with a letter, at most 63 characters' using errcode='22023';
 end if;
 if private and (c in ('general','routines','reference','plugins') or starts_with(c,'plugins_') or starts_with(c,'sessions_')) then
  raise exception 'The code % is kept for OKB''s own scopes',c using errcode='22023';
 end if;
 if c in ('plugins_real_agent','plugins_okb','plugins_business_analyst','plugins_project') then
  raise exception 'The code % names one of Real Agent''s own plugins, which only the plugins scope keeps',c using errcode='22023';
 end if;
 if n='' or length(n)>200 then raise exception 'Give the scope''s name, at most 200 characters, as p_display_name' using errcode='22023'; end if;
 if d='' or length(d)>4000 then raise exception 'Give what the scope covers, at most 4000 characters, as p_description' using errcode='22023'; end if;
 select * into clash from okb.scope x where c=x.code or lower(n) in (lower(btrim(x.display_name)),lower(x.code)) limit 1;
 if found then
  raise exception 'Another scope has the name or code "%": % (code %)',case when c=clash.code then c else n end,clash.display_name,clash.code using errcode='23505';
 end if;
 if private then
  if p_owner is null then
   o:=a.actor_id;
  else
   people:=okb_private.named_people((select coalesce(jsonb_agg(jsonb_build_object('actor_id',x.actor_id,'display_name',x.display_name)),'[]'::jsonb)
    from okb.actor x where x.actor_kind='human' and x.enabled),p_owner);
   if jsonb_array_length(people)=0 then raise exception 'No enabled person has a name with "%"',p_owner using errcode='22023'; end if;
   if jsonb_array_length(people)>1 then
    raise exception 'More than one person fits "%": %',p_owner,(select string_agg(x->>'display_name',', ') from jsonb_array_elements(people) x) using errcode='22023';
   end if;
   o:=(people->0->>'actor_id')::uuid;
  end if;
 end if;
 return okb_private.add_scope(c,n,d,private,o,a.actor_id,btrim(p_reason));
end $$;
reset role;
set role okb_owner;
revoke create on schema okb_private from okb_writer;
reset role;
-- Only the real_agent template names the administration scope, and only to read it.
set role okb_owner;
create or replace function okb_private.save_access_template(p_code text, p_grants jsonb, p_description text, p_authority_class text, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; o okb.access_template; n okb.access_template; c text:=lower(btrim(coalesce(p_code,'')));
 old_value jsonb; new_value jsonb;
begin
 a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator changes an access template' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for the change, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 if c !~ '^[a-z][a-z0-9_]{0,62}$' then raise exception 'A template''s code is lower case letters, digits and underscores, starting with a letter' using errcode='22023'; end if;
 lock table okb.access_template in share row exclusive mode;
 select * into o from okb.access_template where code=c;
 if found then
  n:=o;
  old_value:=jsonb_build_object('description',o.description,'authority_class',o.authority_class,'grants',o.grants);
 elsif p_description is null or p_authority_class is null or p_grants is null then
  raise exception 'A new template needs its description, authority class and grants' using errcode='22023';
 end if;
 n.code:=c;
 n.description:=coalesce(nullif(btrim(coalesce(p_description,'')),''),o.description);
 n.authority_class:=coalesce(p_authority_class,o.authority_class);
 n.grants:=case when p_grants is null then o.grants else okb_private.template_grants(p_grants) end;
 -- Only Real Agent's template changes the plugins scope's files; every other template only reads them.
 if c<>'real_agent' and exists(select 1 from jsonb_array_elements(n.grants) x where x->>'scope'='plugins' and x->'actions'<>'["read"]'::jsonb) then
  raise exception 'Only the real_agent template changes the plugins scope; the % template only reads it',c using errcode='22023'; end if;
 -- The setup and access records in Administration are read by the client's administrators and Real Agent alone.
 if exists(select 1 from jsonb_array_elements(n.grants) x where x->>'scope'='administration' and (c<>'real_agent' or x->'actions'<>'["read"]'::jsonb)) then
  raise exception 'Only administrators and Real Agent read the administration scope; the real_agent template reads it, and no template changes it' using errcode='22023'; end if;
 if n.description is null or length(n.description)>4000 then raise exception 'A template''s description is 1 to 4000 characters' using errcode='22023'; end if;
 if n.authority_class not in ('restricted','administrator') then raise exception 'A template''s authority class is restricted or administrator' using errcode='22023'; end if;
 if n.authority_class='administrator' and jsonb_array_length(n.grants)>0 then
  raise exception 'The administrator authority class reads and changes every scope, and its template has no grants' using errcode='22023'; end if;
 new_value:=jsonb_build_object('description',n.description,'authority_class',n.authority_class,'grants',n.grants);
 if new_value=old_value then raise exception 'The % access template already has that description, authority class and grants',c using errcode='22023'; end if;
 insert into okb.access_template(code,description,authority_class,grants,changed_at,changed_by_actor_id)
 values(c,n.description,n.authority_class,n.grants,clock_timestamp(),a.actor_id)
 on conflict (code) do update set description=excluded.description,authority_class=excluded.authority_class,grants=excluded.grants,
  changed_at=excluded.changed_at,changed_by_actor_id=excluded.changed_by_actor_id;
 insert into okb.access_template_change(code,old_value,new_value,changed_by_actor_id,reason) values(c,old_value,new_value,a.actor_id,btrim(p_reason));
 return jsonb_build_object('code',c,'old',old_value,'new',new_value,'changed_at',clock_timestamp(),'changed_by',a.display_name,'reason',btrim(p_reason));
end $$;
reset role;

-- The real_agent template's read grant in Administration, unless an administrator has changed the template.
update okb.access_template
set grants=grants||'[{"scope":"administration","record_kinds":["activity","decision","model","evidence"],"actions":["read"],"own_records":false}]'::jsonb,
 description='Real Agent''s staff: interviews, designs and supports in General, Routines and Reference, publishes the client''s plugins, the one template that changes the plugins scope''s files, and reads the setup and access records in Administration.'
where code='real_agent' and changed_by_actor_id is null
 and not exists(select 1 from jsonb_array_elements(grants) x where x->>'scope'='administration');

-- The Administration scope, made in an enabled administrator's name, with its private bucket.
insert into okb.scope(code, display_name, description, created_by)
select 'administration', 'Administration',
 'The setup record and each access record: who set the project up, each actor made, each grant given and why. Read only by the firm''s administrators and Real Agent.',
 a.actor_id
from okb.actor a
where a.actor_kind='human' and a.authority_class='administrator' and a.enabled
 and not exists(select 1 from okb.scope where code='administration')
order by a.actor_id
limit 1;

insert into okb_private.schema_upgrade(id) values ('0002-administration-and-plugin-scopes') on conflict (id) do nothing;
