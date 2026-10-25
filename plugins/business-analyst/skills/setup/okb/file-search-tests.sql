-- file_search checks 1.2.0
-- File search: checks that file-search.sql works as its skill says, installed as a stored
-- function. Install this file as postgres, after file-search.sql, then run the checks with:
--   select file_search.run_checks();
-- Installing again replaces the checks. Only postgres may run them. Like the project's own tests,
-- a run always ends with an error, so that nothing it creates is kept: "PASS: file search checks
-- passed" when every check passed. It adds a rule of its own for the run, under which users see
-- only their own files.

create or replace function file_search.run_checks() returns void language plpgsql
 set search_path = pg_catalog, public, extensions, storage, auth, file_search as $checks$
declare mine uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); obj uuid; obj2 uuid; old_file uuid; fv uuid; fv2 uuid; n bigint; res jsonb; calls bigint; call1 bigint; call2 bigint; obj3 uuid; obj4 uuid; obj5 uuid; fv5 uuid; sheet text;
 ga uuid; gb uuid; fva uuid; fvb uuid; ca uuid; cb uuid; supplier real[]:=array_fill(0::real, array[384]);
 near real[]:=array_fill(0::real, array[384]); far real[]:=array_fill(0::real, array[384]);
 as_user text:='select file_search.search(%L, %L::real[])'; in_bucket text:='select file_search.search(%L, null, %L)';
