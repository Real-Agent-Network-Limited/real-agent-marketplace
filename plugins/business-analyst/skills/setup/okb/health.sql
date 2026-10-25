-- OKB setup: the health check at the end of setup, in place of the release checks, which are Real Agent's own and
-- never run in a client's project. Reads only, as postgres, through the Supabase connector's execute_sql. One row,
-- whose ok is true when every part is:
--   scopes        the six scopes are there, each enabled, with a sessions scope for each person with a sign-in; a
--                 person invited with a code gets theirs when they spend it;
--   administrator the first administrator is there, enabled;
--   real_agent    Real Agent's staff actors, each with the real_agent template's grants;
--   data_api      the Data API serves okb;
--   schedule      file search's schedule and both its secrets are there;
--   searchable    file search covers every scope's bucket but the plugins scopes'.
with scopes as (
 select count(*) filter (where code in ('general', 'routines', 'reference', 'plugins', 'administration', 'guides') and enabled) as six,
  count(*) filter (where starts_with(code, 'sessions_')) as sessions
 from okb.scope
), people as (
 select count(*) filter (where authority_class = 'administrator' and enabled) as administrators,
  count(*) filter (where display_name like '% (Real Agent)' and enabled) as real_agent,
  count(*) filter (where actor_kind = 'human' and auth_user_id is not null) as humans
 from okb.actor
), parts as (
 select
  (select six = 6 and sessions = (select humans from people) from scopes) as scopes,
  (select administrators >= 1 from people) as administrator,
  (select real_agent from people) as real_agent,
  coalesce((select bool_or(c like 'pgrst.db_schemas=%' and c ~ '(^|[=, ])okb(,|$)') from pg_roles r, unnest(r.rolconfig) c where r.rolname = 'authenticator'), false) as data_api,
  exists(select 1 from cron.job where jobname = 'file-search-work' and active)
   and (select count(*) from vault.decrypted_secrets where name in ('file_search_worker_secret', 'file_search_project_url')) = 2 as schedule,
  not exists(select 1 from okb.scope s where s.code <> 'plugins' and not starts_with(s.code, 'plugins_')
   and not exists(select 1 from file_search.indexed_bucket b where b.bucket_id = s.code)) as searchable
)
select scopes and administrator and data_api and schedule and searchable as ok, * from parts;
