-- 0005-set-based-lookups
-- base: 5acb5ac
-- From HED's upgrade 0072. A record named by its title is looked up among the readable records whose titles hold its
-- words, and a record named by its id must be readable too. A read's cutoff is the highest change number among the
-- readable records, found as a set. Row-level security reads the person's grants a fixed number of times, however
-- many records OKB holds, and matches each record's scope, kind and creator against them. Who may read what is
-- unchanged. The same text is in setup.sql. Safe to run twice. Run as the postgres login.

-- ===================================================================
-- 8w. A record named by its title, and a read's cutoff, found from the readable records as a set.
-- Upgrade 0005-set-based-lookups, from HED's 0072.
-- ===================================================================
grant create on schema okb_private to okb_identity;
set role okb_identity;
-- The highest change number among the records the current actor may read.
create or replace function okb_private.readable_cutoff() returns bigint
language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(max(v.change_no),0) from okb.record_version v where v.record_id in (select okb_private.readable_records())
$$;

-- The record named by its id, or by the exact title of its latest version in any case, among every
-- record the current actor may read that is not deleted. A title is looked up among the readable
-- records whose titles hold its words.
create or replace function okb_private.named_record(p_record text) returns uuid
language plpgsql stable security definer set search_path=pg_catalog as $$
declare t text:=btrim(coalesce(p_record,'')); hits uuid[];
begin
 if t='' then raise exception 'Name a record by its id or its title' using errcode='22023'; end if;
 if t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  if not exists(select 1 from okb.record where record_id=t::uuid) or not okb_private.can_read_record(t::uuid) then
   raise exception 'Record unavailable: no record has the id %',t using errcode='42501';
  end if;
  return t::uuid;
 end if;
 select array_agg(r.record_id order by r.record_id) into hits from okb.record r
  cross join lateral (select v.title from okb.record_version v where v.record_id=r.record_id order by v.change_no desc limit 1) lv
  where r.record_id in (select okb_private.readable_records(null,null,t,null,null))
   and r.deleted_at is null and lower(btrim(lv.title))=lower(t);
 if cardinality(hits)=1 then return hits[1]; end if;
 if hits is null then raise exception 'Record unavailable: no record has the title "%"',t using errcode='42501'; end if;
 raise exception 'More than one record has the title "%": %',t,
  (select string_agg(format('%s (%s, id %s)',t,s.display_name,r.record_id),'; ' order by r.record_id)
   from okb.record r join okb.scope s using(scope_id) where r.record_id=any(hits)) using errcode='22023';
end $$;
reset role;
revoke create on schema okb_private from okb_identity;
revoke all on function okb_private.readable_cutoff() from public, anon, authenticated;
grant execute on function okb_private.readable_cutoff() to okb_owner, okb_writer, okb_reader;

grant create on schema okb_private to okb_reader;
set role okb_reader;
create or replace function okb_private.read_cutoff(p_cutoff bigint) returns bigint
language plpgsql stable set search_path=pg_catalog as $$
declare m bigint;
begin
 perform okb_private.read_actor();
 m:=okb_private.readable_cutoff();
 if p_cutoff is not null and (p_cutoff<0 or p_cutoff>m) then raise exception 'Cutoff outside accessible history' using errcode='22023'; end if;
 return coalesce(p_cutoff,m);
end $$;
reset role;
revoke create on schema okb_private from okb_reader;

-- Row-level security reads the person's grants a fixed number of times, however many records OKB
-- holds, and matches each record's scope, kind and creator against them. A version, a deletion and
-- a link are visible when their records are, and a link joins two records in one scope.
set role okb_owner;
alter policy record_writer_read on okb.record using (exists(select 1 from okb_private.read_grants() g
 where g.scope_id=record.scope_id and (g.record_kinds is null or record.kind=any(g.record_kinds))
 and (g.record_id is null or g.record_id=record.record_id)
 and (not g.own_records or okb_private.is_own_record(g.actor_id,record.record_id))));
alter policy record_reader_read on okb.record using (exists(select 1 from okb_private.read_grants() g
 where g.scope_id=record.scope_id and (g.record_kinds is null or record.kind=any(g.record_kinds))
 and (g.record_id is null or g.record_id=record.record_id)
 and (not g.own_records or okb_private.is_own_record(g.actor_id,record.record_id))));
alter policy version_writer_read on okb.record_version using (exists(select 1 from okb.record r where r.record_id=record_version.record_id));
alter policy version_reader_read on okb.record_version using (exists(select 1 from okb.record r where r.record_id=record_version.record_id));
alter policy deletion_reader_read on okb.record_deletion using (exists(select 1 from okb.record r where r.record_id=record_deletion.record_id));
alter policy link_writer_read on okb.version_link using (exists(select 1 from okb.record_version sv join okb.record sr on sr.record_id=sv.record_id
 join okb.record_version tv on tv.version_id=version_link.target_version_id join okb.record tr on tr.record_id=tv.record_id
 where sv.version_id=version_link.source_version_id and sr.scope_id=tr.scope_id));
alter policy link_reader_read on okb.version_link using (exists(select 1 from okb.record_version sv join okb.record sr on sr.record_id=sv.record_id
 join okb.record_version tv on tv.version_id=version_link.target_version_id join okb.record tr on tr.record_id=tv.record_id
 where sv.version_id=version_link.source_version_id and sr.scope_id=tr.scope_id));
alter policy link_writer_insert on okb.version_link with check (exists(select 1 from okb.record_version sv join okb.record sr on sr.record_id=sv.record_id
 join okb.record_version tv on tv.version_id=version_link.target_version_id join okb.record tr on tr.record_id=tv.record_id
 where sv.version_id=version_link.source_version_id and sr.scope_id=tr.scope_id));
reset role;


insert into okb_private.schema_upgrade(id) values ('0005-set-based-lookups') on conflict (id) do nothing;
