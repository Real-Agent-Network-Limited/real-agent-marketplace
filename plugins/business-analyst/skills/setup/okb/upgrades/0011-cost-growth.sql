-- 0011-cost-growth
-- base: new
-- OKB's reads cost in step with their data. The audit log checks the caller's read access once, as a set, and takes
-- one page from each kind of event before the merge. Finding the unowned activities reads each owner's grants once.
-- The task functions read a scope's activities in one query. A move's preview reads each actor's grants once. Who may
-- read what is unchanged. The same text is in setup.sql. Safe to run twice. Run as the postgres login.

-- ===================================================================
-- 8ab. Reads cost in step with their data. Upgrade 0011-cost-growth.
-- ===================================================================
-- The audit log reads the caller's readable records once, as a set, for the moves, in place of a check of the
-- caller's grants for each row. It reads the moves and deletions with the caller's grants read once. Each kind of
-- event applies the cursor and takes one page before the merge.
-- The moves and deletions in a period the caller reads, as the reader's row rules give them, from the caller's grants
-- read once.
grant create on schema okb_private to okb_identity;
set role okb_identity;
create or replace function okb_private.audit_moves(p_from timestamptz, p_to timestamptz) returns setof okb.record_move
language sql stable security definer set search_path=pg_catalog as $$
 with g as materialized (select * from okb_private.read_grants())
 select m.* from okb.record_move m where m.moved_at>=p_from and m.moved_at<p_to
  and exists(select 1 from g where g.scope_id in (m.from_scope_id,m.to_scope_id) and (g.record_kinds is null or m.kind=any(g.record_kinds))
   and (g.record_id is null or g.record_id=m.record_id) and (not g.own_records or okb_private.is_own_record(g.actor_id,m.record_id)))
$$;
create or replace function okb_private.audit_deletions(p_from timestamptz, p_to timestamptz) returns setof okb.record_deletion
language sql stable security definer set search_path=pg_catalog as $$
 select d.* from okb.record_deletion d where d.deleted_at>=p_from and d.deleted_at<p_to
  and d.record_id in (select okb_private.readable_records())
