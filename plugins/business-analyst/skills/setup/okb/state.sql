-- OKB setup: where this project stands, read before setup builds anything. Reads only, as postgres, through the
-- Supabase connector's execute_sql. One row:
--   okb_built       the okb schema is there;
--   setup_finished  general, routines, reference and plugins are all there, each enabled;
--   actors          OKB's actors;
--   records         OKB's records;
--   files           files in OKB's scopes' buckets;
--   runner_ready    the okb_setup schema, which the okb-setup hosted function reads, is there.
-- A project with okb_built false is new. One with okb_built true and setup_finished false is an earlier, unfinished
-- attempt: reset.sql takes it off when records and files are both 0.
select
 to_regnamespace('okb') is not null as okb_built,
 case when to_regclass('okb.scope') is null then false
  else (xpath('/row/n/text()', query_to_xml($q$select count(*) as n from okb.scope
   where code in ('general', 'routines', 'reference', 'plugins') and enabled$q$, false, true, '')))[1]::text::int = 4 end as setup_finished,
 case when to_regclass('okb.actor') is null then 0
  else (xpath('/row/n/text()', query_to_xml('select count(*) as n from okb.actor', false, true, '')))[1]::text::int end as actors,
 case when to_regclass('okb.record') is null then 0
  else (xpath('/row/n/text()', query_to_xml('select count(*) as n from okb.record', false, true, '')))[1]::text::int end as records,
 case when to_regclass('okb.scope') is null then 0
  else (xpath('/row/n/text()', query_to_xml('select count(*) as n from storage.objects o join okb.scope s on s.code = o.bucket_id',
   false, true, '')))[1]::text::int end as files,
 to_regclass('okb_setup.approved') is not null as runner_ready;
