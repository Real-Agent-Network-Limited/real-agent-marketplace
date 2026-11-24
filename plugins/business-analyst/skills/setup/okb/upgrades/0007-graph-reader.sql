-- 0007-graph-reader
-- base: 5aa0584
-- redeploy: graph-reader
-- The graph reader, off until an administrator
-- keeps the firm's own Anthropic API key in the Vault with graph-reader's set_key: Graph reader, the actor it
-- saves as; the scopes it reads; okb_get_graph_reader and okb_get_file_parts; each read fitted to the glossary, with
-- what fits none dropped and kept; its 15-minute schedule, with the secret graph_reader_secret; and its batches in the
-- audit log. A person with read and create in a scope replaces Graph reader's save. The same text is in setup.sql and
-- schedule.sql. Apply file search's upgrade 0003-graph-reader first. Safe to run twice. Run as the postgres login.
-- Then deploy graph-reader with JWT verification off.

-- ===================================================================
-- 8y. The graph reader, off until the firm adds its own Anthropic API key.
-- ===================================================================
-- The hosted function graph-reader reads each waiting part of the firm's files with Claude, through Anthropic's
-- Message Batches API, every 15 minutes, and saves what it finds as the part's entities and relations, in the name of
-- Graph reader, an application actor with no sign-in. It is off until an administrator keeps the firm's own
-- Anthropic API key in the Vault with graph-reader's set_key, so the firm decides what goes to Claude, and pays
-- for it. Until then, and in the scopes it leaves out, a person's agent reads parts in the person's own Claude
-- subscription, as before. It reads no private scope's files, no sessions scope's, no Administration file, no
-- Guides file and no plugin scope's. Each entity's type is one of the glossary's classes and each relation one of its
-- relationships; a finding that fits none is dropped and kept with its reason. okb_get_graph_reader says whether it
-- is on and which scopes it reads, and okb_get_file_parts gives a file's parts, for a person to correct one. The
-- audit log gives each batch to administrators.
-- Owned by the postgres login, which owns file search and reads the Vault.

-- Graph reader's actor id, or null before its first save.
create or replace function okb_private.graph_reader_id() returns uuid
language sql stable set search_path=pg_catalog as $$
 select x.actor_id from okb.actor x
 where x.actor_kind='application' and x.auth_user_id is null and x.display_name='Graph reader' order by x.actor_id limit 1
$$;

-- Graph reader's actor id, made the first time, accountable to the first enabled administrator, who approves it.
create or replace function okb_private.graph_reader() returns uuid
language plpgsql volatile set search_path=pg_catalog as $$
declare id uuid:=okb_private.graph_reader_id(); admin uuid; previous text;
begin
 if id is not null then return id; end if;
 perform pg_advisory_xact_lock(hashtextextended('okb_private.graph_reader',19483));
 id:=okb_private.graph_reader_id();
 if id is not null then return id; end if;
 select x.actor_id into admin from okb.actor x
 where x.actor_kind='human' and x.authority_class='administrator' and x.enabled order by x.actor_id limit 1;
 if admin is null then raise exception 'OKB has no administrator yet' using errcode='55000'; end if;
 previous:=current_setting('okb.provisioning_actor',true);
 perform set_config('okb.provisioning_actor',admin::text,true);
 insert into okb.actor(display_name,actor_kind,accountable_human_id,authority_class,requires_human_approval,enabled)
 values('Graph reader','application',admin,'restricted',false,true) returning actor_id into id;
 perform set_config('okb.provisioning_actor',coalesce(previous,''),true);
 return id;
end $$;

-- The scopes whose files graph-reader reads, by their buckets' names: every enabled scope except private scopes,
-- sessions scopes, the Administration and Guides scopes, the Plugins scope and each workflow plugin's scope.
create or replace function okb_private.graph_reader_buckets() returns text[]
language sql stable set search_path=pg_catalog as $$
 select coalesce(array_agg(s.code order by s.code),'{}') from okb.scope s
 where s.enabled and not s.is_private and s.code not in ('administration','guides','plugins')
  and s.code not like 'sessions\_%' and s.code not like 'plugins\_%'
