-- OKB: index every scope's bucket for file search.
-- Run once, after setup.sql and file-search.sql, as postgres.
-- File search then covers each scope's files, and OKB's storage rules decide who finds them.
-- The plugins scope holds the firm's plugin releases, as does any scope whose code starts plugins_.
-- File search leaves them all out.
-- A search across every scope ranks the reference scope's files apart, returned as reference_hits,
-- and leaves out each person's sessions scope, whose code starts sessions_, searched only by name.

-- The scopes that exist now, with the files already in their buckets.
select file_search.index_bucket(code) from okb.scope where code<>'plugins' and not starts_with(code, 'plugins_');
update file_search.indexed_bucket set ranked_apart=(bucket_id='reference'), searched_by_default=not starts_with(bucket_id, 'sessions_')
where bucket_id in (select code from okb.scope);

-- Each scope created later, with its bucket. Owned by postgres, like the bucket trigger.
create function okb_storage.index_scope_bucket() returns trigger
language plpgsql security definer set search_path=pg_catalog as $$
begin
 if new.code<>'plugins' and not starts_with(new.code, 'plugins_') then
  perform file_search.index_bucket(new.code);
  update file_search.indexed_bucket set ranked_apart=(new.code='reference'), searched_by_default=not starts_with(new.code, 'sessions_')
  where bucket_id=new.code;
 end if;
 return new;
end $$;
revoke all on function okb_storage.index_scope_bucket() from public, anon, authenticated;
create trigger scope_file_search after insert on okb.scope
 for each row execute function okb_storage.index_scope_bucket();
