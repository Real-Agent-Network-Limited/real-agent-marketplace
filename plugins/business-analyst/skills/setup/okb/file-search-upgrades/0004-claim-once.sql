-- 0004-claim-once: file search upgrade
-- base: e8fa7a3
-- File search's claims take at most the rows they ask for, and never a row another worker has just claimed.
-- claim_files, claim_entities, claim_chunks and claim_sentences each picked their rows in a LIMIT ... SKIP
-- LOCKED subquery inside the UPDATE. Once file_version held dead rows and its statistics were fresh, Postgres
-- could run that subquery again for each row it updated, so claim_files(1) took two or three files. The
-- worker read only the first, and the others waited five minutes before anyone tried them. Each claim now
-- picks its rows once, in a materialized step, and the UPDATE joins to it. claim_files, claim_entities and
-- claim_chunks also tested whether a row was waiting in a separate subquery, which locking a row does not
-- check again, so two workers side by side could claim the same row; the test is now on the locked row.
-- Safe to run twice. Run as postgres.

create or replace function file_search.claim_entities(p_limit integer)
returns table(entity_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with picked as materialized (
  select w.entity_id from file_search.entity w
  where w.state='waiting' and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.created_at, w.entity_id limit greatest(1, least(p_limit, 50)) for update of w skip locked),
 claimed as (
  update file_search.entity e set attempts=e.attempts+1, last_attempt_at=clock_timestamp()
  from picked p where e.entity_id=p.entity_id
  returning e.entity_id, e.name, e.entity_type)
 select c.entity_id, c.name||' ('||c.entity_type||')' from claimed c
$$;

create or replace function file_search.claim_files(p_limit integer, p_call bigint default null)
returns table(version_id uuid, bucket_id text, name text)
language plpgsql volatile set search_path=pg_catalog as $$
#variable_conflict use_column
begin
 -- A version whose file is gone, or which a newer content has replaced, is retired unread.
 update file_search.file_version v set state='retired', finished_at=clock_timestamp(), error='The file is no longer in storage'
 where v.state='waiting' and not exists(select 1 from storage.objects o where o.id=v.object_id);
 update file_search.file_version v set state='retired', finished_at=clock_timestamp(), error='A newer content replaced it'
 where v.state='waiting' and exists(select 1 from file_search.file_version n
  where n.object_id=v.object_id and n.queued_at>v.queued_at and n.state not in ('retired','purged'));
 -- The rows are picked once, in a materialized step, then updated: a LIMIT ... SKIP LOCKED subquery inside the
 -- UPDATE can be planned to run again for each row, each run skipping the rows already locked and taking more.
 -- The conditions are on the locked row itself, so a row another worker claimed after this one began is
 -- checked again as it now stands, and skipped.
 return query
 with picked as materialized (
  select w.version_id from file_search.file_version w
  where w.state='waiting' and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.queued_at limit greatest(1, least(p_limit, 20)) for update skip locked),
 claimed as (
  update file_search.file_version f set attempts=f.attempts+1, last_attempt_at=clock_timestamp()
  from picked p, storage.objects o
  where f.version_id=p.version_id and o.id=f.object_id
  returning f.version_id, f.object_id, o.bucket_id, o.name),
 noted as (
  insert into file_search.worker_claim(call_id, version_id, object_id)
  select p_call, c.version_id, c.object_id from claimed c where p_call is not null)
 select c.version_id, c.bucket_id, c.name from claimed c;
end $$;

create or replace function file_search.claim_chunks(p_limit integer, p_call bigint default null)
returns table(chunk_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with picked as materialized (
  select w.chunk_id from file_search.chunk w join file_search.file_version v on v.version_id=w.version_id
  where w.state='waiting' and v.state not in ('retired','purged') and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.chunk_id limit greatest(1, least(p_limit, 50)) for update of w skip locked),
 claimed as (
  update file_search.chunk c set attempts=c.attempts+1, last_attempt_at=clock_timestamp()
  from picked p where c.chunk_id=p.chunk_id
  returning c.chunk_id, c.version_id, c.object_id, c.body),
 noted as (
  insert into file_search.worker_claim(call_id, version_id, chunk_id, object_id)
  select p_call, c.version_id, c.chunk_id, c.object_id from claimed c where p_call is not null)
 select c.chunk_id, c.body from claimed c
$$;

create or replace function file_search.claim_sentences(p_limit integer)
returns table(sentence_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with picked as materialized (
  select w.sentence_id from file_search.chunk_sentence w join file_search.chunk c on c.chunk_id=w.chunk_id
  where w.state='waiting' and c.state='embedded' and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.last_attempt_at nulls first, w.chunk_id, w.ordinal limit greatest(1, least(p_limit, 50)) for update of w skip locked)
 update file_search.chunk_sentence s set attempts=s.attempts+1, last_attempt_at=clock_timestamp()
 from picked p where s.sentence_id=p.sentence_id
 returning s.sentence_id, s.body
$$;

insert into file_search.schema_upgrade(id) values ('0004-claim-once') on conflict (id) do nothing;
