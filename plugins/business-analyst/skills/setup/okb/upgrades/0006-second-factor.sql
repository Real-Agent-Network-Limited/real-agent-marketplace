-- 0006-second-factor
-- base: bb6f1c9
-- redeploy: okb-invite, okb-upgrade, file-search, file-search-purge
-- A second factor at sign-in, for administrators. Adds the setting, off to
-- start, okb_set_second_factor, and the log of its changes. request_auth_uid() gives no caller for an administrator's
-- password-only sign-in once the setting is administrators, so each OKB function, Storage policy and file search
-- policy refuses it. Each hosted function named above passes the sign-in's level. The same text is in setup.sql.
-- Safe to run twice. Run as the postgres login.

-- ===================================================================
-- 8x. A second factor at sign-in, for administrators.
-- ===================================================================
-- One setting: off or administrators. Under administrators, a call signed in with a password alone is refused to each
-- actor whose authority class is administrator: request_auth_uid() gives no caller for it, so each OKB function, Storage
-- policy and file search policy refuses it. Every other actor, Real Agent's included, keeps its password sign-in. The
-- level of a sign-in is the access token's aal claim: aal2 once the sign-in gave a code from an authenticator app.
set role okb_owner;
create table if not exists okb_private.sign_in_setting (
 only_row boolean primary key default true check (only_row),
 second_factor text not null default 'off' check (second_factor in ('off','administrators')),
 changed_at timestamptz not null default clock_timestamp()
);
insert into okb_private.sign_in_setting(second_factor) values('off') on conflict (only_row) do nothing;
revoke all on okb_private.sign_in_setting from public, anon, authenticated;
grant select, update on okb_private.sign_in_setting to okb_writer;

-- Each change of the setting: its old and new value, the reason, the administrator and the time. Append-only.
create table if not exists okb.sign_in_setting_change (
 event_id bigint generated always as identity primary key,
 at timestamptz not null default clock_timestamp(),
 old_value text not null check (old_value in ('off','administrators')),
 new_value text not null check (new_value in ('off','administrators')),
 reason text not null check (length(btrim(reason)) between 1 and 4000),
 changed_by_actor_id uuid not null references okb.actor(actor_id)
);
create index if not exists sign_in_setting_change_time_idx on okb.sign_in_setting_change(at desc);
create index if not exists sign_in_setting_change_actor_idx on okb.sign_in_setting_change(changed_by_actor_id);
alter table okb.sign_in_setting_change enable row level security;
revoke all on okb.sign_in_setting_change from public, anon, authenticated;
grant select on okb.sign_in_setting_change to okb_writer, okb_reader;
grant insert on okb.sign_in_setting_change to okb_writer;
drop policy if exists sign_in_setting_change_internal on okb.sign_in_setting_change;
create policy sign_in_setting_change_internal on okb.sign_in_setting_change for all to okb_writer using (true) with check (true);
drop policy if exists sign_in_setting_change_reader_read on okb.sign_in_setting_change;
create policy sign_in_setting_change_reader_read on okb.sign_in_setting_change for select to okb_reader using (true);

create or replace function okb_private.guard_sign_in_setting_change()
returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 raise exception 'The second factor log is append-only' using errcode='23514';
end $$;
revoke all on function okb_private.guard_sign_in_setting_change() from public, anon, authenticated;
drop trigger if exists sign_in_setting_change_immutable on okb.sign_in_setting_change;
create trigger sign_in_setting_change_immutable before update or delete on okb.sign_in_setting_change
 for each row execute function okb_private.guard_sign_in_setting_change();
drop trigger if exists sign_in_setting_change_no_truncate on okb.sign_in_setting_change;
create trigger sign_in_setting_change_no_truncate before truncate on okb.sign_in_setting_change
 for each statement execute function okb_private.guard_sign_in_setting_change();
reset role;

