-- 0012-waiting-for-classes
-- base: 383e56c
-- OKB says when the graph reader is on but waits for the glossary's first class: okb_get_graph_reader gains
-- waiting_for_classes, true while the firm's Anthropic API key is kept and the glossary has no class, as OKB then
-- reads no part. The graph reader card and a search's stages show it. The same text is in setup.sql. Safe to run
-- twice. Run as the postgres login.

-- Whether graph-reader is on, the scopes it reads, and, for an administrator, the month's cost and its cap. An agent
-- reads a part itself only where it is off, or the scope is not one it reads. waiting_for_classes is true while the key
-- is kept and the glossary has no class: graph_reader_dispatch then sends no new batch, so no part is read until a
-- class is saved.
create or replace function okb.okb_get_graph_reader() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare a okb.actor; result jsonb; cost jsonb; is_on boolean:=okb_private.graph_reader_on();
begin
 a:=okb_private.read_actor();
 result:=jsonb_build_object('on',is_on,
  'waiting_for_classes',is_on and not exists(select 1 from okb.glossary_term g where g.kind='class'),
  'scopes',(select coalesce(jsonb_agg(s.code order by s.code),'[]'::jsonb) from unnest(okb_private.graph_reader_buckets()) s(code)
   where s.code in (select okb_storage.usable_buckets('read'))));
 if a.authority_class='administrator' and to_regclass('file_search.graph_settings') is not null then
  execute 'select jsonb_build_object(''month_cost_usd'',file_search.graph_month_cost(),''monthly_cap_usd'',s.monthly_cap_usd) from file_search.graph_settings s'
   into strict cost;
  result:=result||cost;
 end if;
 return result;
end $$;
revoke all on function okb.okb_get_graph_reader() from public, anon;
grant execute on function okb.okb_get_graph_reader() to authenticated;

insert into okb_private.schema_upgrade(id) values ('0012-waiting-for-classes') on conflict (id) do nothing;
