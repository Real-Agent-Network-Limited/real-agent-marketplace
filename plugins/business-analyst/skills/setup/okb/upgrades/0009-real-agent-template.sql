-- 0009-real-agent-template
-- base: new
-- Real Agent's own access template is real_agent, and Real Agent's own plugin's scope is plugins_real_agent. The template
-- kinetik becomes real_agent, with its grants, and Kinetik becomes Real Agent in the templates' descriptions and in
-- the messages of okb_private.save_access_template and okb.okb_get_file_parts. The same text is in setup.sql. Safe to
-- run twice. Run as the postgres login.

-- ===================================================================
-- 8aa. The real_agent template.
-- ===================================================================
set role okb_owner;
update okb.access_template set code='real_agent'
 where code='kinetik' and not exists(select 1 from okb.access_template where code='real_agent');
update okb.access_template set description=replace(description,'Kinetik','Real Agent') where description like '%Kinetik%';
alter table okb.scope drop constraint if exists scope_code_not_own_plugin;
alter table okb.scope add constraint scope_code_not_own_plugin check (code not in ('plugins_real_agent','plugins_okb','plugins_business_analyst','plugins_project'));

-- Adds a template, or changes one's grants, description or authority class, and logs the change. A
-- null leaves that part as it is. Only a person who is an administrator changes a template, only
-- the real_agent template changes the plugins and guides scopes, and only it names the administration
-- scope, to read it.
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

-- Each part of a file in a scope, from p_from on, with its text and where its graph stands: read, with who saved it;
-- failed, with the reason; in a batch; or waiting. Needs read in the scope. A person reads a part's text and chunk_id
-- here to correct its graph with okb_save_extraction.
create or replace function okb.okb_get_file_parts(p_scope text, p_file text, p_from integer default 0, p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare sc okb.scope;
begin
 perform okb_private.read_actor();
 begin
  sc:=okb_private.named_scope(p_scope);
 exception when insufficient_privilege then sc:=null;
 end;
 if sc.code is null or sc.code not in (select okb_storage.usable_buckets('read')) then
  raise exception 'Scope unavailable: no scope has the id, code or name "%"',p_scope using errcode='42501';
 end if;
 if to_regprocedure('file_search.file_parts(text,text,integer,integer)') is null then
  raise exception 'File search''s graph reader is not set up yet: ask Real Agent to apply file search''s upgrade 0003-graph-reader' using errcode='55000';
 end if;
 return jsonb_build_object('scope',sc.display_name,'code',sc.code)||file_search.file_parts(sc.code,p_file,p_from,p_limit);
end $$;
notify pgrst, 'reload schema';

insert into okb_private.schema_upgrade(id) values ('0009-real-agent-template') on conflict (id) do nothing;