-- Owned by the postgres login, as request_auth_uid() is. The level of the caller's sign-in: aal2 or aal1.
create or replace function okb_private.request_aal()
returns text language sql stable security definer set search_path=pg_catalog
as $$ select case when auth.jwt()->>'aal'='aal2' then 'aal2' else 'aal1' end $$;

-- True when the setting covers the Auth user and the sign-in's level is not aal2.
create or replace function okb_private.second_factor_missing(p_auth_user_id uuid, p_aal text)
returns boolean language sql stable security definer set search_path=pg_catalog
as $$
 select p_auth_user_id is not null and p_aal is distinct from 'aal2' and exists(
  select 1 from okb_private.sign_in_setting s where s.second_factor='administrators'
   and exists(select 1 from okb.actor a where a.auth_user_id=p_auth_user_id and a.authority_class='administrator'))
$$;

-- The caller's Auth user, or null for a sign-in the setting refuses.
create or replace function okb_private.request_auth_uid()
returns uuid language sql stable security definer set search_path=pg_catalog
as $$ select case when okb_private.second_factor_missing(auth.uid(), okb_private.request_aal()) then null else auth.uid() end $$;

revoke all on function okb_private.request_aal(), okb_private.second_factor_missing(uuid,text), okb_private.request_auth_uid() from public, anon, authenticated;
grant execute on function okb_private.request_aal(), okb_private.request_auth_uid() to okb_owner, okb_identity, okb_writer, okb_reader;

