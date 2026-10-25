-- 0001-baseline: the first OKB build, which setup.sql holds whole.
-- base: new
-- A project built with setup.sql already lists this upgrade; this file only records it, and is
-- safe to run twice. Each later upgrade is numbered from 0002 and names, as its base, the commit
-- of setup.sql it upgrades.
insert into okb_private.schema_upgrade(id) values ('0001-baseline') on conflict (id) do nothing;
