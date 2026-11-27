-- 0014-shared-logins
-- base: 59e745e
-- OKB keeps the logins a firm's staff share for outside portals: each one's scope, service, web address, username
-- and notes in okb_private.shared_login, and its password and previous password in Vault alone. A person who is an
-- administrator adds, changes and removes a login with okb_save_login and okb_remove_login. A person whose grant in the
-- login's scope holds read, for every record, lists the logins with okb_find_logins, which gives no password, and opens
-- one with okb_open_login, which gives its password and previous password. The audit log gives each add, change,
-- removal and opening, without the password. A scope that holds a login is not deleted. The same text is in setup.sql.
-- Safe to run twice. Run as the postgres login.

-- ===================================================================
-- 8ad. Shared logins, with each password in Vault. Upgrade 0014-shared-logins.
-- ===================================================================
set role okb_owner;
-- Each shared login. The password is the Vault secret secret_id, and the password before the last change
-- previous_secret_id. A service and username are one login, in any case.
create table if not exists okb_private.shared_login (
 login_id uuid primary key default gen_random_uuid(),
 scope_id uuid not null references okb.scope(scope_id),
 service text not null check (btrim(service)<>'' and length(service)<=200),
 web_address text check (web_address ~ '^https?://[^[:space:]]+$' and length(web_address)<=2000),
 username text not null check (btrim(username)<>'' and length(username)<=320),
 notes text check (length(notes)<=2000),
 secret_id uuid not null unique,
 previous_secret_id uuid unique,
 password_changed_at timestamptz not null default clock_timestamp(),
 previous_changed_at timestamptz,
 added_at timestamptz not null default clock_timestamp(),
 added_by uuid not null references okb.actor(actor_id),
 changed_at timestamptz not null default clock_timestamp(),
 changed_by uuid not null references okb.actor(actor_id)
);
create unique index if not exists shared_login_service_username on okb_private.shared_login(lower(btrim(service)),lower(btrim(username)));
create index if not exists shared_login_scope_idx on okb_private.shared_login(scope_id);
create index if not exists shared_login_added_by_idx on okb_private.shared_login(added_by);
create index if not exists shared_login_changed_by_idx on okb_private.shared_login(changed_by);
alter table okb_private.shared_login enable row level security;
revoke all on okb_private.shared_login from public, anon, authenticated;

-- Each add, change, removal and opening of a shared login, for the audit log. It holds no password: fields names each
-- field a change made, password among them.
create table if not exists okb_private.shared_login_event (
 event_id bigint generated always as identity primary key,
 at timestamptz not null default clock_timestamp(),
 actor_id uuid not null references okb.actor(actor_id),
 login_id uuid not null,
 scope_id uuid not null,
 event text not null check (event in ('login_added','login_changed','login_removed','login_opened')),
 service text not null,
 username text not null,
 fields text[] not null default '{}'
);
create index if not exists shared_login_event_at_idx on okb_private.shared_login_event(at);
create index if not exists shared_login_event_actor_idx on okb_private.shared_login_event(actor_id);
alter table okb_private.shared_login_event enable row level security;
revoke all on okb_private.shared_login_event from public, anon, authenticated;
grant select, insert, update, delete on okb_private.shared_login to okb_writer;
grant select on okb_private.shared_login to okb_reader;
grant select, insert on okb_private.shared_login_event to okb_writer;
grant select on okb_private.shared_login_event to okb_reader;
reset role;

-- Vault, as the postgres login, which alone of OKB's logins reaches it. Each function takes only a shared login's
-- secret: a new one, one a login holds, or one no login holds any longer. okb_writer alone runs them.
create or replace function okb_private.login_secret_new(p_password text) returns uuid
language plpgsql volatile security definer set search_path=pg_catalog as $$
begin
 return vault.create_secret(p_password, null, 'A shared login''s password in OKB');
end $$;