begin
 near[2]:=1; far[1]:=1; supplier[3]:=1;
 insert into auth.users(id) values (mine), (other);
 insert into storage.buckets(id, name, public) values ('fs_check', 'fs_check', false), ('fs_check_two', 'fs_check_two', false), ('fs_check_plain', 'fs_check_plain', false);
 insert into file_search.indexed_bucket(bucket_id) values ('fs_check'), ('fs_check_two');
 create policy "File search check: users see their own files" on storage.objects for select to authenticated
  using (bucket_id in ('fs_check','fs_check_two','fs_check_plain') and owner_id = auth.uid()::text);

 -- A file is queued once its content lands, once per content, and only in an indexed bucket.
 insert into storage.objects(bucket_id, name, owner_id) values ('fs_check', 'prices.pdf', mine::text) returning id into obj;
 if exists(select 1 from file_search.file_version where object_id=obj) then raise exception 'FAIL a file was queued before its content landed'; end if;
 update storage.objects set metadata='{"eTag":"e1"}' where id=obj;
 update storage.objects set metadata='{"eTag":"e1","lastModified":"x"}' where id=obj;
 if (select count(*) from file_search.file_version where object_id=obj)<>1 then raise exception 'FAIL one upload was not queued exactly once'; end if;
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_plain', 'other.pdf', mine::text, '{"eTag":"p1"}');
 if exists(select 1 from file_search.file_version v join storage.objects o on o.id=v.object_id where o.bucket_id='fs_check_plain') then
  raise exception 'FAIL a file outside the indexed buckets was queued'; end if;

 -- The worker takes the text as chunks, and records each vector as it is made.
 select version_id into fv from file_search.claim_files(20) where bucket_id='fs_check';
 if fv is null then raise exception 'FAIL a waiting file was not claimed'; end if;
 perform file_search.record_file_text(fv, 'extracted', jsonb_build_array(
  jsonb_build_object('ordinal',0,'place','page 1','body','Wholesale price list for spring bedding, including duvets.','section',0),
  jsonb_build_object('ordinal',1,'place','page 2','body','Delivery charges apply to orders under fifty pounds.','section',1)), null,
  jsonb_build_array(
  jsonb_build_object('ordinal',0,'place','page 1','body','Wholesale price list for spring bedding, including duvets.'),
  jsonb_build_object('ordinal',1,'place','page 2','body','Delivery charges apply to orders under fifty pounds.')));
 -- The project's own chunks may be waiting too, so the checks claim until theirs come, or nothing is
 -- left to claim.
 n:=0;
 loop
  select count(*) filter (where k.version_id=fv), count(*) into calls, call1
  from file_search.claim_chunks(50) c join file_search.chunk k on k.chunk_id=c.chunk_id;
  n:=n+calls;
  exit when n>=2 or call1=0;
 end loop;
 if n<>2 then raise exception 'FAIL expected two chunks to embed, claimed %', n; end if;
 perform file_search.record_chunk_vector(k.chunk_id, (case when k.ordinal=0 then far else near end)::extensions.vector::text, null)
  from file_search.chunk k where k.version_id=fv;
 if exists(select 1 from file_search.chunk where version_id=fv and state<>'embedded') then raise exception 'FAIL a vector was not recorded'; end if;
 -- Text without its sections, from a worker older than this file, is refused and the file waits.
 begin
  perform file_search.record_file_text(fv, 'extracted', '[]'::jsonb, null);
  raise exception 'FAIL text without its sections was recorded';
 exception when invalid_parameter_value then null;
 end;

 -- The owner finds the file by keyword, by meaning, and by both; another user finds nothing.
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'duvets', null) into res;
 if res->'hits'->0->>'place'<>'page 1' or res->'hits'->0->'found'<>'["words"]'::jsonb or res->>'degraded' is null then raise exception 'FAIL by keyword: %', res; end if;
 execute format(as_user, 'carriage fees', near) into res;
 if res->'hits'->0->>'place'<>'page 2' or res->'hits'->0->'found'<>'["meaning"]'::jsonb or res->>'degraded' is not null then raise exception 'FAIL by meaning: %', res; end if;
 execute format(as_user, 'delivery', near) into res;
 if res->'hits'->0->'found'<>'["words", "meaning"]'::jsonb then raise exception 'FAIL by both: %', res; end if;
 -- Each hit names its section, which comes back whole, once.
 if res->'sections'->((res->'hits'->0->>'section')::integer)->>'text'<>'Delivery charges apply to orders under fifty pounds.'
  or res->'sections'->((res->'hits'->0->>'section')::integer)->>'truncated'<>'false'
  or jsonb_array_length(res->'sections')<>(select count(distinct h->>'section') from jsonb_array_elements(res->'hits') h) then
  raise exception 'FAIL a hit''s section: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'duvets', far) into res;
 if jsonb_array_length(res->'hits')<>0 then raise exception 'FAIL another user found a file they cannot open: %', res; end if;
 if (select count(*) from file_search.chunk)<>0 then raise exception 'FAIL another user read chunks directly'; end if;
 if jsonb_array_length(res->'sections')<>0 or (select count(*) from file_search.section)<>0 then raise exception 'FAIL another user read a section of a file they cannot open: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A search for one bucket returns only that bucket's files.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_two', 'bedding.txt', mine::text, '{"eTag":"t1"}') returning id into obj2;
 select version_id into fv2 from file_search.claim_files(20) where bucket_id='fs_check_two';
 perform file_search.record_file_text(fv2, 'extracted', jsonb_build_array(
  jsonb_build_object('ordinal',0,'place',null,'body','Duvets for the second bucket.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Duvets for the second bucket. '||repeat('More of the same. ', 1000))));
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'duvets', null) into res;
 if jsonb_array_length(res->'hits')<>2 then raise exception 'FAIL an unfiltered search did not cover both buckets: %', res; end if;
 execute format(in_bucket, 'duvets', 'fs_check') into res;
 if jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'bucket'<>'fs_check' then raise exception 'FAIL a search for one bucket returned another''s files: %', res; end if;
 -- A section longer than a search returns whole comes back cut, and says so.
 execute format(in_bucket, 'duvets', 'fs_check_two') into res;
 if res->'sections'->0->>'truncated'<>'true' or length(res->'sections'->0->>'text')>=length('Duvets for the second bucket. '||repeat('More of the same. ', 1000)) then
  raise exception 'FAIL a long section was not cut: %', left(res::text, 300); end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A hit in the last row of a 20,000-character sheet returns that row, under the sheet's first row,
 -- in a part of the sheet that holds whole rows and says where it falls.
 sheet:='sku_code,name,description'||E'\n'||(select string_agg(format('SKU-%s,Product number %s,Plain words about this product',lpad(i::text,4,'0'),i),E'\n' order by i) from generate_series(1,350) i)
  ||E'\nMK-BAG-JUM-01,JUMEIRAH TOTE BAG,A red tote bag with a printed logo';
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check', 'sku.xlsx', mine::text, '{"eTag":"s1"}') returning id into obj5;
 select version_id into fv5 from file_search.claim_files(20) where name='sku.xlsx';
 perform file_search.record_file_text(fv5, 'extracted', jsonb_build_array(
  jsonb_build_object('ordinal',0,'place','sheet sku','body',left(sheet, 1200),'section',0),
  jsonb_build_object('ordinal',1,'place','sheet sku','body',right(sheet, 1200),'section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place','sheet sku','body',sheet)));
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(in_bucket, 'jumeirah', 'fs_check') into res;
 if length(sheet)<20000 or res->'sections'->0->>'truncated'<>'true' or length(res->'sections'->0->>'text')>8000
  or split_part(res->'sections'->0->>'text', E'\n', 1)<>'sku_code,name,description'
  or split_part(res->'sections'->0->>'text', E'\n', 2) !~ '^SKU-[0-9]{4},Product number [0-9]+,Plain words about this product$'
  or right(res->'sections'->0->>'text', 67)<>E'\nMK-BAG-JUM-01,JUMEIRAH TOTE BAG,A red tote bag with a printed logo'
  or (res->'sections'->0->>'after')::integer<>0 or (res->'sections'->0->>'end')::integer<>length(sheet)
  or (res->'sections'->0->>'before')::integer<>(res->'sections'->0->>'start')::integer-length('sku_code,name,description')-1 then
  raise exception 'FAIL a hit in a long sheet''s last row did not come back under its first row: %', (res->'sections'->0)-'text'; end if;
 -- A sheet whose first row alone is longer than a search returns comes back as the rows around the hit, without it.
 if (file_search.section_part(repeat('wide_column_name,', 600)||E'\n'||repeat(E'row of plain words\n', 600)||'MK-BAG-JUM-01,JUMEIRAH TOTE BAG', 'sheet wide',
   array['MK-BAG-JUM-01,JUMEIRAH TOTE BAG'], 8000)->>'text') !~ E'^row of plain words\n.*\nMK-BAG-JUM-01,JUMEIRAH TOTE BAG$' then
  raise exception 'FAIL a sheet with a first row over the cap: %', left(file_search.section_part(repeat('wide_column_name,', 600)||E'\n'||repeat(E'row of plain words\n', 600)||'MK-BAG-JUM-01,JUMEIRAH TOTE BAG', 'sheet wide',
   array['MK-BAG-JUM-01,JUMEIRAH TOTE BAG'], 8000)::text, 300); end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A file moved out of the indexed buckets is retired, and moved back is found again.
 update storage.objects set bucket_id='fs_check_plain' where id=obj2;
 if exists(select 1 from file_search.file_version where object_id=obj2 and state<>'retired') then raise exception 'FAIL a file moved out of the indexed buckets was not retired'; end if;
 update storage.objects set bucket_id='fs_check_two' where id=obj2;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(in_bucket, 'duvets', 'fs_check_two') into res;
 if jsonb_array_length(res->'hits')<>1 then raise exception 'FAIL a file moved back into an indexed bucket was not found: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- Indexing a bucket queues the files already in it; un-indexing retires them.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_plain', 'older.pdf', mine::text, '{"eTag":"o1"}') returning id into old_file;
 perform file_search.index_bucket('fs_check_plain');
 if not exists(select 1 from file_search.file_version where object_id=old_file and state='waiting') then raise exception 'FAIL indexing a bucket did not queue the file already in it'; end if;
 perform file_search.unindex_bucket('fs_check_plain');
 if exists(select 1 from file_search.file_version where object_id=old_file and state<>'retired')
  or exists(select 1 from file_search.indexed_bucket where bucket_id='fs_check_plain') then raise exception 'FAIL un-indexing a bucket left its files searchable'; end if;

 -- A move keeps the file's chunks, under its new name; a replace is found only by its new content.
 update storage.objects set name='archive/prices-2026.pdf' where id=obj;
 update storage.objects set metadata='{"eTag":"e2"}', updated_at=clock_timestamp() where id=obj;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(in_bucket, 'duvets', 'fs_check') into res;
 if jsonb_array_length(res->'hits')<>0 or (res->'stages'->>'awaiting_text')::integer<>1 then raise exception 'FAIL a replaced file''s old content was found: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);
 select version_id into fv2 from file_search.claim_files(20) where bucket_id='fs_check';
 perform file_search.record_file_text(fv2, 'extracted', jsonb_build_array(
  jsonb_build_object('ordinal',0,'place','page 1','body','Autumn catalogue of wool blankets.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place','page 1','body','Autumn catalogue of wool blankets.')));
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'blankets', null) into res;
 if res->'hits'->0->>'file'<>'archive/prices-2026.pdf' then raise exception 'FAIL a moved file was not found under its new name: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- Each version knows where its file was last seen, and its text cannot be purged while the file is still there.
 if exists(select 1 from file_search.file_version where object_id=obj and (bucket_id, name) is distinct from ('fs_check', 'archive/prices-2026.pdf')) then
  raise exception 'FAIL a moved file''s versions do not know where it now is'; end if;
 n:=null;
 begin perform file_search.purge(obj); n:=0; exception when sqlstate '55000' then n:=1; end;
 if n<>1 then raise exception 'FAIL a file still in its bucket had its text purged'; end if;

 -- A deleted file is retired and found no more.
 -- Supabase refuses a SQL delete on its storage tables unless storage.allow_delete_query is set.
 n:=null;
 begin delete from storage.objects where id=obj; n:=0; exception when sqlstate '42501' then n:=1; end;
 if n<>1 then raise exception 'FAIL a SQL delete from storage.objects was not refused by Supabase''s guard'; end if;
 -- Stands in for the Storage API's delete, which Supabase's storage.protect_delete lets through.
 perform set_config('storage.allow_delete_query', 'true', true);
 delete from storage.objects where id=obj;
 if exists(select 1 from file_search.file_version where object_id=obj and state<>'retired') then raise exception 'FAIL a deleted file''s versions were not retired'; end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'blankets', null) into res;
 if jsonb_array_length(res->'hits')<>0 then raise exception 'FAIL a deleted file was still found: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A deleted file's text and embeddings stay until purged; purging deletes them and keeps its record.
 if not exists(select 1 from file_search.chunk where object_id=obj) then raise exception 'FAIL a deleted file''s text went before it was purged'; end if;
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check', 'archive/prices-2026.pdf', mine::text, '{"eTag":"n1"}') returning id into obj2;
 if file_search.purge_file('fs_check', 'archive/prices-2026.pdf')<1 then raise exception 'FAIL purging a deleted file by its last name deleted nothing'; end if;
 if exists(select 1 from file_search.file_version where object_id=obj2 and state='purged') then raise exception 'FAIL a new file under the same name was purged'; end if;
 if exists(select 1 from file_search.chunk where object_id=obj) then raise exception 'FAIL a purged file''s chunks remain'; end if;
 if not exists(select 1 from file_search.file_version where object_id=obj)
  or exists(select 1 from file_search.file_version where object_id=obj and state<>'purged') then raise exception 'FAIL a purged file''s record was not kept, marked purged'; end if;

 -- A replace that lands before the first content is read retires the first unread.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check', 'draft.pdf', mine::text, '{"eTag":"d1"}') returning id into obj;
 update storage.objects set metadata='{"eTag":"d2"}' where id=obj;
 if (select count(*) from file_search.claim_files(20) c join file_search.file_version v on v.version_id=c.version_id where v.object_id=obj)<>1 then
  raise exception 'FAIL both contents of a quickly replaced file were claimed'; end if;
 if (select state from file_search.file_version where object_id=obj and content_tag='d1')<>'retired' then raise exception 'FAIL a replaced content waiting for its text was not retired'; end if;

 -- A row claimed five times without an answer fails for good, and the search says so.
 update file_search.file_version set attempts=5, last_attempt_at=clock_timestamp()-interval '10 minutes', error=null where object_id=obj and state='waiting';
 if file_search.expire_exhausted()<1 then raise exception 'FAIL an exhausted row was not failed'; end if;
 if (select state||':'||error from file_search.file_version where object_id=obj and content_tag='d2') not like 'failed:No answer after five attempts%' then
  raise exception 'FAIL an exhausted row did not fail with its reason'; end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if (res->'stages'->>'failed_text')::integer<>1 then raise exception 'FAIL the search did not report the failed file: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);
 update storage.objects set metadata='{"eTag":"d2","lastModified":"again"}', updated_at=clock_timestamp() where id=obj;
 if (select state||':'||attempts from file_search.file_version where object_id=obj and content_tag='d2')<>'waiting:0' then
  raise exception 'FAIL re-uploading a failed file''s same content did not try it again'; end if;

 -- Each row a run claims is recorded against the run's call, and its outcome closes the claim.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check', 'stock.xlsx', mine::text, '{"eTag":"s1"}') returning id into obj3;
 insert into file_search.worker_call(request_id, job) values (-101, 'extract') returning call_id into call1;
 if (select count(*) from file_search.claim_files(20, call1) c join file_search.file_version v on v.version_id=c.version_id where v.object_id=obj3)<>1 then
  raise exception 'FAIL a waiting file was not claimed for a call'; end if;
 if (select count(*) from file_search.worker_claim where call_id=call1 and object_id=obj3 and chunk_id is null and recorded_at is null)<>1 then
  raise exception 'FAIL a claim was not recorded against its call'; end if;
 perform file_search.record_file_text(v.version_id, 'failed', null, 'Too large to read') from file_search.file_version v where v.object_id=obj3;
 if exists(select 1 from file_search.worker_claim where call_id=call1 and object_id=obj3 and recorded_at is null) then raise exception 'FAIL an outcome did not close its claim'; end if;
 -- A run stopped at a row leaves its claim open, and search names the file to those who can open it.
 update file_search.file_version set last_attempt_at=clock_timestamp()-interval '10 minutes' where object_id=obj3;
 insert into file_search.worker_call(request_id, job) values (-102, 'extract') returning call_id into call2;
 perform file_search.claim_files(20, call2);
 update file_search.worker_call set answered_at=clock_timestamp(), status=546, problem='WORKER_RESOURCE_LIMIT' where call_id=call2;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if not exists(select 1 from jsonb_array_elements(res->'stages'->'worker_problems') p
   where p->>'problem'='WORKER_RESOURCE_LIMIT' and (p->>'status')::integer=546
    and p->'files' @> '[{"bucket":"fs_check","file":"stock.xlsx","in_flight":true}]'::jsonb) then
  raise exception 'FAIL the search did not name the file a stopped run was at: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if not exists(select 1 from jsonb_array_elements(res->'stages'->'worker_problems') p where p->>'problem'='WORKER_RESOURCE_LIMIT')
  or exists(select 1 from jsonb_array_elements(res->'stages'->'worker_problems') p where p->'files'<>'[]'::jsonb)
  or (select count(*) from file_search.worker_claim)<>0 then
  raise exception 'FAIL another user saw a file a run claimed: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);
 -- A stopped run drops out of search once the row it was at is done. A run that claimed no row stays.
 n:=(res->'stages'->>'failed_worker_runs')::bigint;
 perform file_search.record_file_text(v.version_id, 'extracted', '[]'::jsonb, null, '[]'::jsonb) from file_search.file_version v where v.object_id=obj3;
 insert into file_search.worker_call(request_id, job, answered_at, status, problem) values (-104, 'embed', clock_timestamp(), 500, 'Boot failed');
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if exists(select 1 from jsonb_array_elements(res->'stages'->'worker_problems') p where p->>'problem'='WORKER_RESOURCE_LIMIT')
  or (res->'stages'->>'failed_worker_runs')::bigint<>n then
  raise exception 'FAIL a stopped run whose row was done still showed in search: %', res->'stages'; end if;
 if not exists(select 1 from jsonb_array_elements(res->'stages'->'worker_problems') p where p->>'problem'='Boot failed') then
  raise exception 'FAIL a failed run that claimed no row was not shown: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);
 update file_search.file_version set state='waiting', finished_at=null, error='Too large to read' where object_id=obj3;
 -- A row that fails for good names the run that took it, over a later run of its job.
 insert into file_search.worker_call(request_id, job, answered_at, status, problem) values (-103, 'extract', clock_timestamp()+interval '1 second', 500, 'Another file');
 update file_search.file_version set attempts=5, last_attempt_at=clock_timestamp()-interval '10 minutes' where object_id=obj3;
 perform file_search.expire_exhausted();
 if (select error from file_search.file_version where object_id=obj3) not like 'Too large to read%'
  or file_search.last_problem((select version_id from file_search.file_version where object_id=obj3), null)
   not like '. The last run that took it and went wrong, at %, answered 546: WORKER_RESOURCE_LIMIT' then
  raise exception 'FAIL a failed row did not name the run that took it: %',
   file_search.last_problem((select version_id from file_search.file_version where object_id=obj3), null); end if;

 -- A file of a type the worker does not read says why, and search lists it for its owner only.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check', 'notes.pages', mine::text, '{"eTag":"u1"}') returning id into obj4;
 perform file_search.claim_files(20);
 perform file_search.record_file_text(v.version_id, 'unsupported', null, null) from file_search.file_version v where v.object_id=obj4;
 if (select state||':'||coalesce(error, '') from file_search.file_version where object_id=obj4) not like 'unsupported:OKB reads PDF, %Save this file as one of those.' then
  raise exception 'FAIL an unsupported file did not say why: %', (select error from file_search.file_version where object_id=obj4); end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if (res->'stages'->>'unsupported')::integer<>1
  or not res->'stages'->'unreadable' @> jsonb_build_array(jsonb_build_object('bucket','fs_check','file','notes.pages','state','unsupported')) then
  raise exception 'FAIL the search did not list the file it cannot read: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format(as_user, 'anything', null) into res;
 if (res->'stages'->>'unsupported')::integer<>0 or res->'stages'->'unreadable'<>'[]'::jsonb then
  raise exception 'FAIL another user saw a file they cannot open listed as unreadable: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- The graph. A contract names a supplier and the SKU it supplies; a sheet names that SKU and the
 -- warehouse that holds it. Each chunk is saved once, by the user who may open it.
 -- A project may hold a graph of its own, so the checks count only the entities and relations their
 -- own files support.
 insert into storage.buckets(id, name, public) values ('fs_check_graph', 'fs_check_graph', false);
 insert into file_search.indexed_bucket(bucket_id) values ('fs_check_graph');
 alter policy "File search check: users see their own files" on storage.objects
  using (bucket_id in ('fs_check','fs_check_two','fs_check_plain','fs_check_graph') and owner_id = auth.uid()::text);
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_graph', 'contract.txt', mine::text, '{"eTag":"g1"}') returning id into ga;
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_graph', 'sku-sheet.txt', mine::text, '{"eTag":"g2"}') returning id into gb;
 select version_id into fva from file_search.file_version where object_id=ga;
 select version_id into fvb from file_search.file_version where object_id=gb;
 perform file_search.claim_files(20);
 perform file_search.record_file_text(fva, 'extracted', jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Northfield Packaging supplies the shipper cartons for SKU HT-01.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Northfield Packaging supplies the shipper cartons for SKU HT-01.')));
 perform file_search.record_file_text(fvb, 'extracted', jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','HT-01 is stored at the Basildon site.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','HT-01 is stored at the Basildon site.')));
 select chunk_id into ca from file_search.chunk where version_id=fva;
 select chunk_id into cb from file_search.chunk where version_id=fvb;
 perform file_search.record_chunk_vector(k.chunk_id, far::extensions.vector::text, null) from file_search.chunk k where k.chunk_id in (ca, cb);
 res:=file_search.unextracted('fs_check_graph', 50);
 if (res->>'waiting')::integer<>2 or res->'chunks'->0->>'file'<>'contract.txt' or res->'chunks'->0->>'text' not like 'Northfield%' then
  raise exception 'FAIL the chunks waiting for their graph: %', res; end if;
 res:=file_search.save_extraction(ca, jsonb_build_array(
   jsonb_build_object('name','Northfield Packaging','type','Supplier','description','Supplies shipper cartons.'),
   jsonb_build_object('name','HT-01','type','Product','description','A SKU in cartons from Northfield Packaging.')),
  jsonb_build_array(jsonb_build_object('source','Northfield Packaging','target','HT-01','keywords','supplies, cartons','description','Northfield Packaging supplies HT-01''s cartons.')),
  mine, 'Check user');
 if res->>'saved'<>'true' or (res->>'entities')::integer<>2 or (res->>'relations')::integer<>1 then raise exception 'FAIL the first save: %', res; end if;
 -- A save never says whether an entity already existed, which another bucket may hold, and a
 -- relation keeps its keywords only with each chunk that gave them.
 if res ? 'merged' or exists(select 1 from information_schema.columns where table_schema='file_search' and table_name='relation' and column_name='keywords') then
  raise exception 'FAIL a save or a shared relation tells of other buckets: %', res; end if;
 -- The same name in another case, with other spaces, and the same type, merges; each source keeps its own description.
 res:=file_search.save_extraction(cb, jsonb_build_array(
   jsonb_build_object('name',' ht-01 ','type','product','description','Stored at the Basildon site.'),
   jsonb_build_object('name','Basildon','type','Warehouse','description','Holds HT-01.')),
  jsonb_build_array(jsonb_build_object('source','Basildon','target','HT-01','keywords',jsonb_build_array('stores'),'description','Basildon stores HT-01.')),
  mine, 'Check user');
 if (select count(*) from file_search.entity where name_key='ht-01')<>1
  or (select count(*) from file_search.entity_source s join file_search.entity e using (entity_id) where e.name_key='ht-01')<>2 then
  raise exception 'FAIL an entity of the same normalised name and type did not merge: %', res; end if;
 -- A chunk is saved once, unless it is replaced. A replacement deletes what only the earlier one
 -- supported, and keeps what other chunks support.
 if file_search.save_extraction(ca, '[]', '[]', mine, 'Check user')->>'saved'<>'false' then raise exception 'FAIL a chunk was saved twice'; end if;
 res:=file_search.save_extraction(cb, jsonb_build_array(jsonb_build_object('name','Basildn','type','Warehouse','description','A misread name.')), '[]', mine, 'Check user', true);
 if res->>'replaced'<>'true' or exists(select 1 from file_search.entity where name_key='basildon')
  or (select count(*) from file_search.entity_source s join file_search.entity e using (entity_id) where e.name_key='ht-01')<>1
  or exists(select 1 from file_search.relation_source where chunk_id=cb) then
  raise exception 'FAIL replacing a chunk''s extraction: %', res; end if;
 res:=file_search.save_extraction(cb, jsonb_build_array(
   jsonb_build_object('name',' ht-01 ','type','product','description','Stored at the Basildon site.'),
   jsonb_build_object('name','Basildon','type','Warehouse','description','Holds HT-01.')),
  jsonb_build_array(jsonb_build_object('source','Basildon','target','HT-01','keywords',jsonb_build_array('stores'),'description','Basildon stores HT-01.')),
  mine, 'Check user', true);
 if exists(select 1 from file_search.entity where name_key='basildn') or (select count(distinct s.entity_id) from file_search.entity_source s join storage.objects o on o.id=s.object_id where o.bucket_id='fs_check_graph')<>3 then
  raise exception 'FAIL a second replacement: %', res; end if;
 if (file_search.unextracted('fs_check_graph', 50)->>'waiting')::integer<>0 then raise exception 'FAIL a saved chunk still waits'; end if;
 -- A relation must join two entities the chunk names.
 begin perform file_search.save_extraction(k.chunk_id, jsonb_build_array(jsonb_build_object('name','A','type','T','description','d')),
   jsonb_build_array(jsonb_build_object('source','A','target','Nobody','description','d')), mine, null)
  from file_search.chunk k where k.version_id=fv5 limit 1; n:=0;
 exception when invalid_parameter_value then n:=1; end;
 if n<>1 then raise exception 'FAIL a relation to an entity the chunk does not name was saved'; end if;
 -- The worker makes each entity's vector from its name and type alone, never from a description a
 -- file gave it.
 if not file_search.has_work('graph') then raise exception 'FAIL entities without a vector are not work for the graph job'; end if;
 -- The project's own entities may be waiting too, older than the checks', so the checks claim until
 -- theirs comes, or nothing is left to claim.
 n:=0;
 loop
  select count(*) filter (where c.body='Northfield Packaging (Supplier)'), count(*) into calls, call1 from file_search.claim_entities(50) c;
  n:=n+calls;
  exit when calls>0 or call1=0;
 end loop;
 if n=0 then
  raise exception 'FAIL an entity''s text for its vector'; end if;
 perform file_search.record_entity_vector(e.entity_id, (case when e.name_key='northfield packaging' then supplier else far end)::extensions.vector::text, null)
  from file_search.entity e where exists(select 1 from file_search.entity_source s join storage.objects o on o.id=s.object_id where s.entity_id=e.entity_id and o.bucket_id='fs_check_graph');
 if exists(select 1 from file_search.entity e where e.state<>'embedded' and exists(select 1 from file_search.entity_source s join storage.objects o on o.id=s.object_id where s.entity_id=e.entity_id and o.bucket_id='fs_check_graph')) then raise exception 'FAIL an entity''s vector was not recorded'; end if;

 -- A question near the supplier reaches the warehouse's sheet two steps away, through the SKU.
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 -- A search that is not explained marks no section and places no chunk.
 execute format('select file_search.search(%L, %L::real[], %L)', 'which site holds the stock', supplier, 'fs_check_graph') into res;
 if exists(select 1 from jsonb_array_elements(res->'hits') h where h ? 'chunk' or h ? 'sentences')
  or exists(select 1 from jsonb_array_elements(res->'sections') x where x ? 'marked') then
  raise exception 'FAIL a search that is not explained gave marks or chunks: %', res; end if;
 execute format('select file_search.search(%L, %L::real[], %L, 10, true)', 'which site holds the stock', supplier, 'fs_check_graph') into res;
 if not exists(select 1 from jsonb_array_elements(res->'hits') h where h->>'file'='sku-sheet.txt' and h->'found' ? 'graph'
   and exists(select 1 from jsonb_array_elements(h->'entities') e where e->>'name'='Basildon' and (e->>'steps')::integer=2)
   and exists(select 1 from jsonb_array_elements(h->'relations') r where r->>'description'='Basildon stores HT-01.'))
  or (res->'stages'->>'graph')::integer<>2 or res->'stages'->'graph_seeds'->0->>'name'<>'Northfield Packaging' then
  raise exception 'FAIL the graph did not reach the warehouse''s sheet: %', res; end if;
 -- The hit gives its rank in each way that found it, its similarity, its graph weight, where its
 -- chunk falls in its section, and each entity's id. Its section gives the question's words marked.
 if not exists(select 1 from jsonb_array_elements(res->'hits') h where h->>'file'='sku-sheet.txt'
   and h->'ranks'->'words'='null'::jsonb and (h->'ranks'->>'meaning')::integer>=1 and (h->'ranks'->>'graph')::integer>=1
   and jsonb_typeof(h->'similarity')='number' and (h->>'graph_weight')::numeric=1.3333
   and h->'chunk'='{"start": 0, "end": 37}'::jsonb
   and exists(select 1 from jsonb_array_elements(h->'entities') e where e->>'name'='Basildon'
    and e->>'entity_id'=(select entity_id::text from file_search.entity where name_key='basildon')))
  or not exists(select 1 from jsonb_array_elements(res->'sections') x where x->>'file'='sku-sheet.txt'
   and x->>'marked'='HT-01 is stored at the Basildon '||chr(57344)||'site'||chr(57345)||'.' and x->>'text'='HT-01 is stored at the Basildon site.') then
  raise exception 'FAIL a hit''s ranks, similarity, graph weight, chunk or marks: %', res; end if;
 -- The walk, as its edges: from the supplier to the SKU at step 1, and on to the warehouse at step 2,
 -- each name as the chunk that holds the relation spells it.
 if res->'stages'->'graph_walk'<>jsonb_build_array(
   jsonb_build_object('from', (select entity_id from file_search.entity where name_key='northfield packaging'), 'from_name', 'Northfield Packaging',
    'relation', (select r.relation_id from file_search.relation r join file_search.entity e on e.entity_id=r.source_id where e.name_key='northfield packaging'),
    'keywords', '["cartons", "supplies"]'::jsonb, 'to', (select entity_id from file_search.entity where name_key='ht-01'), 'to_name', 'HT-01', 'step', 1, 'weight', 1.0000),
   jsonb_build_object('from', (select entity_id from file_search.entity where name_key='ht-01'), 'from_name', 'ht-01',
    'relation', (select r.relation_id from file_search.relation r join file_search.entity e on e.entity_id=r.source_id where e.name_key='basildon'),
    'keywords', '["stores"]'::jsonb, 'to', (select entity_id from file_search.entity where name_key='basildon'), 'to_name', 'Basildon', 'step', 2, 'weight', 0.5000))
  or res->'stages'->'graph_seeds'->0->>'entity_id'<>(select entity_id::text from file_search.entity where name_key='northfield packaging') then
  raise exception 'FAIL the graph walk''s edges or seeds: %', res->'stages'; end if;
 -- A question with no words to search marks no section.
 execute format('select file_search.search(%L, %L::real[], %L, 10, true)', 'the of a', supplier, 'fs_check_graph') into res;
 if jsonb_array_length(res->'sections')=0 or exists(select 1 from jsonb_array_elements(res->'sections') x where x->'marked'<>'null'::jsonb) then
  raise exception 'FAIL a question with no words to search marked a section: %', res->'sections'; end if;
 if (select count(*) from file_search.entity)<>3 or (select count(*) from file_search.relation)<>2 then raise exception 'FAIL the owner does not see the graph of their files'; end if;
 execute 'reset role';
 -- Another user sees no entity or relation, and the graph finds them nothing.
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 if (select count(*) from file_search.entity)<>0 or (select count(*) from file_search.relation)<>0
  or (select count(*) from file_search.entity_source)<>0 or (select count(*) from file_search.chunk_extraction)<>0 then
  raise exception 'FAIL another user saw the graph of files they cannot open'; end if;
 execute format('select file_search.search(%L, %L::real[])', 'which site holds the stock', supplier) into res;
 if (res->'stages'->>'graph')::integer<>0 or jsonb_array_length(res->'stages'->'graph_seeds')<>0 then raise exception 'FAIL another user''s search used the graph: %', res->'stages'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- Purging the contract deletes the supplier and its relation, and keeps the SKU and the warehouse,
 -- which the sheet still supports.
 perform set_config('storage.allow_delete_query', 'true', true);
 delete from storage.objects where id=ga;
 perform file_search.purge(ga);
 if exists(select 1 from file_search.entity where name_key='northfield packaging')
  or exists(select 1 from file_search.relation r join file_search.entity e on e.entity_id in (r.source_id, r.target_id) where e.name_key='northfield packaging')
  or not exists(select 1 from file_search.entity where name_key='ht-01') or not exists(select 1 from file_search.entity where name_key='basildon')
  or (select count(distinct s.relation_id) from file_search.relation_source s join storage.objects o on o.id=s.object_id where o.bucket_id='fs_check_graph')<>1 or (select count(*) from file_search.entity_source s join file_search.entity e using (entity_id) where e.name_key='ht-01')<>1
  or exists(select 1 from file_search.chunk_extraction where object_id=ga) then
  raise exception 'FAIL purging a file did not delete only the graph it alone supported'; end if;

 -- Another user's file names HT-01 in their own spelling. Their search gives their spelling, never the
 -- owner's, and the shared entity's own name, type and times are closed to them.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_graph', 'their-note.txt', other::text, '{"eTag":"g3"}') returning id into obj4;
 select version_id into fv5 from file_search.file_version where object_id=obj4;
 perform file_search.claim_files(20);
 perform file_search.record_file_text(fv5, 'extracted', jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Their note: the ht-01 item ships in May.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Their note: the ht-01 item ships in May.')));
 perform file_search.record_chunk_vector(k.chunk_id, far::extensions.vector::text, null) from file_search.chunk k where k.version_id=fv5;
 res:=file_search.save_extraction((select chunk_id from file_search.chunk where version_id=fv5), jsonb_build_array(
   jsonb_build_object('name','ht-01 ','type','PRODUCT','description','Ships in May.')), '[]', other, 'Other user');
 if (select count(*) from file_search.entity where name_key='ht-01')<>1 then raise exception 'FAIL another user''s spelling did not merge with the entity: %', res; end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, %L::real[], %L)', 'when does it ship', far, 'fs_check_graph') into res;
 if (select jsonb_agg(x - 'entity_id') from jsonb_array_elements(res->'stages'->'graph_seeds') x)<>'[{"name": "ht-01", "type": "PRODUCT", "similarity": 1.0000}]'::jsonb
  or res->'stages'->'graph_seeds'->0->>'entity_id'<>(select entity_id::text from file_search.entity where name_key='ht-01')
  or not exists(select 1 from jsonb_array_elements(res->'hits') h, jsonb_array_elements(h->'entities') e where e->>'name'='ht-01' and e->>'type'='PRODUCT')
  or res::text like '%HT-01%' or res::text like '%"Product"%' then
  raise exception 'FAIL another user''s search gave a spelling from a file they cannot open: %', res; end if;
 n:=0;
 begin execute 'select name from file_search.entity limit 1'; exception when insufficient_privilege then n:=n+1; end;
 begin execute 'select entity_type from file_search.entity limit 1'; exception when insufficient_privilege then n:=n+1; end;
 begin execute 'select created_at from file_search.entity limit 1'; exception when insufficient_privilege then n:=n+1; end;
 begin execute 'select created_at from file_search.relation limit 1'; exception when insufficient_privilege then n:=n+1; end;
 if n<>4 then raise exception 'FAIL a reader may select the shared entity''s or relation''s spelling or times'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A bucket ranked apart. One passage there names a word once; ten passages in another bucket repeat
 -- it. A search across every bucket ranks the two apart, each list up to the limit, and numbers the
 -- sections of both, the reference hits' first. A search that names a bucket returns one list.
 -- A bucket not searched by default, whose passage repeats the word more, is searched only by name.
 insert into storage.buckets(id, name, public) values ('fs_check_apart', 'fs_check_apart', false), ('fs_check_many', 'fs_check_many', false), ('fs_check_hidden', 'fs_check_hidden', false);
 insert into file_search.indexed_bucket(bucket_id, ranked_apart) values ('fs_check_apart', true);
 insert into file_search.indexed_bucket(bucket_id) values ('fs_check_many');
 insert into file_search.indexed_bucket(bucket_id, searched_by_default) values ('fs_check_hidden', false);
 alter policy "File search check: users see their own files" on storage.objects
  using (bucket_id in ('fs_check','fs_check_two','fs_check_plain','fs_check_graph','fs_check_apart','fs_check_many','fs_check_hidden') and owner_id = auth.uid()::text);
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_apart', 'guide.txt', mine::text, '{"eTag":"r1"}') returning id into ca;
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_many', 'updates.txt', mine::text, '{"eTag":"r2"}') returning id into cb;
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_hidden', 'session.txt', mine::text, '{"eTag":"r3"}') returning id into obj5;
 perform file_search.claim_files(20);
 perform file_search.record_file_text((select version_id from file_search.file_version where object_id=ca), 'extracted',
  jsonb_build_array(jsonb_build_object('ordinal',0,'place','Sales progression','body','The progressor asks whether the buyer''s own sale sits in a chain.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place','Sales progression','body','The progressor asks whether the buyer''s own sale sits in a chain.')));
 perform file_search.record_file_text((select version_id from file_search.file_version where object_id=cb), 'extracted',
  (select jsonb_agg(jsonb_build_object('ordinal',i,'place',format('sale %s',i),'body',format('Sale %s: chain of four, chain moving, chain call, chain notes.',i),'section',i) order by i) from generate_series(0,9) i), null,
  (select jsonb_agg(jsonb_build_object('ordinal',i,'place',format('sale %s',i),'body',format('Sale %s: chain of four, chain moving, chain call, chain notes.',i)) order by i) from generate_series(0,9) i));
 perform file_search.record_file_text((select version_id from file_search.file_version where object_id=obj5), 'extracted',
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','OKB has no chain, chain, chain, chain, chain, chain definition.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','OKB has no chain, chain, chain, chain, chain, chain definition.')));
 -- A bucket searched only by name keeps its chunks' sentences unsplit; another bucket's are split.
 if exists(select 1 from file_search.chunk_sentence where object_id=obj5) or not exists(select 1 from file_search.chunk_sentence where object_id=ca) then
  raise exception 'FAIL sentences were split in a bucket searched only by name, or not in one searched by default'; end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, null, null, 1)', 'chain') into res;
 if jsonb_array_length(res->'reference_hits')<>1 or res->'reference_hits'->0->>'file'<>'guide.txt'
  or jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'bucket'<>'fs_check_many'
  or (res->'reference_hits'->0->>'section')::integer<>0 or (res->'hits'->0->>'section')::integer<>1
  or res->'sections'->0->>'file'<>'guide.txt' or res->'sections'->1->>'file'<>'updates.txt' or jsonb_array_length(res->'sections')<>2
  or (res->'stages'->>'words')::integer<>11 or (res->'stages'->>'returned')::integer<>2 then
  raise exception 'FAIL a search across every bucket did not rank the bucket ranked apart on its own: %', left(res::text, 600); end if;
 execute format('select file_search.search(%L, null, null)', 'chain') into res;
 if jsonb_array_length(res->'reference_hits')<>1 or jsonb_array_length(res->'hits')<>10
  or exists(select 1 from jsonb_array_elements(res->'hits'||res->'reference_hits') h where h->>'bucket'='fs_check_hidden') then
  raise exception 'FAIL a search across every bucket returned a bucket not searched by default: %', left(res::text, 600); end if;
 execute format('select file_search.search(%L, null, %L, 1)', 'chain', 'fs_check_apart') into res;
 if res->'reference_hits'<>'[]'::jsonb or jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'file'<>'guide.txt' then
  raise exception 'FAIL a search naming the bucket ranked apart did not return it as hits: %', left(res::text, 600); end if;
 execute format('select file_search.search(%L, null, %L, 1)', 'chain', 'fs_check_many') into res;
 if res->'reference_hits'<>'[]'::jsonb or jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'bucket'<>'fs_check_many' then
  raise exception 'FAIL a search naming one bucket returned more than its hits: %', left(res::text, 600); end if;
 execute format('select file_search.search(%L, null, %L, 1)', 'chain', 'fs_check_hidden') into res;
 if res->'reference_hits'<>'[]'::jsonb or jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'file'<>'session.txt' then
  raise exception 'FAIL a search naming a bucket not searched by default did not search it: %', left(res::text, 600); end if;
 execute 'reset role';
 -- A user sees how a bucket is searched only for a bucket holding a file they can open.
 perform set_config('request.jwt.claims', jsonb_build_object('sub',other,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute 'select count(*) from file_search.indexed_bucket where bucket_id in (''fs_check_apart'',''fs_check_hidden'')' into n;
 if n<>0 then raise exception 'FAIL a user saw how a bucket they cannot open a file in is searched'; end if;
 execute format('select file_search.search(%L, null, null)', 'chain') into res;
 if res->'hits'<>'[]'::jsonb or res->'reference_hits'<>'[]'::jsonb then raise exception 'FAIL another user found files they cannot open: %', left(res::text, 600); end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A hit's chunk is placed in its section's text, its spaces matched as any run of spaces, and only
 -- the words found are marked.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_many', 'notes.txt', mine::text, '{"eTag":"r5"}') returning id into obj4;
 perform file_search.claim_files(20);
 perform file_search.record_file_text((select version_id from file_search.file_version where object_id=obj4), 'extracted',
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','Delivery notes.','section',0),
   jsonb_build_object('ordinal',1,'place',null,'body','The MoS is booked by the supplier. It arrives on Monday.','section',0)), null,
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body',E'Delivery  notes.\r\n\r\nThe\tMoS is booked by the supplier.  It arrives on Monday.')));
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, null, %L, 10, true)', 'who booked it', 'fs_check_many') into res;
 if jsonb_array_length(res->'hits')<>1 or res->'hits'->0->'chunk'<>'{"start": 20, "end": 77}'::jsonb
  or res->'hits'->0->'ranks'<>'{"words": 1, "meaning": null, "graph": null}'::jsonb
  or res->'hits'->0->'similarity'<>'null'::jsonb or res->'hits'->0->'graph_weight'<>'null'::jsonb
  or res->'sections'->0->>'marked'<>E'Delivery  notes.\r\n\r\nThe\tMoS is '||chr(57344)||'booked'||chr(57345)||' by the supplier.  It arrives on Monday.' then
  raise exception 'FAIL a hit''s chunk in its section, or its marks: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- A chunk with no section, from a file read before sections were kept, stays a hit, with neither
 -- section nor chunk.
 insert into storage.objects(bucket_id, name, owner_id, metadata) values ('fs_check_many', 'legacy.txt', mine::text, '{"eTag":"r6"}') returning id into obj3;
 perform file_search.claim_files(20);
 perform file_search.record_file_text((select version_id from file_search.file_version where object_id=obj3), 'extracted',
  jsonb_build_array(jsonb_build_object('ordinal',0,'place',null,'body','A palimpsest from before sections were kept.')), null, '[]'::jsonb);
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, null, %L, 10, true)', 'palimpsest', 'fs_check_many') into res;
 if jsonb_array_length(res->'hits')<>1 or res->'hits'->0->'section'<>'null'::jsonb or res->'hits'->0->'chunk'<>'null'::jsonb
  or (res->'stages'->>'returned')::integer<>1 then
  raise exception 'FAIL a hit whose chunk has no section: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- Each chunk's sentences wait for their vectors until their chunk has its own. An explained search
 -- gives each hit's sentences with stored vectors, placed in its section's text from the chunk's
 -- start, and counts those still waiting. A search that is not explained gives neither.
 if (select array_agg(s.body order by c.ordinal, s.ordinal) from file_search.chunk_sentence s join file_search.chunk c using (chunk_id)
     where c.version_id=(select version_id from file_search.file_version where object_id=obj4))
    <>array['Delivery notes.', 'The MoS is booked by the supplier.', 'It arrives on Monday.'] then
  raise exception 'FAIL a chunk''s sentences: %', (select array_agg(body) from file_search.chunk_sentence where object_id=obj4); end if;
 if exists(select 1 from file_search.claimable_sentence where object_id=obj4) then raise exception 'FAIL a sentence was claimable before its chunk had a vector'; end if;
 perform file_search.record_chunk_vector(k.chunk_id, far::extensions.vector::text, null) from file_search.chunk k where k.object_id=obj4;
 if not file_search.has_work('embed') then raise exception 'FAIL sentences waiting for vectors are not work for the embed job'; end if;
 perform set_config('request.jwt.claims', jsonb_build_object('sub',mine,'role','authenticated')::text, true);
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, %L::real[], %L, 10, true)', 'who booked it', near, 'fs_check_many') into res;
 if (res->'stages'->>'awaiting_sentence_vector')::integer<>3 or jsonb_typeof(res->'explain_ms')<>'number'
  or exists(select 1 from jsonb_array_elements(res->'hits') h where h->'sentences'<>'[]'::jsonb) then
  raise exception 'FAIL an explained search before its sentences have vectors: %', res; end if;
 execute 'reset role';
 -- A project's own sentences may be waiting too, so the checks record their own three directly.
 if not exists(select 1 from file_search.claimable_sentence where object_id=obj4) then raise exception 'FAIL a sentence was not claimable once its chunk had a vector'; end if;
 perform file_search.record_sentence_vector(s.sentence_id, (case when s.body like 'The MoS%' then near else far end)::extensions.vector::text, null)
  from file_search.chunk_sentence s where s.object_id=obj4;
 execute 'set local role authenticated';
 execute format('select file_search.search(%L, %L::real[], %L, 10, true)', 'who booked it', near, 'fs_check_many') into res;
 if not exists(select 1 from jsonb_array_elements(res->'hits') h where h->'chunk'='{"start": 20, "end": 77}'::jsonb
   and h->'sentences'='[{"start": 20, "end": 54, "similarity": 1.0000}, {"start": 56, "end": 77, "similarity": 0.0000}]'::jsonb)
  or (res->'stages'->>'awaiting_sentence_vector')::integer<>0 or res::text like '%chunk_id%' then
  raise exception 'FAIL an explained search''s sentences: %', res; end if;
 execute format('select file_search.search(%L, %L::real[], %L)', 'who booked it', near, 'fs_check_many') into res;
 if res ? 'explain_ms' or res->'stages' ? 'awaiting_sentence_vector' or exists(select 1 from jsonb_array_elements(res->'hits') h where h ? 'sentences') then
  raise exception 'FAIL a search that is not explained gave sentences: %', res; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims', '{}', true);

 -- The timer reads pg_net's answers to the worker's calls as this project's pg_net keeps them,
 -- once schedule.sql has installed pg_net.
 if to_regclass('net._http_response') is not null then perform file_search.record_worker_answers(); end if;

 -- Only signed-in users may search, and nobody but postgres may run the worker's functions.
 if has_function_privilege('anon', 'file_search.search(text,real[],text,integer,boolean)', 'execute')
  or has_function_privilege('authenticated', 'file_search.run_checks()', 'execute')
  or has_function_privilege('anon', 'file_search.run_checks()', 'execute')
  or has_function_privilege('service_role', 'file_search.run_checks()', 'execute')
  or has_function_privilege('authenticated', 'file_search.claim_files(integer,bigint)', 'execute')
  or has_function_privilege('authenticated', 'file_search.last_problem(uuid,uuid)', 'execute')
  or has_function_privilege('anon', 'file_search.worker_problems()', 'execute')
  or has_table_privilege('authenticated', 'file_search.worker_claim', 'insert,update,delete')
  or has_function_privilege('authenticated', 'file_search.dispatch()', 'execute')
  or has_function_privilege('authenticated', 'file_search.purge(uuid)', 'execute')
  or has_function_privilege('authenticated', 'file_search.purge_file(text,text)', 'execute')
  or has_function_privilege('authenticated', 'file_search.call_worker(text)', 'execute')
  or has_function_privilege('authenticated', 'file_search.record_worker_answers()', 'execute')
  or has_function_privilege('anon', 'file_search.failed_worker_runs()', 'execute')
  or has_table_privilege('authenticated', 'file_search.worker_call', 'select,insert,update,delete')
  or has_table_privilege('authenticated', 'file_search.claimable_chunk', 'select')
  or has_table_privilege('authenticated', 'file_search.file_version', 'insert,update,delete')
  or has_function_privilege('authenticated', 'file_search.save_extraction(uuid,jsonb,jsonb,uuid,text,boolean)', 'execute')
  or has_function_privilege('authenticated', 'file_search.unextracted(text,integer)', 'execute')
  or has_function_privilege('authenticated', 'file_search.claim_entities(integer)', 'execute')
  or has_function_privilege('authenticated', 'file_search.record_entity_vector(uuid,text,text)', 'execute')
  or has_function_privilege('authenticated', 'file_search.claim_sentences(integer)', 'execute')
  or has_function_privilege('authenticated', 'file_search.record_sentence_vector(uuid,text,text)', 'execute')
  or has_table_privilege('authenticated', 'file_search.chunk_sentence', 'insert,update,delete')
  or has_function_privilege('authenticated', 'file_search.delete_unsupported()', 'execute')
  or has_table_privilege('authenticated', 'file_search.entity', 'insert,update,delete')
  or has_table_privilege('authenticated', 'file_search.relation_source', 'insert,update,delete')
  or has_table_privilege('authenticated', 'file_search.chunk_extraction', 'insert,update,delete') then
  raise exception 'FAIL a client role holds more than search'; end if;

 raise exception using errcode='PHT09', message='PASS: file search checks passed';
end $checks$;

revoke execute on function file_search.run_checks() from public, anon, authenticated, service_role;

comment on function file_search.run_checks() is 'file_search checks 1.2.0';
