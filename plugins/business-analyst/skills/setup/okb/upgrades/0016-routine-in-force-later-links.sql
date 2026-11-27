-- 0016-routine-in-force-later-links
-- base: 7bd9e28
-- okb_routine_in_force counts an approval only from the version of the decision that made it, with the links that
-- version holds. A later save of the decision, by the person who decided or anyone else, could link it to another model
-- version and move the routine in force with no new decision. The same text is in setup.sql. Safe to
-- run twice. Run as the postgres login.

grant create on schema okb to okb_reader;
set role okb_reader;
-- Each routine of the model p_model that is in force, or the one p_routine names by its id, its name, or both, in any
-- case. A routine is a routine or route_group node of a version; a version with neither is one routine, named by the
-- version's title. An approval is a version of a decision record, made, with its decision text and decided_on set,
-- that links to a version of the model with supports. It approves the routine its title names as ", routine <id>
-- <name>,", or, when its title names no routine of that version, every routine of it. The approval is the version whose
-- save set the decision text, as OKB asks decide for that save alone, with its own title, decided_on and supports links. A
-- link saved first, with okb_link while the question is undecided, is carried into that save. It counts while the
-- record's latest version still holds that decision text. A later save of the decision, by anyone, that relinks, retitles
-- or clears decided_on changes nothing: only a new made decision moves the version in force. A request for changes links with
-- describes, and approves nothing. The routine's version in force is the one its newest approval supports: the latest
-- decided_on, then the latest save. The answer is null when the actor may not read the model, and names each routine's
-- version, the change_no okb_get_record takes as p_cutoff to read it, its approval and who made it, and how many newer
-- versions of the model wait for their own approval.
create or replace function okb.okb_routine_in_force(p_model uuid, p_routine text default null) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare m okb.record; latest okb.record_version; result jsonb;
begin
 perform okb_private.read_actor();
 select * into m from okb.record where record_id=p_model and kind='model' and deleted_at is null;
 if not found then return null; end if;
 select * into latest from okb.record_version where record_id=p_model order by change_no desc limit 1;
 if not found then return null; end if;
 with versions as (
  select v.version_id,v.version_number,v.change_no,v.title,v.payload from okb.record_version v where v.record_id=p_model),
 grouped as (
  select v.version_id,coalesce(n->'attributes'->>'reference','') ref,n->>'label' label,n->>'type' rtype,coalesce(n->'attributes'->>'plugin','') plugin
  from versions v cross join lateral jsonb_array_elements(case when jsonb_typeof(v.payload->'graph'->'nodes')='array' then v.payload->'graph'->'nodes' else '[]'::jsonb end) n
  where n->>'type' in ('routine','route_group')),
 routines as (
  select g.*,btrim(case when g.ref='' then g.label else g.ref||' '||g.label end) rname from grouped g
  union all
  select v.version_id,'',v.title,'model','',v.title from versions v where not exists(select 1 from grouped g where g.version_id=v.version_id)),
 latest_decisions as (
  select distinct on (d.record_id) d.* from okb.record_version d join okb.record dr on dr.record_id=d.record_id
  where dr.kind='decision' and dr.deleted_at is null and dr.scope_id=m.scope_id
  order by d.record_id,d.change_no desc),
 made as (
  select distinct on (d.record_id) d.* from okb.record_version d join latest_decisions ld on ld.record_id=d.record_id
  left join okb.record_version prev on prev.version_id=d.previous_version_id
  where (prev.version_id is null or prev.payload->'decision' is distinct from d.payload->'decision')
   and d.payload->>'decision'<>'' and d.payload->'decided_on'<>'null'::jsonb and ld.payload->'decision'=d.payload->'decision'
  order by d.record_id,d.change_no desc),
 decisions as (
  select md.record_id,md.version_id,md.title,md.change_no,md.executor_actor_id,md.payload from made md),
 approvals as (
  select r.rname,r.ref,r.label,r.rtype,r.plugin,v.version_id,v.version_number,v.change_no version_change_no,v.payload->>'model_kind' model_kind,
   d.record_id decision_id,d.version_id decision_version_id,d.title decision_title,d.payload->>'decided_on' decided_on,d.change_no decision_change_no,
   d.executor_actor_id decided_by
  from decisions d join okb.version_link l on l.source_version_id=d.version_id and l.relation='supports'
  join versions v on v.version_id=l.target_version_id
  join routines r on r.version_id=v.version_id
  where d.payload->>'decision'<>'' and d.payload->'decided_on'<>'null'::jsonb
   and (strpos(lower(d.title||','),lower(', routine '||r.rname||','))>0
    or not exists(select 1 from routines o where o.version_id=v.version_id and o.rtype<>'model'
     and strpos(lower(d.title||','),lower(', routine '||o.rname||','))>0))),
 in_force as (
  select distinct on (lower(a.rname)) a.* from approvals a
  where p_routine is null or lower(btrim(p_routine)) in (lower(a.rname),lower(a.ref),lower(a.label))
  order by lower(a.rname),a.decided_on desc,a.decision_change_no desc)
 select jsonb_build_object('model_id',m.record_id,'scope_id',m.scope_id,'title',latest.title,
  'latest_version_id',latest.version_id,'latest_version_number',latest.version_number,
  'routines',coalesce(jsonb_agg(jsonb_build_object(
   'routine',jsonb_build_object('reference',f.ref,'name',f.label,'type',f.rtype,'plugin',f.plugin),
   'version_id',f.version_id,'version_number',f.version_number,'change_no',f.version_change_no,'model_kind',f.model_kind,
   'approval',jsonb_build_object('record_id',f.decision_id,'version_id',f.decision_version_id,'title',f.decision_title,
    'decided_on',f.decided_on,'decided_by',f.decided_by,'decided_by_name',okb_private.actor_name(f.decided_by)),
   'newer_versions',(select count(*) from versions n where n.version_number>f.version_number))
   order by f.ref='',f.ref,lower(f.label)),'[]'::jsonb))
 into result from in_force f;
 return result;
end $$;
reset role;
revoke create on schema okb from okb_reader;
revoke all on function okb.okb_routine_in_force(uuid,text) from public, anon;
grant execute on function okb.okb_routine_in_force(uuid,text) to authenticated;
notify pgrst, 'reload schema';

insert into okb_private.schema_upgrade(id) values ('0016-routine-in-force-later-links') on conflict (id) do nothing;
