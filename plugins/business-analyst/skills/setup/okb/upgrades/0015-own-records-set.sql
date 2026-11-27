-- 0015-own-records-set
-- base: 8b4577b
-- Each read finds the actor's own records once, as a set, for a grant limited to them. own_records_of gives every
-- record is_own_record is true for, in one query. readable_records reads it once for each read, in place of a call to
-- is_own_record for each record. is_own_record stays, for the checks of one record. Who may read what is unchanged.
-- The same text is in setup.sql. Safe to run twice. Run as the postgres login.

grant create on schema okb_private to okb_identity;
set role okb_identity;
-- Every record is_own_record(p_actor, record) is true for, found as a set: each record whose creator
-- answers to the same person as the actor.
create or replace function okb_private.own_records_of(p_actor uuid) returns setof uuid
language sql stable security definer set search_path=pg_catalog rows 200 as $$
 select r.record_id from okb.actor x join okb.actor c on c.accountable_human_id=x.accountable_human_id
  join okb.record r on r.created_by=c.actor_id
 where x.actor_id=p_actor
$$;

-- The records the current actor may read, as can_read_record checks each, found as a set. Each
-- argument that is not null narrows them: the scope, the kind, words that all appear in one of the
-- record's titles, in any case, and a version saved from p_from until p_to. A grant limited to the
-- actor's own records reads them from own_records_of, once for each read.
create or replace function okb_private.readable_records(p_scope uuid, p_kind text, p_title text, p_from timestamptz, p_to timestamptz)
returns setof uuid
language sql stable security definer set search_path=pg_catalog as $$
 with g as materialized (select * from okb_private.read_grants()),
 o as materialized (select okb_private.own_records_of(a.actor_id) record_id from (select distinct g.actor_id from g where g.own_records) a),
 w as materialized (select replace(replace(replace(x,'\','\\'),'%','\%'),'_','\_') w from regexp_split_to_table(btrim(coalesce(p_title,'')),'\s+') x where x<>'')
 select r.record_id from okb.record r
 where (p_scope is null or r.scope_id=p_scope) and (p_kind is null or r.kind=p_kind)
  and (not exists(select 1 from w) or exists(select 1 from okb.record_version v where v.record_id=r.record_id
   and not exists(select 1 from w where v.title not ilike '%'||w.w||'%')))
  and (p_from is null or exists(select 1 from okb.record_version v where v.record_id=r.record_id and v.recorded_at>=p_from and v.recorded_at<p_to))
  and exists(select 1 from g where g.scope_id=r.scope_id and (g.record_kinds is null or r.kind=any(g.record_kinds))
   and (g.record_id is null or g.record_id=r.record_id)
   and case when g.own_records then r.record_id in (select o.record_id from o) else true end)
$$;
revoke all on function okb_private.own_records_of(uuid) from public, anon, authenticated;
grant execute on function okb_private.own_records_of(uuid) to okb_owner, okb_writer, okb_reader;
reset role;
revoke create on schema okb_private from okb_identity;

insert into okb_private.schema_upgrade(id) values ('0015-own-records-set') on conflict (id) do nothing;