$$;

-- True once an administrator has kept the firm's Anthropic API key in the Vault with graph-reader's set_key.
create or replace function okb_private.graph_reader_on() returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select exists(select 1 from vault.decrypted_secrets where name='anthropic_api_key' and coalesce(decrypted_secret,'')<>'')
$$;

-- A read's entities and relations fitted to the glossary, as okb_save_extraction holds a person's: each entity's type
-- is a class, written as the glossary writes it, and each relation names a relationship from an entity of its from
-- class to one of its to class, with the relationship's name among its keywords. A finding that fits none is dropped,
-- with its reason, in place of refusing the part. Lists that are not lists are given back as they came.
create or replace function okb_private.fit_glossary(p_entities jsonb, p_relations jsonb) returns jsonb
language plpgsql stable set search_path=pg_catalog as $$
declare x jsonb; cls text; rel okb.glossary_term; types jsonb:='{}'::jsonb; src text; tgt text;
 ents jsonb:='[]'::jsonb; rels jsonb:='[]'::jsonb; dropped jsonb:='[]'::jsonb;
begin
 if jsonb_typeof(coalesce(p_entities,'null'))<>'array' or jsonb_typeof(coalesce(p_relations,'null'))<>'array' then
  return jsonb_build_object('entities',p_entities,'relations',p_relations,'dropped','[]'::jsonb);
 end if;
 for x in select value from jsonb_array_elements(p_entities) loop
  cls:=(select g.term from okb.glossary_term g where g.kind='class' and lower(g.term)=lower(btrim(coalesce(x->>'type',''))));
  if cls is null then
   dropped:=dropped||jsonb_build_array(jsonb_build_object('reason','An entity''s type is not a class in the glossary','item',x));
   continue;
  end if;
  ents:=ents||jsonb_build_array(x||jsonb_build_object('type',cls));
  -- A name given twice keeps its first class, as file search's trim keeps its first entity.
  if not types ? file_search.graph_key(x->>'name') then types:=types||jsonb_build_object(file_search.graph_key(x->>'name'),cls); end if;
 end loop;
 for x in select value from jsonb_array_elements(p_relations) loop
  select g.* into rel from okb.glossary_term g where g.kind='relationship' and lower(g.term)=lower(btrim(coalesce(x->>'relationship','')));
  if rel.term is null then
   dropped:=dropped||jsonb_build_array(jsonb_build_object('reason','A relation names no relationship in the glossary','item',x));
   continue;
  end if;
  src:=types->>file_search.graph_key(x->>'source'); tgt:=types->>file_search.graph_key(x->>'target');
  if src is not null and tgt is not null and (src<>rel.from_class or tgt<>rel.to_class) then
   dropped:=dropped||jsonb_build_array(jsonb_build_object('reason','A relation''s ends are not the classes its relationship joins','item',x));
   continue;
  end if;
  rels:=rels||jsonb_build_array(x||jsonb_build_object('keywords',jsonb_build_array(rel.term)||case jsonb_typeof(x->'keywords') when 'array' then x->'keywords' else '[]'::jsonb end));
 end loop;
 return jsonb_build_object('entities',ents,'relations',rels,'dropped',dropped);
end $$;

-- Closes graph-reader's open batch with its results, each read fitted to the glossary, saved under Graph reader.
create or replace function okb_private.save_graph_batch(p_batch uuid, p_results jsonb, p_usage jsonb) returns jsonb
language plpgsql volatile set search_path=pg_catalog as $$
declare r jsonb; f jsonb; fitted jsonb:='[]'::jsonb;
begin
 if jsonb_typeof(coalesce(p_results,'null'))<>'array' then raise exception 'The results are a list' using errcode='22023'; end if;
 for r in select value from jsonb_array_elements(p_results) loop
  if r ? 'entities' then
   f:=okb_private.fit_glossary(r->'entities',r->'relations');
   r:=r||jsonb_build_object('entities',f->'entities','relations',f->'relations','dropped',f->'dropped');
  end if;
  fitted:=fitted||jsonb_build_array(r);
 end loop;
 return file_search.close_graph_batch(p_batch,fitted,p_usage,okb_private.graph_reader(),'Graph reader');
