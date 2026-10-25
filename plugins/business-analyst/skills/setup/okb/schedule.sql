-- File search: the schedule that keeps files and chunks moving.
-- Run once, after file-search.sql and after the file-search-worker and file-search hosted
-- functions are deployed, in the SQL Editor as postgres (or through execute_sql).
-- Replace <project reference> first: the 20-character code in the project's web address.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- The worker secret, which only the database and file-search-worker read, and the project's address.
select vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'file_search_worker_secret',
 'Shared secret the schedule sends to the file-search-worker hosted function');
select vault.create_secret('https://<project reference>.supabase.co', 'file_search_project_url',
 'The project''s own address, for the schedule''s calls to its hosted functions');

-- Every minute, fail exhausted rows and call file-search-worker while any work waits.
select cron.schedule('file-search-work', '* * * * *', 'select file_search.dispatch()');

-- Check: the job, and both secrets by name. The secrets' values are never shown.
select jobname, schedule, active from cron.job where jobname = 'file-search-work';
select name from vault.decrypted_secrets where name in ('file_search_worker_secret', 'file_search_project_url') order by name;
