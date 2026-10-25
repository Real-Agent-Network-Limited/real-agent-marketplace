-- File search for a Supabase project: the text of files in chosen Storage buckets, found by
-- lexical keyword search and by semantic similarity, merged by reciprocal rank fusion.
-- Run once, as postgres, in the SQL Editor or through apply_migration.
--
-- Access follows the project's own Storage rules: a search runs as the signed-in user, and finds
-- chunks only of files that user could open. It names no project and holds no data.
-- Choose the buckets to index by adding them to file_search.indexed_bucket.

create extension if not exists vector with schema extensions;

create schema file_search;
revoke all on schema file_search from public;
grant usage on schema file_search to authenticated;

-- The upgrades this build already contains, and each upgrade applied later. See the skill's
-- Upgrades section.
create table file_search.schema_upgrade (
 id text primary key check (id ~ '^[0-9]{4}-[a-z0-9-]+$'),
 applied_at timestamptz not null default clock_timestamp(),
 applied_by_login name not null default session_user
);
revoke all on file_search.schema_upgrade from public, anon, authenticated;

-- The buckets whose files are indexed. A search across every bucket ranks each bucket marked
-- ranked_apart on its own, and returns its hits as a list of their own, and leaves out each
-- bucket not searched_by_default. A search that names a bucket searches it.
create table file_search.indexed_bucket (
 bucket_id text primary key,
 added_at timestamptz not null default clock_timestamp(),
 ranked_apart boolean not null default false,
 searched_by_default boolean not null default true
);

-- One row per content of a stored file. The rows are the queue: each carries its state,
-- attempts and last error, and where the file was last seen. A deleted file's versions are
-- retired, never removed; its text and embeddings stay until purged on request.
create table file_search.file_version (
 version_id uuid primary key default gen_random_uuid(),
 object_id uuid not null,
 content_tag text not null,
 bucket_id text not null,
 name text not null,
 queued_at timestamptz not null default clock_timestamp(),
 state text not null default 'waiting'
  check (state in ('waiting','extracted','no_text','unsupported','failed','retired','purged')),
 attempts integer not null default 0 check (attempts>=0),
 last_attempt_at timestamptz,
 error text,
 finished_at timestamptz,
 unique (object_id, content_tag)
);
create index file_version_latest on file_search.file_version(object_id, queued_at desc);
create index file_version_place on file_search.file_version(bucket_id, name);
create index file_version_waiting on file_search.file_version(last_attempt_at) where state='waiting';

create table file_search.chunk (
 chunk_id uuid primary key default gen_random_uuid(),
 version_id uuid not null references file_search.file_version(version_id),
 object_id uuid not null,
 ordinal integer not null check (ordinal>=0),
 place text,
 body text not null check (length(body) between 1 and 4000),
 words tsvector generated always as (to_tsvector('english'::regconfig, body)) stored,
 embedding extensions.vector(384),
 state text not null default 'waiting' check (state in ('waiting','embedded','failed')),
 attempts integer not null default 0 check (attempts>=0),
 last_attempt_at timestamptz,
 error text,
 embedded_at timestamptz,
 section_ordinal integer,
 unique (version_id, ordinal)
);
create index chunk_words on file_search.chunk using gin(words);
create index chunk_waiting on file_search.chunk(last_attempt_at) where state='waiting';

-- Each section of a file's text, whole: a Markdown heading's part, a PDF page, a sheet, or the
-- whole of any other file. A search returns the section around each of its hits.
create table if not exists file_search.section (
 version_id uuid not null references file_search.file_version(version_id),
 object_id uuid not null,
 ordinal integer not null check (ordinal>=0),
 place text,
 body text not null,
 primary key (version_id, ordinal)
);
create index if not exists section_object on file_search.section(object_id);

-- Each sentence of a chunk, up to 40, with its own vector, made after the chunks' vectors. An
-- explained search compares each hit's sentences with the question, to show which sentence is
-- nearest. A sentence ends at a line break, or at a full stop, question mark or exclamation mark
-- before a capital, a digit, a quote or a bracket.
create table if not exists file_search.chunk_sentence (
 sentence_id uuid primary key default gen_random_uuid(),
 chunk_id uuid not null references file_search.chunk(chunk_id) on delete cascade,
 object_id uuid not null,
 ordinal integer not null check (ordinal>=0),
 body text not null check (length(body) between 1 and 2000),
 embedding extensions.vector(384),
 state text not null default 'waiting' check (state in ('waiting','embedded','failed')),
 attempts integer not null default 0 check (attempts>=0),
 last_attempt_at timestamptz,
 error text,
 embedded_at timestamptz,
 unique (chunk_id, ordinal)
);
create index if not exists chunk_sentence_waiting on file_search.chunk_sentence(last_attempt_at) where state='waiting';
alter table file_search.chunk_sentence enable row level security;
drop policy if exists "File search: files the user can open" on file_search.chunk_sentence;
create policy "File search: files the user can open" on file_search.chunk_sentence for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
revoke all on file_search.chunk_sentence from public, anon, authenticated;
grant select on file_search.chunk_sentence to authenticated;

-- Each call to file-search-worker, until its answer is in. pg_net keeps answers for hours only,
-- so an answer that is not a success is kept here, with its status and reason, for a month.
create table file_search.worker_call (
 call_id bigint generated always as identity primary key,
 request_id bigint,
 job text not null check (job in ('extract','embed','graph')),
 called_at timestamptz not null default clock_timestamp(),
 answered_at timestamptz,
 status integer,
 problem text
);
create index worker_call_unanswered on file_search.worker_call(request_id) where answered_at is null;
create index worker_call_problems on file_search.worker_call(answered_at) where problem is not null;
alter table file_search.worker_call enable row level security;

-- Each file or chunk a call to file-search-worker claimed, and when its outcome was recorded. A
-- claim with no outcome, on a call that went wrong, is the row the run was at when it stopped.
-- A call that succeeds is forgotten, and its claims with it.
create table file_search.worker_claim (
 claim_id bigint generated always as identity primary key,
 call_id bigint not null references file_search.worker_call(call_id) on delete cascade,
 version_id uuid not null references file_search.file_version(version_id),
 chunk_id uuid references file_search.chunk(chunk_id) on delete cascade,
 object_id uuid not null,
 claimed_at timestamptz not null default clock_timestamp(),
 recorded_at timestamptz
);
create index worker_claim_call on file_search.worker_claim(call_id);
create index worker_claim_version on file_search.worker_claim(version_id);
create index worker_claim_chunk on file_search.worker_claim(chunk_id);
create index worker_claim_object on file_search.worker_claim(object_id);
-- No approximate vector index: pgvector's HNSW applies a filter only after choosing its nearest
-- candidates, so a small bucket among large ones could lose every semantic match. The exact scan
-- compares the question with every chunk the user can see, which is right at this size.

-- A signed-in user sees versions and chunks only of files they can open under Storage's rules.
alter table file_search.file_version enable row level security;
alter table file_search.chunk enable row level security;
create policy "File search: files the user can open" on file_search.file_version for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
create policy "File search: files the user can open" on file_search.chunk for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
grant select on file_search.file_version, file_search.chunk to authenticated;
-- A signed-in user sees how each bucket is searched only for a bucket holding a file they can open.
alter table file_search.indexed_bucket enable row level security;
create policy "File search: buckets the user can open a file in" on file_search.indexed_bucket for select to authenticated
 using (exists (select 1 from storage.objects o where o.bucket_id = indexed_bucket.bucket_id));
grant select on file_search.indexed_bucket to authenticated;
alter table file_search.section enable row level security;
create policy "File search: files the user can open" on file_search.section for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
grant select on file_search.section to authenticated;
alter table file_search.worker_claim enable row level security;
create policy "File search: files the user can open" on file_search.worker_claim for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
grant select on file_search.worker_claim to authenticated;

-- The graph: the things the files name, such as people, products, suppliers and places, and how
-- they relate. An agent reads each chunk once and saves what it found with save_extraction; the
-- database calls no language model. An entity merges with one of the same normalised name and type,
-- and a relation with one between the same two entities, in either direction. Each source keeps its
-- own description, so nothing needs to be summarised. A user sees an entity or a relation only
-- through a chunk of a file they can open.
create table if not exists file_search.entity (
 entity_id uuid primary key default gen_random_uuid(),
 name text not null check (length(name) between 1 and 200),
 name_key text not null,
 entity_type text not null check (length(entity_type) between 1 and 100),
 type_key text not null,
 embedding extensions.vector(384),
 state text not null default 'waiting' check (state in ('waiting','embedded','failed')),
 attempts integer not null default 0 check (attempts>=0),
 last_attempt_at timestamptz,
 error text,
 embedded_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 unique (name_key, type_key)
);
create index if not exists entity_waiting on file_search.entity(last_attempt_at) where state='waiting';

