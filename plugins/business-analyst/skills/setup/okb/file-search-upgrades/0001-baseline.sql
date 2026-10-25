-- 0001-baseline: the first file search build in OKB, which file-search.sql holds whole.
-- base: new
-- A project built with file-search.sql already lists this upgrade; this file only records it, and
-- is safe to run twice. Each later upgrade is numbered from 0002 and names, as its base, the commit
-- of file-search.sql it upgrades.
insert into file_search.schema_upgrade(id) values ('0001-baseline') on conflict (id) do nothing;
