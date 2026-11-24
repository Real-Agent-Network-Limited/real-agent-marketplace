-- OKB setup: the Data API serves the okb schema, beside Supabase's own public and graphql_public, and no other of
-- OKB's schemas. Run as postgres, through Supabase's Management API, after setup.sql. Supabase's
-- documentation gives this statement for exposing a schema without the dashboard; once it is set, the dashboard's
-- Exposed schemas list no longer manages the setting, and reset.sql resets it. The Data API then reloads its setting and
-- its list of functions, which otherwise misses the functions setup.sql made until something else reloads it.
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, okb';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
-- Check: the setting the Data API now reads.
select rolconfig from pg_roles where rolname = 'authenticator';
