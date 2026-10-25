-- OKB setup: the Data API serves the okb schema, beside Supabase's own public and graphql_public, and no other of
-- OKB's schemas. Run as postgres, through the Supabase connector's execute_sql, after setup.sql. Supabase's
-- documentation gives this statement for exposing a schema without the dashboard; once it is set, the dashboard's
-- Exposed schemas list no longer manages the setting, and reset.sql resets it.
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, okb';
notify pgrst, 'reload config';
-- Check: the setting the Data API now reads.
select rolconfig from pg_roles where rolname = 'authenticator';