end $$;

-- Called every 15 minutes by the schedule schedule.sql sets up. Calls graph-reader while a batch is open, or, once
-- the firm's key is in the Vault and its glossary has a class, while a part waits and the month's cost is
-- under the cap.
create or replace function okb_private.graph_reader_dispatch() returns boolean
language plpgsql volatile set search_path=pg_catalog as $$
declare address text; secret text;
begin
 if to_regprocedure('file_search.graph_has_work(text[])') is null then return false; end if;
 if not okb_private.graph_reader_on() then return false; end if;
 if not exists(select 1 from file_search.graph_batch where closed_at is null)
    and not exists(select 1 from okb.glossary_term where kind='class') then return false; end if;
 select decrypted_secret into address from vault.decrypted_secrets where name='file_search_project_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='graph_reader_secret';
 if address is null or secret is null then
  raise exception 'The project address or the graph reader secret is missing from Vault: run schedule.sql' using errcode='55000';
 end if;
 if not file_search.graph_has_work(okb_private.graph_reader_buckets()) then return false; end if;
 perform net.http_post(url:=address||'/functions/v1/graph-reader', body:='{}'::jsonb,
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||secret), timeout_milliseconds:=150000);
 return true;
end $$;

-- Each batch graph-reader sent, and each it closed, with its drops by reason, for the audit log.
create or replace function okb_private.graph_batch_events(p_from timestamptz, p_to timestamptz)
returns table(at timestamptz, k text, event text, actor_id uuid, subject text, details jsonb)
language plpgsql stable security definer set search_path=pg_catalog as $$
begin
 if to_regclass('file_search.graph_batch') is null then return; end if;
 return query execute $q$
  select b.sent_at,'b:'||b.batch_id::text,'graph_batch_sent',okb_private.graph_reader_id(),
   format('%s parts sent to Claude',cardinality(b.chunks)),
   jsonb_build_object('batch_id',b.batch_id,'api_batch_id',b.api_batch_id,'model',b.model,'parts',cardinality(b.chunks))
  from file_search.graph_batch b where b.sent_at>=$1 and b.sent_at<$2
  union all
  select b.closed_at,'e:'||b.batch_id::text,'graph_batch_saved',okb_private.graph_reader_id(),
   format('%s parts saved, %s failed, %s findings dropped',b.saved,b.failed,b.dropped),
   jsonb_build_object('batch_id',b.batch_id,'api_batch_id',b.api_batch_id,'model',b.model,'parts',cardinality(b.chunks),
    'saved',b.saved,'failed',b.failed,'retried',b.retried,'input_tokens',b.input_tokens,'cache_write_tokens',b.cache_write_tokens,
    'cache_read_tokens',b.cache_read_tokens,'output_tokens',b.output_tokens,'cost_usd',b.cost_usd,'problem',b.problem,'dropped',b.dropped,
    'drops',coalesce((select jsonb_object_agg(r.reason,r.n) from (select d.reason,count(*)::int as n from file_search.graph_drop d
     where d.batch_id=b.batch_id group by d.reason) r),'{}'::jsonb))
  from file_search.graph_batch b where b.closed_at>=$1 and b.closed_at<$2 and b.sent_at is not null$q$ using p_from,p_to;
end $$;