create or replace function okb_private.login_secret_read(p_secret_id uuid) returns text
language sql stable security definer set search_path=pg_catalog as $$
 select s.decrypted_secret from vault.decrypted_secrets s
 where s.id=p_secret_id and exists(select 1 from okb_private.shared_login l where l.secret_id=p_secret_id or l.previous_secret_id=p_secret_id)
$$;

create or replace function okb_private.login_secret_drop(p_secret_id uuid) returns void
language sql volatile security definer set search_path=pg_catalog as $$
 delete from vault.secrets s where s.id=p_secret_id and s.description='A shared login''s password in OKB'
  and not exists(select 1 from okb_private.shared_login l where l.secret_id=p_secret_id or l.previous_secret_id=p_secret_id)
$$;
revoke all on function okb_private.login_secret_new(text), okb_private.login_secret_read(uuid), okb_private.login_secret_drop(uuid)
 from public, anon, authenticated, service_role;
grant execute on function okb_private.login_secret_new(text), okb_private.login_secret_read(uuid), okb_private.login_secret_drop(uuid)
 to okb_writer;

-- A shared login as OKB gives it, without its password.
grant create on schema okb_private to okb_reader;
set role okb_reader;
create or replace function okb_private.login_json(l okb_private.shared_login) returns jsonb
language sql stable set search_path=pg_catalog as $$
 select jsonb_build_object('login_id',l.login_id,'scope_id',l.scope_id,'scope_name',okb_private.scope_name(l.scope_id),
  'service',l.service,'web_address',l.web_address,'username',l.username,'notes',l.notes,
  'password_changed_at',l.password_changed_at,'has_previous',l.previous_secret_id is not null,
  'changed_at',l.changed_at,'changed_by_name',okb_private.actor_name(l.changed_by))
$$;

-- Whether the actor opens the logins of a scope: one of the firm's own staff, with a grant there that holds read, for
-- every record of its kinds, not one record or the holder's own. An agent or application actor opens none, and nor does
-- Real Agent's staff: an actor named "<name> (Real Agent)", as setup and okb-invite name them, or one ever given a grant
-- by the real_agent access template.
create or replace function okb_private.opens_logins(p_scope uuid) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select exists(select 1 from (select (okb_private.current_actor()).*) a
  where a.actor_kind='human' and a.display_name !~ '\(Real Agent\)\s*$'
   and not exists(select 1 from okb.authorisation z where z.executor_actor_id=a.actor_id and z.reason='The real_agent access template.'))
  and exists(select 1 from okb_private.read_grants() g
  where g.scope_id=p_scope and not g.own_records and g.record_id is null)
$$;

