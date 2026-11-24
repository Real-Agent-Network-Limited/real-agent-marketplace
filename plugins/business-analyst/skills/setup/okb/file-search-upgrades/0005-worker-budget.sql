-- 0005-worker-budget: file search upgrade
-- base: 6a7533f
-- redeploy: file-search-worker
-- claim_sentences takes a character budget as well as a count: it takes sentences in its order while their
-- lengths add up to no more than the budget, and always one. It locks the next sentences no other claim holds
-- before it adds up their lengths. The claim of a count alone stays, as a call of the new one, so a worker
-- deployed before this upgrade still runs. Each file, chunk, sentence and entity that failed after five attempts
-- waits again, with no attempts, once, whatever error it kept from an earlier attempt. Safe to run twice.
-- Run as postgres.

-- It takes sentences in that order while their lengths add up to no more than
-- p_chars, and always one. It locks the next sentences no other claim holds before it adds up their lengths.
create or replace function file_search.claim_sentences(p_limit integer, p_chars integer)
returns table(sentence_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with locked as materialized (
  select w.sentence_id, w.body, w.last_attempt_at, w.chunk_id, w.ordinal
  from file_search.chunk_sentence w join file_search.chunk c on c.chunk_id=w.chunk_id
  where w.state='waiting' and c.state='embedded' and w.attempts<5
   and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes')
  order by w.last_attempt_at nulls first, w.chunk_id, w.ordinal limit greatest(1, least(p_limit, 50))
  for update of w skip locked),
 picked as materialized (
  select l.sentence_id from (select l.sentence_id, row_number() over k as n, sum(length(l.body)) over k as total
   from locked l
   window k as (order by l.last_attempt_at nulls first, l.chunk_id, l.ordinal rows between unbounded preceding and current row)) l
  where l.n=1 or l.total<=p_chars)
 update file_search.chunk_sentence s set attempts=s.attempts+1, last_attempt_at=clock_timestamp()
 from picked p where s.sentence_id=p.sentence_id
 returning s.sentence_id, s.body
$$;
-- The claim of a count alone, as a worker deployed before 0005-worker-budget calls it.
create or replace function file_search.claim_sentences(p_limit integer)
returns table(sentence_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 select * from file_search.claim_sentences(p_limit, 2147483647)
$$;
revoke all on function file_search.claim_sentences(integer,integer), file_search.claim_sentences(integer) from public, anon, authenticated;

-- The rows that failed after five attempts wait again, once, when this upgrade is first applied. The sweep that
-- failed them keeps an error an earlier attempt recorded, so a row is known by its attempts, not its error.
do $$
begin
 if exists(select 1 from file_search.schema_upgrade where id='0005-worker-budget') then return; end if;
 update file_search.file_version set state='waiting', attempts=0, last_attempt_at=null, error=null, finished_at=null
 where state='failed' and attempts>=5;
 update file_search.chunk set state='waiting', attempts=0, last_attempt_at=null, error=null
 where state='failed' and attempts>=5;
 update file_search.chunk_sentence set state='waiting', attempts=0, last_attempt_at=null, error=null
 where state='failed' and attempts>=5;
 update file_search.entity set state='waiting', attempts=0, last_attempt_at=null, error=null
 where state='failed' and attempts>=5;
end $$;

insert into file_search.schema_upgrade(id) values ('0005-worker-budget') on conflict (id) do nothing;