$$;
reset role;
revoke create on schema okb_private from okb_identity;
revoke all on function okb_private.audit_moves(timestamptz,timestamptz), okb_private.audit_deletions(timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function okb_private.audit_moves(timestamptz,timestamptz), okb_private.audit_deletions(timestamptz,timestamptz) to okb_reader;
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
-- administrators.
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
notify pgrst, 'reload schema';
-- Finding the unowned activities reads each owner's grants in the scope once, as a set, in place of
-- owner_ok for each activity.
grant create on schema okb_private to okb_identity;
set role okb_identity;
-- The read grants in a scope of each of the people named, who are enabled human actors.
create or replace function okb_private.owner_grants(p_scope uuid, p_owners uuid[])
returns table(owner_id uuid, record_kinds text[], record_id uuid, own_records boolean)
language sql stable security definer set search_path=pg_catalog as $$
 select x.actor_id,g.record_kinds,g.record_id,g.own_records
 from okb.actor x cross join lateral okb_private.read_grants(x.actor_id) g
 where x.actor_id=any(p_owners) and x.actor_kind='human' and x.enabled and g.scope_id=p_scope
$$;
reset role;
revoke create on schema okb_private from okb_identity;
revoke all on function okb_private.owner_grants(uuid,uuid[]) from public, anon, authenticated;
grant execute on function okb_private.owner_grants(uuid,uuid[]) to okb_reader;

grant create on schema okb to okb_reader;
set role okb_reader;
-- The activities in a scope the caller may read whose latest version has no owner, or an owner who
-- is not an enabled person who can read activities in the scope. An actor who cannot read the
-- scope gets none.
create or replace function okb.okb_find_unowned(p_scope_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
begin
 perform okb_private.read_actor();
 if p_scope_id is null or not okb_private.can_read_scope(p_scope_id) then return jsonb_build_object('items','[]'::jsonb); end if;
 return jsonb_build_object('items',coalesce((
  with l as materialized (select o.*,case when coalesce(o.payload->>'owner_actor_id','') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     then (o.payload->>'owner_actor_id')::uuid end owner_id
    from (select distinct on(v.record_id) v.* from okb.record_version v join okb.record r using(record_id)
     where r.kind='activity' and r.scope_id=p_scope_id and r.deleted_at is null and r.record_id in (select okb_private.readable_records(p_scope_id,'activity',null,null,null))
     order by v.record_id,v.change_no desc) o),
  g as materialized (select * from okb_private.owner_grants(p_scope_id,array(select distinct l.owner_id from l where l.owner_id is not null)))
  select jsonb_agg(jsonb_build_object('record_id',l.record_id,'index',l.payload->>'index','title',l.title,
   'activity_kind',l.payload->>'activity_kind','owner_actor_id',l.payload->>'owner_actor_id','owner_label',l.payload->>'owner_label')
   order by l.payload->>'index' nulls last,l.title,l.record_id)
  from l
  where not exists(select 1 from g where g.owner_id=l.owner_id and (g.record_kinds is null or 'activity'=any(g.record_kinds))
   and (g.record_id is null or g.record_id=l.record_id) and (not g.own_records or okb_private.is_own_record(g.owner_id,l.record_id)))),'[]'::jsonb));
end $$;
reset role;
revoke create on schema okb from okb_reader;

-- The task functions read a scope's activities in one query, in place of paging through them 100 at a time,
-- each page reading the scope's whole history again.
grant create on schema okb_private to okb_identity;
set role okb_identity;
-- The progress of the activities the caller reads, as okb_get_progress gives it: one page, or with p_all every activity
-- after the cursor, with no next cursor.
create or replace function okb_private.progress_of(p_cutoff bigint, p_observed_at timestamptz, p_cursor uuid, p_limit integer, p_scope_id uuid, p_all boolean)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare rr uuid[]; m bigint; c bigint; obs timestamptz:=coalesce(p_observed_at,clock_timestamp()); latest_time timestamptz; result jsonb;
begin
 perform okb_private.read_actor();
 rr:=array(select okb_private.readable_records());
 select coalesce(max(v.change_no),0) into m from okb.record_version v where v.record_id in (select unnest(rr));
 if p_cutoff is not null and (p_cutoff<0 or p_cutoff>m) then raise exception 'Cutoff outside accessible history' using errcode='22023'; end if;
 c:=coalesce(p_cutoff,m);
 if (not p_all and (p_limit is null or p_limit not between 1 and 100)) or not isfinite(obs) or obs>clock_timestamp() then raise exception 'Invalid progress page or observation time' using errcode='22023'; end if;
 select max(v.recorded_at) into latest_time from okb.record_version v join okb.record r using(record_id) where v.change_no<=c and (p_scope_id is null or r.scope_id=p_scope_id) and r.record_id in (select unnest(rr));
 if obs<latest_time then raise exception 'Observation time precedes selected content' using errcode='22023'; end if;
 with hist as (
  select v.*,r.scope_id,okb_private.activity_state(v.payload->>'state') state,
   lag(okb_private.activity_state(v.payload->>'state')) over(partition by v.record_id order by v.change_no) prior_state
  from okb.record_version v join okb.record r using(record_id) where r.kind='activity' and r.deleted_at is null and r.record_id in (select unnest(rr)) and v.change_no<=c and (p_scope_id is null or r.scope_id=p_scope_id)
 ), latest as (select distinct on(record_id) * from hist order by record_id,change_no desc),
 times as (select record_id,min(recorded_at) first_saved_at,min(recorded_at) filter(where state='in_progress' and prior_state is distinct from 'in_progress') started_at,
  max(recorded_at) filter(where state='completed' and prior_state is distinct from 'completed') finished_at from hist group by record_id),
 page as (select l.*,t.first_saved_at,t.started_at,case when l.state='completed' then t.finished_at else null end actual_finish
  from latest l join times t using(record_id) where p_cursor is null or l.record_id>p_cursor order by l.record_id limit case when p_all then null else p_limit end),
 items as (select q.record_id,to_jsonb(q)||jsonb_build_object(
  'assignee_name',okb_private.actor_name((q.payload->>'assignee_actor_id')::uuid),
  'creator_actor_id',case when q.payload->>'activity_kind'='plan' then (select okb_private.actor_person(o.created_by) from okb.record o where o.record_id=q.record_id) end,
  'creator_name',case when q.payload->>'activity_kind'='plan' then (select okb_private.actor_name(okb_private.actor_person(o.created_by)) from okb.record o where o.record_id=q.record_id) end,
  'baseline_finish_variance_seconds',extract(epoch from (q.actual_finish-(q.payload->>'baseline_finish_at')::timestamptz)),
  'forecast_finish_variance_seconds',extract(epoch from (q.actual_finish-(q.payload->>'forecast_finish_at')::timestamptz)),
  'baseline_overdue_seconds',case when q.payload->>'state' not in ('completed','cancelled') and q.payload->>'baseline_finish_at' is not null then greatest(0,extract(epoch from(obs-(q.payload->>'baseline_finish_at')::timestamptz))) else null end,
  'forecast_overdue_seconds',case when q.payload->>'state' not in ('completed','cancelled') and q.payload->>'forecast_finish_at' is not null then greatest(0,extract(epoch from(obs-(q.payload->>'forecast_finish_at')::timestamptz))) else null end,
  'overdue_seconds',case when q.payload->>'state' not in ('completed','cancelled') and coalesce(q.payload->>'forecast_finish_at',q.payload->>'baseline_finish_at') is not null then greatest(0,extract(epoch from(obs-coalesce(q.payload->>'forecast_finish_at',q.payload->>'baseline_finish_at')::timestamptz))) else null end,
  'dependencies',coalesce((select jsonb_agg(jsonb_build_object('record_id',d.record_id,'referenced_version_id',vl.target_version_id,'current_version_id',d.version_id,'state',d.state,'unfinished',d.state<>'completed') order by d.record_id)
   from okb.version_link vl join okb.record_version referenced on referenced.version_id=vl.target_version_id
   join latest d on d.record_id=referenced.record_id where vl.source_version_id=q.version_id and vl.relation='depends_on'),'[]'::jsonb),
  'parent',(select jsonb_build_object('record_id',referenced.record_id,'referenced_version_id',vl.target_version_id)
   from okb.version_link vl join okb.record_version referenced on referenced.version_id=vl.target_version_id
   join latest pl on pl.record_id=referenced.record_id where vl.source_version_id=q.version_id and vl.relation='parent'),
  -- The activity's links to evidence, and the evidence linked to a version of the activity that
  -- differs from this one only in its state.
  'evidence',coalesce((select jsonb_agg(e.item order by e.record_id,e.referenced_version_id) from (
   select referenced.record_id,vl.target_version_id referenced_version_id,jsonb_build_object('record_id',referenced.record_id,'referenced_version_id',vl.target_version_id,
    'current_version_id',(select cv.version_id from okb.record_version cv where cv.record_id=referenced.record_id and cv.change_no<=c order by cv.change_no desc limit 1),
    'title',referenced.title,'standing',referenced.payload->>'standing','deleted',er.deleted_at is not null) item
   from okb.version_link vl join okb.record_version referenced on referenced.version_id=vl.target_version_id
   join okb.record er on er.record_id=referenced.record_id where vl.source_version_id=q.version_id and vl.relation='supports' and er.kind='evidence' and er.record_id in (select unnest(rr))
   union all
   select ev.record_id,ev.version_id,jsonb_build_object('record_id',ev.record_id,'referenced_version_id',ev.version_id,'current_version_id',ev.version_id,
    'title',ev.title,'standing',ev.payload->>'standing','deleted',false)
   from okb_private.evidence_through_state(q.record_id,q.title,q.payload,c) t join okb.record_version ev on ev.version_id=t.version_id
   where t.record_id in (select unnest(rr)) and not exists(select 1 from okb.version_link ol join okb.record_version ot on ot.version_id=ol.target_version_id
    where ol.source_version_id=q.version_id and ol.relation='supports' and ot.record_id=t.record_id)) e),'[]'::jsonb)) item from page q),
 counts as (select state,count(*) n from latest group by state)
 select jsonb_build_object('cutoff',c,'observed_at',obs,'counts',
  '{"pending":0,"in_progress":0,"paused":0,"completed":0,"cancelled":0}'::jsonb||coalesce((select jsonb_object_agg(state,n) from counts),'{}'::jsonb),
  'items',coalesce((select jsonb_agg(item order by record_id) from items),'[]'::jsonb),
  'next_cursor',case when not p_all and (select count(*) from page)=p_limit then (select record_id from page order by record_id desc limit 1) end) into result;
 return result;
end $$;
create or replace function okb_private.read_progress(p_cutoff bigint, p_observed_at timestamptz, p_cursor uuid, p_limit integer, p_scope_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog as $$
 select okb_private.progress_of(p_cutoff,p_observed_at,p_cursor,p_limit,p_scope_id,false)
$$;
reset role;
revoke create on schema okb_private from okb_identity;
revoke all on function okb_private.progress_of(bigint,timestamptz,uuid,integer,uuid,boolean) from public, anon, authenticated;
grant execute on function okb_private.progress_of(bigint,timestamptz,uuid,integer,uuid,boolean) to okb_owner, okb_reader;

-- The activities in a scope, as okb_get_progress gives them, read in one query.
set role okb_owner;
create or replace function okb_task.activities(p_scope_id uuid) returns jsonb
language sql stable security definer set search_path=pg_catalog as $$
 select okb_private.progress_of(null,null,null,null,p_scope_id,true)->'items'
$$;
reset role;
revoke all on function okb_task.activities(uuid) from public, anon;
grant execute on function okb_task.activities(uuid) to authenticated;

-- A move's preview reads each enabled actor's read grants once, as a set, in place of two grant checks for each
-- actor and record.
grant create on schema okb_private to okb_identity;
set role okb_identity;
-- What a move of p_records to p_to would do: the records, their scope, each link between one of
-- them and a record outside them, each record the move refuses and why, and each enabled actor
-- who would lose or gain read access to them, from each actor's read grants, read once. Every list is sorted, so two answers compare equal.
create or replace function okb_private.move_facts(p_records uuid[], p_to uuid) returns jsonb
language sql stable security definer set search_path=pg_catalog as $$
 with recs as (
  select r.record_id,r.kind,r.scope_id,r.deleted_at,
   (select v.title from okb.record_version v where v.record_id=r.record_id order by v.change_no desc limit 1) title
  from okb.record r where r.record_id=any(p_records)),
 mine as (select v.version_id,v.record_id from okb.record_version v where v.record_id in (select record_id from recs)),
 outside as (
  select distinct m.record_id,ov.record_id linked_record_id,l.relation,
   case when l.source_version_id=m.version_id then 'links_to' else 'linked_from' end direction
  from mine m join okb.version_link l on m.version_id in (l.source_version_id,l.target_version_id)
  join okb.record_version ov on ov.version_id=case when l.source_version_id=m.version_id then l.target_version_id else l.source_version_id end
  where ov.record_id not in (select record_id from recs)),
 refused as (
  select record_id,'The record was deleted' reason from recs where deleted_at is not null
  union all
  select record_id,'The record holds a glossary term or a record kind of the data dictionary' from recs
   where exists(select 1 from okb.glossary_term g where g.record_id=recs.record_id) or exists(select 1 from okb.dictionary_table d where d.record_id=recs.record_id)
  union all
  select record_id,'A live grant or an unused approval names the record: '||string_agg(z.authorisation_id::text,', ' order by z.authorisation_id)
  from recs join okb.authorisation z using(record_id)
  where z.revoked_at is null and (z.expires_at is null or z.expires_at>clock_timestamp())
   and z.consumed_version_id is null and z.consumed_deletion_id is null
  group by record_id),
 grants as materialized (
  select a.actor_id,a.display_name,g.scope_id,g.record_kinds,g.record_id,g.own_records
  from okb.actor a cross join lateral okb_private.read_grants(a.actor_id) g
  where a.enabled and (g.scope_id=p_to or g.scope_id in (select scope_id from recs))),
 access as (
  select a.actor_id,a.display_name,r.record_id,
   exists(select 1 from grants g where g.actor_id=a.actor_id and g.scope_id=r.scope_id and (g.record_kinds is null or r.kind=any(g.record_kinds))
    and (g.record_id is null or g.record_id=r.record_id) and (not g.own_records or okb_private.is_own_record(a.actor_id,r.record_id))) before,
   exists(select 1 from grants g where g.actor_id=a.actor_id and g.scope_id=p_to and (g.record_kinds is null or r.kind=any(g.record_kinds))
    and (g.record_id is null or g.record_id=r.record_id) and (not g.own_records or okb_private.is_own_record(a.actor_id,r.record_id))) after
  from (select distinct actor_id,display_name from grants) a cross join recs r)
 select jsonb_build_object(
  'from_scope_id',case when (select count(distinct scope_id) from recs)=1 then (select min(scope_id::text) from recs)::uuid end,
  'from_scope_name',case when (select count(distinct scope_id) from recs)=1 then okb_private.scope_name((select min(scope_id::text) from recs)::uuid) end,
  'to_scope_name',okb_private.scope_name(p_to),
  'records',coalesce((select jsonb_agg(jsonb_build_object('record_id',record_id,'kind',kind,'title',title) order by record_id) from recs),'[]'::jsonb),
  'outside_links',coalesce((select jsonb_agg(jsonb_build_object('record_id',o.record_id,'linked_record_id',o.linked_record_id,
     'linked_title',(select v.title from okb.record_version v where v.record_id=o.linked_record_id order by v.change_no desc limit 1),
     'linked_scope_name',(select okb_private.scope_name(x.scope_id) from okb.record x where x.record_id=o.linked_record_id),
     'relation',o.relation,'direction',o.direction) order by o.record_id,o.linked_record_id,o.relation,o.direction) from outside o),'[]'::jsonb),
  'refused',coalesce((select jsonb_agg(jsonb_build_object('record_id',record_id,'reason',reason) order by record_id,reason) from refused),'[]'::jsonb),
  'losing_access',coalesce((select jsonb_agg(x order by x->>'actor_id') from (select jsonb_build_object('actor_id',actor_id,'name',display_name,
     'record_ids',jsonb_agg(record_id order by record_id)) x from access where before and not after group by actor_id,display_name) q),'[]'::jsonb),
  'gaining_access',coalesce((select jsonb_agg(x order by x->>'actor_id') from (select jsonb_build_object('actor_id',actor_id,'name',display_name,
     'record_ids',jsonb_agg(record_id order by record_id)) x from access where after and not before group by actor_id,display_name) q),'[]'::jsonb))
$$;
reset role;
revoke create on schema okb_private from okb_identity;


insert into okb_private.schema_upgrade(id) values ('0011-cost-growth') on conflict (id) do nothing;
