-- 0006-retired-chunks: file search upgrade
-- base: 383e56c
-- A chunk takes a fourth state, retired. A retired version's waiting chunks are retired with it, as its sentences were,
-- and wait again when it comes back. A file's older content keeps its version and its embedded chunks, and its
-- waiting chunks are retired once new content lands. claim_chunks then no longer passes over the one or embeds the
-- other. chunks_follow_version replaces sentences_follow_version, and retire_chunks replaces retire_sentences. Every
-- waiting chunk of a version already retired or purged, or of a file's older content, is retired, with its waiting
-- sentences. A file's current content is queued again as its latest where an older one stood ahead of it. Safe to run
-- twice. Run as postgres.

alter table file_search.chunk drop constraint if exists chunk_state_check;
alter table file_search.chunk add constraint chunk_state_check check (state in ('waiting','embedded','failed','retired'));

-- A retired version's waiting chunks and sentences are retired, and a version that comes back makes them wait again,
-- so no claim passes over them. A purged version's chunks are deleted with it.
create or replace function file_search.retire_chunks(p_version_id uuid) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 update file_search.chunk_sentence s set state='retired' from file_search.chunk c
 where c.version_id=p_version_id and s.chunk_id=c.chunk_id and s.state='waiting';
 update file_search.chunk set state='retired' where version_id=p_version_id and state='waiting';
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function file_search.retire_chunks(uuid) from public, anon, authenticated;
create or replace function file_search.chunks_follow_version() returns trigger
language plpgsql set search_path=pg_catalog as $$
begin
 if new.state='retired' then
  perform file_search.retire_chunks(new.version_id);
 elsif old.state='retired' and new.state<>'purged' then
  update file_search.chunk set state='waiting' where version_id=new.version_id and state='retired';
  update file_search.chunk_sentence s set state='waiting' from file_search.chunk c
  where c.version_id=new.version_id and s.chunk_id=c.chunk_id and s.state='retired';
 end if;
 return null;
end $$;
revoke all on function file_search.chunks_follow_version() from public, anon, authenticated;
drop trigger if exists chunks_follow_version on file_search.file_version;
create trigger chunks_follow_version after update of state on file_search.file_version
 for each row when (old.state is distinct from new.state) execute function file_search.chunks_follow_version();

-- A file's older content keeps its version and its embedded chunks, and its waiting chunks and sentences are
-- retired. The current content's retired chunks and sentences wait again, unless its version is retired or purged.
-- queue_object calls it each time a file's content lands. Returns how many chunks it retired.
create or replace function file_search.chunks_follow_content(p_object_id uuid, p_content_tag text) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 update file_search.chunk_sentence s set state='retired' from file_search.chunk c, file_search.file_version v
 where v.object_id=p_object_id and v.content_tag<>p_content_tag and c.version_id=v.version_id and s.chunk_id=c.chunk_id
  and s.state='waiting';
 update file_search.chunk c set state='retired' from file_search.file_version v
 where v.object_id=p_object_id and v.content_tag<>p_content_tag and c.version_id=v.version_id and c.state='waiting';
 get diagnostics n=row_count;
 update file_search.chunk c set state='waiting' from file_search.file_version v
 where v.object_id=p_object_id and v.content_tag=p_content_tag and v.state not in ('retired','purged')
  and c.version_id=v.version_id and c.state='retired';
 update file_search.chunk_sentence s set state='waiting' from file_search.chunk c, file_search.file_version v
 where v.object_id=p_object_id and v.content_tag=p_content_tag and v.state not in ('retired','purged')
  and c.version_id=v.version_id and s.chunk_id=c.chunk_id and s.state='retired';
 return n;
end $$;
revoke all on function file_search.chunks_follow_content(uuid,text) from public, anon, authenticated;

drop trigger if exists sentences_follow_version on file_search.file_version;
drop function if exists file_search.sentences_follow_version();
drop function if exists file_search.retire_sentences(uuid);

-- Each time a file's content lands, only its current content's chunks wait, and a content that comes back is queued
-- again as the file's latest, so search and the graph reader read it.
create or replace function file_search.queue_object() returns trigger
language plpgsql security definer set search_path=pg_catalog as $$
begin
 if tg_op='UPDATE' then
  update file_search.file_version set bucket_id=new.bucket_id, name=new.name
  where object_id=new.id and (bucket_id is distinct from new.bucket_id or name is distinct from new.name);
 end if;
 if tg_op='DELETE' then
  update file_search.file_version set state='retired', finished_at=clock_timestamp(), error='The file was deleted'
  where object_id=old.id and state not in ('retired','purged');
  return old;
 end if;
 if not exists(select 1 from file_search.indexed_bucket where bucket_id=new.bucket_id) then
  if tg_op='UPDATE' then
   update file_search.file_version set state='retired', finished_at=clock_timestamp(), error='The file left the indexed buckets'
   where object_id=new.id and state not in ('retired','purged');
  end if;
  return new;
 end if;
 if new.metadata is null then return new; end if;
 insert into file_search.file_version(object_id, content_tag, bucket_id, name)
 values (new.id, coalesce(new.metadata->>'eTag', new.updated_at::text), new.bucket_id, new.name)
 on conflict (object_id, content_tag) do update set
  state=case when file_version.state not in ('retired','failed') then file_version.state
   when exists(select 1 from file_search.chunk c where c.version_id=file_version.version_id) then 'extracted' else 'waiting' end,
  attempts=case when file_version.state in ('retired','failed') then 0 else file_version.attempts end,
  error=case when file_version.state in ('retired','failed') then null else file_version.error end,
  finished_at=case when file_version.state in ('retired','failed') then null else file_version.finished_at end,
  queued_at=clock_timestamp()
 where file_version.state in ('retired','failed') or exists(select 1 from file_search.file_version n
  where n.object_id=file_version.object_id and n.queued_at>file_version.queued_at);
 perform file_search.chunks_follow_content(new.id, coalesce(new.metadata->>'eTag', new.updated_at::text));
 return new;
end $$;

-- The chunks waiting now that no claim should take: those of a version retired or purged, or of a file's older content.
update file_search.chunk_sentence s set state='retired' from file_search.chunk c, file_search.file_version v
where s.chunk_id=c.chunk_id and c.version_id=v.version_id and s.state='waiting'
 and (v.state in ('retired','purged') or exists(select 1 from storage.objects o
  where o.id=v.object_id and v.content_tag<>coalesce(o.metadata->>'eTag', o.updated_at::text)));
update file_search.chunk c set state='retired' from file_search.file_version v
where c.version_id=v.version_id and c.state='waiting'
 and (v.state in ('retired','purged') or exists(select 1 from storage.objects o
  where o.id=v.object_id and v.content_tag<>coalesce(o.metadata->>'eTag', o.updated_at::text)));

-- A file whose older content came back before this upgrade: its current content is queued again as its latest.
update file_search.file_version v set queued_at=clock_timestamp()
from storage.objects o
where o.id=v.object_id and v.content_tag=coalesce(o.metadata->>'eTag', o.updated_at::text) and v.state not in ('retired','purged')
 and exists(select 1 from file_search.file_version n where n.object_id=v.object_id and n.queued_at>v.queued_at);

insert into file_search.schema_upgrade(id) values ('0006-retired-chunks') on conflict (id) do nothing;