-- Sets the second factor. Only a person who is an administrator sets it, with a reason. Turning it on needs the
-- administrator's own sign-in to carry a code, so an administrator with no authenticator app leaves it off.
grant create on schema okb_private to okb_writer;
set role okb_writer;
create or replace function okb_private.set_second_factor(p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; was text; at_ timestamptz:=clock_timestamp();
begin
 a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator sets the second factor' using errcode='42501';
 end if;
 if p_value is null or p_value not in ('off','administrators') then
  raise exception 'The second factor is off or administrators, as p_value' using errcode='22023';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for the change, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 if p_value<>'off' and okb_private.request_aal()<>'aal2' then
  raise exception 'Sign in with a code from your authenticator app, then set the second factor' using errcode='22023';
 end if;
 select s.second_factor into was from okb_private.sign_in_setting s for update;
 if was=p_value then raise exception 'The second factor is already %',p_value using errcode='22023'; end if;
 update okb_private.sign_in_setting set second_factor=p_value, changed_at=at_;
 insert into okb.sign_in_setting_change(at,old_value,new_value,reason,changed_by_actor_id) values(at_,was,p_value,btrim(p_reason),a.actor_id);
 return jsonb_build_object('second_factor',p_value,'was',was,'changed_at',at_);
end $$;
reset role;
revoke create on schema okb_private from okb_writer;
revoke all on function okb_private.set_second_factor(text,text) from public, anon, authenticated;

grant create on schema okb to okb_writer;
set role okb_writer;
create or replace function okb.okb_set_second_factor(p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare m text; c text;
begin
 return okb_private.set_second_factor(p_value,p_reason);
exception when insufficient_privilege then
 get stacked diagnostics m=message_text, c=pg_exception_context;
 if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
 return okb_private.log_refusal('okb_set_second_factor',m,null,null,null);
end $$;
reset role;
revoke create on schema okb from okb_writer;
revoke all on function okb.okb_set_second_factor(text,text) from public, anon;
grant execute on function okb.okb_set_second_factor(text,text) to authenticated;

-- The audit log, with each change of the second factor, as second_factor_set, to administrators.
grant create on schema okb to okb_reader;
set role okb_reader;
-- What happened from p_from until p_to, newest first, as far as the caller may read. Each item
-- names its time, event, scope, actor and subject, with the ids that lead to the full entry. A
-- private scope's handing on is scope_handed_on, and an administrator sees no description of a
-- deleted private scope, nor its grants, unless they deleted it. A refused change is change_refused,
-- for the refused actor, an administrator, and a private scope's owner, with the scope only for a
-- reader who can see it. A change to an access template is access_template_changed. A scope's making
-- is scope_created, with the reason it was added. A change of the second factor is second_factor_set,
-- for administrators.
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
 with events as (
  select v.recorded_at at,'v:'||v.version_id::text k,'record_saved' event,r.scope_id,v.executor_actor_id actor_id,v.title subject,v.change_reason reason,
   jsonb_build_object('record_id',v.record_id,'kind',r.kind,'version_id',v.version_id,'version_number',v.version_number,
    'authorisation_id',v.authorisation_id,'accountable_human_id',v.accountable_human_id,'accountable_human_name',okb_private.actor_name(v.accountable_human_id)) details
  from okb_private.audit_versions(p_from,p_to) v cross join lateral (select v.kind,v.scope_id) r
  union all
  select d.deleted_at,'d:'||d.deletion_id::text,'record_deleted',d.scope_id,d.executor_actor_id,d.kind,d.reason,
   jsonb_build_object('record_id',d.record_id,'kind',d.kind,'deletion_id',d.deletion_id,'authorisation_id',d.authorisation_id,
    'accountable_human_id',d.accountable_human_id,'accountable_human_name',okb_private.actor_name(d.accountable_human_id),
    'approved_by_actor_id',z.issued_by_actor_id,'approved_by_name',okb_private.actor_name(z.issued_by_actor_id),'content_sha256',d.content_sha256)
  from okb.record_deletion d left join okb.authorisation z on z.authorisation_id=d.authorisation_id
  where d.deleted_at>=p_from and d.deleted_at<p_to
  union all
  select m.moved_at,'m:'||m.move_id::text,'record_moved',m.to_scope_id,m.executor_actor_id,
   coalesce(case when okb_private.can_read_record(m.record_id) then
    (select v.title from okb.record_version v where v.record_id=m.record_id order by v.change_no desc limit 1) end,m.kind),m.reason,
   jsonb_build_object('record_id',m.record_id,'kind',m.kind,'move_id',m.move_id,'request_id',m.request_id,
    'from_scope_id',m.from_scope_id,'from_scope_name',okb_private.scope_name(m.from_scope_id),
    'to_scope_id',m.to_scope_id,'to_scope_name',okb_private.scope_name(m.to_scope_id))
   ||case when a.authority_class='administrator' then jsonb_build_object('losing_access',m.losing_access,'gaining_access',m.gaining_access) else '{}'::jsonb end
  from okb.record_move m where m.moved_at>=p_from and m.moved_at<p_to
  union all
  select c.at,'c:'||lpad(c.event_id::text,19,'0'),case when c.field='owner_actor_id' then 'scope_handed_on' else 'scope_renamed' end,c.scope_id,c.changed_by_actor_id,
   case when c.field='owner_actor_id' then okb_private.actor_name(c.new_value::uuid) else c.new_value end,c.reason,
   jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value)
   ||case when c.field='owner_actor_id' then jsonb_build_object('old_owner_name',okb_private.actor_name(c.old_value::uuid),
    'new_owner_name',okb_private.actor_name(c.new_value::uuid)) else '{}'::jsonb end
  from okb.scope_change c where c.at>=p_from and c.at<p_to
  union all
  select s.created_at,'o:'||s.scope_id::text,'scope_created',s.scope_id,s.created_by,s.display_name,coalesce(s.created_reason,'Made at setup'),
   jsonb_build_object('code',s.code,'description',s.description,'is_private',s.is_private,'owner_name',okb_private.actor_name(s.owner_actor_id))
  from okb.scope s where s.created_at>=p_from and s.created_at<p_to
  union all
  select x.at,'x:'||lpad(x.event_id::text,19,'0'),'scope_deleted',null::uuid,x.deleted_by_actor_id,x.display_name,x.reason,
   jsonb_build_object('deleted_scope_id',x.scope_id,'code',x.code,'is_private',x.is_private,
    'description',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.description end,
    'grants_removed',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.grants_removed end)
  from okb.scope_deletion x where x.at>=p_from and x.at<p_to
  union all
  select z.issued_at,'g:'||z.authorisation_id::text,case when z.mode='explicit_approval' then 'approval_given' else 'grant_issued' end,z.scope_id,z.issued_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,
    'record_kinds',z.record_kinds,'record_id',z.record_id,'own_records',z.own_records,'expires_at',z.expires_at)
  from okb.authorisation z where z.issued_at>=p_from and z.issued_at<p_to
  union all
  select z.revoked_at,'r:'||z.authorisation_id::text,'grant_revoked',z.scope_id,z.revoked_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.revocation_reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,'record_kinds',z.record_kinds)
  from okb.authorisation z where z.revoked_at>=p_from and z.revoked_at<p_to
  union all
  select c.changed_at,'a:'||c.change_id::text,case when c.old_value is null then 'actor_created' else 'actor_changed' end,null::uuid,c.changed_by_actor_id,
   okb_private.actor_name(c.actor_id),null::text,
   jsonb_build_object('changed_actor_id',c.actor_id)||case when c.old_value is null then '{}'::jsonb
    else jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value) end
  from okb.actor_change c where c.changed_at>=p_from and c.changed_at<p_to and (c.old_value is not null or c.field='actor_id')
  union all
  select f.at,'f:'||lpad(f.event_id::text,19,'0'),'file_'||f.event,f.scope_id,f.actor_id,f.name,null::text,
   jsonb_build_object('object_id',f.object_id,'previous_name',f.previous_name,'attributed_by',f.attributed_by,'login',f.login)
  from okb.file_event f where f.at>=p_from and f.at<p_to
  union all
  select s.at,'s:'||lpad(s.event_id::text,19,'0'),s.event,null::uuid,s.actor_id,okb_private.actor_name(s.actor_id),null::text,
   jsonb_build_object('session_id',s.session_id,'auth_user_id',s.auth_user_id,'user_agent',s.user_agent,'ip',s.ip)
  from okb.sign_in_event s where s.at>=p_from and s.at<p_to
  union all
  select n.at,'n:'||lpad(n.event_id::text,19,'0'),'change_refused',
   case when a.authority_class='administrator' or okb_private.can_see_scope(n.scope_id) or okb_private.scope_owner(n.scope_id)=a.actor_id then n.scope_id end,
   n.actor_id,n.problem,null::text,
   jsonb_build_object('function',n.function_name,'kind',n.kind,'record_id',n.record_id,'problem',n.problem,'auth_user_id',n.auth_user_id)
  from okb.refusal_event n where n.at>=p_from and n.at<p_to
  union all
  select t.at,'t:'||lpad(t.event_id::text,19,'0'),'access_template_changed',null::uuid,t.changed_by_actor_id,t.code,t.reason,
   jsonb_build_object('code',t.code,'old_grants',t.old_value->'grants','new_grants',t.new_value->'grants',
    'old_description',t.old_value->>'description','new_description',t.new_value->>'description',
    'old_authority_class',t.old_value->>'authority_class','new_authority_class',t.new_value->>'authority_class')
  from okb.access_template_change t where t.at>=p_from and t.at<p_to
  union all
  select q2.at,'h:'||lpad(q2.event_id::text,19,'0'),'second_factor_set',null::uuid,q2.changed_by_actor_id,q2.new_value,q2.reason,
   jsonb_build_object('old_value',q2.old_value,'new_value',q2.new_value)
  from okb.sign_in_setting_change q2 where q2.at>=p_from and q2.at<p_to and a.authority_class='administrator'),
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
notify pgrst, 'reload schema';

insert into okb_private.schema_upgrade(id) values ('0006-second-factor') on conflict (id) do nothing;
