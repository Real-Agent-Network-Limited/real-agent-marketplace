-- 0010-save-version-check
-- base: new
-- A save checks again, just before it writes, that the record's latest version is the one it was read from. A save
-- of the same record kept while this one waited is refused with 40001, as a save under way is. The same text is in
-- setup.sql. Safe to run twice. Run as the postgres login.

grant create on schema okb_private to okb_writer;
set role okb_writer;
CREATE OR REPLACE FUNCTION okb_private.save_version(p_request jsonb, p_authorisation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
AS $function$
declare a okb.actor; z okb.authorisation; v okb.record_version; oldv okb.record_version;
 h text; actions text[]; aid uuid:=p_authorisation_id; l jsonb; rid uuid; vnum integer; vid uuid; t timestamptz; w jsonb:='[]'::jsonb; k text; own uuid;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 perform okb_private.validate_shape(p_request);
 rid:=(p_request->>'record_id')::uuid;
 -- The record and each record it links to stay as they are until the save ends: a deletion or a
 -- move waits. Other saves go on.
 perform okb_private.hold_records(rid||okb_private.link_targets(p_request),false);
 perform okb_private.assert_request_scope(p_request,a.actor_id);
 h:=okb_private.canonical_request_hash(p_request,a.actor_id,a.accountable_human_id);
 select * into v from okb.record_version where request_id=(p_request->>'request_id')::uuid;
 if found then
  if v.executor_actor_id<>a.actor_id or v.request_hash<>h or not okb_private.can_read_record(v.record_id) then
   raise exception 'Save retry unavailable or different' using errcode='42501';
  end if;
  return to_jsonb(v)||jsonb_build_object('scope_id',(p_request->>'scope_id')::uuid,'warnings',w);
 end if;
 actions:=okb_private.validate_version(p_request);
 if aid is null then
  -- A person approves their own change where they approve others': as an administrator outside a
  -- private scope, or as a private scope's owner in it.
  own:=okb_private.scope_owner((p_request->>'scope_id')::uuid);
  if a.actor_kind<>'human' or (own is null and a.authority_class<>'administrator') or (own is not null and a.actor_id<>own) then
   raise exception 'Supply the id of a grant or approval that covers this change' using errcode='42501';
  end if;
  aid:=(okb_private.approve_change((p_request->>'request_id')::uuid,a.actor_id,p_request,clock_timestamp()+interval '5 minutes',p_request->>'reason')->>'authorisation_id')::uuid;
 end if;
 perform okb_private.hold_approval(aid);
 z:=okb_private.assert_authority(p_request,aid,actions);
 select * into oldv from okb.record_version where record_id=rid order by change_no desc limit 1;
 -- A save of the same record kept after this one checked its version is refused here. Upgrade 0010-save-version-check.
 if oldv.version_id is distinct from (p_request->>'expected_previous_version_id')::uuid then
  raise exception 'This record was changed by another save. Read it again, then save again.' using errcode='40001';
 end if;
 t:=clock_timestamp(); vid:=gen_random_uuid(); vnum:=coalesce(oldv.version_number,0)+1;
 begin
  if oldv.version_id is null then
   insert into okb.record(record_id,kind,scope_id,created_by,created_at) values(rid,p_request->>'kind',(p_request->>'scope_id')::uuid,a.actor_id,t);
  end if;
  insert into okb.record_version(version_id,record_id,version_number,previous_version_id,change_no,request_id,request_hash,recorded_at,
   executor_actor_id,accountable_human_id,authority_mode,authorisation_id,title,change_reason,payload)
  values(vid,rid,vnum,oldv.version_id,nextval('okb.change_no_seq'::regclass),(p_request->>'request_id')::uuid,h,t,
   a.actor_id,a.accountable_human_id,z.mode,z.authorisation_id,p_request->>'title',p_request->>'reason',okb_private.with_owner_label(p_request)->'payload') returning * into v;
 exception when unique_violation then
  -- Another save of the same record, or of the same request, finished first.
  get stacked diagnostics k=constraint_name;
  if k in ('record_pkey','record_version_record_id_version_number_key','record_version_request_id_key') then
   raise exception 'This record was changed by another save. Read it again, then save again.' using errcode='40001';
  end if;
  raise;
 end;
 perform set_config('okb.saving_version',vid::text,true);
 for l in select value from jsonb_array_elements(p_request->'links') loop
  insert into okb.version_link(source_version_id,target_version_id,relation,locator,note)
   values(vid,(l->>'target_version_id')::uuid,l->>'relation',l->>'locator',l->>'note');
 end loop;
 perform set_config('okb.saving_version','',true);
 if z.mode='explicit_approval' then
  update okb.authorisation set consumed_version_id=vid where authorisation_id=z.authorisation_id;
 end if;
 return to_jsonb(v)||jsonb_build_object('scope_id',(p_request->>'scope_id')::uuid,'warnings',w);
end $function$
;
reset role;
revoke create on schema okb_private from okb_writer;

insert into okb_private.schema_upgrade(id) values ('0010-save-version-check') on conflict (id) do nothing;