-- The login named by its id, or by its service where one login the actor opens has it.
create or replace function okb_private.login_named(p_login text) returns okb_private.shared_login
language plpgsql stable security definer set search_path=pg_catalog as $$
declare l okb_private.shared_login; n int;
begin
 if btrim(coalesce(p_login,'')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  select * into l from okb_private.shared_login x where x.login_id=btrim(p_login)::uuid and okb_private.opens_logins(x.scope_id);
  return l;
 end if;
 select count(*) into n from okb_private.shared_login x where lower(btrim(x.service))=lower(btrim(p_login)) and okb_private.opens_logins(x.scope_id);
 if n>1 then raise exception 'More than one shared login has that service. Name it by its login_id, from okb_find_logins' using errcode='22023'; end if;
 select * into l from okb_private.shared_login x where lower(btrim(x.service))=lower(btrim(p_login)) and okb_private.opens_logins(x.scope_id);
 return l;
end $$;
reset role;
revoke all on function okb_private.login_json(okb_private.shared_login), okb_private.opens_logins(uuid),
 okb_private.login_named(text) from public, anon, authenticated;
grant execute on function okb_private.login_json(okb_private.shared_login), okb_private.opens_logins(uuid),
 okb_private.login_named(text) to okb_writer, okb_reader;

-- Who reads which shared logins and their events: the functions that change them, each one, and a reader the logins of
-- the scopes whose logins the actor opens.
drop policy if exists shared_login_writer_all on okb_private.shared_login;
create policy shared_login_writer_all on okb_private.shared_login for all to okb_writer using (true) with check (true);
drop policy if exists shared_login_reader_read on okb_private.shared_login;
create policy shared_login_reader_read on okb_private.shared_login for select to okb_reader using (okb_private.opens_logins(scope_id));
drop policy if exists shared_login_event_writer_all on okb_private.shared_login_event;
create policy shared_login_event_writer_all on okb_private.shared_login_event for all to okb_writer using (true) with check (true);
drop policy if exists shared_login_event_reader_read on okb_private.shared_login_event;
create policy shared_login_event_reader_read on okb_private.shared_login_event for select to okb_reader using (okb_private.opens_logins(scope_id));

-- The logins the actor opens, without passwords, those whose service, username or web address holds p_search alone
-- when it is given.
grant create on schema okb to okb_reader;
set role okb_reader;
create or replace function okb.okb_find_logins(p_search text default null) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare a okb.actor;
begin
 a:=okb_private.read_actor();
 return jsonb_build_object('administrator',a.authority_class='administrator','logins',coalesce((
  select jsonb_agg(okb_private.login_json(l) order by lower(l.service),lower(l.username))
  from okb_private.shared_login l
  where okb_private.opens_logins(l.scope_id)
   and (nullif(btrim(p_search),'') is null or strpos(lower(concat_ws(' ',l.service,l.username,l.web_address)),lower(btrim(p_search)))>0)),'[]'::jsonb));
end $$;
reset role;
revoke create on schema okb from okb_reader;
revoke create on schema okb_private from okb_reader;
revoke all on function okb.okb_find_logins(text) from public, anon;
grant execute on function okb.okb_find_logins(text) to authenticated;

-- The bodies of the functions that change shared logins. A refusal names no value given, so no password reaches the
-- refusal log.
grant create on schema okb_private to okb_writer;
set role okb_writer;
create or replace function okb_private.save_login(p_login uuid, p_scope text, p_service text, p_web_address text,
 p_username text, p_notes text, p_password text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; l okb_private.shared_login; was okb_private.shared_login; sid uuid; s text:=lower(btrim(coalesce(p_scope,'')));
 fields text[]:='{}'; old_secret uuid;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator adds or changes a shared login' using errcode='42501'; end if;
 if p_password is not null and (p_password='' or length(p_password)>256) then
  raise exception 'A password holds 1 to 256 characters' using errcode='22023'; end if;
 if s<>'' then
  if s ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   select scope_id into sid from okb.scope where scope_id=s::uuid and enabled and not is_private;
  else
   select min(scope_id::text)::uuid into sid from okb.scope where (code=s or lower(btrim(display_name))=s) and enabled and not is_private having count(*)=1;
  end if;
  if sid is null then raise exception 'That scope is not one an administrator keeps a shared login in. Name an enabled scope that is not private, by its id, code or name' using errcode='22023'; end if;
 end if;
 if p_login is null then
  -- A new login.
  if sid is null or btrim(coalesce(p_service,''))='' or btrim(coalesce(p_username,''))='' or p_password is null then
   raise exception 'A new shared login needs its scope, service, username and password' using errcode='22023'; end if;
  insert into okb_private.shared_login(scope_id,service,web_address,username,notes,secret_id,added_by,changed_by)
  values(sid,btrim(p_service),nullif(btrim(p_web_address),''),btrim(p_username),nullif(btrim(p_notes),''),
   okb_private.login_secret_new(p_password),a.actor_id,a.actor_id)
  returning * into l;
  insert into okb_private.shared_login_event(actor_id,login_id,scope_id,event,service,username)
  values(a.actor_id,l.login_id,l.scope_id,'login_added',l.service,l.username);
  return jsonb_build_object('saved','added','login',okb_private.login_json(l));
 end if;
 -- A change: each field given replaces the one held, an empty web address or notes clears it, and a new password
 -- moves the one held to the previous password, and deletes the one before it.
 select * into was from okb_private.shared_login where login_id=p_login for update;
 if not found then raise exception 'No shared login has that login_id' using errcode='22023'; end if;
 l:=was;
 if sid is not null then l.scope_id:=sid; end if;
 if p_service is not null then
  if btrim(p_service)='' then raise exception 'A shared login keeps a service' using errcode='22023'; end if;
  l.service:=btrim(p_service); end if;
 if p_username is not null then
  if btrim(p_username)='' then raise exception 'A shared login keeps a username' using errcode='22023'; end if;
  l.username:=btrim(p_username); end if;
 if p_web_address is not null then l.web_address:=nullif(btrim(p_web_address),''); end if;
 if p_notes is not null then l.notes:=nullif(btrim(p_notes),''); end if;
 fields:=array_remove(array[
  case when l.scope_id is distinct from was.scope_id then 'scope' end,
  case when l.service is distinct from was.service then 'service' end,
  case when l.web_address is distinct from was.web_address then 'web_address' end,
  case when l.username is distinct from was.username then 'username' end,
  case when l.notes is distinct from was.notes then 'notes' end,
  case when p_password is not null then 'password' end],null);
 if cardinality(fields)=0 then return jsonb_build_object('saved','unchanged','login',okb_private.login_json(was)); end if;
 if p_password is not null then
  old_secret:=was.previous_secret_id;
  l.previous_secret_id:=was.secret_id; l.previous_changed_at:=was.password_changed_at;
  l.secret_id:=okb_private.login_secret_new(p_password); l.password_changed_at:=clock_timestamp();
 end if;
 l.changed_at:=clock_timestamp(); l.changed_by:=a.actor_id;
 update okb_private.shared_login x set scope_id=l.scope_id,service=l.service,web_address=l.web_address,username=l.username,notes=l.notes,
  secret_id=l.secret_id,previous_secret_id=l.previous_secret_id,password_changed_at=l.password_changed_at,previous_changed_at=l.previous_changed_at,
  changed_at=l.changed_at,changed_by=l.changed_by
 where x.login_id=l.login_id returning * into l;
 if old_secret is not null then perform okb_private.login_secret_drop(old_secret); end if;
 insert into okb_private.shared_login_event(actor_id,login_id,scope_id,event,service,username,fields)
 values(a.actor_id,l.login_id,l.scope_id,'login_changed',l.service,l.username,fields);
 return jsonb_build_object('saved','changed','fields',to_jsonb(fields),'login',okb_private.login_json(l));
end $$;

create or replace function okb_private.remove_login(p_login uuid) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare a okb.actor; l okb_private.shared_login;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator removes a shared login' using errcode='42501'; end if;
 delete from okb_private.shared_login where login_id=p_login returning * into l;
 if not found then raise exception 'No shared login has that login_id' using errcode='22023'; end if;
 perform okb_private.login_secret_drop(l.secret_id);
 if l.previous_secret_id is not null then perform okb_private.login_secret_drop(l.previous_secret_id); end if;
 insert into okb_private.shared_login_event(actor_id,login_id,scope_id,event,service,username)
 values(a.actor_id,l.login_id,l.scope_id,'login_removed',l.service,l.username);
 return jsonb_build_object('removed',true,'login_id',l.login_id,'service',l.service,'username',l.username);
end $$;

create or replace function okb_private.open_login(p_login text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare a okb.actor; l okb_private.shared_login;
begin
 a:=okb_private.current_actor();
 l:=okb_private.login_named(p_login);
 if l.login_id is null then raise exception 'No shared login by that name or id is one you may open' using errcode='42501'; end if;
 insert into okb_private.shared_login_event(actor_id,login_id,scope_id,event,service,username)
 values(a.actor_id,l.login_id,l.scope_id,'login_opened',l.service,l.username);
 return okb_private.login_json(l)||jsonb_build_object('password',okb_private.login_secret_read(l.secret_id),
  'previous_password',case when l.previous_secret_id is not null then okb_private.login_secret_read(l.previous_secret_id) end,
  'previous_changed_at',l.previous_changed_at);
end $$;
reset role;
revoke all on function okb_private.save_login(uuid,text,text,text,text,text,text), okb_private.remove_login(uuid),
 okb_private.open_login(text) from public, anon, authenticated;

-- The functions a person calls. A permission refusal is logged, and given as {"refused": true, "problem": ...}.
-- okb_save_login and okb_open_login are volatile, so the Data API takes them only as a POST, with the password in the
-- body.
grant create on schema okb to okb_writer;
set role okb_writer;
create or replace function okb.okb_save_login(p_login uuid default null, p_scope text default null, p_service text default null,
 p_web_address text default null, p_username text default null, p_notes text default null, p_password text default null) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare m text; c text;
begin
 return okb_private.save_login(p_login,p_scope,p_service,p_web_address,p_username,p_notes,p_password);
exception
 when insufficient_privilege then
  get stacked diagnostics m=message_text, c=pg_exception_context;
  if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
  return okb_private.log_refusal('okb_save_login',m,null,null,null);
 when unique_violation then
  raise exception 'A shared login already has that service and username' using errcode='23505';
 when check_violation then
  raise exception 'A shared login''s service holds up to 200 characters, its username up to 320, its notes up to 2,000, and its web address starts http:// or https://' using errcode='23514';
end $$;

create or replace function okb.okb_remove_login(p_login uuid) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare m text; c text;
begin
 return okb_private.remove_login(p_login);
exception when insufficient_privilege then
 get stacked diagnostics m=message_text, c=pg_exception_context;
 if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
 return okb_private.log_refusal('okb_remove_login',m,null,null,null);
end $$;

create or replace function okb.okb_open_login(p_login text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare m text; c text;
begin
 return okb_private.open_login(p_login);
exception when insufficient_privilege then
 get stacked diagnostics m=message_text, c=pg_exception_context;
 if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
 return okb_private.log_refusal('okb_open_login',m,null,null,null);
end $$;
reset role;
revoke create on schema okb from okb_writer;
revoke create on schema okb_private from okb_writer;
revoke all on function okb.okb_save_login(uuid,text,text,text,text,text,text), okb.okb_remove_login(uuid), okb.okb_open_login(text) from public, anon;
grant execute on function okb.okb_save_login(uuid,text,text,text,text,text,text), okb.okb_remove_login(uuid), okb.okb_open_login(text) to authenticated;

-- A scope that holds a shared login is not deleted: the login is removed, or moved to another scope, first.
-- Otherwise a scope that holds no record is deleted, with its grants and bucket.
create or replace function okb_private.delete_scope(p_scope uuid, p_executor uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare s okb.scope; n bigint; k bigint; g jsonb; logins text;
begin
 select * into s from okb.scope where scope_id=p_scope for update;
 select count(*), count(*) filter (where deleted_at is not null) into n, k from okb.record where scope_id=p_scope;
 if n>0 then
  raise exception 'The scope % holds % records, % of them deleted; a scope is deleted only when it holds none',s.display_name,n,k using errcode='23503';
 end if;
 select string_agg(l.service||' ('||l.username||')',', ' order by lower(l.service),lower(l.username)) into logins
 from okb_private.shared_login l where l.scope_id=p_scope;
 if logins is not null then
  raise exception 'The scope % holds the shared login %; a scope is deleted only when it holds none',s.display_name,logins using errcode='23503';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('authorisation_id',z.authorisation_id,'mode',z.mode,
   'executor',okb_private.actor_name(z.executor_actor_id),'accountable_human',okb_private.actor_name(z.accountable_human_id),
   'allowed_actions',z.allowed_actions,'record_kinds',z.record_kinds,'issued_at',z.issued_at,'revoked_at',z.revoked_at) order by z.issued_at,z.authorisation_id),'[]'::jsonb)
  into g from okb.authorisation z where z.scope_id=p_scope;
 perform set_config('okb.deleting_scope',p_scope::text,true);
 insert into okb.scope_deletion(scope_id,code,display_name,description,grants_removed,deleted_by_actor_id,reason,is_private)
 values (s.scope_id,s.code,s.display_name,s.description,g,p_executor,p_reason,s.is_private);
 delete from okb.authorisation where scope_id=p_scope;
 perform okb_storage.delete_scope_bucket(s.code);
 delete from okb.scope where scope_id=p_scope;
 perform set_config('okb.deleting_scope','',true);
 return jsonb_build_object('scope_id',s.scope_id,'code',s.code,'name',s.display_name,'description',s.description,
  'grants_removed',jsonb_array_length(g),'deleted_at',clock_timestamp(),
  'deleted_by',okb_private.actor_name(p_executor),'reason',p_reason);
end $$;

-- The audit log gives each add, change, removal and opening of a shared login, without its password, to an
-- administrator and to each person who opens the login's scope's logins.
grant create on schema okb to okb_reader;
set role okb_reader;
-- What happened from p_from until p_to, newest first, as far as the caller may read. Each item
-- names its time, event, scope, actor and subject, with the ids that lead to the full entry. A
-- private scope's handing on is scope_handed_on, and an administrator sees no description of a
-- deleted private scope, nor its grants, unless they deleted it. A refused change is change_refused,
-- for the refused actor, an administrator, and a private scope's owner, with the scope only for a
-- reader who can see it. A change to an access template is access_template_changed. A scope's making
-- is scope_created, with the reason it was added. A change of the second factor is second_factor_set,
-- for administrators. Each batch graph-reader sent and closed is graph_batch_sent and graph_batch_saved, for
-- administrators. Each add, change, removal and opening of a shared login is login_added, login_changed,
-- login_removed and login_opened, without its password, for administrators and each person who opens the
-- login's scope's logins.
create or replace function okb.okb_get_audit(p_from timestamptz, p_to timestamptz, p_cursor text default null, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare a okb.actor; c_at bigint; c_key text; result jsonb;
begin
 a:=okb_private.read_actor();
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Limit must be 1 through 100' using errcode='22023'; end if;
 if p_from is null or p_to is null or p_from>=p_to then raise exception 'A period needs a start before its end' using errcode='22023'; end if;
 if p_cursor is not null then
  if p_cursor !~ '^[0-9]+/[a-z]:[0-9a-f-]+$' then raise exception 'Invalid audit cursor' using errcode='22023'; end if;
  c_at:=split_part(p_cursor,'/',1)::bigint; c_key:=split_part(p_cursor,'/',2);
 end if;
 with readable as materialized (select okb_private.readable_records() record_id),
 events as (
  (select * from (
  select v.recorded_at at,'v:'||v.version_id::text k,'record_saved' event,r.scope_id,v.executor_actor_id actor_id,v.title subject,v.change_reason reason,
   jsonb_build_object('record_id',v.record_id,'kind',r.kind,'version_id',v.version_id,'version_number',v.version_number,
    'authorisation_id',v.authorisation_id,'accountable_human_id',v.accountable_human_id,'accountable_human_name',okb_private.actor_name(v.accountable_human_id)) details
  from okb_private.audit_versions(p_from,p_to) v cross join lateral (select v.kind,v.scope_id) r) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select d.deleted_at,'d:'||d.deletion_id::text,'record_deleted',d.scope_id,d.executor_actor_id,d.kind,d.reason,
   jsonb_build_object('record_id',d.record_id,'kind',d.kind,'deletion_id',d.deletion_id,'authorisation_id',d.authorisation_id,
    'accountable_human_id',d.accountable_human_id,'accountable_human_name',okb_private.actor_name(d.accountable_human_id),
    'approved_by_actor_id',z.issued_by_actor_id,'approved_by_name',okb_private.actor_name(z.issued_by_actor_id),'content_sha256',d.content_sha256)
  from okb_private.audit_deletions(p_from,p_to) d left join okb.authorisation z on z.authorisation_id=d.authorisation_id) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select m.moved_at,'m:'||m.move_id::text,'record_moved',m.to_scope_id,m.executor_actor_id,
   coalesce(case when m.record_id in (select x.record_id from readable x) then
    (select v.title from okb.record_version v where v.record_id=m.record_id order by v.change_no desc limit 1) end,m.kind),m.reason,
   jsonb_build_object('record_id',m.record_id,'kind',m.kind,'move_id',m.move_id,'request_id',m.request_id,
    'from_scope_id',m.from_scope_id,'from_scope_name',okb_private.scope_name(m.from_scope_id),
    'to_scope_id',m.to_scope_id,'to_scope_name',okb_private.scope_name(m.to_scope_id))
   ||case when a.authority_class='administrator' then jsonb_build_object('losing_access',m.losing_access,'gaining_access',m.gaining_access) else '{}'::jsonb end
  from okb_private.audit_moves(p_from,p_to) m) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select c.at,'c:'||lpad(c.event_id::text,19,'0'),case c.field when 'owner_actor_id' then 'scope_handed_on'
    when 'is_private' then case when c.new_value='true' then 'sessions_made_private' else 'sessions_made_ordinary' end else 'scope_renamed' end,c.scope_id,c.changed_by_actor_id,
   case c.field when 'owner_actor_id' then okb_private.actor_name(c.new_value::uuid) when 'is_private' then okb_private.scope_name(c.scope_id) else c.new_value end,c.reason,
   jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value)
   ||case when c.field='owner_actor_id' then jsonb_build_object('old_owner_name',okb_private.actor_name(c.old_value::uuid),
    'new_owner_name',okb_private.actor_name(c.new_value::uuid)) else '{}'::jsonb end
  from okb.scope_change c where c.at>=p_from and c.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select s.created_at,'o:'||s.scope_id::text,'scope_created',s.scope_id,s.created_by,s.display_name,coalesce(s.created_reason,'Made at setup'),
   jsonb_build_object('code',s.code,'description',s.description,'is_private',s.is_private,'owner_name',okb_private.actor_name(s.owner_actor_id))
  from okb.scope s where s.created_at>=p_from and s.created_at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select x.at,'x:'||lpad(x.event_id::text,19,'0'),'scope_deleted',null::uuid,x.deleted_by_actor_id,x.display_name,x.reason,
   jsonb_build_object('deleted_scope_id',x.scope_id,'code',x.code,'is_private',x.is_private,
    'description',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.description end,
    'grants_removed',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.grants_removed end)
  from okb.scope_deletion x where x.at>=p_from and x.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select z.issued_at,'g:'||z.authorisation_id::text,case when z.mode='explicit_approval' then 'approval_given' else 'grant_issued' end,z.scope_id,z.issued_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,
    'record_kinds',z.record_kinds,'record_id',z.record_id,'own_records',z.own_records,'expires_at',z.expires_at)
  from okb.authorisation z where z.issued_at>=p_from and z.issued_at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select z.revoked_at,'r:'||z.authorisation_id::text,'grant_revoked',z.scope_id,z.revoked_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.revocation_reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,'record_kinds',z.record_kinds)
  from okb.authorisation z where z.revoked_at>=p_from and z.revoked_at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select c.changed_at,'a:'||c.change_id::text,case when c.old_value is null then 'actor_created' else 'actor_changed' end,null::uuid,c.changed_by_actor_id,
   okb_private.actor_name(c.actor_id),null::text,
   jsonb_build_object('changed_actor_id',c.actor_id)||case when c.old_value is null then '{}'::jsonb
    else jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value) end
  from okb.actor_change c where c.changed_at>=p_from and c.changed_at<p_to and (c.old_value is not null or c.field='actor_id')) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select f.at,'f:'||lpad(f.event_id::text,19,'0'),'file_'||f.event,f.scope_id,f.actor_id,f.name,null::text,
   jsonb_build_object('object_id',f.object_id,'previous_name',f.previous_name,'attributed_by',f.attributed_by,'login',f.login)
  from okb.file_event f where f.at>=p_from and f.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select s.at,'s:'||lpad(s.event_id::text,19,'0'),s.event,null::uuid,s.actor_id,okb_private.actor_name(s.actor_id),null::text,
   jsonb_build_object('session_id',s.session_id,'auth_user_id',s.auth_user_id,'user_agent',s.user_agent,'ip',s.ip)
  from okb.sign_in_event s where s.at>=p_from and s.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select n.at,'n:'||lpad(n.event_id::text,19,'0'),'change_refused',
   case when a.authority_class='administrator' or okb_private.can_see_scope(n.scope_id) or okb_private.scope_owner(n.scope_id)=a.actor_id then n.scope_id end,
   n.actor_id,n.problem,null::text,
   jsonb_build_object('function',n.function_name,'kind',n.kind,'record_id',n.record_id,'problem',n.problem,'auth_user_id',n.auth_user_id)
  from okb.refusal_event n where n.at>=p_from and n.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select t.at,'t:'||lpad(t.event_id::text,19,'0'),'access_template_changed',null::uuid,t.changed_by_actor_id,t.code,t.reason,
   jsonb_build_object('code',t.code,'old_grants',t.old_value->'grants','new_grants',t.new_value->'grants',
    'old_description',t.old_value->>'description','new_description',t.new_value->>'description',
    'old_authority_class',t.old_value->>'authority_class','new_authority_class',t.new_value->>'authority_class')
  from okb.access_template_change t where t.at>=p_from and t.at<p_to) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select q2.at,'h:'||lpad(q2.event_id::text,19,'0'),'second_factor_set',null::uuid,q2.changed_by_actor_id,q2.new_value,q2.reason,
   jsonb_build_object('old_value',q2.old_value,'new_value',q2.new_value)
  from okb.sign_in_setting_change q2 where q2.at>=p_from and q2.at<p_to and a.authority_class='administrator') b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select g.at,g.k,g.event,null::uuid,g.actor_id,g.subject,null::text,g.details
  from okb_private.graph_batch_events(p_from,p_to) g where a.authority_class='administrator') b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)
  union all
  (select * from (
  select sl.at,'i:'||lpad(sl.event_id::text,19,'0'),sl.event,sl.scope_id,sl.actor_id,sl.service,null::text,
   jsonb_build_object('login_id',sl.login_id,'service',sl.service,'username',sl.username,'fields',to_jsonb(sl.fields))
  from okb_private.shared_login_event sl where sl.at>=p_from and sl.at<p_to
   and (a.authority_class='administrator' or okb_private.opens_logins(sl.scope_id))) b(at,k,event,scope_id,actor_id,subject,reason,details)
  where p_cursor is null or ((extract(epoch from b.at)*1000000)::bigint,b.k)<(c_at,c_key) order by b.at desc,b.k desc limit p_limit)),
 keyed as (select e.*,(extract(epoch from e.at)*1000000)::bigint micros from events e),
 page as (select * from keyed where p_cursor is null or (micros,k)<(c_at,c_key) order by micros desc,k desc limit p_limit)
 select jsonb_build_object(
  'items',coalesce(jsonb_agg(jsonb_build_object('at',p.at,'event',p.event,'scope_id',p.scope_id,'scope_name',okb_private.scope_name(p.scope_id),
    'actor_id',p.actor_id,'actor_name',okb_private.actor_name(p.actor_id),'subject',p.subject,'reason',p.reason)||p.details order by p.micros desc,p.k desc),'[]'::jsonb),
  'next_cursor',case when count(*)=p_limit then (array_agg(p.micros::text||'/'||p.k order by p.micros,p.k))[1] end) into result
 from page p;
 return result;
end $$;
reset role;
revoke create on schema okb from okb_reader;
revoke all on function okb.okb_get_audit(timestamptz,timestamptz,text,integer) from public, anon;
grant execute on function okb.okb_get_audit(timestamptz,timestamptz,text,integer) to authenticated;
notify pgrst, 'reload schema';

insert into okb_private.schema_upgrade(id) values ('0014-shared-logins') on conflict (id) do nothing;
