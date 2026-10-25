-- OKB setup: takes an earlier, unfinished attempt back off a project, so setup can build it again from the start.
-- Run as postgres, through okb-setup or the SQL Editor. It refuses, and changes nothing, once OKB holds a record or
-- a file in a scope's bucket: from then on the project holds the firm's work, and only Real Agent's staff decide.
-- It removes OKB's and file search's schemas with everything in them, their four roles, the empty buckets of OKB's
-- scopes, file search's schedule and its two secrets, and the Data API's okb schema. The Auth users an earlier
-- attempt made stay: the owner's first sign-in gives the owner's a new password. The okb_setup schema and the
-- okb-setup hosted function stay, for the build that follows. One transaction: a failure keeps nothing.
do $$
declare
 n bigint;
 r record;
begin
 if to_regclass('okb.record') is not null then
  execute 'select count(*) from okb.record' into n;
  if n > 0 then
   raise exception 'OKB holds % record(s), so nothing was reset', n using errcode = '55000';
  end if;
 end if;
 if to_regclass('okb.scope') is not null then
  execute 'select count(*) from storage.objects o join okb.scope s on s.code = o.bucket_id' into n;
  if n > 0 then
   raise exception 'OKB''s scopes hold % file(s), so nothing was reset', n using errcode = '55000';
  end if;
  -- Each scope's bucket, empty, so the scopes can be made again.
  perform set_config('storage.allow_delete_query', 'true', true);
  execute 'delete from storage.buckets b using okb.scope s where s.code = b.id';
 end if;

 -- The Data API stops serving okb before the schema goes, so its schema cache can still be built.
 alter role authenticator reset pgrst.db_schemas;
 perform pg_notify('pgrst', 'reload config');

 if to_regnamespace('cron') is not null and exists(select 1 from pg_proc where proname = 'unschedule' and pronamespace = 'cron'::regnamespace) then
  for r in execute 'select jobname from cron.job where jobname = ''file-search-work''' loop
   perform cron.unschedule(r.jobname);
  end loop;
 end if;
 if to_regclass('vault.secrets') is not null then
  delete from vault.secrets where name in ('file_search_worker_secret', 'file_search_project_url');
 end if;

 -- Each schema with everything in it, and what depends on it elsewhere: OKB's and file search's triggers and policies
 -- on storage.objects, and the foreign key to auth.users.
 drop schema if exists okb_tests, file_search, okb_task, okb_storage, okb, okb_private cascade;

 for r in select rolname from pg_roles where rolname in ('okb_owner', 'okb_identity', 'okb_writer', 'okb_reader') loop
  execute format('drop owned by %I cascade', r.rolname);
  execute format('drop role %I', r.rolname);
 end loop;

 if to_regclass('okb_setup.person') is not null then
  delete from okb_setup.person;
 end if;
 if to_regclass('okb_setup.staff_code') is not null then
  delete from okb_setup.staff_code;
 end if;
end $$;