create table if not exists file_search.relation (
 relation_id uuid primary key default gen_random_uuid(),
 source_id uuid not null references file_search.entity(entity_id) on delete cascade,
 target_id uuid not null references file_search.entity(entity_id) on delete cascade,
 created_at timestamptz not null default clock_timestamp(),
 check (source_id<>target_id)
);
create unique index if not exists relation_pair on file_search.relation(least(source_id, target_id), greatest(source_id, target_id));
create index if not exists relation_source_entity on file_search.relation(source_id);
create index if not exists relation_target_entity on file_search.relation(target_id);

-- Each chunk an entity or a relation came from, with what that chunk says of it, and who saved it:
-- the id the project gives the saver, and their name. Each source keeps the entity's name and type as
-- its own chunk spells them, and a reader sees only these: the shared entity keeps the first save's
-- spelling, which may come from a file the reader cannot open. A relation's keywords are kept only here, with
-- the chunk that gave them: a relation is shared by every file that names it.
create table if not exists file_search.entity_source (
 entity_id uuid not null references file_search.entity(entity_id) on delete cascade,
 chunk_id uuid not null references file_search.chunk(chunk_id) on delete cascade,
 object_id uuid not null,
 name text not null check (length(name) between 1 and 200),
 entity_type text not null check (length(entity_type) between 1 and 100),
 description text not null check (length(description) between 1 and 2000),
 saved_by uuid not null,
 saved_by_name text,
 saved_at timestamptz not null default clock_timestamp(),
 primary key (entity_id, chunk_id)
);
create index if not exists entity_source_chunk on file_search.entity_source(chunk_id);

create table if not exists file_search.relation_source (
 relation_id uuid not null references file_search.relation(relation_id) on delete cascade,
 chunk_id uuid not null references file_search.chunk(chunk_id) on delete cascade,
 object_id uuid not null,
 keywords text[] not null default '{}',
 description text not null check (length(description) between 1 and 2000),
 saved_by uuid not null,
 saved_by_name text,
 saved_at timestamptz not null default clock_timestamp(),
 primary key (relation_id, chunk_id)
);
create index if not exists relation_source_chunk on file_search.relation_source(chunk_id);

-- One row for each chunk whose entities and relations were saved. A chunk is extracted once.
create table if not exists file_search.chunk_extraction (
 chunk_id uuid primary key references file_search.chunk(chunk_id) on delete cascade,
 object_id uuid not null,
 entities integer not null check (entities>=0),
 relations integer not null check (relations>=0),
 saved_by uuid not null,
 saved_by_name text,
 saved_at timestamptz not null default clock_timestamp()
);
create index if not exists chunk_extraction_object on file_search.chunk_extraction(object_id);

alter table file_search.entity enable row level security;
alter table file_search.relation enable row level security;
alter table file_search.entity_source enable row level security;
alter table file_search.relation_source enable row level security;
alter table file_search.chunk_extraction enable row level security;
drop policy if exists "File search: through files the user can open" on file_search.entity;
create policy "File search: through files the user can open" on file_search.entity for select to authenticated
 using (exists (select 1 from file_search.entity_source s join storage.objects o on o.id=s.object_id where s.entity_id=entity.entity_id));
drop policy if exists "File search: through files the user can open" on file_search.relation;
create policy "File search: through files the user can open" on file_search.relation for select to authenticated
 using (exists (select 1 from file_search.relation_source s join storage.objects o on o.id=s.object_id where s.relation_id=relation.relation_id));
drop policy if exists "File search: files the user can open" on file_search.entity_source;
create policy "File search: files the user can open" on file_search.entity_source for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
drop policy if exists "File search: files the user can open" on file_search.relation_source;
create policy "File search: files the user can open" on file_search.relation_source for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
drop policy if exists "File search: files the user can open" on file_search.chunk_extraction;
create policy "File search: files the user can open" on file_search.chunk_extraction for select to authenticated
 using (exists (select 1 from storage.objects o where o.id = object_id));
revoke all on file_search.entity, file_search.relation, file_search.entity_source, file_search.relation_source,
 file_search.chunk_extraction from public, anon, authenticated;
grant select on file_search.entity_source, file_search.relation_source, file_search.chunk_extraction to authenticated;
-- Of the shared entity and relation, only what joins them and finds them: their spelling and times may
-- come from another bucket's file.
grant select (entity_id, name_key, type_key, embedding, state) on file_search.entity to authenticated;
grant select (relation_id, source_id, target_id) on file_search.relation to authenticated;

