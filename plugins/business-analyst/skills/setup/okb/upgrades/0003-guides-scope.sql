-- 0003-guides-scope
-- base: 98a8ac4
-- Plan 1's decision 2.30 for a project built before it. The Guides scope, guides, keeps Real Agent's guides,
-- docs/support/, which scripts/load-guides.mjs loads there as Real Agent's actor. Every actor reads it: the basic
-- and real_agent templates gain a grant there, unless an administrator has changed the template, and an
-- administrator reads it with their authority. Its files change only with an actor's own grant there, as the
-- plugins scope's do, and only the real_agent template creates, edits and deletes there. okb_delete_scope does
-- not delete it, nor the Administration scope, as the database admin's text already said. File search indexes it, as file-search-scopes.sql's trigger does each new scope. The scope is
-- made in an enabled administrator's name; a project with no administrator yet gets it at bootstrap.sql's step 2.
-- Each person made from basic or real_agent gets the grant when the template is applied to them again.
-- Safe to run twice. Run as the postgres login.

-- The plugins scope's storage rules, for the guides scope too.
drop policy if exists "OKB: plugins files only with a plugins grant (upload)" on storage.objects;
drop policy if exists "OKB: plugins files only with a plugins grant (replace)" on storage.objects;
drop policy if exists "OKB: plugins files only with a plugins grant (delete)" on storage.objects;
create policy "OKB: plugins files only with a plugins grant (upload)" on storage.objects as restrictive
 for insert to authenticated with check ((bucket_id not in ('plugins','guides') and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('create')));
create policy "OKB: plugins files only with a plugins grant (replace)" on storage.objects as restrictive
 for update to authenticated using ((bucket_id not in ('plugins','guides') and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('edit')))
 with check ((bucket_id not in ('plugins','guides') and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('edit')));
create policy "OKB: plugins files only with a plugins grant (delete)" on storage.objects as restrictive
 for delete to authenticated using ((bucket_id not in ('plugins','guides') and not starts_with(bucket_id,'plugins_')) or bucket_id in (select okb_storage.granted_buckets('delete')));

-- okb_delete_scope keeps the guides and administration scopes, as it keeps OKB's other setup scopes.
set role okb_owner;
grant create on schema okb_private to okb_writer;
reset role;
set role okb_writer;
create or replace function okb_private.delete_scope(p_scope text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; sc okb.scope;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or (a.authority_class<>'administrator' and not exists(select 1 from okb_private.granting_scopes())) then
  raise exception 'Only a person who is an administrator deletes a scope' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for the deletion, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 sc:=okb_private.named_scope(p_scope);
 if sc.is_private then
  if a.actor_id<>sc.owner_actor_id then raise exception 'Only the scope''s owner deletes a private scope' using errcode='42501'; end if;
 elsif a.authority_class<>'administrator' then raise exception 'Only a person who is an administrator deletes a scope' using errcode='42501'; end if;
 if sc.code in ('general','routines','reference','plugins','administration','guides') then
  raise exception 'The scope % is part of OKB''s setup and is not deleted',sc.display_name using errcode='42501';
 end if;
 return okb_private.delete_scope(sc.scope_id,a.actor_id,btrim(p_reason));
end $$;
reset role;
set role okb_owner;
revoke create on schema okb_private from okb_writer;
reset role;

-- Only the real_agent template changes the guides scope.
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
 -- Real Agent's guides change only with Real Agent's template; every other template only reads them.
 if c<>'real_agent' and exists(select 1 from jsonb_array_elements(n.grants) x where x->>'scope'='guides' and x->'actions'<>'["read"]'::jsonb) then
  raise exception 'Only the real_agent template changes the guides scope; the % template only reads it',c using errcode='22023'; end if;
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

-- The templates' grants in Guides, unless an administrator has changed the template.
update okb.access_template
set grants=grants||'[{"scope":"guides","record_kinds":["activity","decision","model","evidence"],"actions":["read"],"own_records":false}]'::jsonb,
 description='A member of staff: works in General, writes down routines and proposes terms, and reads the plugins scope and Real Agent''s guides.'
where code='basic' and changed_by_actor_id is null
 and not exists(select 1 from jsonb_array_elements(grants) x where x->>'scope'='guides');
update okb.access_template
set grants=grants||'[{"scope":"guides","record_kinds":["activity","decision","model","evidence"],"actions":["read","create","edit","delete"],"own_records":false}]'::jsonb,
 description='Real Agent''s staff: interviews, designs and supports in General, Routines and Reference, publishes the client''s plugins and Real Agent''s guides, the one template that changes the plugins and guides scopes'' files, and reads the setup and access records in Administration.'
where code='real_agent' and changed_by_actor_id is null
 and not exists(select 1 from jsonb_array_elements(grants) x where x->>'scope'='guides');
update okb.access_template
set description='The client''s administrator: administrator authority, which reads and changes every scope''s records with no grant, and keeps scopes and staff. Reads the plugins and guides scopes'' files and changes none.'
where code='administrator' and changed_by_actor_id is null;

-- The Guides scope, made in an enabled administrator's name, with its private bucket.
insert into okb.scope(code, display_name, description, created_by)
select 'guides', 'Guides',
 'Real Agent''s guides to installing, updating, printing, support and leaving, which everyone reads and only Real Agent changes.',
 a.actor_id
from okb.actor a
where a.actor_kind='human' and a.authority_class='administrator' and a.enabled
 and not exists(select 1 from okb.scope where code='guides')
order by a.actor_id
limit 1;

insert into okb_private.schema_upgrade(id) values ('0003-guides-scope') on conflict (id) do nothing;