revoke all on function okb_private.graph_reader_id(), okb_private.graph_reader(), okb_private.graph_reader_buckets(),
 okb_private.graph_reader_on(), okb_private.fit_glossary(jsonb,jsonb), okb_private.save_graph_batch(uuid,jsonb,jsonb),
 okb_private.graph_reader_dispatch(), okb_private.graph_batch_events(timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function okb_private.graph_reader_id() to okb_writer, okb_reader;
grant execute on function okb_private.graph_batch_events(timestamptz,timestamptz) to okb_reader;

-- Whether graph-reader is on, the scopes it reads, and, for an administrator, the month's cost and its cap. An agent
-- reads a part itself only where it is off, or the scope is not one it reads.
create or replace function okb.okb_get_graph_reader() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare a okb.actor; result jsonb; cost jsonb;
begin
 a:=okb_private.read_actor();
 result:=jsonb_build_object('on',okb_private.graph_reader_on(),
  'scopes',(select coalesce(jsonb_agg(s.code order by s.code),'[]'::jsonb) from unnest(okb_private.graph_reader_buckets()) s(code)
   where s.code in (select okb_storage.usable_buckets('read'))));
 if a.authority_class='administrator' and to_regclass('file_search.graph_settings') is not null then
  execute 'select jsonb_build_object(''month_cost_usd'',file_search.graph_month_cost(),''monthly_cap_usd'',s.monthly_cap_usd) from file_search.graph_settings s'
   into strict cost;
  result:=result||cost;
 end if;
 return result;
end $$;
revoke all on function okb.okb_get_graph_reader() from public, anon;
grant execute on function okb.okb_get_graph_reader() to authenticated;

-- Each part of a file in a scope, from p_from on, with its text and where its graph stands: read, with who saved it;
-- failed, with the reason; in a batch; or waiting. Needs read in the scope. A person reads a part's text and chunk_id
-- here to correct its graph with okb_save_extraction.
create or replace function okb.okb_get_file_parts(p_scope text, p_file text, p_from integer default 0, p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare sc okb.scope;
begin
 perform okb_private.read_actor();
 begin
  sc:=okb_private.named_scope(p_scope);
 exception when insufficient_privilege then sc:=null;
 end;
 if sc.code is null or sc.code not in (select okb_storage.usable_buckets('read')) then
  raise exception 'Scope unavailable: no scope has the id, code or name "%"',p_scope using errcode='42501';
 end if;
 if to_regprocedure('file_search.file_parts(text,text,integer,integer)') is null then
  raise exception 'File search''s graph reader is not set up yet: ask Real Agent to apply file search''s upgrade 0003-graph-reader' using errcode='55000';
 end if;
 return jsonb_build_object('scope',sc.display_name,'code',sc.code)||file_search.file_parts(sc.code,p_file,p_from,p_limit);
end $$;
revoke all on function okb.okb_get_file_parts(text,text,integer,integer) from public, anon;
grant execute on function okb.okb_get_file_parts(text,text,integer,integer) to authenticated;

-- okb_save_extraction, as section 8p holds it, with Graph reader's save replaceable by a person with read and create.
-- Saves the entities and relations the caller's agent read in one chunk, once. Needs read and
-- create in the chunk's scope. Each entity's type is a glossary class, named in any case, and is
-- saved as the glossary names it. Each relation names a glossary relationship, as relationship,
-- from an entity of its from class to one of its to class, and keeps the relationship's name among
-- its keywords. Each entity merges by its normalised name and type, and the save names the caller
-- as the actor who saved it. With p_replace, the actor who saved the chunk's extraction, or an
-- administrator, replaces it, and a person with read and create in the scope replaces Graph reader's.
create or replace function okb.okb_save_extraction(p_chunk uuid, p_entities jsonb, p_relations jsonb default '[]', p_replace boolean default false) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare a okb.actor; b text; saver uuid; x jsonb; cls text; rel okb.glossary_term; types jsonb:='{}'::jsonb;
 ents jsonb:='[]'::jsonb; rels jsonb:='[]'::jsonb; src text; tgt text;
begin
 a:=okb_private.current_actor();
 if to_regprocedure('file_search.save_extraction(uuid,jsonb,jsonb,uuid,text,boolean)') is null then
  raise exception 'File search''s graph is not set up yet: ask the administrator to run file-search.sql' using errcode='55000';
 end if;
 select v.bucket_id into b from file_search.chunk c join file_search.file_version v on v.version_id=c.version_id where c.chunk_id=p_chunk;
 if b is null or not exists(select 1 from okb.scope where code=b) or b not in (select okb_storage.usable_buckets('read')) then
  raise exception 'Chunk unavailable: no chunk with the id "%" in a scope you may read',p_chunk using errcode='42501';
 end if;
 if b not in (select okb_storage.usable_buckets('create')) then
  raise exception 'Saving a chunk''s entities and relations needs create permission in its scope' using errcode='42501';
 end if;
 if coalesce(p_replace,false) then
  select x.saved_by into saver from file_search.chunk_extraction x where x.chunk_id=p_chunk;
  if saver is not null and saver<>a.actor_id and a.authority_class<>'administrator' and saver is distinct from okb_private.graph_reader_id() then
   raise exception 'Only the actor who saved this chunk''s entities and relations, or an administrator, may replace them: %',okb_private.actor_name(saver) using errcode='42501';
  end if;
 end if;
 if jsonb_typeof(coalesce(p_entities,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_relations,'[]'::jsonb))<>'array' then
  raise exception 'Entities and relations are each a list' using errcode='22023';
 end if;
 for x in select value from jsonb_array_elements(coalesce(p_entities,'[]'::jsonb)) loop
  cls:=(select g.term from okb.glossary_term g where g.kind='class' and lower(g.term)=lower(btrim(coalesce(x->>'type',''))));
  if cls is null then
   raise exception 'The entity "%" has the type "%", which is not a class in the glossary. An entity''s type is one of the classes okb_get_unextracted lists',
    x->>'name',coalesce(x->>'type','') using errcode='23514';
  end if;
  ents:=ents||jsonb_build_array(x||jsonb_build_object('type',cls));
  types:=types||jsonb_build_object(file_search.graph_key(x->>'name'),cls);
 end loop;
 for x in select value from jsonb_array_elements(coalesce(p_relations,'[]'::jsonb)) loop
  select g.* into rel from okb.glossary_term g where g.kind='relationship' and lower(g.term)=lower(btrim(coalesce(x->>'relationship','')));
  if rel.term is null then
   raise exception 'The relation from "%" to "%" names "%", which is not a relationship in the glossary. A relation names one of the relationships okb_get_unextracted lists',
    x->>'source',x->>'target',coalesce(x->>'relationship','') using errcode='23514';
  end if;
  src:=types->>file_search.graph_key(x->>'source'); tgt:=types->>file_search.graph_key(x->>'target');
  if src is not null and tgt is not null and (src<>rel.from_class or tgt<>rel.to_class) then
   raise exception 'The relationship "%" goes from a % to a %, and "%" is a % and "%" a %',rel.term,rel.from_class,rel.to_class,
    x->>'source',src,x->>'target',tgt using errcode='23514';
  end if;
  rels:=rels||jsonb_build_array(x||jsonb_build_object('keywords',jsonb_build_array(rel.term)||case jsonb_typeof(x->'keywords') when 'array' then x->'keywords'
   when 'string' then to_jsonb(string_to_array(x->>'keywords',',')) else '[]'::jsonb end));
 end loop;
 return file_search.save_extraction(p_chunk,ents,rels,a.actor_id,a.display_name,coalesce(p_replace,false));
end $$;

-- The audit log, with each batch graph-reader sent and closed, as graph_batch_sent and graph_batch_saved, to
-- administrators.
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
  from okb.sign_in_setting_change q2 where q2.at>=p_from and q2.at<p_to and a.authority_class='administrator'
  union all
  select g.at,g.k,g.event,null::uuid,g.actor_id,g.subject,null::text,g.details
  from okb_private.graph_batch_events(p_from,p_to) g where a.authority_class='administrator'),
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

-- The schedule, as schedule.sql sets it: the secret, then a call every 15 minutes, which does nothing while the
-- graph reader is off.
select vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'graph_reader_secret',
 'Shared secret the schedule sends to the graph-reader hosted function')
where not exists (select 1 from vault.decrypted_secrets where name = 'graph_reader_secret');
select cron.schedule('graph-reader', '*/15 * * * *', 'select okb_private.graph_reader_dispatch()');

insert into okb_private.schema_upgrade(id) values ('0007-graph-reader') on conflict (id) do nothing;