-- A name or a type as entities merge on it: lower case, with its spaces run together, and without
-- quotes or punctuation at either end.
create or replace function file_search.graph_key(p text) returns text
language sql immutable set search_path=pg_catalog as $$
 select lower(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'), ' "''`.,;:!?()[]{}<>'))
$$;

-- The chunks of a bucket whose entities and relations have not been saved, of each file's latest
-- extracted content, with their text, file and place, in file and chunk order; and how many wait in
-- all, and how many of the bucket's files still wait for their text. Only the project's own
-- functions call it, after checking the caller may read the bucket.
create or replace function file_search.unextracted(p_bucket text, p_limit integer) returns jsonb
language plpgsql stable set search_path=pg_catalog as $$
declare result jsonb;
begin
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Limit must be 1 through 50' using errcode='22023'; end if;
 with latest as (
  select distinct on (f.object_id) f.version_id, f.object_id, f.state
  from file_search.file_version f where f.state not in ('retired','purged')
  order by f.object_id, f.queued_at desc),
 files as (
  select l.version_id, l.state, o.name from latest l join storage.objects o on o.id=l.object_id where o.bucket_id=p_bucket),
 waiting as (
  select c.chunk_id, c.ordinal, c.place, c.body, f.name from file_search.chunk c join files f on f.version_id=c.version_id and f.state='extracted'
  where not exists (select 1 from file_search.chunk_extraction x where x.chunk_id=c.chunk_id)),
 page as (select * from waiting order by name, ordinal limit p_limit)
 select jsonb_build_object(
  'chunks', coalesce((select jsonb_agg(jsonb_build_object('chunk_id', p.chunk_id, 'file', p.name, 'place', p.place, 'text', p.body)
    order by p.name, p.ordinal) from page p), '[]'::jsonb),
  'waiting', (select count(*) from waiting),
  'awaiting_text', (select count(*) from files where state='waiting'))
 into result;
 return result;
end $$;

-- Saves one chunk's entities and relations, once. p_entities is [{name, type, description}] and
-- p_relations [{source, target, keywords, description}], each relation naming two of the chunk's
-- entities by name. Each entity merges by its normalised name and type, and each relation by its two
-- entities; each keeps this chunk as a source, with its description. p_saved_by and p_saved_by_name
-- name who saved it. Only the project's own functions call it, after checking the caller may read
-- the chunk and may add to its bucket. Returns what it saved, or that the chunk was saved before,
-- and never whether an entity or a relation already existed, which another bucket may hold.
-- With p_replace, a chunk saved before has its earlier extraction deleted first, with the entities
-- and relations only it supported; the project's function decides who may replace one.
create or replace function file_search.save_extraction(p_chunk uuid, p_entities jsonb, p_relations jsonb,
 p_saved_by uuid, p_saved_by_name text, p_replace boolean default false) returns jsonb
language plpgsql volatile set search_path=pg_catalog as $$
declare c record; e jsonb; r jsonb; ents jsonb:=coalesce(p_entities, '[]'::jsonb); rels jsonb:=coalesce(p_relations, '[]'::jsonb);
 eid uuid; rid uuid; a uuid; b uuid; kw text[]; n_e integer:=0; n_r integer:=0; k text; keys jsonb:='{}'::jsonb;
begin
 if p_saved_by is null then raise exception 'Name who saved the extraction' using errcode='22023'; end if;
 if jsonb_typeof(ents)<>'array' or jsonb_typeof(rels)<>'array' then raise exception 'Entities and relations are each a list' using errcode='22023'; end if;
 if jsonb_array_length(ents)>100 or jsonb_array_length(rels)>200 then
  raise exception 'A chunk takes at most 100 entities and 200 relations' using errcode='22023'; end if;
 select k.chunk_id, k.object_id, v.state as version_state into c from file_search.chunk k join file_search.file_version v on v.version_id=k.version_id
  where k.chunk_id=p_chunk for update of k;
 if c.chunk_id is null or c.version_state in ('retired','purged') then raise exception 'No such chunk' using errcode='22023'; end if;
 if exists (select 1 from file_search.chunk_extraction where chunk_id=p_chunk) then
  if not coalesce(p_replace, false) then
   return jsonb_build_object('chunk_id', p_chunk, 'saved', false, 'reason', 'This chunk''s extraction was saved before');
  end if;
  delete from file_search.entity_source where chunk_id=p_chunk;
  delete from file_search.relation_source where chunk_id=p_chunk;
  delete from file_search.chunk_extraction where chunk_id=p_chunk;
  perform file_search.delete_unsupported();
 end if;
 -- Each entity once, its descriptions in this chunk joined.
 for e in select jsonb_build_object('name', min(x->>'name'), 'type', min(x->>'type'),
   'description', string_agg(btrim(x->>'description'), ' ' order by o))
  from jsonb_array_elements(ents) with ordinality t(x, o)
  group by file_search.graph_key(x->>'name'), file_search.graph_key(x->>'type') loop
  if length(btrim(coalesce(e->>'name', ''))) not between 1 and 200 or length(btrim(coalesce(e->>'type', ''))) not between 1 and 100
   or file_search.graph_key(e->>'name')='' or file_search.graph_key(e->>'type')='' then
   raise exception 'Each entity has a name of 1 to 200 characters and a type of 1 to 100' using errcode='22023'; end if;
  if length(btrim(coalesce(e->>'description', ''))) not between 1 and 2000 then
   raise exception 'Each entity has a description of 1 to 2,000 characters: %', e->>'name' using errcode='22023'; end if;
  insert into file_search.entity(name, name_key, entity_type, type_key)
  values (btrim(e->>'name'), file_search.graph_key(e->>'name'), btrim(e->>'type'), file_search.graph_key(e->>'type'))
  on conflict (name_key, type_key) do nothing returning entity_id into eid;
  if eid is null then
   select entity_id into eid from file_search.entity where name_key=file_search.graph_key(e->>'name') and type_key=file_search.graph_key(e->>'type');
  end if;
  insert into file_search.entity_source(entity_id, chunk_id, object_id, name, entity_type, description, saved_by, saved_by_name)
  values (eid, p_chunk, c.object_id, btrim(e->>'name'), btrim(e->>'type'), btrim(e->>'description'), p_saved_by, p_saved_by_name);
  k:=file_search.graph_key(e->>'name');
  if keys ? k then raise exception 'Two entities in this chunk share the name "%": give each a different name', e->>'name' using errcode='22023'; end if;
  keys:=keys||jsonb_build_object(k, eid);
  n_e:=n_e+1;
 end loop;
 -- Each relation once, between two entities of this chunk, named by name.
 for r in select x from jsonb_array_elements(rels) x loop
  a:=(keys->>file_search.graph_key(r->>'source'))::uuid;
  b:=(keys->>file_search.graph_key(r->>'target'))::uuid;
  if a is null or b is null then
   raise exception 'A relation names an entity this chunk does not: % to %', r->>'source', r->>'target' using errcode='22023'; end if;
  if a=b then raise exception 'A relation joins two different entities: %', r->>'source' using errcode='22023'; end if;
  if length(btrim(coalesce(r->>'description', ''))) not between 1 and 2000 then
   raise exception 'Each relation has a description of 1 to 2,000 characters: % to %', r->>'source', r->>'target' using errcode='22023'; end if;
  select coalesce(array_agg(distinct lower(btrim(w))) filter (where btrim(w)<>''), '{}') into kw
  from jsonb_array_elements_text(case jsonb_typeof(r->'keywords') when 'array' then r->'keywords'
   when 'string' then to_jsonb(string_to_array(r->>'keywords', ',')) else '[]'::jsonb end) w;
  select relation_id into rid from file_search.relation
  where least(source_id, target_id)=least(a, b) and greatest(source_id, target_id)=greatest(a, b);
  if rid is null then
   insert into file_search.relation(source_id, target_id) values (a, b)
   on conflict (least(source_id, target_id), greatest(source_id, target_id)) do nothing returning relation_id into rid;
   if rid is null then
    select relation_id into rid from file_search.relation
    where least(source_id, target_id)=least(a, b) and greatest(source_id, target_id)=greatest(a, b);
   end if;
  end if;
  insert into file_search.relation_source(relation_id, chunk_id, object_id, keywords, description, saved_by, saved_by_name)
  values (rid, p_chunk, c.object_id, kw, btrim(r->>'description'), p_saved_by, p_saved_by_name)
  on conflict (relation_id, chunk_id) do update set keywords=(select array_agg(distinct w order by w) from unnest(relation_source.keywords||excluded.keywords) w),
   description=left(relation_source.description||' '||excluded.description, 2000);
  n_r:=n_r+1;
 end loop;
 insert into file_search.chunk_extraction(chunk_id, object_id, entities, relations, saved_by, saved_by_name)
 values (p_chunk, c.object_id, n_e, n_r, p_saved_by, p_saved_by_name);
 return jsonb_build_object('chunk_id', p_chunk, 'saved', true, 'entities', n_e, 'relations', n_r,
  'replaced', coalesce(p_replace, false));
end $$;

-- The entities waiting for their vector, for file-search-worker's graph job. An entity's vector is
-- made from its name and type alone: an entity is shared by every file that names it, and its
-- descriptions come from files a searcher may not open.
create or replace view file_search.claimable_entity with (security_invoker=true) as
 select w.* from file_search.entity w
 where w.state='waiting' and w.attempts<5
  and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes');
revoke all on file_search.claimable_entity from public, anon, authenticated;

create or replace function file_search.claim_entities(p_limit integer)
returns table(entity_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with claimed as (
  update file_search.entity e set attempts=e.attempts+1, last_attempt_at=clock_timestamp()
  where e.entity_id in (
   select w.entity_id from file_search.entity w
   where w.entity_id in (select c.entity_id from file_search.claimable_entity c)
   order by w.created_at, w.entity_id limit greatest(1, least(p_limit, 50)) for update of w skip locked)
  returning e.entity_id, e.name, e.entity_type)
 select c.entity_id, c.name||' ('||c.entity_type||')' from claimed c
$$;

-- One entity's vector, as '[n,n,...]', recorded as soon as it is made; or its error.
create or replace function file_search.record_entity_vector(p_entity_id uuid, p_embedding text, p_error text)
returns boolean language plpgsql volatile set search_path=pg_catalog as $$
begin
 if p_embedding is not null then
  update file_search.entity set embedding=p_embedding::extensions.vector, state='embedded', embedded_at=clock_timestamp(), error=null
  where entity_id=p_entity_id and state='waiting';
 else
  update file_search.entity set error=left(p_error, 2000), state=case when attempts>=5 then 'failed' else 'waiting' end
  where entity_id=p_entity_id and state='waiting';
 end if;
 return found;
end $$;

-- The entities and relations no chunk supports any more, deleted. purge calls it once a file's
-- chunks are gone.
create or replace function file_search.delete_unsupported() returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer; m integer;
begin
 delete from file_search.relation r where not exists (select 1 from file_search.relation_source s where s.relation_id=r.relation_id);
 get diagnostics n=row_count;
 delete from file_search.entity e where not exists (select 1 from file_search.entity_source s where s.entity_id=e.entity_id);
 get diagnostics m=row_count;
 return n+m;
end $$;

revoke all on function file_search.graph_key(text), file_search.unextracted(text,integer),
 file_search.save_extraction(uuid,jsonb,jsonb,uuid,text,boolean), file_search.claim_entities(integer),
 file_search.record_entity_vector(uuid,text,text), file_search.delete_unsupported()
 from public, anon, authenticated;
grant execute on function file_search.graph_key(text) to authenticated;

-- A file in an indexed bucket is queued once its content has landed, once per content.
-- A move keeps the file's id and content, so it is not queued again; search reads its name live.
-- A deleted file, or one moved out of the indexed buckets, has its versions retired. A retired
-- or failed version whose content comes back is restored: extracted if its chunks remain, else
-- waiting, with its attempts reset.
create function file_search.queue_object() returns trigger
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
  state=case when exists(select 1 from file_search.chunk c where c.version_id=file_version.version_id) then 'extracted' else 'waiting' end,
  attempts=0, error=null, finished_at=null
 where file_version.state in ('retired','failed');
 return new;
end $$;
revoke all on function file_search.queue_object() from public, anon, authenticated;
create trigger file_search_queue after insert or update or delete on storage.objects
 for each row execute function file_search.queue_object();

-- Index a bucket, queueing the files already in it; or stop indexing one, retiring its files'
-- versions. Each returns how many files it queued or retired.
create function file_search.index_bucket(p_bucket text) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 insert into file_search.indexed_bucket(bucket_id) values (p_bucket) on conflict (bucket_id) do nothing;
 insert into file_search.file_version(object_id, content_tag, bucket_id, name)
 select o.id, coalesce(o.metadata->>'eTag', o.updated_at::text), o.bucket_id, o.name from storage.objects o
 where o.bucket_id=p_bucket and o.metadata is not null
 on conflict (object_id, content_tag) do update set
  state=case when exists(select 1 from file_search.chunk c where c.version_id=file_version.version_id) then 'extracted' else 'waiting' end,
  attempts=0, error=null, finished_at=null
 where file_version.state in ('retired','failed');
 get diagnostics n=row_count;
 return n;
end $$;

create function file_search.unindex_bucket(p_bucket text) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 delete from file_search.indexed_bucket where bucket_id=p_bucket;
 update file_search.file_version v set state='retired', finished_at=clock_timestamp(), error='The bucket is no longer indexed'
 from storage.objects o where o.id=v.object_id and o.bucket_id=p_bucket and v.state not in ('retired','purged');
 get diagnostics n=row_count;
 return n;
end $$;

-- Delete a deleted file's text and embeddings, on request. The file must already be gone from
-- its bucket; its versions stay, marked purged, as the record that it was indexed. purge takes
-- the stored file's id, as file-search-purge does; purge_file takes the bucket and name the file
-- was last seen under, skipping any file still there under that name. Each returns how many
-- chunks it deleted. The entities and relations only its chunks supported go with them.
create function file_search.purge(p_object_id uuid) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 if exists(select 1 from storage.objects where id=p_object_id) then
  raise exception 'Delete the file from its bucket first' using errcode='55000';
 end if;
 delete from file_search.chunk where object_id=p_object_id;
 get diagnostics n=row_count;
 perform file_search.delete_unsupported();
 delete from file_search.section where object_id=p_object_id;
 update file_search.file_version set state='purged', finished_at=clock_timestamp(),
  error='Its text and embeddings were deleted on request'
 where object_id=p_object_id and state<>'purged';
 return n;
end $$;

create function file_search.purge_file(p_bucket text, p_name text) returns integer
language sql volatile set search_path=pg_catalog as $$
 select coalesce(sum(file_search.purge(v.object_id)), 0)::integer
 from (select distinct object_id from file_search.file_version f
  where f.bucket_id=p_bucket and f.name=p_name
   and not exists(select 1 from storage.objects o where o.id=f.object_id)) v
$$;

-- A chunk's sentences, up to 40, each holding at least two letters or digits.
create or replace function file_search.sentences_of(p_body text) returns table(ordinal integer, body text)
language sql immutable set search_path=pg_catalog as $$
 select (row_number() over (order by x.n) - 1)::integer, left(btrim(x.s), 2000)
 from regexp_split_to_table(p_body, E'\\n+|(?<=[.!?])[ \\t]+(?=[[:upper:][:digit:]"''(\\[])') with ordinality x(s, n)
 where length(regexp_replace(x.s, '[^[:alnum:]]', '', 'g'))>=2
 order by x.n limit 40
$$;

-- Each sentence of a version's chunks, waiting for its vector, in a bucket searched by default. A
-- bucket searched only by name, such as a person's sessions, keeps its chunks' sentences unsplit.
-- Safe to run twice.
create or replace function file_search.split_sentences(p_version_id uuid) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare n integer;
begin
 insert into file_search.chunk_sentence(chunk_id, object_id, ordinal, body)
 select c.chunk_id, c.object_id, x.ordinal, x.body from file_search.chunk c
 join storage.objects o on o.id=c.object_id left join file_search.indexed_bucket b on b.bucket_id=o.bucket_id
 cross join lateral file_search.sentences_of(c.body) x
 where c.version_id=p_version_id and coalesce(b.searched_by_default, true) on conflict (chunk_id, ordinal) do nothing;
 get diagnostics n=row_count;
 return n;
end $$;

-- The rows a claim may take now: waiting, tried fewer than five times, and not in the last five
-- minutes; for a chunk, of a version not retired or purged. The claims, the dispatcher and the
-- worker all read these, so they cannot disagree.
create view file_search.claimable_file with (security_invoker=true) as
 select w.* from file_search.file_version w
 where w.state='waiting' and w.attempts<5
  and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes');
create view file_search.claimable_chunk with (security_invoker=true) as
 select w.* from file_search.chunk w join file_search.file_version v on v.version_id=w.version_id
 where w.state='waiting' and v.state not in ('retired','purged') and w.attempts<5
  and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes');
revoke all on file_search.claimable_file, file_search.claimable_chunk from public, anon, authenticated;

-- The worker functions. Only the file-search-worker hosted function calls them, connected as
-- postgres. A row is tried five times, at most once every five minutes.
-- p_call is the worker_call the claim is made for; each row claimed is recorded against it.
create function file_search.claim_files(p_limit integer, p_call bigint default null)
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
 return query
 with claimed as (
  update file_search.file_version f set attempts=f.attempts+1, last_attempt_at=clock_timestamp()
  from storage.objects o
  where o.id=f.object_id and f.version_id in (
   select w.version_id from file_search.file_version w
   where w.version_id in (select c.version_id from file_search.claimable_file c)
   order by w.queued_at limit greatest(1, least(p_limit, 20)) for update skip locked)
  returning f.version_id, f.object_id, o.bucket_id, o.name),
 noted as (
  insert into file_search.worker_claim(call_id, version_id, object_id)
  select p_call, c.version_id, c.object_id from claimed c where p_call is not null)
 select c.version_id, c.bucket_id, c.name from claimed c;
end $$;

-- p_state is extracted, no_text, unsupported or failed; p_chunks is [{ordinal, place, body, section}]
-- and p_sections [{ordinal, place, body}]. A failure keeps the row waiting until its fifth attempt.
create or replace function file_search.record_file_text(p_version_id uuid, p_state text, p_chunks jsonb, p_error text, p_sections jsonb default null)
returns integer language plpgsql volatile set search_path=pg_catalog as $$
declare f file_search.file_version; n integer:=0;
begin
 if p_state='extracted' and p_sections is null then
  raise exception 'Extracted text needs its sections: redeploy file-search-worker' using errcode='22023';
 end if;
 select * into f from file_search.file_version where version_id=p_version_id for update;
 update file_search.worker_claim set recorded_at=clock_timestamp()
 where claim_id=(select k.claim_id from file_search.worker_claim k
  where k.version_id=p_version_id and k.chunk_id is null and k.recorded_at is null order by k.claimed_at desc limit 1);
 if f.version_id is null or f.state<>'waiting' then return 0; end if;
 if p_state not in ('extracted','no_text','unsupported','failed') then raise exception 'Unknown file state %', p_state using errcode='22023'; end if;
 if p_state='failed' then
  update file_search.file_version set error=left(p_error, 2000),
   state=case when attempts>=5 then 'failed' else 'waiting' end,
   finished_at=case when attempts>=5 then clock_timestamp() end
  where version_id=p_version_id;
  return 0;
 end if;
 if p_state='extracted' then
  insert into file_search.section(version_id, object_id, ordinal, place, body)
  select p_version_id, f.object_id, (x->>'ordinal')::integer, x->>'place', x->>'body'
  from jsonb_array_elements(coalesce(p_sections, '[]'::jsonb)) x;
  insert into file_search.chunk(version_id, object_id, ordinal, place, body, section_ordinal)
  select p_version_id, f.object_id, (x->>'ordinal')::integer, x->>'place', x->>'body', (x->>'section')::integer
  from jsonb_array_elements(coalesce(p_chunks, '[]'::jsonb)) x;
  get diagnostics n=row_count;
  perform file_search.split_sentences(p_version_id);
 end if;
 -- A file that is not read says why, in words its owner can act on.
 update file_search.file_version set state=case when p_state='extracted' and n=0 then 'no_text' else p_state end,
  error=case when p_state='unsupported' then 'OKB reads PDF, .xlsx, .xls, .ods, .docx, Markdown and plain text files. Save this file as one of those.'
   when p_state='no_text' or n=0 then 'This file has no text to read, such as a scanned document.' end,
  finished_at=clock_timestamp() where version_id=p_version_id;
 return n;
end $$;

create function file_search.claim_chunks(p_limit integer, p_call bigint default null)
returns table(chunk_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 with claimed as (
  update file_search.chunk c set attempts=c.attempts+1, last_attempt_at=clock_timestamp()
  where c.chunk_id in (
   select w.chunk_id from file_search.chunk w
   where w.chunk_id in (select c.chunk_id from file_search.claimable_chunk c)
   order by w.chunk_id limit greatest(1, least(p_limit, 50)) for update of w skip locked)
  returning c.chunk_id, c.version_id, c.object_id, c.body),
 noted as (
  insert into file_search.worker_claim(call_id, version_id, chunk_id, object_id)
  select p_call, c.version_id, c.chunk_id, c.object_id from claimed c where p_call is not null)
 select c.chunk_id, c.body from claimed c
$$;

-- One chunk's vector, as '[n,n,...]', recorded as soon as it is made; or its error.
create function file_search.record_chunk_vector(p_chunk_id uuid, p_embedding text, p_error text)
returns boolean language plpgsql volatile set search_path=pg_catalog as $$
begin
 update file_search.worker_claim set recorded_at=clock_timestamp()
 where claim_id=(select k.claim_id from file_search.worker_claim k
  where k.chunk_id=p_chunk_id and k.recorded_at is null order by k.claimed_at desc limit 1);
 if p_embedding is not null then
  update file_search.chunk set embedding=p_embedding::extensions.vector, state='embedded', embedded_at=clock_timestamp(), error=null
  where chunk_id=p_chunk_id and state='waiting';
 else
  update file_search.chunk set error=left(p_error, 2000), state=case when attempts>=5 then 'failed' else 'waiting' end
  where chunk_id=p_chunk_id and state='waiting';
 end if;
 return found;
end $$;

-- The sentences a claim may take now, as for a chunk, once their chunk has its vector.
create or replace view file_search.claimable_sentence with (security_invoker=true) as
 select w.* from file_search.chunk_sentence w join file_search.chunk c on c.chunk_id=w.chunk_id
 join file_search.file_version v on v.version_id=c.version_id
 where w.state='waiting' and c.state='embedded' and v.state not in ('retired','purged') and w.attempts<5
  and (w.last_attempt_at is null or w.last_attempt_at<clock_timestamp()-interval '5 minutes');
revoke all on file_search.claimable_sentence from public, anon, authenticated;

-- The embed job takes sentences once no chunk waits.
create or replace function file_search.claim_sentences(p_limit integer)
returns table(sentence_id uuid, body text)
language sql volatile set search_path=pg_catalog as $$
 update file_search.chunk_sentence s set attempts=s.attempts+1, last_attempt_at=clock_timestamp()
 where s.sentence_id in (
  select w.sentence_id from file_search.chunk_sentence w
  where w.sentence_id in (select c.sentence_id from file_search.claimable_sentence c)
  order by w.chunk_id, w.ordinal limit greatest(1, least(p_limit, 50)) for update of w skip locked)
 returning s.sentence_id, s.body
$$;

-- One sentence's vector, as '[n,n,...]', recorded as soon as it is made; or its error.
create or replace function file_search.record_sentence_vector(p_sentence_id uuid, p_embedding text, p_error text)
returns boolean language plpgsql volatile set search_path=pg_catalog as $$
begin
 if p_embedding is not null then
  update file_search.chunk_sentence set embedding=p_embedding::extensions.vector, state='embedded', embedded_at=clock_timestamp(), error=null
  where sentence_id=p_sentence_id and state='waiting';
 else
  update file_search.chunk_sentence set error=left(p_error, 2000), state=case when attempts>=5 then 'failed' else 'waiting' end
  where sentence_id=p_sentence_id and state='waiting';
 end if;
 return found;
end $$;

-- A row claimed five times without an answer, from a worker that stopped, fails for good.
-- Calls the worker for a job through pg_net, and notes the call so its answer can be checked.
-- The call's id goes with it, and the worker records each row it claims against it.
create function file_search.call_worker(p_job text) returns bigint
language plpgsql volatile set search_path=pg_catalog as $$
declare address text; secret text; request bigint; call bigint;
begin
 select decrypted_secret into address from vault.decrypted_secrets where name='file_search_project_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='file_search_worker_secret';
 if address is null or secret is null then raise exception 'Run schedule.sql first: the project address or worker secret is missing from Vault' using errcode='55000'; end if;
 insert into file_search.worker_call(job) values (p_job) returning call_id into call;
 request:=net.http_post(url:=address||'/functions/v1/file-search-worker', body:=jsonb_build_object('job', p_job, 'call', call),
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||secret), timeout_milliseconds:=150000);
 update file_search.worker_call set request_id=request where call_id=call;
 return request;
end $$;

-- Reads the answers pg_net has to the worker's calls. A success is forgotten; anything else is
-- kept with its status and reason, as is a call with no answer after an hour. Returns how many
-- calls went wrong.
create function file_search.record_worker_answers() returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare failed integer; unanswered integer;
begin
 delete from file_search.worker_call w using net._http_response r
 where w.answered_at is null and r.id=w.request_id and r.status_code between 200 and 299 and r.error_msg is null;
 update file_search.worker_call w set answered_at=clock_timestamp(), status=r.status_code,
  problem=left(coalesce(r.error_msg, nullif(r.content, ''), 'The worker gave no reason'), 2000)
 from net._http_response r where w.answered_at is null and r.id=w.request_id;
 get diagnostics failed=row_count;
 update file_search.worker_call set answered_at=clock_timestamp(), problem='No answer was recorded'
 where answered_at is null and called_at<clock_timestamp()-interval '1 hour';
 get diagnostics unanswered=row_count;
 delete from file_search.worker_call where answered_at<clock_timestamp()-interval '30 days';
 return failed+unanswered;
end $$;

-- The most recent run that claimed a file (p_chunk_id null) or a chunk and went wrong, as a
-- sentence to add to its error; with none, the most recent run of its job that went wrong.
create function file_search.last_problem(p_version_id uuid, p_chunk_id uuid) returns text
language sql stable set search_path=pg_catalog as $$
 select coalesce(
  (select format('. The last run that took it and went wrong, at %s UTC, answered %s: %s',
    to_char(w.answered_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), coalesce(w.status::text, 'nothing'), w.problem)
   from file_search.worker_call w join file_search.worker_claim k on k.call_id=w.call_id
   where w.problem is not null
    and (k.chunk_id=p_chunk_id or (p_chunk_id is null and k.chunk_id is null and k.version_id=p_version_id))
   order by w.answered_at desc limit 1),
  (select format('. The last %s run that went wrong, at %s UTC, answered %s: %s', w.job,
    to_char(w.answered_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), coalesce(w.status::text, 'nothing'), w.problem)
   from file_search.worker_call w where w.job=case when p_chunk_id is null then 'extract' else 'embed' end
    and w.problem is not null order by w.answered_at desc limit 1), '')
$$;

-- How many of the worker's runs went wrong in the last day and left work unfinished: a row they
-- claimed is still waiting, or they claimed none. Every search reports it.
create function file_search.failed_worker_runs() returns integer
language sql stable security definer set search_path=pg_catalog as $$
 select count(*)::integer from file_search.worker_call w
 where w.problem is not null and w.answered_at>clock_timestamp()-interval '1 day'
  and (not exists (select 1 from file_search.worker_claim k where k.call_id=w.call_id)
   or exists (select 1 from file_search.worker_claim k
    left join file_search.file_version v on k.chunk_id is null and v.version_id=k.version_id
    left join file_search.chunk c on c.chunk_id=k.chunk_id
    where k.call_id=w.call_id and coalesce(c.state, v.state)='waiting'))
$$;

-- The worker's runs that went wrong in the last day and left work unfinished, newest first: a row
-- they claimed is still waiting, or they claimed none. Every search lists them, each with the files
-- it claimed that the signed-in user can open.
create function file_search.worker_problems()
returns table(call_id bigint, job text, called_at timestamptz, answered_at timestamptz, status integer, problem text)
language sql stable security definer set search_path=pg_catalog as $$
 select w.call_id, w.job, w.called_at, w.answered_at, w.status, w.problem from file_search.worker_call w
 where w.problem is not null and w.answered_at>clock_timestamp()-interval '1 day'
  and (not exists (select 1 from file_search.worker_claim k where k.call_id=w.call_id)
   or exists (select 1 from file_search.worker_claim k
    left join file_search.file_version v on k.chunk_id is null and v.version_id=k.version_id
    left join file_search.chunk c on c.chunk_id=k.chunk_id
    where k.call_id=w.call_id and coalesce(c.state, v.state)='waiting'))
 order by w.answered_at desc, w.call_id desc
$$;

create or replace function file_search.expire_exhausted() returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare files integer; chunks integer; entities integer; sentences integer;
begin
 update file_search.file_version set state='failed', finished_at=clock_timestamp(),
  error=coalesce(error, 'No answer after five attempts'||file_search.last_problem(version_id, null))
 where state='waiting' and attempts>=5 and last_attempt_at<clock_timestamp()-interval '5 minutes';
 get diagnostics files=row_count;
 update file_search.chunk set state='failed', error=coalesce(error, 'No answer after five attempts'||file_search.last_problem(version_id, chunk_id))
 where state='waiting' and attempts>=5 and last_attempt_at<clock_timestamp()-interval '5 minutes';
 get diagnostics chunks=row_count;
 update file_search.entity set state='failed', error=coalesce(error, 'No answer after five attempts')
 where state='waiting' and attempts>=5 and last_attempt_at<clock_timestamp()-interval '5 minutes';
 get diagnostics entities=row_count;
 update file_search.chunk_sentence set state='failed', error=coalesce(error, 'No answer after five attempts')
 where state='waiting' and attempts>=5 and last_attempt_at<clock_timestamp()-interval '5 minutes';
 get diagnostics sentences=row_count;
 return files+chunks+entities+sentences;
end $$;

-- Whether a job has a row a claim would take now.
create or replace function file_search.has_work(p_job text) returns boolean
language sql stable set search_path=pg_catalog as $$
 select case p_job
  when 'extract' then exists(select 1 from file_search.claimable_file)
  when 'embed' then exists(select 1 from file_search.claimable_chunk) or exists(select 1 from file_search.claimable_sentence)
  when 'graph' then exists(select 1 from file_search.claimable_entity)
  else false end
$$;

-- Whether a call for a job went out in the last three minutes and has no answer yet: a run, or
-- a chain of runs each queuing the next, is still at work on it.
create function file_search.job_running(p_job text) returns boolean
language sql stable set search_path=pg_catalog as $$
 select exists(select 1 from file_search.worker_call where job=p_job and answered_at is null
  and called_at>clock_timestamp()-interval '3 minutes')
$$;

-- Called every minute by the schedule schedule.sql sets up. Records the worker's answers, fails
-- exhausted rows, then asks the worker to take text, and separately to make chunks' vectors and
-- entities' vectors, while each kind of work waits and no run of that kind is already at work.
-- net and vault are Supabase's own, so this runs only once schedule.sql has run.
create function file_search.dispatch() returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare address text; secret text; calls integer:=0;
begin
 perform file_search.record_worker_answers();
 perform file_search.expire_exhausted();
 select decrypted_secret into address from vault.decrypted_secrets where name='file_search_project_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='file_search_worker_secret';
 if address is null or secret is null then raise exception 'Run schedule.sql first: the project address or worker secret is missing from Vault' using errcode='55000'; end if;
 if file_search.has_work('extract') and not file_search.job_running('extract') then
  perform file_search.call_worker('extract');
  calls:=calls+1;
 end if;
 if file_search.has_work('embed') and not file_search.job_running('embed') then
  perform file_search.call_worker('embed');
  calls:=calls+1;
 end if;
 if file_search.has_work('graph') and not file_search.job_running('graph') then
  perform file_search.call_worker('graph');
  calls:=calls+1;
 end if;
 return calls;
end $$;
revoke all on function file_search.index_bucket(text), file_search.unindex_bucket(text),
 file_search.purge(uuid), file_search.purge_file(text,text),
 file_search.claim_files(integer,bigint), file_search.record_file_text(uuid,text,jsonb,text,jsonb),
 file_search.claim_chunks(integer,bigint), file_search.record_chunk_vector(uuid,text,text),
 file_search.expire_exhausted(), file_search.dispatch(),
 file_search.call_worker(text), file_search.record_worker_answers(), file_search.last_problem(uuid,uuid),
 file_search.has_work(text), file_search.job_running(text),
 file_search.failed_worker_runs(), file_search.worker_problems(),
 file_search.split_sentences(uuid), file_search.claim_sentences(integer), file_search.record_sentence_vector(uuid,text,text)
 from public, anon, authenticated;
grant execute on function file_search.failed_worker_runs(), file_search.worker_problems() to authenticated;

-- The part of a section a search returns. A section of at most p_cap characters comes back whole.
-- A longer one comes back as the p_cap characters around its hits, p_hits being the text of each
-- hit's chunk, best first. The worker cut those chunks from the section with its spaces and tabs
-- run together, so the part is taken from the section written the same way. A sheet's part starts
-- with the sheet's first row, its column names, and holds whole rows. Any other section's part holds
-- whole paragraphs where it can, else whole lines. A sheet whose first row alone takes more than half
-- of p_cap comes back without it. start and end place the part in the section, so before and after
-- are how many characters were left out on each side.
create or replace function file_search.section_part(p_body text, p_place text, p_hits text[], p_cap integer)
returns jsonb language plpgsql immutable set search_path=pg_catalog as $$
declare n text; len integer; head text:=''; first integer:=1; budget integer; h text; p integer;
 lo integer; hi integer; a integer; b integer; seps text[]; sep text; k integer; done boolean;
begin
 if length(p_body)<=p_cap then return jsonb_build_object('text', p_body, 'truncated', false); end if;
 n:=btrim(regexp_replace(regexp_replace(p_body, E'\r\n?', E'\n', 'g'), E'[ \t]+', ' ', 'g'), E' \n');
 len:=length(n);
 if p_place like 'sheet %' and strpos(n, E'\n')>0 then
  head:=left(n, strpos(n, E'\n')-1);
  first:=strpos(n, E'\n')+1;
  seps:=array[E'\n'];
  if length(head)+1>p_cap/2 then head:=''; first:=1; end if;
 else
  seps:=array[E'\n\n', E'\n'];
 end if;
 budget:=p_cap-length(head)-case when head='' then 0 else 1 end;
 -- The best hit first, then each further hit while the span holding them fits.
 foreach h in array coalesce(p_hits, '{}'::text[]) loop
  p:=strpos(n, h);
  if p=0 then p:=strpos(n, left(h, 100)); h:=left(h, 100); end if;
  if p=0 then continue; end if;
  if lo is null then lo:=greatest(p, first); hi:=greatest(p+length(h), lo);
  elsif greatest(hi, p+length(h))-least(lo, greatest(p, first))<=budget then
   lo:=least(lo, greatest(p, first)); hi:=greatest(hi, p+length(h));
  end if;
 end loop;
 if lo is null then lo:=first; hi:=first; end if;
 if hi-lo>budget then hi:=lo+budget; end if;
 a:=lo-(budget-(hi-lo))/2;
 if a<first then a:=first; end if;
 b:=a+budget;
 if b>len+1 then b:=len+1; a:=greatest(first, b-budget); end if;
 -- Whole rows or paragraphs: the start moves forward to the next break before the hits, and the end
 -- back to the last break after them.
 if a>first then
  done:=false;
  foreach sep in array seps loop
   exit when done;
   if substr(n, a-length(sep), length(sep))=sep then done:=true; continue; end if;
   k:=strpos(substr(n, a, lo-a+length(sep)), sep);
   if k>0 then a:=a+k-1+length(sep); done:=true; end if;
  end loop;
 end if;
 if b<=len then
  done:=false;
  foreach sep in array seps loop
   exit when done;
   if substr(n, b, length(sep))=sep then done:=true; continue; end if;
   k:=strpos(reverse(substr(n, hi, b-hi)), reverse(sep));
   if k>0 then b:=b-k-length(sep)+1; done:=true; end if;
  end loop;
 end if;
 return jsonb_build_object(
  'text', case when head='' then '' else head||E'\n' end||substr(n, a, b-a),
  'truncated', true, 'start', a-1, 'end', b-1, 'length', len,
  'before', a-first, 'after', len+1-b);
end $$;
revoke all on function file_search.section_part(text,text,text[],integer) from public, anon;
grant execute on function file_search.section_part(text,text,text[],integer) to authenticated;

-- Search, run as the signed-in user, so Storage's rules decide which files it covers. The
-- lexical half is PostgreSQL full-text search; the semantic half compares the question's
-- vector, made by the file-search hosted function, with each chunk's by cosine similarity. The
-- graph half finds the entities closest to the question's vector, walks their relations two steps
-- either way, and ranks the chunks behind the entities and relations it reached, each weighed by
-- its seed's similarity over one more than its steps. It sees an entity or a relation only through
-- a chunk the user can open, of the files searched. Reciprocal rank fusion merges the three. The
-- floor for weak semantic matches is off until it is measured on the project's own files.
-- A search across every bucket leaves out the buckets not searched by default, and runs the three
-- rankings and their fusion twice: once over the buckets ranked apart, returned as reference_hits,
-- and once over the rest, returned as hits. Each run keeps its own pool and its own limit.
-- Each hit gives its rank in each way that found it, its similarity where the meaning search found
-- it, and its graph weight where the graph found it. stages gives the graph walk as edges, each from
-- the entity it was walked from. An explained search also gives where each hit's chunk falls in its
-- section's text, and each hit's sentences placed there, with their similarity to the question from
-- the vectors the embed job stored. Its sections give their text again as marked, each of the
-- question's words between U+E000 and U+E001.
drop function if exists file_search.search(text,real[],text,integer);
create or replace function file_search.search(p_query text, p_embedding real[] default null,
 p_bucket text default null, p_limit integer default 10, p_explain boolean default false) returns jsonb
language plpgsql stable security invoker set search_path=pg_catalog as $$
declare q tsquery; v extensions.vector; result jsonb; e_started timestamptz; e_list text; e_at integer; e_hit jsonb; e_text text;
 e_pos integer; e_upto integer; e_a integer; e_b integer; e_sentences jsonb; e_row record; e_found jsonb; e_waiting bigint;
 fusion_k constant integer:=60; pool constant integer:=50; meaning_floor constant double precision:=0;
 section_cap constant integer:=8000; seeds constant integer:=10; steps constant integer:=2;
begin
 if auth.uid() is null then raise exception 'Sign in to search files' using errcode='42501'; end if;
 if p_query is null or length(btrim(p_query)) not between 1 and 1000 then raise exception 'The question must be 1 through 1000 characters' using errcode='22023'; end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Limit must be 1 through 50' using errcode='22023'; end if;
 if p_embedding is not null and cardinality(p_embedding)<>384 then raise exception 'A question vector has 384 numbers' using errcode='22023'; end if;
 q:=websearch_to_tsquery('english'::regconfig, p_query);
 if p_embedding is not null then v:=p_embedding::extensions.vector; end if;
 with recursive latest as (
  select distinct on (f.object_id) f.version_id, f.object_id, f.state
  from file_search.file_version f where f.state not in ('retired','purged')
  order by f.object_id, f.queued_at desc),
 -- apart marks a file in a bucket ranked apart, in a search across every bucket.
 visible as (
  select l.version_id, l.state, o.bucket_id, o.name, p_bucket is null and coalesce(b.ranked_apart, false) as apart
  from latest l join storage.objects o on o.id=l.object_id
  left join file_search.indexed_bucket b on b.bucket_id=o.bucket_id
  where case when p_bucket is null then coalesce(b.searched_by_default, true) else o.bucket_id=p_bucket end),
 current_chunks as (
  select c.chunk_id, c.version_id, c.section_ordinal, c.place, c.body, c.words, c.embedding, c.state, s.bucket_id, s.name, s.apart
  from file_search.chunk c join visible s on s.version_id=c.version_id and s.state='extracted'),
 by_words as (
  select w.chunk_id, w.apart, w.rank from (
   select c.chunk_id, c.apart, row_number() over (partition by c.apart order by ts_rank_cd(c.words, q) desc, c.chunk_id) as rank
   from current_chunks c where c.words @@ q) w
  where w.rank<=pool),
 near as (
  (select c.chunk_id, c.apart, 1-(c.embedding operator(extensions.<=>) v) as similarity
   from current_chunks c where v is not null and c.embedding is not null and not c.apart
   order by c.embedding operator(extensions.<=>) v limit pool)
  union all
  (select c.chunk_id, c.apart, 1-(c.embedding operator(extensions.<=>) v) as similarity
   from current_chunks c where v is not null and c.embedding is not null and c.apart
   order by c.embedding operator(extensions.<=>) v limit pool)),
 by_meaning as (
  select n.chunk_id, n.apart, n.similarity, row_number() over (partition by n.apart order by n.similarity desc, n.chunk_id) as rank
  from near n where n.similarity>=meaning_floor),
 -- The graph, as far as it rests on the chunks searched, walked once for each run.
 entity_seen as (
  select distinct s.entity_id, c.apart from file_search.entity_source s join current_chunks c on c.chunk_id=s.chunk_id),
 seed as (
  select x.entity_id, x.apart, x.similarity from (
   select e.entity_id, s.apart, 1-(e.embedding operator(extensions.<=>) v) as similarity,
    row_number() over (partition by s.apart order by e.embedding operator(extensions.<=>) v, e.entity_id) as n
   from file_search.entity e join entity_seen s on s.entity_id=e.entity_id
   where v is not null and e.embedding is not null) x
  where x.n<=seeds),
 -- Each step follows the relations of the entities reached so far, either way, through their
 -- indexes, that rest on a chunk searched in the same run.
 walk(entity_id, from_id, relation_id, similarity, step, apart) as (
  select entity_id, null::uuid, null::uuid, similarity, 0, apart from seed
  union all
  select g.to_id, w.entity_id, g.relation_id, w.similarity, w.step+1, w.apart from walk w
  cross join lateral (
   select r.relation_id, r.target_id as to_id from file_search.relation r where r.source_id=w.entity_id
   union all
   select r.relation_id, r.source_id from file_search.relation r where r.target_id=w.entity_id) g
  where w.step<steps
   and exists (select 1 from file_search.relation_source s join current_chunks c on c.chunk_id=s.chunk_id
    where s.relation_id=g.relation_id and c.apart=w.apart)),
 -- Each entity and relation at the step of its strongest path, in each run.
 reached as (
  select distinct on (w.apart, w.entity_id) w.entity_id, w.apart, w.step, w.similarity/(w.step+1) as weight from walk w
  order by w.apart, w.entity_id, w.similarity/(w.step+1) desc, w.step),
 walked as (
  select distinct on (w.apart, w.relation_id) w.relation_id, w.from_id, w.entity_id as to_id, w.apart, w.step, w.similarity/w.step as weight from walk w where w.relation_id is not null
  order by w.apart, w.relation_id, w.similarity/w.step desc, w.step),
 graph_chunks as (
  select x.chunk_id, x.apart, sum(x.weight) as weight from (
   select s.chunk_id, r.apart, r.weight from reached r join file_search.entity_source s on s.entity_id=r.entity_id
   union all
   select s.chunk_id, w.apart, w.weight from walked w join file_search.relation_source s on s.relation_id=w.relation_id) x
  join current_chunks c on c.chunk_id=x.chunk_id and c.apart=x.apart group by x.chunk_id, x.apart having sum(x.weight)>0),
 by_graph as (
  select g.chunk_id, g.apart, g.weight, g.rank from (
   select g.chunk_id, g.apart, g.weight, row_number() over (partition by g.apart order by g.weight desc, g.chunk_id) as rank
   from graph_chunks g) g
  where g.rank<=pool),
 fused as (
  select x.chunk_id, x.apart, sum(1.0/(fusion_k+x.rank)) as score, array_agg(x.half order by x.half desc) as found,
   jsonb_build_object('words', max(x.rank) filter (where x.half='words'), 'meaning', max(x.rank) filter (where x.half='meaning'),
    'graph', max(x.rank) filter (where x.half='graph')) as ranks,
   max(x.measure) filter (where x.half='meaning') as similarity, max(x.measure) filter (where x.half='graph') as graph_weight
  from (select chunk_id, apart, rank, 'words' as half, null::double precision as measure from by_words
        union all select chunk_id, apart, rank, 'meaning', similarity from by_meaning
        union all select chunk_id, apart, rank, 'graph', weight from by_graph) x
  group by x.chunk_id, x.apart),
 top as (
  select t.* from (
   select f.chunk_id, f.apart, f.score, f.found, f.ranks, f.similarity, f.graph_weight, c.version_id, c.section_ordinal, c.bucket_id, c.name, c.place, c.body,
    row_number() over (partition by f.apart order by f.score desc, f.chunk_id) as pos
   from fused f join current_chunks c on c.chunk_id=f.chunk_id) t
  where t.pos<=p_limit),
 -- Each section a hit falls in, once, in the order of its best hit, the reference hits' first.
 hit_sections as (
  select x.version_id, x.ordinal, x.place, x.body, t.bucket_id, t.name, t.apart, min(t.pos) as best,
   array_agg(t.body order by t.pos) as hit_bodies
  from top t join file_search.section x on x.version_id=t.version_id and x.ordinal=t.section_ordinal
  group by x.version_id, x.ordinal, x.place, x.body, t.bucket_id, t.name, t.apart),
 numbered as (select h.*, (row_number() over (order by h.apart desc, h.best) - 1)::integer as idx from hit_sections h),
 -- Each section's part as returned, and its text again with the question's words marked.
 parts as (
  select n.*, x.part, case when p_explain and numnode(q)>0 then ts_headline('english'::regconfig, x.part->>'text', q,
    'HighlightAll=true, StartSel='||chr(57344)||', StopSel='||chr(57345)) end as marked
  from numbered n cross join lateral (select file_search.section_part(n.body, n.place, n.hit_bodies, section_cap) as part) x),
 hit as (
  select t.chunk_id, t.apart, t.score, jsonb_build_object(
     'bucket', t.bucket_id, 'file', t.name, 'place', t.place,
     'snippet', case when 'words'=any(t.found) then ts_headline('english'::regconfig, t.body, q, 'MaxFragments=1,MaxWords=40,MinWords=15') else left(t.body, 300) end,
     'found', to_jsonb(t.found), 'fusion_score', round(t.score::numeric, 6), 'ranks', t.ranks, 'chunk_id', t.chunk_id,
     'similarity', round(t.similarity::numeric, 4), 'graph_weight', round(t.graph_weight::numeric, 4),
     'section', p.idx)
     -- An explained search gives where the hit's chunk falls in its section's text, in characters
     -- from 0, its spaces matched as any run of spaces; null where the section's part leaves it out.
     || case when p_explain then jsonb_build_object('chunk', case when c.at>0 then jsonb_build_object('start', c.at-1, 'end', c.upto-1) end) else '{}'::jsonb end
     -- A hit the graph found names the entities and relations behind it that its run's walk reached.
     || case when 'graph'=any(t.found) then jsonb_build_object(
      -- Each name and type as the hit's own chunk spells it.
      'entities', coalesce((select jsonb_agg(jsonb_build_object('entity_id', s.entity_id, 'name', s.name, 'type', s.entity_type, 'steps', r.step, 'description', s.description)
        order by r.step, s.name) from reached r
        join file_search.entity_source s on s.entity_id=r.entity_id and s.chunk_id=t.chunk_id where r.apart=t.apart), '[]'::jsonb),
      'relations', coalesce((select jsonb_agg(jsonb_build_object('source', a.name, 'target', b.name, 'keywords', to_jsonb(s.keywords),
         'steps', w.step, 'description', s.description) order by w.step, a.name, b.name)
        from walked w join file_search.relation l on l.relation_id=w.relation_id
        join file_search.relation_source s on s.relation_id=w.relation_id and s.chunk_id=t.chunk_id
        join file_search.entity_source a on a.entity_id=l.source_id and a.chunk_id=t.chunk_id
        join file_search.entity_source b on b.entity_id=l.target_id and b.chunk_id=t.chunk_id
        where w.apart=t.apart), '[]'::jsonb))
      else '{}'::jsonb end as body
  from top t left join parts p on p.version_id=t.version_id and p.ordinal=t.section_ordinal
  cross join lateral (select case when p_explain then regexp_replace(regexp_replace(t.body, '([^[:alnum:][:space:]])', '\\\1', 'g'), '[[:space:]]+', '[[:space:]]+', 'g') end as pattern) r
  cross join lateral (select regexp_instr(p.part->>'text', r.pattern) as at, regexp_instr(p.part->>'text', r.pattern, 1, 1, 1) as upto) c)
 select jsonb_build_object(
  'hits', coalesce((select jsonb_agg(h.body order by h.score desc, h.chunk_id) from hit h where not h.apart), '[]'::jsonb),
  'reference_hits', coalesce((select jsonb_agg(h.body order by h.score desc, h.chunk_id) from hit h where h.apart), '[]'::jsonb),
  'sections', coalesce((select jsonb_agg(jsonb_build_object(
     'bucket', p.bucket_id, 'file', p.name, 'place', p.place)
     || p.part || case when p_explain then jsonb_build_object('marked', p.marked) else '{}'::jsonb end
     order by p.idx) from parts p), '[]'::jsonb),
  'stages', jsonb_build_object(
     'words', (select count(*) from by_words),
     'meaning', (select count(*) from by_meaning),
     'graph', (select count(*) from by_graph),
     -- Each seed's name and type as the earliest chunk its run searched spells it, the reference
     -- run's first.
     'graph_seeds', coalesce((select jsonb_agg(jsonb_build_object('entity_id', x.entity_id, 'name', n.name, 'type', n.entity_type, 'similarity', round(x.similarity::numeric, 4))
        order by x.apart desc, x.similarity desc, n.name) from seed x
        cross join lateral (select s.name, s.entity_type from file_search.entity_source s join current_chunks c on c.chunk_id=s.chunk_id
         where s.entity_id=x.entity_id and c.apart=x.apart order by s.saved_at, s.chunk_id limit 1) n), '[]'::jsonb),
     -- Each relation the walk took, from the entity it was walked from to the one it reached, at the
     -- step of its strongest path, the reference run's first. Its names and keywords are as the
     -- earliest chunk its run searched that holds the relation spells them.
     'graph_walk', coalesce((select jsonb_agg(jsonb_build_object('from', w.from_id, 'from_name', n.from_name, 'relation', w.relation_id,
        'keywords', to_jsonb(n.keywords), 'to', w.to_id, 'to_name', n.to_name, 'step', w.step, 'weight', round(w.weight::numeric, 4))
        order by w.apart desc, w.step, w.weight desc, n.from_name, n.to_name) from walked w
        cross join lateral (select a.name as from_name, b.name as to_name, s.keywords from file_search.relation_source s
         join current_chunks c on c.chunk_id=s.chunk_id and c.apart=w.apart
         join file_search.entity_source a on a.entity_id=w.from_id and a.chunk_id=s.chunk_id
         join file_search.entity_source b on b.entity_id=w.to_id and b.chunk_id=s.chunk_id
         where s.relation_id=w.relation_id order by s.saved_at, s.chunk_id limit 1) n), '[]'::jsonb),
     'suppressed', (select count(*) from near where similarity<meaning_floor),
     'fused', (select count(*) from fused),
     'returned', (select count(*) from top),
     'floor', case when meaning_floor>0 then meaning_floor end,
     'awaiting_text', (select count(*) from visible where state='waiting'),
     'failed_text', (select count(*) from visible where state='failed'),
     'unsupported', (select count(*) from visible where state='unsupported'),
     'no_text', (select count(*) from visible where state='no_text'),
     -- The files this user can open that search cannot read, newest first, each with its reason.
     'unreadable', coalesce((select jsonb_agg(jsonb_build_object('bucket', u.bucket_id, 'file', u.name, 'state', u.state, 'error', u.error)
        order by u.finished_at desc nulls last, u.name)
       from (select s.bucket_id, s.name, s.state, f.error, f.finished_at from visible s
        join file_search.file_version f on f.version_id=s.version_id
        where s.state in ('unsupported','no_text','failed')
        order by f.finished_at desc nulls last, s.name limit 20) u), '[]'::jsonb),
     'awaiting_vector', (select count(*) from current_chunks where state='waiting'),
     'failed_vector', (select count(*) from current_chunks where state='failed'),
     -- Chunks no agent has extracted the graph from yet, and entities still waiting for a vector.
     'awaiting_extraction', (select count(*) from current_chunks c
       where not exists (select 1 from file_search.chunk_extraction x where x.chunk_id=c.chunk_id)),
     'awaiting_entity_vector', (select count(*) from file_search.entity e join entity_seen x on x.entity_id=e.entity_id where e.state='waiting'),
     'failed_worker_runs', file_search.failed_worker_runs(),
     -- Each run that went wrong, with the files it claimed that this user can open. in_flight
     -- marks a file with a claim and no outcome: the run stopped while it was at that file.
     'worker_problems', coalesce((select jsonb_agg(jsonb_build_object(
        'job', p.job, 'called_at', p.called_at, 'answered_at', p.answered_at, 'status', p.status, 'problem', p.problem,
        'files', coalesce((select jsonb_agg(jsonb_build_object('bucket', f.bucket_id, 'file', f.name, 'in_flight', f.in_flight)
           order by f.bucket_id, f.name)
          from (select o.bucket_id, o.name, bool_or(k.recorded_at is null) as in_flight
           from file_search.worker_claim k join storage.objects o on o.id=k.object_id
           where k.call_id=p.call_id and (p_bucket is null or o.bucket_id=p_bucket)
           group by o.bucket_id, o.name) f), '[]'::jsonb))
        order by p.answered_at desc, p.call_id desc) from file_search.worker_problems() p), '[]'::jsonb)),
  'degraded', case when v is null then 'The semantic search did not run: no question vector was given.' end)
 into result;
 if p_explain then
  e_started:=clock_timestamp();
  -- Every hit's sentences in one read, since each read checks again which files the user may open.
  select coalesce(jsonb_object_agg(x.chunk_id, x.found), '{}'), coalesce(sum(x.waiting), 0) into e_found, e_waiting from (
   select s.chunk_id, count(*) filter (where s.state='waiting') as waiting,
    coalesce(jsonb_agg(jsonb_build_object(
      'pattern', regexp_replace(regexp_replace(s.body, '([^[:alnum:][:space:]])', '\\\1', 'g'), '[[:space:]]+', '[[:space:]]+', 'g'),
      'similarity', round(greatest(0, least(1, 1-(s.embedding operator(extensions.<=>) v)))::numeric, 4)) order by s.ordinal)
     filter (where s.state='embedded' and v is not null), '[]') as found
   from file_search.chunk_sentence s
   where s.chunk_id=any(array(select (h->>'chunk_id')::uuid from jsonb_array_elements((result->'hits')||(result->'reference_hits')) h))
   group by s.chunk_id) x;
  foreach e_list in array array['hits','reference_hits'] loop
   for e_at in 0..jsonb_array_length(result->e_list)-1 loop
    e_hit:=result->e_list->e_at;
    continue when jsonb_typeof(e_hit->'chunk')<>'object';
    -- Each sentence placed in order from the chunk's start, its spaces matched as any run of spaces.
    e_text:=result->'sections'->((e_hit->>'section')::integer)->>'text';
    e_pos:=(e_hit->'chunk'->>'start')::integer+1; e_upto:=(e_hit->'chunk'->>'end')::integer+1; e_sentences:='[]';
    for e_row in select x->>'pattern' as pattern, x->'similarity' as similarity from jsonb_array_elements(coalesce(e_found->(e_hit->>'chunk_id'), '[]')) x loop
     e_a:=regexp_instr(e_text, e_row.pattern, e_pos);
     continue when e_a=0 or e_a>=e_upto;
     e_b:=regexp_instr(e_text, e_row.pattern, e_pos, 1, 1);
     e_sentences:=e_sentences||jsonb_build_object('start', e_a-1, 'end', e_b-1, 'similarity', e_row.similarity);
     e_pos:=e_b;
    end loop;
    result:=jsonb_set(result, array[e_list, e_at::text, 'sentences'], e_sentences);
   end loop;
  end loop;
  result:=jsonb_set(result, '{stages,awaiting_sentence_vector}', to_jsonb(e_waiting))
   || jsonb_build_object('explain_ms', round(extract(epoch from clock_timestamp()-e_started)*1000));
 end if;
 return jsonb_set(jsonb_set(result, '{hits}', coalesce((select jsonb_agg(h - 'chunk_id' order by n) from jsonb_array_elements(result->'hits') with ordinality e(h, n)), '[]'::jsonb)),
  '{reference_hits}', coalesce((select jsonb_agg(h - 'chunk_id' order by n) from jsonb_array_elements(result->'reference_hits') with ordinality e(h, n)), '[]'::jsonb));
end $$;
revoke all on function file_search.search(text,real[],text,integer,boolean) from public, anon;
grant execute on function file_search.search(text,real[],text,integer,boolean) to authenticated;

-- The upgrades this build already contains, so a new project has none pending.
insert into file_search.schema_upgrade(id) values ('0001-baseline') on conflict (id) do nothing;
