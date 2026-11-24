-- 0002-sentence-claim: file search upgrade
-- base: 7740797
-- A retired file version retires its waiting sentences, and one that comes back makes them wait
-- again. The sentence claim takes never-tried sentences first, a chunk's together, through an index
-- of waiting sentences, so its cost no longer grows with the sentences of retired files and those
-- already tried.
-- Safe to run twice. Run as postgres.

alter table file_search.chunk_sentence drop constraint if exists chunk_sentence_state_check;
alter table file_search.chunk_sentence add constraint chunk_sentence_state_check
 check (state in ('waiting','embedded','failed','retired'));
drop index if exists file_search.chunk_sentence_waiting;
create index if not exists chunk_sentence_claim on file_search.chunk_sentence(last_attempt_at nulls first, chunk_id, ordinal) where state='waiting';

-- The embed job takes sentences once no chunk waits, those never tried first, a chunk's together,
-- from the index of waiting sentences. A retired file's sentences are retired, so the claim never
-- walks past them.
create or replace function file_search.claim_sentences(p_limit integer)
returns table(sentence_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 update file_search.chunk_sentence s set attempts=s.attempts+1, last_attempt_at=clock_timestamp()
 where s.sentence_id in (
  select w.sentence_id from file_search.chunk_sentence w join file_search.chunk c on c.chunk_id=w.chunk_id
  where w.state='waiting' and c.state='embedded' and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.last_attempt_at nulls first, w.chunk_id, w.ordinal limit greatest(1, least(p_limit, 50)) for update of w skip locked)
 returning s.sentence_id, s.body
$$;

-- A retired version's waiting sentences are retired, and a version that comes back makes them wait again.
create or replace function file_search.retire_sentences(p_version_id uuid) returns integer
language sql volatile set search_path=pg_catalog as $$
 with r as (update file_search.chunk_sentence s set state='retired' from file_search.chunk c
  where c.version_id=p_version_id and s.chunk_id=c.chunk_id and s.state='waiting' returning 1)
 select count(*)::integer from r
$$;
revoke all on function file_search.retire_sentences(uuid) from public, anon, authenticated;
create or replace function file_search.sentences_follow_version() returns trigger
language plpgsql set search_path=pg_catalog as $$
begin
 if new.state='retired' then
  perform file_search.retire_sentences(new.version_id);
 elsif old.state='retired' and new.state<>'purged' then
  update file_search.chunk_sentence s set state='waiting' from file_search.chunk c
  where c.version_id=new.version_id and s.chunk_id=c.chunk_id and s.state='retired';
 end if;
 return null;
end $$;
revoke all on function file_search.sentences_follow_version() from public, anon, authenticated;
drop trigger if exists sentences_follow_version on file_search.file_version;
create trigger sentences_follow_version after update of state on file_search.file_version
 for each row when (old.state is distinct from new.state) execute function file_search.sentences_follow_version();

-- The waiting sentences of every version already retired.
select file_search.retire_sentences(version_id) from file_search.file_version where state='retired';

insert into file_search.schema_upgrade(id) values ('0002-sentence-claim') on conflict (id) do nothing;
