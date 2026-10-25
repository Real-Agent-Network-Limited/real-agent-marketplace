-- okb_tests 1.5.1
-- OKB: setup tests, installed as stored functions in their own schema, okb_tests.
-- Install this file once, as the postgres login, then run the checks part by part, in order:
--   select okb_tests.parts();
--   select okb_tests.run(1);   and each further part
-- or whole, through psql, with:
--   select okb_tests.run();
-- Installing again replaces every check. Only postgres may use the schema.
-- Each run is one transaction and ends in an error, so nothing it created is kept: fixture Auth
-- users, actors, scopes, grants and records are all discarded. Each suite also rolls back its own
-- fixtures in a subtransaction. When every suite passed, the error reads
-- "PASS: every suite passed". Any other error names what failed (FAIL ...).
-- Identity is simulated: request.jwt.claims selects the fixture Auth user, and each okb_* call
-- switches to the authenticated role. This is not password sign-in, token validation or a REST call.

drop schema if exists okb_tests cascade;
create schema okb_tests;
revoke all on schema okb_tests from public;

-- Fixture approval: names an existing enabled administrator, or nobody when there are no actors
-- yet, so the first fixture administrator is created as the first actor. Then names p_admin.
CREATE OR REPLACE FUNCTION okb_tests.approve_fixture(p_admin uuid) returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $approve$
begin
 perform set_config('okb.provisioning_actor', coalesce(p_admin::text,
  (select actor_id::text from okb.actor where actor_kind='human' and authority_class='administrator' and enabled order by actor_id limit 1), ''), true);
end $approve$;

-- Test proxies: call each public function as the authenticated role, then restore the
-- runner's role.
CREATE OR REPLACE FUNCTION okb_tests.okb_get_authorisations(p_executor_id uuid DEFAULT NULL::uuid, p_cursor uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 100)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_authorisations(p_executor_id,p_cursor,p_limit);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_get_record(p_record_id uuid, p_cutoff bigint DEFAULT NULL::bigint)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_record(p_record_id,p_cutoff);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_revoke_authorisation(p_authorisation_id uuid, p_reason text)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=pg_temp.raised(okb.okb_revoke_authorisation(p_authorisation_id,p_reason));
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_grant_permission(p_issuance_request_id uuid, p_executor_id uuid, p_record_kinds text[], p_record_id uuid, p_actions text[], p_expires_at timestamp with time zone, p_reason text)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=pg_temp.raised(okb.okb_grant_permission(p_issuance_request_id,p_executor_id,p_record_kinds,p_record_id,p_actions,p_expires_at,p_reason));
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_approve_change(p_issuance_request_id uuid, p_executor_id uuid, p_request jsonb, p_expires_at timestamp with time zone, p_reason text)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=pg_temp.raised(okb.okb_approve_change(p_issuance_request_id,p_executor_id,p_request,p_expires_at,p_reason));
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_save_version(p_request jsonb, p_authorisation_id uuid DEFAULT NULL::uuid)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=pg_temp.raised(okb.okb_save_version(p_request,p_authorisation_id));
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_grant_permission(p_issuance_request_id uuid, p_executor_id uuid, p_scope_id uuid, p_record_kinds text[], p_record_id uuid, p_actions text[], p_expires_at timestamp with time zone, p_reason text)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=pg_temp.raised(okb.okb_grant_permission(p_issuance_request_id,p_executor_id,p_scope_id,p_record_kinds,p_record_id,p_actions,p_expires_at,p_reason));
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_get_history(p_record_id uuid, p_cutoff bigint DEFAULT NULL::bigint, p_cursor bigint DEFAULT 0, p_limit integer DEFAULT 100)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_history(p_record_id,p_cutoff,p_cursor,p_limit);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_get_progress(p_cutoff bigint DEFAULT NULL::bigint, p_observed_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 100)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_progress(p_cutoff,p_observed_at,p_cursor,p_limit,nullif(current_setting('okb.test_scope',true),'')::uuid);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_get_progress(p_cutoff bigint, p_observed_at timestamp with time zone, p_cursor uuid, p_limit integer, p_scope_id uuid)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_progress(p_cutoff,p_observed_at,p_cursor,p_limit,p_scope_id);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

CREATE OR REPLACE FUNCTION okb_tests.okb_get_scopes(p_cursor uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 100)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $proxy$
declare result jsonb; original_role name:=current_user;
begin
 execute 'set local role authenticated';
 if current_user<>'authenticated' then raise exception 'Test role was not authenticated'; end if;
 result:=okb.okb_get_scopes(p_cursor,p_limit);
 execute format('set local role %I',original_role);
 return result;
exception when others then
 execute format('set local role %I',original_role);
 raise;
end $proxy$;

create function okb_tests.suite_01_smoke() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $test$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); request jsonb; evidence jsonb;
 v jsonb; v2 jsonb; outp jsonb; grant_id uuid; saved_cutoff bigint; denied boolean; _state text;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional test operator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_smoke','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  request:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'kind','activity','expected_previous_version_id',null,'title','Smoke task','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('activity_kind','task','description','Test','owner_actor_id',h,'completion_requirements','Evidence exists','state','pending',
    'baseline_start_at',null,'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note',''));
  v:=okb_tests.okb_save_version(request);
  if v->>'executor_actor_id'<>h::text or v->>'accountable_human_id'<>h::text or v->>'authority_mode'<>'explicit_approval' then raise exception 'FAIL attribution'; end if;
  if okb_tests.okb_save_version(request)<>v then raise exception 'FAIL save retry'; end if;
  -- The kind was renamed from work: the old kind, and the old sub-type field, are both refused.
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'kind','work'));
   _state:='accepted'; exception when others then get stacked diagnostics _state=returned_sqlstate; end;
  if _state<>'22023' then raise exception 'FAIL the old kind work was not refused as invalid: %',_state; end if;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),
    'payload',(request->'payload')-'activity_kind'||jsonb_build_object('work_kind','task')));
   _state:='accepted'; exception when others then get stacked diagnostics _state=returned_sqlstate; end;
  if _state<>'22023' then raise exception 'FAIL the old field work_kind was not refused as invalid: %',_state; end if;
  if (select count(*) from okb.record_version where record_id=r)<>1 then raise exception 'FAIL retry duplicated version'; end if;
  saved_cutoff:=(v->>'change_no')::bigint;
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('title','Changed retry')); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL changed retry accepted'; end if;
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"in_progress"');
  v2:=okb_tests.okb_save_version(request);
  if v2->>'version_number'<>'2' then raise exception 'FAIL version sequence'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid())); exception when serialization_failure then denied:=true; end;
  if not denied then raise exception 'FAIL stale version accepted'; end if;
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{payload,state}','"completed"')); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL completion without evidence'; end if;
  evidence:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',ev,'kind','evidence','expected_previous_version_id',null,'title','Smoke evidence','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('summary','Observed test result','source_reference',null,'source_date',null,'standing','observed','limitations','Test only'));
  outp:=okb_tests.okb_save_version(evidence);
  request:=jsonb_set(request,'{payload,state}','"completed"');
  request:=jsonb_set(request,'{payload,completion_note}','"Evidence checked"');
  request:=jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',outp->>'version_id','relation','supports')));
  v2:=okb_tests.okb_save_version(request);
  if v2#>>'{payload,state}'<>'completed' then raise exception 'FAIL completion'; end if;
  outp:=okb_tests.okb_get_record(r,saved_cutoff);
  if outp#>>'{version,payload,state}'<>'pending' then raise exception 'FAIL historical record'; end if;
  outp:=okb_tests.okb_get_progress();
  if (outp#>>'{counts,completed}')::integer<>1 then raise exception 'FAIL progress count'; end if;
  if outp#>>'{items,0,actual_finish}' is null then raise exception 'FAIL completion time'; end if;
  outp:=okb_tests.okb_get_history(r);
  if jsonb_array_length(outp->'items')<>3 then raise exception 'FAIL history'; end if;
  if (select count(*) from okb.authorisation where executor_actor_id=h and mode='explicit_approval' and consumed_version_id is not null)<>4 then raise exception 'FAIL approval consumption'; end if;
  outp:=okb_tests.okb_grant_permission(gen_random_uuid(),h,_scope,array['activity'],null,array['read','edit'],null,'Test grant');
  grant_id:=(outp->>'authorisation_id')::uuid;
  outp:=okb_tests.okb_get_authorisations(h);
  if jsonb_array_length(outp->'items')<>5 then raise exception 'FAIL authority inspection'; end if;
  outp:=okb_tests.okb_revoke_authorisation(grant_id,'Test revocation');
  if outp->>'revoked_by_actor_id'<>h::text then raise exception 'FAIL revoker attribution'; end if;
  if okb_private.authority_live(grant_id) then raise exception 'FAIL revoked grant remains live'; end if;
  denied:=false;
  begin update okb.record_version set title='Tampered' where record_id=r; exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL immutable guard'; end if;
  -- SET ROLE changes effective privileges, not session_user. This proves ACL refusals only.
  execute 'set local role authenticated';
  denied:=false;
  begin perform 1 from okb.record_version limit 1; exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL caller direct read permitted'; end if;
  denied:=false;
  begin perform okb_private.current_actor(); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL private helper permitted'; end if;
  execute 'reset role';
  set constraints all immediate;
  raise exception 'ROLLBACK_SUCCESSFUL_SMOKE_FIXTURES' using errcode='PHT01';
 exception when sqlstate 'PHT01' then null;
 end;
end $test$;

create function okb_tests.suite_02_saves_and_approvals() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $test$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); request jsonb; evidence jsonb;
 v jsonb; v2 jsonb; outp jsonb; grant_id uuid; denied boolean;
 p2 jsonb; p3 jsonb; vv jsonb; g jsonb; bid1 uuid:=gen_random_uuid(); bid2 uuid:=gen_random_uuid(); r2 uuid:=gen_random_uuid();
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional test operator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_extended','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  request:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'kind','activity','expected_previous_version_id',null,'title','Smoke task','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('activity_kind','task','description','Test','owner_actor_id',h,'completion_requirements','Evidence exists','state','pending',
    'baseline_start_at',null,'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note',''));
  v:=okb_tests.okb_save_version(request);
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"in_progress"');
  v2:=okb_tests.okb_save_version(request);
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  evidence:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',ev,'kind','evidence','expected_previous_version_id',null,'title','Smoke evidence','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('summary','Observed test result','source_reference',null,'source_date',null,'standing','observed','limitations','Test only'));
  outp:=okb_tests.okb_save_version(evidence);
  request:=jsonb_set(request,'{payload,state}','"completed"');
  request:=jsonb_set(request,'{payload,completion_note}','"Evidence checked"');
  request:=jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',outp->>'version_id','relation','supports')));
  v2:=okb_tests.okb_save_version(request);
  -- Reopening preserves history and clears current completion time.
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"in_progress"');
  v2:=okb_tests.okb_save_version(request);
  outp:=okb_tests.okb_get_progress();
  if exists(select 1 from jsonb_array_elements(outp->'items') x where x->>'record_id'=r::text and x->>'actual_finish' is not null) then raise exception 'FAIL reopening retained current finish'; end if;
  if not exists(select 1 from jsonb_array_elements(okb_tests.okb_get_history(r)->'items') x where x#>>'{payload,state}'='completed') then raise exception 'FAIL reopening lost completion history'; end if;
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  request:=jsonb_set(request,'{payload,blockers}',jsonb_build_array(jsonb_build_object('blocker_id',bid1,'description','First blocker'),jsonb_build_object('blocker_id',bid2,'description','Second blocker')));
  v2:=okb_tests.okb_save_version(request);
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  request:=jsonb_set(request,'{payload,blockers}',jsonb_build_array(jsonb_build_object('blocker_id',bid2,'description','Second blocker')));
  v2:=okb_tests.okb_save_version(request);
  if jsonb_array_length(v2#>'{payload,blockers}')<>1 then raise exception 'FAIL independent blocker removal'; end if;
  request:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id');
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{payload,blockers,0,description}','"Different problem"')); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL reused blocker identity'; end if;
  -- A second task depends on the first; the reverse edge would make a cycle.
  p2:=request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r2,'expected_previous_version_id',null,'title','Dependency test');
  p2:=jsonb_set(p2,'{payload,state}','"pending"');
  p2:=jsonb_set(p2,'{payload,blockers}','[]');
  p2:=jsonb_set(p2,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',v2->>'version_id','relation','depends_on')));
  vv:=okb_tests.okb_save_version(p2);
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',vv->>'version_id','relation','depends_on')))); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL dependency cycle accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',v2->>'version_id','relation','depends_on')))); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL self dependency accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',vv->>'version_id','relation','parent')))); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL task accepted as parent'; end if;
  -- Approval binds the complete request; an altered request cannot consume it.
  outp:=okb_tests.okb_approve_change(gen_random_uuid(),h,request,clock_timestamp()+interval '1 hour','Exact request test');
  grant_id:=(outp->>'authorisation_id')::uuid;
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('reason','Changed after approval'),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL altered approved request'; end if;
  -- The refusal left the approval unused: the exact request still saves with it.
  v2:=okb_tests.okb_save_version(request,grant_id);
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v2->>'version_id'),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL approval reuse'; end if;
  -- Reject malformed or oversized requests before any partial save.
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('extra_field','invalid')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL unknown request field'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(request||jsonb_build_object('reason',repeat('x',262145))); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL oversized request'; end if;
  -- Generic graph envelope preserves typed nodes, overlapping membership edges and evidence attributes.
  g:='{"format_version":1,"nodes":[{"id":"routine","type":"process_routine","label":"Routine","attributes":{}},{"id":"route1","type":"process_route","label":"Route 1","attributes":{}},{"id":"route2","type":"process_route","label":"Route 2","attributes":{}},{"id":"state","type":"process_state","label":"Supporting state","attributes":{"participation":"supporting_process","evidence_standing":"stated"}}],"edges":[{"id":"e1","source":"state","target":"routine","type":"belongs_to","attributes":{}},{"id":"e2","source":"state","target":"route1","type":"participates_in","attributes":{}},{"id":"e3","source":"state","target":"route2","type":"participates_in","attributes":{}}]}'::jsonb;
  p3:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'expected_previous_version_id',null,'kind','model','title','Graph test','reason','Transactional graph test','links','[]'::jsonb,
   'payload',jsonb_build_object('model_kind','observed_current','source_version','test-1','source_status','unverified','description','Synthetic graph, not an imported OKB model','graph',g));
  vv:=okb_tests.okb_save_version(p3);
  if okb_tests.okb_get_record((p3->>'record_id')::uuid)#>'{version,payload,graph}'<>g then raise exception 'FAIL graph round trip'; end if;
  p3:=p3||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',vv->>'version_id');
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p3,'{payload,graph,edges,0,target}','"missing"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL dangling graph edge'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p3,'{payload,graph,nodes,1,id}','"routine"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL duplicate graph ID'; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_SUCCESSFUL_EXTENDED_FIXTURES' using errcode='PHT01';
 exception when sqlstate 'PHT01' then null;
 end;
end $test$;

create function okb_tests.suite_03_completion() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $test$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); request jsonb; evidence jsonb;
 v jsonb; outp jsonb; msg text; p2 jsonb; vv jsonb; r2 uuid:=gen_random_uuid(); r3 uuid:=gen_random_uuid(); p4 jsonb; vv3 jsonb; item jsonb; pa jsonb; va jsonb; vb jsonb;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional test operator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_completion_cycle','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  request:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'kind','activity','expected_previous_version_id',null,'title','Smoke task','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('activity_kind','task','description','Test','owner_actor_id',h,'completion_requirements','Evidence exists','state','pending',
    'baseline_start_at',null,'baseline_finish_at','2020-01-01T00:00:00Z','forecast_start_at',null,'forecast_finish_at','2020-01-02T00:00:00Z','blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note',''));
  v:=okb_tests.okb_save_version(request);
  evidence:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',ev,'kind','evidence','expected_previous_version_id',null,'title','Smoke evidence','reason','Transactional test',
   'links','[]'::jsonb,'payload',jsonb_build_object('summary','Observed test result','source_reference',null,'source_date',null,'standing','observed','limitations','Test only'));
  outp:=okb_tests.okb_save_version(evidence);
  request:=request||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"in_progress"');
  v:=okb_tests.okb_save_version(request);
  request:=request||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"completed"');
  request:=jsonb_set(request,'{payload,completion_note}','"Evidence checked"');
  request:=jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',outp->>'version_id','relation','supports')));
  v:=okb_tests.okb_save_version(request);
  -- A completed activity's finish is measured against its baseline and its forecast.
  outp:=okb_tests.okb_get_progress();
  select x into item from jsonb_array_elements(outp->'items') x where x->>'record_id'=r::text;
  if (item->>'baseline_finish_variance_seconds')::numeric is distinct from extract(epoch from((item->>'actual_finish')::timestamptz-'2020-01-01T00:00:00Z'::timestamptz)) then raise exception 'FAIL baseline completion difference'; end if;
  if (item->>'forecast_finish_variance_seconds')::numeric is distinct from extract(epoch from((item->>'actual_finish')::timestamptz-'2020-01-02T00:00:00Z'::timestamptz)) then raise exception 'FAIL forecast completion difference'; end if;
  -- Reopened, the task takes part in a chain of three that may not close into a cycle.
  request:=request||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  request:=jsonb_set(request,'{payload,state}','"in_progress"');
  v:=okb_tests.okb_save_version(request);
  request:=request||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  p2:=request||jsonb_build_object('request_id',gen_random_uuid(),'record_id',r2,'expected_previous_version_id',null,'title','Dependency test');
  p2:=jsonb_set(p2,'{payload,state}','"pending"');
  p2:=jsonb_set(p2,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',v->>'version_id','relation','depends_on')));
  vv:=okb_tests.okb_save_version(p2);
  p4:=p2||jsonb_build_object('request_id',gen_random_uuid(),'record_id',r3,'title','Third dependency test');
  p4:=jsonb_set(p4,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',vv->>'version_id','relation','depends_on')));
  vv3:=okb_tests.okb_save_version(p4);
  msg:=null;
  begin perform okb_tests.okb_save_version(jsonb_set(request,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',vv3->>'version_id','relation','depends_on')))); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Circular activity relationship' then raise exception 'FAIL three-record dependency cycle: %',msg; end if;
  -- A save that keeps its link adds none, and is accepted.
  vv3:=okb_tests.okb_save_version(p4||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',vv3->>'version_id','title','Third dependency test renamed'));
  if vv3->>'version_number'<>'2' then raise exception 'FAIL save keeping its link'; end if;
  -- Two plans may not each be the other's parent.
  pa:=jsonb_set(jsonb_set(p2||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Plan A'),'{payload,activity_kind}','"plan"'),'{links}','[]');
  va:=okb_tests.okb_save_version(pa);
  vb:=okb_tests.okb_save_version(jsonb_set(pa||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Plan B'),
   '{links}',jsonb_build_array(jsonb_build_object('target_version_id',va->>'version_id','relation','parent'))));
  msg:=null;
  begin perform okb_tests.okb_save_version(jsonb_set(pa||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',va->>'version_id'),
   '{links}',jsonb_build_array(jsonb_build_object('target_version_id',vb->>'version_id','relation','parent')))); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Circular activity relationship' then raise exception 'FAIL plans each the other''s parent: %',msg; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_COMPLETION_CYCLE_FIXTURES' using errcode='PHT01';
 exception when sqlstate 'PHT01' then null;
 end;
end $test$;

-- -------------------------------------------------------------------
-- Suite: date
-- -------------------------------------------------------------------
create function okb_tests.suite_05_date() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); p jsonb; v jsonb; result jsonb; item jsonb;
 obs timestamptz; cutoff bigint; denied boolean;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional date test','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_date','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  p:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'kind','activity','expected_previous_version_id',null,'title','Date test','reason','Test date calculations','links','[]'::jsonb,
   'payload',jsonb_build_object('activity_kind','task','description','Test','owner_actor_id',h,'completion_requirements','Test','state','pending','baseline_start_at',null,
    'baseline_finish_at','2020-01-01T00:00:00Z','forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note',''));
  v:=okb_tests.okb_save_version(p); cutoff:=(v->>'change_no')::bigint; obs:=clock_timestamp();
  result:=okb_tests.okb_get_progress(cutoff,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if (item->>'overdue_seconds')::numeric is distinct from extract(epoch from(obs-'2020-01-01T00:00:00Z'::timestamptz)) then raise exception 'FAIL baseline overdue fallback'; end if;
  if item->>'forecast_overdue_seconds' is not null then raise exception 'FAIL unknown forecast manufactured'; end if;
  if item->>'baseline_overdue_seconds' is distinct from item->>'overdue_seconds' then raise exception 'FAIL baseline overdue'; end if;
  if item->'parent' is distinct from 'null'::jsonb then raise exception 'FAIL a task with no parent reports one: %',item->'parent'; end if;
  -- Each activity's parent plan comes back with the version it links to.
  declare plan_v jsonb; task_r uuid:=gen_random_uuid(); begin
   plan_v:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Parent test plan',
    'payload',(p->'payload')||'{"activity_kind":"plan"}'::jsonb));
   perform okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',task_r,'title','Parent test task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',plan_v->>'version_id','relation','parent'))));
   result:=okb_tests.okb_get_progress();
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=task_r::text;
   if item#>>'{parent,record_id}' is distinct from plan_v->>'record_id' or item#>>'{parent,referenced_version_id}' is distinct from plan_v->>'version_id' then
    raise exception 'FAIL progress parent: %',item->'parent'; end if;
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=plan_v->>'record_id';
   if item->'parent' is distinct from 'null'::jsonb then raise exception 'FAIL a plan with no parent reports one: %',item->'parent'; end if;
  end;
  -- Each activity's supporting evidence comes back with the version it links to; an activity with none has [].
  declare ev_v jsonb; ev_task uuid:=gen_random_uuid(); begin
   ev_v:=okb_tests.okb_save_version(jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'kind','evidence',
    'expected_previous_version_id',null,'title','Progress evidence','reason','Transactional test','links','[]'::jsonb,
    'payload',jsonb_build_object('summary','Observed test result','source_reference',null,'source_date',null,'standing','observed','limitations','Test only')));
   perform okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',ev_task,'title','Evidence test task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',ev_v->>'version_id','relation','supports'))));
   result:=okb_tests.okb_get_progress();
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=ev_task::text;
   if item->'evidence' is distinct from jsonb_build_array(jsonb_build_object('record_id',ev_v->>'record_id','referenced_version_id',ev_v->>'version_id',
     'current_version_id',ev_v->>'version_id','title','Progress evidence','standing','observed','deleted',false)) then
    raise exception 'FAIL progress evidence: %',item->'evidence'; end if;
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
   if item->'evidence' is distinct from '[]'::jsonb then raise exception 'FAIL an activity with no evidence reports some: %',item->'evidence'; end if;
  end;
  -- Each activity carries the time of its first version within the read's cutoff, and an activity
  -- with no version within the cutoff is left out.
  declare fs_task uuid:=gen_random_uuid(); fs1 jsonb; fs2 jsonb; fs3 jsonb; fs_first timestamptz; begin
   fs1:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',fs_task,'title','First save test task'));
   fs2:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',fs_task,'title','First save test task',
    'expected_previous_version_id',fs1->>'version_id','reason','Second save'));
   fs3:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',fs_task,'title','First save test task',
    'expected_previous_version_id',fs2->>'version_id','reason','Third save','payload',jsonb_set(p->'payload','{state}','"in_progress"')));
   select recorded_at into fs_first from okb.record_version where version_id=(fs1->>'version_id')::uuid;
   if fs_first>=(select recorded_at from okb.record_version where version_id=(fs3->>'version_id')::uuid) then
    raise exception 'FAIL first save test: the saves share one time'; end if;
   result:=okb_tests.okb_get_progress();
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=fs_task::text;
   if (item->>'first_saved_at')::timestamptz is distinct from fs_first or item->>'version_id' is distinct from fs3->>'version_id' then
    raise exception 'FAIL first save after the later saves: %',jsonb_build_object('first_saved_at',item->'first_saved_at','expected',fs_first); end if;
   result:=okb_tests.okb_get_progress((select change_no from okb.record_version where version_id=(fs1->>'version_id')::uuid),clock_timestamp());
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=fs_task::text;
   if (item->>'first_saved_at')::timestamptz is distinct from fs_first or item->>'version_id' is distinct from fs1->>'version_id' then
    raise exception 'FAIL first save before the later saves: %',jsonb_build_object('first_saved_at',item->'first_saved_at','expected',fs_first); end if;
   result:=okb_tests.okb_get_progress(cutoff,clock_timestamp());
   if exists(select 1 from jsonb_array_elements(result->'items') x where x->>'record_id'=fs_task::text) then
    raise exception 'FAIL progress returns an activity with no version within the cutoff'; end if;
  end;
  -- A version saved by an older build carries an old state name, which OKB reads as its new one;
  -- a new version carries only the new names.
  declare sv jsonb; old_v uuid; old_task uuid:=gen_random_uuid(); msg text; aid uuid; begin
   msg:=null;
   begin perform okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),
     'payload',jsonb_set(p->'payload','{state}','"planned"'))); exception when sqlstate '22023' then msg:=sqlerrm; end;
   if msg is distinct from 'Activity states are pending, in_progress, paused, completed and cancelled' then
    raise exception 'FAIL an old state name in a new version: %',msg; end if;
   sv:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',old_task,'title','Saved before the rename'));
   -- An approval of its own, since each approval is used once.
   aid:=(okb_tests.okb_approve_change(gen_random_uuid(),h,p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',old_task,
    'title','Saved before the rename','expected_previous_version_id',sv->>'version_id'),clock_timestamp()+interval '1 hour','Saved before the rename')->>'authorisation_id')::uuid;
   execute 'set local role okb_writer';
   insert into okb.record_version(version_id,record_id,version_number,previous_version_id,change_no,request_id,request_hash,recorded_at,
    executor_actor_id,accountable_human_id,authority_mode,authorisation_id,title,change_reason,payload)
   select gen_random_uuid(),record_id,version_number+1,version_id,nextval('okb.change_no_seq'::regclass),gen_random_uuid(),request_hash,
    clock_timestamp(),executor_actor_id,accountable_human_id,'explicit_approval',aid,title,'Saved before the rename',
    jsonb_set(payload,'{state}','"planned"')
   from okb.record_version where version_id=(sv->>'version_id')::uuid returning version_id into old_v;
   execute 'reset role';
   -- From planned, read as pending, the activity starts.
   sv:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',old_task,'title','Saved before the rename',
    'expected_previous_version_id',old_v,'payload',jsonb_set(p->'payload','{state}','"in_progress"')));
   result:=okb_tests.okb_get_progress();
   select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=old_task::text;
   if item->>'state' is distinct from 'in_progress' or item->>'prior_state' is distinct from 'pending' or item->>'started_at' is null then
    raise exception 'FAIL progress reads an old state name as its new one: %',jsonb_build_object('state',item->'state','prior_state',item->'prior_state','started_at',item->'started_at'); end if;
   if not (result->'counts' ?& array['pending','in_progress','paused','completed','cancelled']) or result->'counts' ?| array['planned','active','on_hold'] then
    raise exception 'FAIL progress counts by the new names: %',result->'counts'; end if;
  end;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  p:=jsonb_set(p,'{payload,forecast_finish_at}','"2020-01-02T00:00:00Z"');
  v:=okb_tests.okb_save_version(p); obs:=clock_timestamp();
  result:=okb_tests.okb_get_progress(null,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if (item->>'overdue_seconds')::numeric is distinct from extract(epoch from(obs-'2020-01-02T00:00:00Z'::timestamptz)) then raise exception 'FAIL forecast priority'; end if;
  if (item->>'baseline_overdue_seconds')::numeric-(item->>'forecast_overdue_seconds')::numeric<>86400 then raise exception 'FAIL baseline forecast difference'; end if;
  result:=okb_tests.okb_get_progress(cutoff,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if item->>'forecast_overdue_seconds' is not null then raise exception 'FAIL historical forecast changed'; end if;
  -- The baseline changes after it is saved. Progress counts from the new baseline, and the earlier
  -- version keeps the old one.
  p:=p||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','reason','The work moved a day earlier');
  p:=jsonb_set(p,'{payload,baseline_finish_at}','"2019-12-31T00:00:00Z"');
  v:=okb_tests.okb_save_version(p); obs:=clock_timestamp();
  if (v#>>'{payload,baseline_finish_at}')::timestamptz is distinct from '2019-12-31T00:00:00Z'::timestamptz then raise exception 'FAIL baseline not changed: %',v->'payload'; end if;
  result:=okb_tests.okb_get_progress(null,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if (item->>'baseline_overdue_seconds')::numeric is distinct from extract(epoch from(obs-'2019-12-31T00:00:00Z'::timestamptz)) then raise exception 'FAIL progress from the new baseline'; end if;
  result:=okb_tests.okb_get_progress(cutoff,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if (item->>'baseline_overdue_seconds')::numeric is distinct from extract(epoch from(obs-'2020-01-01T00:00:00Z'::timestamptz)) then raise exception 'FAIL historical baseline changed'; end if;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,forecast_finish_at}','"2026-10-01T10:00:00"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL timezone omitted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,forecast_start_at}','"2020-01-03T00:00:00Z"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL reversed dates'; end if;
  -- No activity finishes before a child, or a deliverable it waits on, either way. A cancelled one, and
  -- one with no finish, is left out.
  declare base jsonb; proj jsonb; spr jsonb; t1 jsonb; t3 jsonb; dl jsonb; x jsonb; open_spr jsonb; msg text;
  begin
   base:=jsonb_build_object('scope_id',_scope,'kind','activity','expected_previous_version_id',null,'reason','Finish order test','links','[]'::jsonb,
    'payload',jsonb_build_object('activity_kind','plan','description','Test','owner_actor_id',h,'completion_requirements','Test','state','pending',
     'baseline_start_at',null,'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note',''));
   proj:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order project',
    'payload',(base->'payload')||'{"baseline_finish_at":"2030-01-20T17:00:00Z"}'));
   spr:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"index":"1","baseline_finish_at":"2030-01-10T17:00:00Z"}'));
   t1:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.1","baseline_finish_at":"2030-01-09T17:00:00Z"}'));
   -- A task finishing after its sprint is refused, by its baseline and by its forecast.
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order late task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.2","baseline_finish_at":"2030-01-11T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order sprint finishes 10 Jan 17:00, before its task 1.2, which finishes 11 Jan 17:00.' then
    raise exception 'FAIL finish order: a task finishing after its sprint: %',msg; end if;
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',t1->'record_id','expected_previous_version_id',t1->'version_id','title','Finish order task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(t1->'payload')||'{"forecast_finish_at":"2030-01-12T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order sprint finishes 10 Jan 17:00, before its task 1.1, which finishes 12 Jan 17:00.' then
    raise exception 'FAIL finish order: a task''s forecast after its sprint: %',msg; end if;
   -- A sprint finishing before its task is refused.
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',spr->'record_id','expected_previous_version_id',spr->'version_id','title','Finish order sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(spr->'payload')||'{"forecast_finish_at":"2030-01-08T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order sprint finishes 8 Jan 17:00, before its task 1.1, which finishes 9 Jan 17:00.' then
    raise exception 'FAIL finish order: a sprint finishing before its task: %',msg; end if;
   -- A project finishing before its sprint is refused.
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',proj->'record_id','expected_previous_version_id',proj->'version_id','title','Finish order project',
    'payload',(proj->'payload')||'{"forecast_finish_at":"2030-01-05T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order project finishes 5 Jan 17:00, before its sprint 1, which finishes 10 Jan 17:00.' then
    raise exception 'FAIL finish order: a project finishing before its sprint: %',msg; end if;
   -- A deliverable made with okb_add_deliverable has no finish. Moved past its task's finish, it is refused.
   execute 'set local role authenticated';
   x:=pg_temp.raised(okb.okb_add_deliverable((t1->>'record_id'),'Finish order deliverable','The document','Finish order test'));
   execute 'reset role';
   dl:=x->'deliverable'; t1:=x->'task';
   if dl->'payload'->>'index' is distinct from '1.1a' or t1->>'version_id' is null then raise exception 'FAIL finish order: the deliverable reads %',x; end if;
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',dl->'record_id','expected_previous_version_id',dl->'version_id','title','Finish order deliverable',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(dl->'payload')||'{"baseline_finish_at":"2030-01-09T18:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order task finishes 9 Jan 17:00, before its deliverable 1.1a, which finishes 9 Jan 18:00.' then
    raise exception 'FAIL finish order: a deliverable moved past its task: %',msg; end if;
   dl:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',dl->'record_id','expected_previous_version_id',dl->'version_id','title','Finish order deliverable',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(dl->'payload')||'{"baseline_finish_at":"2030-01-08T17:00:00Z"}'));
   -- A task finishing before a deliverable it waits on is refused.
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',t1->'record_id','expected_previous_version_id',t1->'version_id','title','Finish order task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent'),jsonb_build_object('target_version_id',dl->>'version_id','relation','depends_on')),
    'payload',(t1->'payload')||'{"baseline_finish_at":"2030-01-07T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order task finishes 7 Jan 17:00, before its deliverable 1.1a, which finishes 8 Jan 17:00.' then
    raise exception 'FAIL finish order: a task finishing before its deliverable: %',msg; end if;
   -- A cancelled deliverable and a cancelled child are left out.
   dl:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',dl->'record_id','expected_previous_version_id',dl->'version_id','title','Finish order deliverable',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(dl->'payload')||'{"state":"cancelled"}'));
   t1:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',t1->'record_id','expected_previous_version_id',t1->'version_id','title','Finish order task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent'),jsonb_build_object('target_version_id',dl->>'version_id','relation','depends_on')),
    'payload',(t1->'payload')||'{"baseline_finish_at":"2030-01-07T17:00:00Z","state":"cancelled"}'));
   spr:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',spr->'record_id','expected_previous_version_id',spr->'version_id','title','Finish order sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(spr->'payload')||'{"forecast_finish_at":"2030-01-05T17:00:00Z"}'));
   -- An activity with no finish is left out, as a parent and as a child.
   perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order open task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.3"}'));
   open_spr:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order open sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"index":"2"}'));
   perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order open sprint task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',open_spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"2.1","baseline_finish_at":"2031-01-01T17:00:00Z"}'));
   -- A sprint and its task moved later, sprint first, both save.
   t3:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order later task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.4","baseline_finish_at":"2030-01-05T17:00:00Z"}'));
   spr:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',spr->'record_id','expected_previous_version_id',spr->'version_id','title','Finish order sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(spr->'payload')||'{"forecast_finish_at":"2030-01-15T17:00:00Z"}'));
   t3:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',t3->'record_id','expected_previous_version_id',t3->'version_id','title','Finish order later task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(t3->'payload')||'{"forecast_finish_at":"2030-01-15T17:00:00Z"}'));
   if t3->'payload'->>'forecast_finish_at' is distinct from '2030-01-15T17:00:00Z' then raise exception 'FAIL finish order: the later task reads %',t3; end if;
   -- A task waiting on a work task, which then becomes a deliverable that finishes after it, is refused.
   dl:=okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order work task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.5","baseline_finish_at":"2030-01-14T17:00:00Z"}'));
   perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Finish order waiting task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent'),jsonb_build_object('target_version_id',dl->>'version_id','relation','depends_on')),
    'payload',(base->'payload')||'{"activity_kind":"task","task_type":"work","index":"1.6","baseline_finish_at":"2030-01-13T17:00:00Z"}'));
   -- One message names each break, and a time carries its year when the other falls in another year.
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',spr->'record_id','expected_previous_version_id',spr->'version_id','title','Finish order sprint',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',proj->>'version_id','relation','parent')),
    'payload',(spr->'payload')||'{"forecast_finish_at":"2029-12-31T17:00:00Z"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order sprint finishes 31 Dec 2029 17:00, before its task 1.6, which finishes 13 Jan 2030 17:00; '
     'Finish order sprint finishes 31 Dec 2029 17:00, before its task 1.5, which finishes 14 Jan 2030 17:00; '
     'Finish order sprint finishes 31 Dec 2029 17:00, before its task 1.4, which finishes 15 Jan 2030 17:00.' then
    raise exception 'FAIL finish order: several breaks across a year: %',msg; end if;
   msg:=null;
   begin perform okb_tests.okb_save_version(base||jsonb_build_object('request_id',gen_random_uuid(),'record_id',dl->'record_id','expected_previous_version_id',dl->'version_id','title','Finish order work task',
    'links',jsonb_build_array(jsonb_build_object('target_version_id',spr->>'version_id','relation','parent')),
    'payload',(dl->'payload')||'{"task_type":"deliverable"}'));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'This finish cannot be saved: Finish order waiting task finishes 13 Jan 17:00, before its deliverable 1.5, which finishes 14 Jan 17:00.' then
    raise exception 'FAIL finish order: a task type changed to deliverable: %',msg; end if;
  end;
  p:=jsonb_set(p,'{payload,state}','"cancelled"'); v:=okb_tests.okb_save_version(p);
  result:=okb_tests.okb_get_progress();
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if item->>'overdue_seconds' is not null or item->>'baseline_overdue_seconds' is not null then raise exception 'FAIL cancelled task overdue'; end if;
  denied:=false;
  begin perform okb_tests.okb_get_progress(null,null,null,101); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL uncapped page'; end if;
  denied:=false;
  begin perform okb_tests.okb_get_progress(null,clock_timestamp()+interval '1 day'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL future observation'; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_DATE_TEST_FIXTURES' using errcode='PHT02';
 exception when sqlstate 'PHT02' then null;
 end;
end $$;

-- -------------------------------------------------------------------
-- Suite: history
-- -------------------------------------------------------------------
create function okb_tests.suite_06_history() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); p jsonb; v jsonb; target jsonb; history jsonb; item jsonb;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional history test','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_history','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  p:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'expected_previous_version_id',null,'kind','evidence','title','History test','reason','Test','links','[]'::jsonb,
   'payload',jsonb_build_object('summary','Evidence','source_reference',null,'source_date',null,'standing','observed','limitations','Test','file_sha256',repeat('a',64)));
  v:=okb_tests.okb_save_version(p);
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  p:=jsonb_set(p,'{payload}',(p->'payload')-'file_sha256');
  v:=okb_tests.okb_save_version(p);
  history:=okb_tests.okb_get_history(r);
  item:=history#>'{items,1}';
  if item->'changed_fields' is distinct from '["file_sha256"]'::jsonb then raise exception 'FAIL removed optional field'; end if;
  target:=okb_tests.okb_save_version(p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'expected_previous_version_id',null));
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  p:=jsonb_set(p,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',target->>'version_id','relation','supports','note','Original link note')));
  v:=okb_tests.okb_save_version(p);
  history:=okb_tests.okb_get_history(r);
  if history#>'{items,2,changed_fields}' is distinct from '["links"]'::jsonb then raise exception 'FAIL added link not flagged'; end if;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  v:=okb_tests.okb_save_version(p);
  history:=okb_tests.okb_get_history(r);
  if history#>'{items,3,changed_fields}' is distinct from '[]'::jsonb then raise exception 'FAIL unchanged link reported changed'; end if;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  p:=jsonb_set(p,'{links,0,note}','"Changed link note"');
  v:=okb_tests.okb_save_version(p);
  history:=okb_tests.okb_get_history(r);
  if history#>'{items,4,changed_fields}' is distinct from '["links"]'::jsonb then raise exception 'FAIL changed link note not flagged'; end if;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','links','[]'::jsonb);
  v:=okb_tests.okb_save_version(p);
  history:=okb_tests.okb_get_history(r);
  if history#>'{items,5,changed_fields}' is distinct from '["links"]'::jsonb then raise exception 'FAIL removed link not flagged'; end if;
  history:=okb_tests.okb_get_history(r,null,0,2);
  if jsonb_array_length(history->'items')<>2 then raise exception 'FAIL history page limit'; end if;
  history:=okb_tests.okb_get_history(r,(history->>'cutoff')::bigint,(history->>'next_cursor')::bigint,2);
  if history#>>'{items,0,version_number}'<>'3' then raise exception 'FAIL history cursor'; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_HISTORY_TEST_FIXTURES' using errcode='PHT03';
 exception when sqlstate 'PHT03' then null;
 end;
end $$;

-- -------------------------------------------------------------------
-- Suite: plan-boundary
-- -------------------------------------------------------------------
create function okb_tests.suite_07_plan_boundary() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); p jsonb; v jsonb; result jsonb; item jsonb;
 obs timestamptz; cutoff bigint; denied boolean;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Transactional date test','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(_scope,'auth_test_plan_boundary','Auth test scope','Rolled-back fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  p:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',r,'kind','activity','expected_previous_version_id',null,'title','Date test','reason','Test date calculations','links','[]'::jsonb,
   'payload',jsonb_build_object('activity_kind','plan','description','Test','owner_actor_id',h,'completion_requirements','Test','state','pending','baseline_start_at',null,
    'baseline_finish_at','2020-01-01T00:00:00Z','forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note','','index','2'));
  v:=okb_tests.okb_save_version(p); cutoff:=(v->>'change_no')::bigint; obs:=clock_timestamp();
  result:=okb_tests.okb_get_progress(cutoff,obs);
  select x into item from jsonb_array_elements(result->'items') x where x->>'record_id'=r::text;
  if item->'payload'->>'index' is distinct from '2' then raise exception 'FAIL activity index kept'; end if;
  p:=p||jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id');
  -- An index is one line of at most 20 characters, and only a task has a task type.
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,index}','"123456789012345678901"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL long index'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,index}',to_jsonb(E'2\n3'::text))); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL index on two lines'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,index}','""')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL blank index'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{payload,task_type}','"work"')); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL task type on a plan'; end if;
  -- A link to a version that does not exist is refused.
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(p,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',gen_random_uuid(),'relation','supports')))); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL nonexistent link target'; end if;
  -- A task under the plan, saved with each task type and an index, and refused with any other type.
  item:=jsonb_build_object('scope_id',_scope,'request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'kind','activity','expected_previous_version_id',null,'title','Index test','reason','Test the index','links',
   jsonb_build_array(jsonb_build_object('target_version_id',v->>'version_id','relation','parent')),
   'payload',jsonb_build_object('activity_kind','task','description','Test','owner_actor_id',h,'completion_requirements','Test','state','pending','baseline_start_at',null,
    'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb,'completion_note','','index','2.2a','task_type','deliverable'));
  perform okb_tests.okb_save_version(item);
  perform okb_tests.okb_save_version(jsonb_set(jsonb_set(item,'{record_id}',to_jsonb(gen_random_uuid())),'{payload,task_type}','"blocker"')||jsonb_build_object('request_id',gen_random_uuid()));
  perform okb_tests.okb_save_version(jsonb_set(jsonb_set(item,'{record_id}',to_jsonb(gen_random_uuid())),'{payload,task_type}','"work"')||jsonb_build_object('request_id',gen_random_uuid()));
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(jsonb_set(item,'{record_id}',to_jsonb(gen_random_uuid())),'{payload,task_type}','"milestone"')||jsonb_build_object('request_id',gen_random_uuid())); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL unknown task type'; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_PLAN_TEST_FIXTURES' using errcode='PHT02';
 exception when sqlstate 'PHT02' then null;
 end;
end $$;

create function okb_tests.suite_08_scoped_grants() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $tests$
declare _scope uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); sa uuid; sb uuid:=gen_random_uuid(); t0 timestamptz:=clock_timestamp();
 req jsonb; other_req jsonb; v jsonb; foreign_v jsonb; grant_id uuid; approved uuid; outp jsonb; denied boolean;
 k text; payload jsonb; p jsonb; activity_payload jsonb; ids uuid[]:='{}'; cutoff bigint;
 e2 uuid:=gen_random_uuid(); pp uuid:=gen_random_uuid(); lx jsonb; ly jsonb; lz jsonb; g1 uuid; gp uuid; later jsonb; assigned jsonb;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Scope test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into auth.users(id) values(e);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(e,e,'Scope test restricted agent','agent',h,'restricted',true);
  insert into auth.users(id) values(e2);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(e2,e2,'Scope test record agent','agent',h,'restricted',true);
  insert into auth.users(id) values(pp);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(pp,pp,'Scope test assignee','human',pp,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  sa:=_scope;
  insert into okb.scope(scope_id,code,display_name,description,created_by)
  values(_scope,'auth_test_scope','Auth test scope','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sb,'scope_test_other','Other test scope','Fixture',h);
  perform set_config('okb.test_scope',_scope::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  activity_payload:='{"activity_kind":"task","description":"Test","completion_requirements":"Evidence","state":"pending","baseline_start_at":null,"baseline_finish_at":null,"forecast_start_at":null,"forecast_finish_at":null,"blockers":[],"external_references":[],"completion_note":""}'::jsonb||jsonb_build_object('owner_actor_id',h);
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sa,'kind','activity','expected_previous_version_id',null,'title','Administrator-owned audit','reason','Scope test','payload',activity_payload,'links','[]'::jsonb);
  v:=okb_tests.okb_save_version(req);
  if (v->>'scope_id')::uuid<>sa then raise exception 'FAIL save scope missing'; end if;
  cutoff:=(v->>'change_no')::bigint;
  other_req:=req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sb,'title','Foreign confidential work');
  foreign_v:=okb_tests.okb_save_version(other_req);
  denied:=false;
  begin perform okb_tests.okb_save_version(req-'scope_id'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL unscoped request accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_grant_permission(gen_random_uuid(),e,array['activity'],null,array['read'],clock_timestamp()+interval '1 hour','Legacy'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL legacy grant accepted'; end if;
  outp:=okb_tests.okb_grant_permission(gen_random_uuid(),e,sa,array['activity','decision','model','evidence'],null,array['read','create','edit','start','hold','complete','reopen','cancel','decide'],clock_timestamp()+interval '1 hour','Test scope grant');
  grant_id:=(outp->>'authorisation_id')::uuid;
  denied:=false;
  begin perform okb_tests.okb_grant_permission(gen_random_uuid(),e,sa,array['activity'],(foreign_v->>'record_id')::uuid,array['read'],clock_timestamp()+interval '1 hour','Mismatched record'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL foreign record grant'; end if;
  denied:=false;
  begin perform okb_tests.okb_approve_change(gen_random_uuid(),e,other_req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',foreign_v->>'version_id'),clock_timestamp()+interval '1 hour','Foreign approval'); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL foreign approval issued'; end if;
  req:=req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','title','Agent may edit another author');
  outp:=okb_tests.okb_approve_change(gen_random_uuid(),e,req,clock_timestamp()+interval '1 hour','Approved audit edit');
  approved:=(outp->>'authorisation_id')::uuid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  if okb_tests.okb_get_record((foreign_v->>'record_id')::uuid) is not null then raise exception 'FAIL foreign record exposed'; end if;
  if jsonb_array_length(okb_tests.okb_get_history((foreign_v->>'record_id')::uuid)->'items')<>0 then raise exception 'FAIL foreign history exposed'; end if;
  outp:=okb_tests.okb_get_progress();
  if (outp#>>'{counts,pending}')::int<>1 or jsonb_array_length(outp->'items')<>1 then raise exception 'FAIL foreign progress exposed'; end if;
  if jsonb_array_length(okb_tests.okb_get_progress(null,null,null,100,sb)->'items')<>0 then raise exception 'FAIL foreign scope filter'; end if;
  if jsonb_array_length(okb_tests.okb_get_scopes()->'items')<>1 then raise exception 'FAIL foreign scope catalogue'; end if;
  if okb_tests.okb_get_record((v->>'record_id')::uuid,cutoff)#>>'{version,title}'<>'Administrator-owned audit' then raise exception 'FAIL historical scope read'; end if;
  execute 'set local role okb_reader';
  if exists(select 1 from okb.record where scope_id=sb) or exists(select 1 from okb.record_version where record_id=(foreign_v->>'record_id')::uuid) then raise exception 'FAIL direct effective-role RLS read'; end if;
  execute 'reset role';
  denied:=false;
  begin perform okb_tests.okb_save_version(other_req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',foreign_v->>'version_id'),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL foreign edit accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(other_req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid()),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL foreign create accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(req||jsonb_build_object('scope_id',sb),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL scope move accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(jsonb_set(req,'{links}',jsonb_build_array(jsonb_build_object('target_version_id',foreign_v->>'version_id','relation','depends_on'))),grant_id); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL cross-scope link accepted'; end if;
  denied:=false;
  begin perform okb_tests.okb_grant_permission(gen_random_uuid(),e,sb,array['activity'],null,array['read'],clock_timestamp()+interval '1 hour','Escalation'); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL restricted grant issued'; end if;
  v:=okb_tests.okb_save_version(req,approved);
  if (v->>'executor_actor_id')::uuid<>e or (v->>'accountable_human_id')::uuid<>h then raise exception 'FAIL restricted attribution'; end if;
  if okb_tests.okb_save_version(req,approved)<>v then raise exception 'FAIL scoped retry'; end if;
  foreach k in array array['activity','decision','evidence','model'] loop
   payload:=case k
    when 'activity' then activity_payload
    when 'decision' then '{"question":"Test","alternatives":[],"decision":"","rationale":"","decided_on":null}'::jsonb
    when 'evidence' then '{"summary":"Test","source_reference":null,"source_date":null,"standing":"observed","limitations":"Fixture"}'::jsonb
    else '{"model_kind":"observed_current","source_version":"fixture","source_status":"unverified","description":"Fixture","graph":{"format_version":1,"nodes":[],"edges":[]}}'::jsonb end;
   p:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sa,'kind',k,'expected_previous_version_id',null,'title','Agent scope fixture','reason','Scope test','payload',payload,'links','[]'::jsonb);
   outp:=okb_tests.okb_save_version(p,grant_id);
   ids:=ids||((outp->>'record_id')::uuid);
   p:=p||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',outp->>'version_id','title','Updated agent fixture');
   outp:=okb_tests.okb_save_version(p,grant_id);
   if outp->>'version_number'<>'2' then raise exception 'FAIL kind edit %',k; end if;
  end loop;
  -- A loop through a task the saving agent cannot read is refused.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  p:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sa,'kind','activity','expected_previous_version_id',null,'title','Loop X','reason','Scope test','payload',activity_payload,'links','[]'::jsonb);
  lx:=okb_tests.okb_save_version(p);
  ly:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Loop Y',
   'links',jsonb_build_array(jsonb_build_object('target_version_id',lx->>'version_id','relation','depends_on'))));
  lz:=okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Loop Z',
   'links',jsonb_build_array(jsonb_build_object('target_version_id',ly->>'version_id','relation','depends_on'))));
  g1:=(okb_tests.okb_grant_permission(gen_random_uuid(),e2,sa,array['activity'],(lx->>'record_id')::uuid,array['read','edit'],clock_timestamp()+interval '1 hour','Loop X')->>'authorisation_id')::uuid;
  perform okb_tests.okb_grant_permission(gen_random_uuid(),e2,sa,array['activity'],(lz->>'record_id')::uuid,array['read'],clock_timestamp()+interval '1 hour','Loop Z');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e2,'role','authenticated')::text,true);
  if okb_tests.okb_get_record((ly->>'record_id')::uuid) is not null then raise exception 'FAIL record agent reads Loop Y'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(p||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',lx->>'version_id',
   'links',jsonb_build_array(jsonb_build_object('target_version_id',lz->>'version_id','relation','depends_on'))),g1); exception when check_violation then denied:=true; end;
  if not denied then raise exception 'FAIL loop through an unreadable task accepted'; end if;
  -- The reads hold only the reader's records, and history up to the reader's latest version.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  later:=okb_tests.okb_save_version(other_req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Foreign later work'));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  denied:=false;
  begin perform okb_tests.okb_get_progress((later->>'change_no')::bigint,null); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL progress cutoff beyond readable history'; end if;
  execute 'set local role authenticated';
  outp:=okb.okb_find_records(null,null,null,null,null,100);
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(outp->'items') x where (x->>'scope_id')::uuid=sb) then raise exception 'FAIL foreign record found'; end if;
  if not exists(select 1 from jsonb_array_elements(outp->'items') x where (x->>'record_id')::uuid=(v->>'record_id')::uuid) then raise exception 'FAIL own record not found'; end if;
  execute 'set local role authenticated';
  outp:=okb.okb_get_audit(t0,clock_timestamp(),null,100);
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(outp->'items') x where x->>'event'='record_saved' and (x->>'scope_id')::uuid=sb) then raise exception 'FAIL foreign save in the audit log'; end if;
  if not exists(select 1 from jsonb_array_elements(outp->'items') x where x->>'event'='record_saved' and (x->>'record_id')::uuid=(v->>'record_id')::uuid) then raise exception 'FAIL own save missing from the audit log'; end if;
  -- A task assigned to a person leaves their assigned tasks when they lose read in its scope.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  gp:=(okb_tests.okb_grant_permission(gen_random_uuid(),pp,sb,array['activity'],null,array['read'],clock_timestamp()+interval '1 hour','Assignee read')->>'authorisation_id')::uuid;
  assigned:=okb_tests.okb_save_version(other_req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'title','Assigned foreign task',
   'payload',activity_payload||jsonb_build_object('assignee_actor_id',pp)));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pp,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  outp:=okb.okb_get_assigned(false,null,null,100);
  execute 'reset role';
  if not exists(select 1 from jsonb_array_elements(outp->'items') x where (x->>'record_id')::uuid=(assigned->>'record_id')::uuid) then raise exception 'FAIL assigned task missing'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  perform okb_tests.okb_revoke_authorisation(gp,'Assignee loses read');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pp,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  outp:=okb.okb_get_assigned(false,null,null,100);
  execute 'reset role';
  if jsonb_array_length(outp->'items')<>0 then raise exception 'FAIL assigned task in an unreadable scope'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  -- The administrative harness disables a scope while the fixture identity remains restricted.
  update okb.scope set enabled=false where scope_id=sa;
  if okb_tests.okb_get_record((v->>'record_id')::uuid) is not null then raise exception 'FAIL disabled scope read'; end if;
  denied:=false;
  begin perform okb_tests.okb_save_version(req,approved); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL disabled scope retry'; end if;
  update okb.scope set enabled=true where scope_id=sa;
  if okb_tests.okb_get_record((v->>'record_id')::uuid) is null then raise exception 'FAIL re-enabled scope read'; end if;
  -- Issue another exact approval, then remove its required read boundary.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  req:=req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','title','Revoked read boundary');
  outp:=okb_tests.okb_approve_change(gen_random_uuid(),e,req,clock_timestamp()+interval '1 hour','Test revoke read');
  approved:=(outp->>'authorisation_id')::uuid;
  perform okb_tests.okb_revoke_authorisation(grant_id,'Revoke read boundary');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  denied:=false;
  begin perform okb_tests.okb_save_version(req,approved); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL approval bypassed read revocation'; end if;
  if jsonb_array_length(okb_tests.okb_get_progress()->'items')<>0 then raise exception 'FAIL revoked scope progress'; end if;
  set constraints all immediate;
  raise exception 'ROLLBACK_SCOPE_FIXTURES' using errcode='PHT02';
 exception when sqlstate 'PHT02' then null;
 end;
end $tests$;

create function okb_tests.suite_09_grant_expiry() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $tests$
declare h uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); sa uuid:=gen_random_uuid();
 req jsonb; v jsonb; grant_id uuid; outp jsonb; denied boolean; activity_payload jsonb;
begin
 begin
  insert into auth.users(id) values(h);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Scope test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into auth.users(id) values(e);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(e,e,'Scope test restricted agent','agent',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by)
  values(sa,'auth_test_optional_expiry','Auth test scope','Rolled-back fixture',h);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  activity_payload:='{"activity_kind":"task","description":"Test","completion_requirements":"Evidence","state":"pending","baseline_start_at":null,"baseline_finish_at":null,"forecast_start_at":null,"forecast_finish_at":null,"blockers":[],"external_references":[],"completion_note":""}'::jsonb||jsonb_build_object('owner_actor_id',h);
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sa,'kind','activity','expected_previous_version_id',null,'title','Administrator-owned audit','reason','Scope test','payload',activity_payload,'links','[]'::jsonb);
  v:=okb_tests.okb_save_version(req);
  -- A grant with no expiry is standing.
  outp:=okb_tests.okb_grant_permission(gen_random_uuid(),e,sa,array['activity'],null,array['read','create','edit'],null::timestamptz,'Test scope grant');
  grant_id:=(outp->>'authorisation_id')::uuid;
  if outp->'expires_at' is distinct from 'null'::jsonb then raise exception 'FAIL standing grant has expiry'; end if;
  -- An exact approval needs an expiry.
  req:=req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','title','Agent may edit another author');
  denied:=false;
  begin perform okb_tests.okb_approve_change(gen_random_uuid(),e,req,null::timestamptz,'Missing exact expiry'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'FAIL exact approval without expiry'; end if;
  -- The standing grant creates and edits.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sa,'kind','activity','expected_previous_version_id',null,'title','Agent scope fixture','reason','Scope test','payload',activity_payload,'links','[]'::jsonb);
  outp:=okb_tests.okb_save_version(req,grant_id);
  req:=req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',outp->>'version_id','title','Updated agent fixture');
  outp:=okb_tests.okb_save_version(req,grant_id);
  if outp->>'version_number'<>'2' then raise exception 'FAIL standing grant edit'; end if;
  perform set_config('request.jwt.claims','{}',true);
  set constraints all immediate;
  raise exception 'ROLLBACK_OPTIONAL_EXPIRY_FIXTURES' using errcode='PHT02';
 exception when sqlstate 'PHT02' then null;
 end;
end $tests$;

-- -------------------------------------------------------------------
-- Suite: actor-history.
-- The direct-insert refusal is an added assertion.
-- -------------------------------------------------------------------
create function okb_tests.suite_10_actor_history() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $actor_history$
declare h uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); n bigint;
 f uuid:=gen_random_uuid(); fa uuid; g uuid:=gen_random_uuid(); ga uuid; pp uuid:=gen_random_uuid(); pa uuid; x text; rejected boolean; message text;
begin
 if not exists(select 1 from okb.actor) then
  begin
   perform set_config('okb.provisioning_actor','',true);
   rejected:=false;
   begin perform okb_private.provision_first_administrator(null,'No Auth user');
   exception when invalid_parameter_value then get stacked diagnostics message=message_text; rejected:=message='Auth user id required'; end;
   if not rejected then raise exception 'FAIL first administrator without Auth user'; end if;
   insert into auth.users(id) values(f),(g);
   fa:=okb_private.provision_first_administrator(f,'First administrator test');
   if not exists(select 1 from okb.actor where actor_id=fa and auth_user_id=f and actor_kind='human' and accountable_human_id=fa
     and authority_class='administrator' and enabled) then raise exception 'FAIL first administrator created'; end if;
   if not exists(select 1 from okb.actor_change where actor_id=fa) or exists(select 1 from okb.actor_change where actor_id=fa and changed_by_actor_id<>fa)
     then raise exception 'FAIL first administrator self-attribution'; end if;
   if nullif(current_setting('okb.provisioning_actor',true),'') is not null then raise exception 'FAIL first administrator setting leaked'; end if;
   rejected:=false;
   begin perform okb_private.provision_actor_enabled(fa,fa,false);
   exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='At least one enabled administrator must remain'; end;
   if not rejected then raise exception 'FAIL sole administrator disabled themselves'; end if;
   ga:=okb_private.provision_actor(fa,g,'Administrator agent test','agent',fa,'administrator',false);
   rejected:=false;
   begin perform okb_private.provision_actor_enabled(ga,fa,false);
   exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='At least one enabled administrator must remain'; end;
   if not rejected then raise exception 'FAIL last accountable person disabled'; end if;
   raise exception using errcode='PHT06',message='Rollback first-administrator fixtures';
  exception when sqlstate 'PHT06' then null;
  end;
  perform set_config('okb.test_first_administrator','checked',true);
 end if;
 begin
  insert into auth.users(id) values(h),(a);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'History test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(a,a,'History test agent','agent',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  if (select count(*) from okb.actor_change where actor_id in (h,a) and field='auth_user_id' and old_value is null)<>2 then raise exception 'FAIL Auth link audit count'; end if;
  if not exists(select 1 from okb.actor_change where actor_id=a) or exists(select 1 from okb.actor_change where actor_id=a and changed_by_actor_id<>h) then raise exception 'FAIL creation attribution'; end if;
  rejected:=false;
  begin update okb.actor set enabled=false where actor_id=a;
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Actor changes must name the approving administrator'; end;
  if not rejected then raise exception 'FAIL missing approver'; end if;
  perform set_config('okb.provisioning_actor',a::text,true);
  rejected:=false;
  begin update okb.actor set enabled=false where actor_id=a;
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Enabled administrator approver required'; end;
  if not rejected then raise exception 'FAIL restricted approver'; end if;
  perform set_config('okb.provisioning_actor','',true);
  rejected:=false;
  begin perform okb_private.provision_first_administrator(a,'Second first administrator');
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Actor changes must name the approving administrator'; end;
  if not rejected then raise exception 'FAIL first-administrator route reused'; end if;
  insert into auth.users(id) values(d);
  d:=okb_private.provision_actor(h,d,'History test second administrator','human',null,'administrator',false);
  perform okb_private.provision_actor_enabled(h,d,false);
  rejected:=false;
  begin perform okb_private.provision_actor_enabled(d,a,false);
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Enabled administrator approver required'; end;
  if not rejected then raise exception 'FAIL disabled approver'; end if;
  if not exists(select 1 from okb.actor_change where actor_id=d) or exists(select 1 from okb.actor_change where actor_id=d and changed_by_actor_id<>h) then raise exception 'FAIL provisioned attribution'; end if;
  if nullif(current_setting('okb.provisioning_actor',true),'') is not null then raise exception 'FAIL actor provisioning setting leaked'; end if;
  perform set_config('okb.provisioning_actor',h::text,true);
  select count(*) into n from okb.actor_change where actor_id=a;
  update okb.actor set enabled=false where actor_id=a;
  if not exists(select 1 from okb.actor_change where actor_id=a and field='enabled' and old_value='true'::jsonb and new_value='false'::jsonb) then raise exception 'FAIL disable audit'; end if;
  update okb.actor set enabled=true where actor_id=a;
  if (select count(*) from okb.actor_change where actor_id=a)<>n+2 then raise exception 'FAIL enable audit'; end if;
  if exists(select 1 from okb.actor_change where actor_id=a and field='enabled' and changed_by_actor_id<>h) then raise exception 'FAIL change attribution'; end if;
  perform set_config('okb.provisioning_actor','',true);
  rejected:=false;
  begin perform okb_private.provision_actor(h,null,'No Auth user','agent',h,'restricted',false);
  exception when invalid_parameter_value then get stacked diagnostics message=message_text; rejected:=message='Auth user id required'; end;
  if not rejected then raise exception 'FAIL actor without Auth user'; end if;
  insert into auth.users(id) values(pp);
  pa:=okb_private.provision_actor(h,pp,'History test person','human',null,'restricted',false);
  if not exists(select 1 from okb.actor where actor_id=pa and accountable_human_id=pa and actor_kind='human') then raise exception 'FAIL person accountable to themselves'; end if;
  insert into auth.users(id) values(g);
  ga:=okb_private.provision_actor(h,g,'History test agent of a person','agent',pa,'restricted',false);
  if not exists(select 1 from okb.actor where actor_id=ga and accountable_human_id=pa and actor_kind='agent') then raise exception 'FAIL agent accountable to its person'; end if;
  perform set_config('okb.provisioning_actor',h::text,true);
  perform okb_private.provision_actor_enabled(h,ga,false);
  x:=current_setting('okb.provisioning_actor',true);
  if x is distinct from h::text then raise exception 'FAIL provisioning setting not restored'; end if;
  perform set_config('okb.provisioning_actor','',true);
  perform okb_private.provision_actor_enabled(h,ga,true);
  if (select count(*) from okb.actor_change where actor_id=ga and field='enabled' and old_value is not null and changed_by_actor_id=h)<>2
   then raise exception 'FAIL enable and disable attributed'; end if;
  if not (select enabled from okb.actor where actor_id=ga) then raise exception 'FAIL re-enabled'; end if;
  perform set_config('okb.provisioning_actor',h::text,true);
  rejected:=false;
  begin update okb.actor set auth_user_id=null where actor_id=a;
  exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='Auth user link is immutable once set'; end;
  if not rejected then raise exception 'FAIL immutable Auth link'; end if;
  rejected:=false;
  begin update okb.actor_change set field='tampered' where actor_id=a;
  exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='Actor change history is append-only'; end;
  if not rejected then raise exception 'FAIL history update refusal'; end if;
  rejected:=false;
  begin delete from okb.actor_change where actor_id=a;
  exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='Actor change history is append-only'; end;
  if not rejected then raise exception 'FAIL history deletion refusal'; end if;
  rejected:=false;
  begin truncate okb.actor_change;
  exception when check_violation then get stacked diagnostics message=message_text; rejected:=message='Actor change history is append-only'; end;
  if not rejected then raise exception 'FAIL history truncate refusal'; end if;
  rejected:=false;
  begin insert into okb.actor_change(actor_id,field) values(a,'forged');
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Actor change history is written only by the actor trigger'; end;
  if not rejected then raise exception 'FAIL direct history insert refusal'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  rejected:=false;
  begin update okb.actor set enabled=false where actor_id=a;
  exception when insufficient_privilege then get stacked diagnostics message=message_text; rejected:=message='Actor changes require the administrator login without an Auth identity'; end;
  if not rejected then raise exception 'FAIL Auth-context actor update refusal'; end if;
  set constraints all immediate;
  raise exception using errcode='PHT04',message='Rollback actor history fixtures';
 exception when sqlstate 'PHT04' then null;
 end;
end $actor_history$;

-- -------------------------------------------------------------------
-- Suite: provisioning.
-- -------------------------------------------------------------------
create function okb_tests.suite_11_provisioning() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $provisioning$
declare approver uuid:=gen_random_uuid(); agent uuid:=gen_random_uuid(); backup uuid:=gen_random_uuid(); scope uuid:=gen_random_uuid();
 z jsonb; g uuid; denied boolean; message text;
begin
 begin
  insert into auth.users(id) values(approver),(agent);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(approver,approver,'Provisioning test administrator','human',approver,'administrator',true);
  perform okb_tests.approve_fixture(approver);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(agent,agent,'Provisioning test agent','agent',approver,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(scope,'auth_test_provisioning','Provisioning test scope','Rolled-back fixture',approver);
  z:=okb_private.provision_grant(approver,gen_random_uuid(),agent,scope,array['activity'],null,array['read','create','edit'],null::timestamptz,'Rolled-back provisioning verification');
  g:=(z->>'authorisation_id')::uuid;
  if z->>'issued_by_actor_id'<>approver::text or z->>'scope_id'<>scope::text or z->'expires_at'<>'null'::jsonb then raise exception 'FAIL provisioning grant'; end if;
  if nullif(current_setting('okb.provisioning_actor',true),'') is not null then raise exception 'FAIL provisioning setting leaked'; end if;
  z:=okb_private.provision_revocation(approver,g,'Rolled-back revocation verification');
  if z->>'revoked_by_actor_id'<>approver::text or z->>'revoked_at' is null then raise exception 'FAIL provisioning revocation'; end if;
  denied:=false;
  begin perform okb_private.provision_grant(agent,gen_random_uuid(),agent,scope,array['activity'],null,array['read'],null::timestamptz,'Must fail');
  exception when insufficient_privilege then get stacked diagnostics message=message_text; denied:=message='Enabled administrator approver required'; end;
  if not denied then raise exception 'FAIL restricted approver'; end if;
  insert into auth.users(id) values(backup);
  perform okb_private.provision_actor(approver,backup,'Provisioning backup administrator','human',null,'administrator',false);
  begin
   perform set_config('okb.provisioning_actor',approver::text,true);
   update okb.actor set enabled=false where actor_id=approver;
   perform set_config('okb.provisioning_actor','',true);
   denied:=false;
   begin perform okb_private.provision_grant(approver,gen_random_uuid(),agent,scope,array['activity'],null,array['read'],null::timestamptz,'Must fail');
   exception when insufficient_privilege then get stacked diagnostics message=message_text; denied:=message='Enabled administrator approver required'; end;
   if not denied then raise exception 'FAIL disabled approver'; end if;
   raise exception using errcode='PHT05',message='Restore approver';
  exception when sqlstate 'PHT05' then null;
  end;
  perform set_config('okb.provisioning_actor',approver::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',agent,'role','authenticated')::text,true);
  -- Check the internal refusal even while the management login has EXECUTE.
  denied:=false;
  begin perform okb_private.provision_grant(approver,gen_random_uuid(),agent,scope,array['activity'],null,array['read'],null::timestamptz,'Must fail');
  exception when insufficient_privilege then get stacked diagnostics message=message_text; denied:=message='Provisioning requires the administrator login without an Auth identity'; end;
  if not denied then raise exception 'FAIL Auth claims bypassed provisioning guard'; end if;
  execute 'set local role authenticated';
  denied:=false;
  begin perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),agent,scope,array['activity'],null,array['read'],null::timestamptz,'Must fail'));
  exception when insufficient_privilege then get stacked diagnostics message=message_text; denied:=message='Administrator authority required'; end;
  if not denied then raise exception 'FAIL provisioning setting escalated public grant'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT06',message='Rollback provisioning fixtures';
 exception when sqlstate 'PHT06' then null;
 end;
end $provisioning$;

-- the dropped caller-cutover check with catalogue checks of the final grant model.
-- -------------------------------------------------------------------
create function okb_tests.suite_12_grants() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $grants$
declare bad text;
begin
 select string_agg(p.oid::regprocedure::text,', ') into bad from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='okb_task' and has_function_privilege('anon',p.oid,'EXECUTE');
 if bad is not null then raise exception 'FAIL anon execute on task helpers: %',bad; end if;
 select string_agg(p.oid::regprocedure::text,', ') into bad from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='okb' and p.proname like 'okb\_%' escape '\'
  and (not has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'));
 if bad is not null then raise exception 'FAIL okb_* execute grants: %',bad; end if;
 select string_agg(p.oid::regprocedure::text,', ') into bad from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='okb_private' or (n.nspname='okb' and p.proname not like 'okb\_%' escape '\'))
  and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'));
 if bad is not null then raise exception 'FAIL client execute on internal functions: %',bad; end if;
 select string_agg(c.oid::regclass::text,', ') into bad from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('okb','okb_private') and c.relkind in ('r','p','v','m')
  and (has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
   or has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
   or has_any_column_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,REFERENCES')
   or has_any_column_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,REFERENCES'));
 if bad is not null then raise exception 'FAIL client table privileges: %',bad; end if;
 select string_agg(c.oid::regclass::text,', ') into bad from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('okb','okb_private') and c.relkind='S'
  and (has_sequence_privilege('authenticated',c.oid,'USAGE,SELECT,UPDATE') or has_sequence_privilege('anon',c.oid,'USAGE,SELECT,UPDATE'));
 if bad is not null then raise exception 'FAIL client sequence privileges: %',bad; end if;
 if not has_schema_privilege('authenticated','okb','USAGE') or has_schema_privilege('authenticated','okb','CREATE')
  or has_schema_privilege('authenticated','okb_private','USAGE') or has_schema_privilege('anon','okb','USAGE')
  or has_schema_privilege('anon','okb_private','USAGE') then raise exception 'FAIL schema privileges'; end if;
 select string_agg(format('%s in %s',m.rolname,g.rolname),', ') into bad from pg_roles m cross join pg_roles g
  where m.rolname in ('anon','authenticated','authenticator','service_role') and g.rolname in ('okb_owner','okb_identity','okb_writer','okb_reader')
  and pg_has_role(m.oid,g.oid,'MEMBER');
 if bad is not null then raise exception 'FAIL client role holds a OKB role: %',bad; end if;
 select string_agg(format('%s in %s',m.rolname,g.rolname),', ') into bad from pg_auth_members x
  join pg_roles m on m.oid=x.member join pg_roles g on g.oid=x.roleid
  where g.rolname in ('okb_owner','okb_identity','okb_writer','okb_reader') and m.rolname<>'postgres';
 if bad is not null then raise exception 'FAIL unexpected OKB role membership: %',bad; end if;
 if exists(select 1 from pg_roles where rolname in ('okb_owner','okb_identity','okb_writer','okb_reader') and rolcanlogin) then raise exception 'FAIL internal role can log in'; end if;
 select string_agg(c.relname::text,', ') into bad from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='okb' and c.relkind='r' and not c.relrowsecurity;
 if bad is not null then raise exception 'FAIL row-level security not enabled on: %',bad; end if;
 -- Functions any OKB role creates later start with no PUBLIC EXECUTE, in every schema.
 select string_agg(r,', ') into bad from unnest(array['okb_owner','okb_identity','okb_writer','okb_reader']) r
  where not exists(select 1 from pg_default_acl d where d.defaclrole=r::regrole and d.defaclnamespace=0 and d.defaclobjtype='f'
   and not exists(select 1 from aclexplode(d.defaclacl) x where x.grantee=0 and x.privilege_type='EXECUTE'));
 if bad is not null then raise exception 'FAIL default EXECUTE still granted to PUBLIC for: %',bad; end if;
 select string_agg(format('%s owned by %s, expected %s',e.fn,pg_get_userbyid(p.proowner),e.owner),'; ') into bad
 from (values
  ('okb_private.request_auth_uid()','postgres'),
  ('okb_private.sign_ins()','postgres'),
  ('okb_private.current_actor()','okb_identity'),
  ('okb_private.authority_live(uuid)','okb_identity'),
  ('okb_private.scope_read_for(uuid,uuid,text,uuid)','okb_identity'),
  ('okb_private.can_read_record(uuid)','okb_identity'),
  ('okb_private.can_read_scope(uuid)','okb_identity'),
  ('okb_private.can_see_scope(uuid)','okb_identity'),
  ('okb_private.is_own_record(uuid,uuid)','okb_identity'),
  ('okb_private.scope_insert_for(uuid,uuid,text)','okb_identity'),
  ('okb_private.assert_request_scope(jsonb,uuid)','okb_identity'),
  ('okb_private.can_insert_record(uuid,text)','okb_identity'),
  ('okb_private.can_insert_version(uuid,uuid)','okb_identity'),
  ('okb_private.can_link(uuid,uuid)','okb_identity'),
  ('okb_private.guard_actor_reference()','okb_identity'),
  ('okb_private.acting_actor()','okb_identity'),
  ('okb_private.deleting_record()','okb_identity'),
  ('okb_private.deletion_facts(uuid)','okb_identity'),
  ('okb_private.actor_name(uuid)','okb_identity'),
  ('okb_private.carries_record(jsonb,uuid)','okb_identity'),
  ('okb_private.erased_request(jsonb,uuid)','okb_identity'),
  ('okb_private.scope_name(uuid)','okb_identity'),
  ('okb_private.readable_records()','okb_identity'),
  ('okb_private.readable_records(uuid,text,text,timestamptz,timestamptz)','okb_identity'),
  ('okb_private.read_grants(uuid)','okb_identity'),
  ('okb_private.read_grants()','okb_identity'),
  ('okb_private.link_targets(jsonb)','okb_identity'),
  ('okb_private.activity_loop(uuid,text,uuid[])','okb_identity'),
  ('okb_private.audit_versions(timestamptz,timestamptz)','okb_identity'),
  ('okb_private.read_progress(bigint,timestamptz,uuid,integer,uuid)','okb_identity'),
  ('okb_private.read_records(text,uuid,text,bigint,bigint,integer)','okb_identity'),
  ('okb_private.read_assigned(boolean,bigint,integer,integer)','okb_identity'),
  ('okb_private.lock_writes()','okb_owner'),
  ('okb_private.hold_records(uuid[],boolean)','okb_owner'),
  ('okb_private.hold_approval(uuid)','okb_owner'),
  ('okb_private.guard_actor_change()','okb_owner'),
  ('okb_private.guard_version()','okb_owner'),
  ('okb_private.guard_version_link()','okb_owner'),
  ('okb_private.guard_authorisation()','okb_owner'),
  ('okb_private.guard_scope()','okb_owner'),
  ('okb_private.log_actor_change()','okb_owner'),
  ('okb_private.guard_actor_change_log()','okb_owner'),
  ('okb_private.guard_approver_remains()','okb_owner'),
  ('okb_private.guard_record_deletion()','okb_owner'),
  ('okb_private.guard_file_event()','okb_owner'),
  ('okb_private.log_file_event()','okb_owner'),
  ('okb_private.guard_sign_in_event()','okb_owner'),
  ('okb_private.log_sign_in_event()','okb_owner'),
  ('okb_private.erase_record(jsonb,uuid,uuid,uuid)','okb_owner'),
  ('okb_private.guard_record_move()','okb_owner'),
  ('okb_private.move_records(jsonb,uuid,jsonb)','okb_owner'),
  ('okb_private.renaming_scope()','okb_owner'),
  ('okb_private.guard_scope_change()','okb_owner'),
  ('okb_private.rename_scope(uuid,text,text,uuid,text)','okb_owner'),
  ('okb_private.deleting_scope()','okb_owner'),
  ('okb_private.guard_scope_deletion()','okb_owner'),
  ('okb_private.delete_scope(uuid,uuid,text)','okb_owner'),
  ('okb_private.opening_scope()','okb_owner'),
  ('okb_private.handing_on_scope()','okb_owner'),
  ('okb_private.open_scope_for(uuid,uuid)','okb_owner'),
  ('okb_private.add_scope(text,text,text,boolean,uuid,uuid,text)','okb_owner'),
  ('okb_private.hand_on_scope(uuid,uuid,uuid,text)','okb_owner'),
  ('okb_private.scope_owner(uuid)','okb_identity'),
  ('okb_private.granting_scopes()','okb_identity'),
  ('okb_private.can_move(uuid,uuid,uuid)','okb_identity'),
  ('okb_private.read_scopes(uuid,integer)','okb_identity'),
  ('okb_private.find_actors(text)','okb_identity'),
  ('okb_private.moving_records()','okb_identity'),
  ('okb_private.named_scope(text)','okb_identity'),
  ('okb_private.named_record(text)','okb_identity'),
  ('okb_private.move_facts(uuid[],uuid)','okb_identity'),
  ('okb_private.move_result(uuid)','okb_identity'),
  ('okb_private.provision_first_administrator(uuid,text)','okb_owner'),
  ('okb_private.provision_actor(uuid,uuid,text,text,uuid,text,boolean)','okb_owner'),
  ('okb_private.provision_actor_enabled(uuid,uuid,boolean)','okb_owner'),
  ('okb_private.require_object(jsonb,text[],text[])','okb_writer'),
  ('okb_private.require_text(jsonb,text,boolean,integer,boolean)','okb_writer'),
  ('okb_private.require_array(jsonb,text,integer)','okb_writer'),
  ('okb_private.iso_time(jsonb,text)','okb_writer'),
  ('okb_private.validate_reference(text)','okb_writer'),
  ('okb_private.validate_reference(text,text)','okb_writer'),
  ('okb_private.canonical_request_hash(jsonb,uuid,uuid)','okb_writer'),
  ('okb_private.validate_shape(jsonb)','okb_writer'),
  ('okb_private.validate_version(jsonb)','okb_writer'),
  ('okb_private.check_version(jsonb)','okb_identity'),
  ('okb_private.assert_authority(jsonb,uuid,text[])','okb_writer'),
  ('okb_private.validate_deletion(jsonb)','okb_writer'),
  ('okb_private.provision_grant(uuid,uuid,uuid,uuid,text[],uuid,text[],timestamptz,text,boolean)','okb_writer'),
  ('okb_private.provision_revocation(uuid,uuid,text)','okb_writer'),
  ('okb_private.read_actor()','okb_reader'),
  ('okb_private.read_cutoff(bigint)','okb_reader'),
  ('okb.okb_get_unextracted(text,integer)','postgres'),
  ('okb.okb_save_extraction(uuid,jsonb,jsonb,boolean)','postgres'),
  ('okb.okb_grant_permission(uuid,uuid,text[],uuid,text[],timestamptz,text)','okb_writer'),
  ('okb.okb_grant_permission(uuid,uuid,uuid,text[],uuid,text[],timestamptz,text,boolean)','okb_writer'),
  ('okb.okb_approve_change(uuid,uuid,jsonb,timestamptz,text)','okb_writer'),
  ('okb.okb_revoke_authorisation(uuid,text)','okb_writer'),
  ('okb.okb_save_version(jsonb,uuid)','okb_writer'),
  ('okb.okb_delete_record(jsonb,uuid)','okb_writer'),
  ('okb.okb_preview_deletion(uuid)','okb_reader'),
  ('okb.okb_preview_move(text[],text,text)','okb_reader'),
  ('okb.okb_move_records(jsonb)','okb_writer'),
  ('okb.okb_rename_scope(text,text,text,text)','okb_writer'),
  ('okb.okb_delete_scope(text,text)','okb_writer'),
  ('okb.okb_add_scope(text,text,text,text,boolean,text)','okb_writer'),
  ('okb.okb_hand_on_scope(text,text,text)','okb_writer'),
  ('okb.okb_find_actors(text)','okb_reader'),
  ('okb.okb_get_record(uuid,bigint)','okb_reader'),
  ('okb.okb_get_authorisations(uuid,uuid,integer)','okb_reader'),
  ('okb.okb_get_history(uuid,bigint,bigint,integer)','okb_reader'),
  ('okb.okb_get_progress(bigint,timestamptz,uuid,integer,uuid)','okb_reader'),
  ('okb.okb_get_progress(bigint,timestamptz,uuid,integer)','okb_reader'),
  ('okb.okb_get_scopes(uuid,integer)','okb_reader'),
  ('okb.okb_find_records(text,uuid,text,bigint,bigint,integer)','okb_reader'),
  ('okb.okb_get_assigned(boolean,bigint,integer,integer)','okb_reader'),
  ('okb.okb_get_actor()','okb_reader'),
  ('okb.okb_get_audit(timestamptz,timestamptz,text,integer)','okb_reader'),
  ('okb.okb_get_sign_ins()','okb_reader'),
  ('okb.okb_get_reference(text)','okb_reader'),
  ('okb.okb_save_term(text,text,text,text,text[],text,text,boolean)','okb_reader'),
  ('okb.okb_save_dictionary(text,text,text,jsonb,text,boolean)','okb_reader'),
  ('okb_private.reference_scope()','okb_identity'),
  ('okb_private.in_reference_scope(uuid)','okb_identity'),
  ('okb_private.keep_reference()','okb_writer'),
  ('okb_private.forget_reference()','okb_writer')
 ) as e(fn,owner) join pg_proc p on p.oid=e.fn::regprocedure
 where pg_get_userbyid(p.proowner)<>e.owner;
 if bad is not null then raise exception 'FAIL function ownership: %',bad; end if;
end $grants$;

-- -------------------------------------------------------------------
-- Suite: files. Access follows the scope: read lists and downloads, create uploads, and
-- read, create and edit together replace, and read with delete deletes any file in the scope,
-- whatever record kinds the grant names.
-- A replace is what the Storage API's upload with x-upsert issues: an insert that
-- updates the existing row on conflict, which PostgreSQL checks against the insert, select
-- and update rules alike. The HTTP path itself is not driven here.
-- -------------------------------------------------------------------
create function okb_tests.suite_13_files() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $files$
declare h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); w uuid:=gen_random_uuid(); o uuid:=gen_random_uuid();
 c uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); x uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); dn uuid:=gen_random_uuid();
 sc uuid:=gen_random_uuid(); g jsonb; gd jsonb; n bigint; denied boolean; stray text;
begin
 -- PostgreSQL allows a file action if any permissive rule allows it, so only OKB's four may
 -- exist. Checked first, so a stray rule is named before it makes an actor check fail.
 select string_agg(policyname,', ' order by policyname) into stray from pg_policies
  where schemaname='storage' and tablename='objects' and permissive='PERMISSIVE'
   and policyname not in ('OKB: list and download with read permission',
    'OKB: upload with create permission','OKB: replace with edit permission',
    'OKB: delete with delete permission');
 if stray is not null then raise exception 'FAIL files: another permissive rule on storage.objects widens access: %',stray; end if;
 begin
  insert into auth.users(id) values(h),(r),(w),(o),(c),(e),(x),(d),(dn);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Files test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(r,r,'Files test reader','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(w,w,'Files test writer','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(o,o,'Files test outsider','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(c,c,'Files test creator','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(e,e,'Files test editor','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(x,x,'Files test unreading writer','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(d,d,'Files test deleter','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(dn,dn,'Files test unreading deleter','agent',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_files','Files test scope','Rolled-back fixture',h);
  if not exists(select 1 from storage.buckets where id='auth_test_files' and not public) then
   raise exception 'FAIL files: a new scope has no private bucket'; end if;
  -- A scope never takes over a bucket that already exists.
  insert into storage.buckets(id,name,public) values('auth_test_taken','auth_test_taken',true);
  denied:=false;
  begin insert into okb.scope(code,display_name,description,created_by) values('auth_test_taken','Taken','Rolled-back fixture',h);
  exception when unique_violation then denied:=true; end;
  if not denied then raise exception 'FAIL files: a scope adopted an existing bucket'; end if;
  -- The reader's grant names only activity records: files ignore record kinds.
  perform okb_private.provision_grant(h,gen_random_uuid(),r,sc,array['activity'],null,array['read'],null::timestamptz,'Files read');
  g:=okb_private.provision_grant(h,gen_random_uuid(),w,sc,array['evidence'],null,array['read','create','edit'],null::timestamptz,'Files write');
  perform okb_private.provision_grant(h,gen_random_uuid(),c,sc,array['activity'],null,array['read','create'],null::timestamptz,'Files create only');
  perform okb_private.provision_grant(h,gen_random_uuid(),e,sc,array['activity'],null,array['read','edit'],null::timestamptz,'Files edit only');
  perform okb_private.provision_grant(h,gen_random_uuid(),x,sc,array['activity'],null,array['create','edit'],null::timestamptz,'Files create and edit without read');
  gd:=okb_private.provision_grant(h,gen_random_uuid(),d,sc,array['activity'],null,array['read','delete'],null::timestamptz,'Files read and delete');
  perform okb_private.provision_grant(h,gen_random_uuid(),dn,sc,array['activity'],null,array['delete'],null::timestamptz,'Files delete without read');

  -- A replace is the upsert Supabase's Storage API runs, on the current version of each name.
  -- The writer, with read, create and edit, uploads and replaces.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','source.pdf',w::text);
  insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','source.pdf',w::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  get diagnostics n=row_count; if n<>1 then raise exception 'FAIL files: replace with read, create and edit permission'; end if;
  execute 'reset role';

  -- Read and edit without create neither replace an existing file nor add a new one.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','source.pdf',e::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL files: replace without create permission'; end if;
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','editor.pdf',e::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL files: upload without create permission'; end if;
  execute 'reset role';

  -- Create and edit without read cannot replace an existing file either: the replace reads the file it replaces.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',x,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','source.pdf',x::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL files: replace without read permission'; end if;
  execute 'reset role';

  -- Create permission alone uploads a new file, and cannot replace an existing one.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','creator.pdf',c::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','source.pdf',c::text)
   on conflict (bucket_id,name collate "C") where archived_at is null do update set owner_id=excluded.owner_id, updated_at=clock_timestamp();
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FAIL files: replace with create permission only'; end if;
  execute 'reset role';

  -- The reader sees the file, and cannot replace it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='auth_test_files';
  if n<>2 then raise exception 'FAIL files: read permission lists the scope''s files'; end if;
  update storage.objects set name='changed.pdf' where bucket_id='auth_test_files';
  get diagnostics n=row_count; if n<>0 then raise exception 'FAIL files: replace without edit permission'; end if;
  execute 'reset role';

  -- The outsider sees nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='auth_test_files';
  if n<>0 then raise exception 'FAIL files: an actor without permission sees files'; end if;
  execute 'reset role';

  -- Deleting a file needs its own delete permission, with read: an actor who may read and delete
  -- in a scope can delete any file in it, whoever uploaded it. Create or edit alone deletes nothing.

  -- These deletes stand in for the Storage API's, which Supabase's storage.protect_delete lets through.
  perform set_config('storage.allow_delete_query','true',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner_id) values('auth_test_files','writer-draft.pdf',w::text);
  delete from storage.objects where bucket_id='auth_test_files' and name='writer-draft.pdf';
  get diagnostics n=row_count; if n<>0 then raise exception 'FAIL files: create and edit permission deleted a file'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',dn,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id='auth_test_files' and name='writer-draft.pdf';
  get diagnostics n=row_count; if n<>0 then raise exception 'FAIL files: delete permission without read deleted a file'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id='auth_test_files' and name='writer-draft.pdf';
  get diagnostics n=row_count; if n<>1 then raise exception 'FAIL files: an actor with read and delete permission could not delete another actor''s file'; end if;
  execute 'reset role';
  -- Revoking the delete grant stops the deleting at once.
  perform set_config('request.jwt.claims','{}',true);
  perform okb_private.provision_revocation(h,(gd->>'authorisation_id')::uuid,'Files delete revocation check');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id='auth_test_files' and name='creator.pdf';
  get diagnostics n=row_count; if n<>0 then raise exception 'FAIL files: a revoked delete grant still deletes files'; end if;
  execute 'reset role';

  -- Revoking the writer's grant stops their access at once.
  perform set_config('request.jwt.claims','{}',true);
  perform okb_private.provision_revocation(h,(g->>'authorisation_id')::uuid,'Files revocation check');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='auth_test_files';
  if n<>0 then raise exception 'FAIL files: a revoked grant still lists files'; end if;
  execute 'reset role';

  -- Disabling the scope stops the reader too.
  perform set_config('request.jwt.claims','{}',true);
  update okb.scope set enabled=false where scope_id=sc;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='auth_test_files';
  if n<>0 then raise exception 'FAIL files: a disabled scope still lists files'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);

  if has_schema_privilege('authenticated','okb_tests','usage') or has_schema_privilege('anon','okb_tests','usage')
   or has_schema_privilege('service_role','okb_tests','usage')
   or has_function_privilege('authenticated','okb_tests.run()','execute') or has_function_privilege('anon','okb_tests.run()','execute')
   or has_function_privilege('service_role','okb_tests.run()','execute')
   or has_function_privilege('public','okb_tests.run()','execute') then raise exception 'FAIL a client role may use the checks'; end if;
  if has_function_privilege('anon','okb_storage.usable_buckets(text)','execute')
   or has_function_privilege('public','okb_storage.usable_buckets(text)','execute')
   or has_schema_privilege('anon','okb_storage','usage') then raise exception 'FAIL files: anonymous access to the permission check'; end if;
  raise exception using errcode='PHT07',message='Rollback files fixtures';
 exception when sqlstate 'PHT07' then null;
 end;
end $files$;

-- -------------------------------------------------------------------
-- Suite: file search. Needs file-search.sql and file-search-scopes.sql.
-- Every scope's bucket is indexed, and OKB's storage rules decide who finds what: an actor
-- finds chunks only in scopes they may read. The reference scope's bucket is ranked apart, and a
-- sessions scope's is not searched by default. Fixed chunks stand in for the worker.
-- -------------------------------------------------------------------
create function okb_tests.suite_14_search() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $search$
declare h uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); w uuid:=gen_random_uuid(); w2 uuid:=gen_random_uuid();
 sc uuid:=gen_random_uuid(); g jsonb; fv uuid; res jsonb; ch uuid; msg text;
 search_as text:='select file_search.search(%L,null,''auth_test_search'')';
begin
 if to_regclass('file_search.indexed_bucket') is null or to_regprocedure('okb_storage.index_scope_bucket()') is null then
  raise exception 'FAIL file search: run file-search.sql and file-search-scopes.sql first'; end if;
 begin
  insert into auth.users(id) values(h),(r),(o),(w),(w2);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Search test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(r,r,'Search test reader','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(o,o,'Search test outsider','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(w,w,'Search test writer','agent',h,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(w2,w2,'Search test second writer','agent',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_search','Search test scope','Rolled-back fixture',h);
  if not exists(select 1 from file_search.indexed_bucket where bucket_id='auth_test_search') then
   raise exception 'FAIL file search: a new scope''s bucket is not indexed'; end if;
  -- A search across every scope ranks the reference scope apart, and leaves out each sessions scope.
  if not exists(select 1 from file_search.indexed_bucket where bucket_id='auth_test_search' and searched_by_default and not ranked_apart) then
   raise exception 'FAIL file search: a new scope''s bucket is ranked apart or not searched by default'; end if;
  insert into okb.scope(code,display_name,description,created_by) values('sessions_auth_test_search','Search test sessions','Rolled-back fixture',h);
  if not exists(select 1 from file_search.indexed_bucket where bucket_id='sessions_auth_test_search' and not searched_by_default and not ranked_apart) then
   raise exception 'FAIL file search: a new sessions scope''s bucket is searched by default'; end if;
  -- File search leaves out the plugins scope, and any scope whose code starts plugins_.
  if exists(select 1 from file_search.indexed_bucket where bucket_id='plugins') then
   raise exception 'FAIL file search: the plugins scope''s bucket is indexed'; end if;
  insert into okb.scope(code,display_name,description,created_by) values('plugins_auth_test_search','Search test plugins','Rolled-back fixture',h);
  if exists(select 1 from file_search.indexed_bucket where bucket_id='plugins_auth_test_search') then
   raise exception 'FAIL file search: a new plugins_ scope''s bucket is indexed'; end if;
  if not exists(select 1 from okb.scope where code='reference') then
   insert into okb.scope(code,display_name,description,created_by) values('reference','Reference data','Rolled-back fixture',h);
  end if;
  if not exists(select 1 from file_search.indexed_bucket where bucket_id='reference' and ranked_apart and searched_by_default) then
   raise exception 'FAIL file search: the reference scope''s bucket is not ranked apart'; end if;
  if not exists(select 1 from okb.scope where code='plugins') then
   insert into okb.scope(code,display_name,description,created_by) values('plugins','Plugins','Rolled-back fixture',h);
  end if;
  if exists(select 1 from file_search.indexed_bucket where bucket_id='plugins' and ranked_apart) then
   raise exception 'FAIL file search: the plugins scope''s bucket is ranked apart'; end if;
  if exists(select 1 from file_search.indexed_bucket where ranked_apart and bucket_id<>'reference') then
   raise exception 'FAIL file search: a bucket other than the reference scope''s is ranked apart'; end if;
  g:=okb_private.provision_grant(h,gen_random_uuid(),r,sc,array['activity'],null,array['read'],null::timestamptz,'Search read');
  perform okb_private.provision_grant(h,gen_random_uuid(),w,sc,array['activity'],null,array['read','create'],null::timestamptz,'Search read and create');
  perform okb_private.provision_grant(h,gen_random_uuid(),w2,sc,array['activity'],null,array['read','create'],null::timestamptz,'Search read and create');

  insert into storage.objects(bucket_id,name,owner_id,metadata) values('auth_test_search','pricing.pdf',h::text,'{"eTag":"a1"}');
  select version_id into fv from file_search.file_version where bucket_id='auth_test_search' and name='pricing.pdf' and state='waiting';
  if fv is null then raise exception 'FAIL file search: a file in a scope''s bucket was not queued'; end if;
  perform file_search.record_file_text(fv,'extracted',jsonb_build_array(
   jsonb_build_object('ordinal',0,'place','page 1','body','Wholesale price list for spring bedding, including duvets.','section',0)),null,
   jsonb_build_array(jsonb_build_object('ordinal',0,'place','page 1','body','Wholesale price list for spring bedding, including duvets.')));

  -- The reader finds it; the outsider does not.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  execute format(search_as,'duvets') into res;
  if jsonb_array_length(res->'hits')<>1 or res->'hits'->0->>'file'<>'pricing.pdf' then raise exception 'FAIL file search: the reader did not find the file: %',res; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  execute format(search_as,'duvets') into res;
  if jsonb_array_length(res->'hits')<>0 then raise exception 'FAIL file search: an actor without read permission found %',res; end if;
  execute 'reset role';

  -- The graph's entity types and relation names: the glossary's classes and relationships.
  if not exists(select 1 from okb.scope where code='reference') then
   insert into okb.scope(code,display_name,description,created_by) values('reference','Reference data','Rolled-back fixture',h);
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_save_term('Search test product','class','A thing the firm sells.','Search test'));
  perform pg_temp.raised(okb.okb_save_term('Search test document','class','A file the firm keeps.','Search test'));
  perform pg_temp.raised(okb.okb_save_term('Search test prices','relationship','Gives the price of.','Search test',
   p_from_class=>'Search test document',p_to_class=>'Search test product'));
  execute 'reset role';

  -- The graph. A reader lists the chunks waiting for their graph, with the glossary's classes and
  -- relationships, and cannot save one; an actor with read and create saves it, named as its saver;
  -- an outsider does neither, and sees none of it.
  select chunk_id into ch from file_search.chunk c where c.version_id=fv;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  res:=okb.okb_get_unextracted('Search test scope',10);
  if res->>'code'<>'auth_test_search' or (res->>'waiting')::integer<>1 or res->'chunks'->0->>'chunk_id'<>ch::text then
   raise exception 'FAIL graph: a reader did not list the chunk waiting for its graph: %',res; end if;
  if not res->'classes' @> '["Search test document","Search test product"]'
   or not res->'relationships' @> '[{"relationship":"Search test prices","from_class":"Search test document","to_class":"Search test product"}]' then
   raise exception 'FAIL graph: the chunks waiting do not come with the glossary''s classes and relationships: %',res; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Product","description":"Bedding."}]')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Saving a chunk''s entities and relations needs create permission in its scope' then
   raise exception 'FAIL graph: a reader without create saved a chunk''s graph: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform okb.okb_get_unextracted('auth_test_search',10); exception when sqlstate '42501' then msg:='refused'; end;
  if msg is null then raise exception 'FAIL graph: an outsider listed a scope''s chunks'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Product","description":"Bedding."}]')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'Chunk unavailable%' then raise exception 'FAIL graph: an outsider saved a chunk''s graph: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  -- An entity whose type is not a glossary class, a relation that names no relationship, and a
  -- relation whose ends are the wrong classes are refused.
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Bedding","description":"Spring bedding."}]')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The entity "Duvet" has the type "Bedding", which is not a class in the glossary. An entity''s type is one of the classes okb_get_unextracted lists' then
   raise exception 'FAIL graph: an entity whose type is not a class: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Search test product","description":"Spring bedding."},{"name":"Spring price list","type":"Search test document","description":"Lists wholesale prices."}]',
   '[{"source":"Spring price list","target":"Duvet","relationship":"lists","description":"The price list lists duvets."}]')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The relation from "Spring price list" to "Duvet" names "lists", which is not a relationship in the glossary. A relation names one of the relationships okb_get_unextracted lists' then
   raise exception 'FAIL graph: a relation that names no relationship: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Search test product","description":"Spring bedding."},{"name":"Spring price list","type":"Search test document","description":"Lists wholesale prices."}]',
   '[{"source":"Duvet","target":"Spring price list","relationship":"Search test prices","description":"Backwards."}]')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The relationship "Search test prices" goes from a Search test document to a Search test product, and "Duvet" is a Search test product and "Spring price list" a Search test document' then
   raise exception 'FAIL graph: a relation between the wrong classes: %',msg; end if;
  res:=pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"search test PRODUCT","description":"Spring bedding."},{"name":"Spring price list","type":"Search test document","description":"Lists wholesale prices."}]',
   '[{"source":"Spring price list","target":"Duvet","relationship":"search test prices","keywords":["wholesale"],"description":"The price list prices duvets."}]'));
  if res->>'saved'<>'true' or (res->>'entities')::integer<>2 or (res->>'relations')::integer<>1 then raise exception 'FAIL graph: a save with read and create: %',res; end if;
  if (okb.okb_get_unextracted('auth_test_search',10)->>'waiting')::integer<>0 then raise exception 'FAIL graph: a saved chunk still waits'; end if;
  execute 'reset role';
  if (select entity_type from file_search.entity where name_key='duvet')<>'Search test product'
   or (select keywords from file_search.relation_source where chunk_id=ch)<>array['search test prices','wholesale'] then
   raise exception 'FAIL graph: an entity''s type is not saved as the glossary''s class, or a relation does not keep its relationship''s name'; end if;
  if (select string_agg(distinct saved_by_name,',') from file_search.entity_source where chunk_id=ch)<>'Search test writer'
   or (select saved_by from file_search.chunk_extraction where chunk_id=ch)<>w then
   raise exception 'FAIL graph: the save does not name the actor who saved it'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if (select count(*) from file_search.entity e where e.name_key in ('duvet','spring price list'))<>2 then raise exception 'FAIL graph: a reader does not see the scope''s entities'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from file_search.entity e where e.name_key in ('duvet','spring price list')) or exists(select 1 from file_search.relation_source where chunk_id=ch) then
   raise exception 'FAIL graph: an outsider sees the scope''s entities or relations'; end if;
  execute 'reset role';
  -- Another actor with create may not replace the writer's extraction; the writer and an administrator may.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w2,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_extraction(ch,'[]','[]',true)); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'Only the actor who saved%Search test writer' then raise exception 'FAIL graph: another actor replaced a chunk''s graph: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',w,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  res:=pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Search test product","description":"Spring bedding."}]','[]',true));
  if res->>'replaced'<>'true' or (res->>'entities')::integer<>1 then raise exception 'FAIL graph: the saver could not replace their extraction: %',res; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  res:=pg_temp.raised(okb.okb_save_extraction(ch,'[{"name":"Duvet","type":"Search test product","description":"Spring bedding."},{"name":"Spring price list","type":"Search test document","description":"Lists wholesale prices."}]','[]',true));
  if res->>'replaced'<>'true' then raise exception 'FAIL graph: an administrator could not replace an extraction: %',res; end if;
  execute 'reset role';
  if (select saved_by from file_search.chunk_extraction where chunk_id=ch)<>h then raise exception 'FAIL graph: a replacement does not name its saver'; end if;

  -- A disabled scope, then a revoked grant, stop the reader finding it.
  perform set_config('request.jwt.claims','{}',true);
  update okb.scope set enabled=false where scope_id=sc;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  execute format(search_as,'duvets') into res;
  if jsonb_array_length(res->'hits')<>0 then raise exception 'FAIL file search: a disabled scope was still searched'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  update okb.scope set enabled=true where scope_id=sc;
  perform okb_private.provision_revocation(h,(g->>'authorisation_id')::uuid,'Search revocation check');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  execute format(search_as,'duvets') into res;
  if jsonb_array_length(res->'hits')<>0 then raise exception 'FAIL file search: a revoked grant still searched'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);

  raise exception using errcode='PHT08',message='Rollback file search fixtures';
 exception when sqlstate 'PHT08' then null;
 end;
end $search$;

-- Runs every suite in order, then ends in an error, so the whole run rolls back.
-- -------------------------------------------------------------------
-- Suite: record deletion. A person granted delete deletes an activity under a human
-- administrator's exact approval, used once. Its content goes from every version, and its log
-- keeps the fingerprint. An agent administrator cannot approve a deletion, and nothing but a
-- deletion can empty a version or change the log.
-- -------------------------------------------------------------------
create function okb_tests.suite_15_record_deletion() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $deletion$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); ga uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid();
 act uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); gp uuid; req jsonb; v jsonb; prev jsonb; delreq jsonb; appr jsonb; rcpt jsonb;
 msg text; prog jsonb;
begin
 begin
  insert into auth.users(id) values(h),(p),(ga);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Deletion test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Deletion test person','human',p,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ga,ga,'Deletion test agent administrator','agent',h,'administrator',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_deletion','Deletion test scope','Rolled-back fixture',h);
  gp:=(okb_private.provision_grant(h,gen_random_uuid(),p,sc,array['activity'],null,array['read','create','edit','delete'],null::timestamptz,'Deletion test grant')->>'authorisation_id')::uuid;

  -- The person saves two activities; the first, a plan, is the one deleted, and the second is a task under it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',act,'scope_id',sc,'kind','activity','expected_previous_version_id',null,
   'title','Call Jane Doe on 07700 900123','reason','Deletion test','links','[]'::jsonb,
   'payload',jsonb_build_object('activity_kind','plan','state','pending','description','Jane Doe, 07700 900123','owner_actor_id',h,
    'completion_requirements','Called','completion_note','','baseline_start_at',null,'baseline_finish_at',null,
    'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb));
  v:=pg_temp.raised(okb.okb_save_version(req,gp));
  perform pg_temp.raised(okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',other,'title','Another task',
   'links',jsonb_build_array(jsonb_build_object('target_version_id',v->>'version_id','relation','parent')),'payload',
   jsonb_set(jsonb_set(req->'payload','{description}','"Kept"'),'{activity_kind}','"task"')),gp));
  prog:=okb.okb_get_progress(null,null,null,100,sc);
  if (select i#>>'{parent,record_id}' from jsonb_array_elements(prog->'items') i where i->>'record_id'=other::text) is distinct from act::text then
   raise exception 'FAIL deletion: the task does not name its plan as its parent %',prog; end if;
  prev:=okb.okb_preview_deletion(act);
  if (prev->>'versions')::int<>1 or position(other::text in prev->>'dependents')=0 or prev->'request'->>'record_id'<>act::text then raise exception 'FAIL deletion: preview %',prev; end if;
  delreq:=jsonb_set(prev->'request','{reason}','"Asked to be forgotten"');
  execute 'reset role';
  if exists(select 1 from okb.record where record_id=act and deleted_at is not null) then raise exception 'FAIL deletion: a preview changed the record'; end if;

  -- An agent administrator cannot approve a deletion; a human administrator can.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ga,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),p,delreq,clock_timestamp()+interval '1 hour','Agent approval'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Record deletion needs a human administrator''s approval' then raise exception 'FAIL deletion: an agent approved: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  appr:=pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),p,delreq,clock_timestamp()+interval '1 hour','Erasure'));
  execute 'reset role';

  -- The deletion runs once; the approval is then used, and the activity leaves progress.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  rcpt:=pg_temp.raised(okb.okb_delete_record(delreq,(appr->>'authorisation_id')::uuid));
  if (rcpt->>'versions_emptied')::int<>1 or rcpt->>'content_sha256' !~ '^[0-9a-f]{64}$' then raise exception 'FAIL deletion: receipt %',rcpt; end if;
  if pg_temp.raised(okb.okb_delete_record(delreq,(appr->>'authorisation_id')::uuid))->>'deletion_id' is distinct from rcpt->>'deletion_id' then
   raise exception 'FAIL deletion: a retry of the same request did not return its receipt'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_delete_record(jsonb_build_object('operation','delete','request_id',gen_random_uuid(),'record_id',other,'scope_id',sc,
    'kind','activity','reason','Reuse','dependents','[]'::jsonb),(appr->>'authorisation_id')::uuid));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Action outside authority scope' then raise exception 'FAIL deletion: an approval covered another record: %',msg; end if;
  prog:=okb.okb_get_progress(null,null,null,100,sc);
  if (prog->'counts'->>'pending')::int<>1 or exists(select 1 from jsonb_array_elements(prog->'items') i where i->>'record_id'=act::text) then
   raise exception 'FAIL deletion: progress still counts the deleted activity %',prog; end if;
  if (select i->'parent' from jsonb_array_elements(prog->'items') i where i->>'record_id'=other::text) is distinct from 'null'::jsonb then
   raise exception 'FAIL deletion: a task still names its deleted plan as its parent %',prog; end if;
  prog:=okb.okb_find_records(null,sc);
  if jsonb_array_length(prog->'items')<>1 or prog->'items'->0->>'record_id'<>other::text then
   raise exception 'FAIL deletion: finding records still lists the deleted activity %',prog; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);

  if exists(select 1 from okb.record_version where record_id=act and (title<>'Deleted' or change_reason<>'Deleted' or payload<>'{}'::jsonb))
   or exists(select 1 from okb.record_version where record_id in (act,other) and record_version::text like '%07700 900123%') then
   raise exception 'FAIL deletion: content remains in a version'; end if;
  if (select consumed_deletion_id::text from okb.authorisation where authorisation_id=(appr->>'authorisation_id')::uuid) is distinct from rcpt->>'deletion_id' then
   raise exception 'FAIL deletion: the approval is not marked used by the deletion'; end if;
  if (select content_sha256 from okb.record_deletion where record_id=act) is distinct from rcpt->>'content_sha256' then
   raise exception 'FAIL deletion: the log does not hold the fingerprint'; end if;

  -- Nothing but a deletion empties a version or changes the log.
  msg:=null;
  begin update okb.record_version set payload='{}'::jsonb,title='Deleted',change_reason='Deleted' where record_id=other;
  exception when sqlstate '23514' then msg:=sqlerrm; end;
  if msg is distinct from 'Saved versions and record identities are immutable' then raise exception 'FAIL deletion: a version was emptied directly: %',msg; end if;
  msg:=null;
  begin update okb.record_deletion set reason='Changed' where record_id=act;
  exception when sqlstate '23514' then msg:=sqlerrm; end;
  if msg is distinct from 'Record deletions are append-only; use okb_delete_record' then raise exception 'FAIL deletion: the log was changed: %',msg; end if;
  msg:=null;
  begin delete from okb.record_deletion where record_id=act;
  exception when sqlstate '23514' then msg:=sqlerrm; end;
  if msg is distinct from 'Record deletions are append-only; use okb_delete_record' then raise exception 'FAIL deletion: the log was deleted from: %',msg; end if;
  raise exception using errcode='PHT15',message='Rollback deletion fixtures';
 exception when sqlstate 'PHT15' then null;
 end;
end $deletion$;

-- -------------------------------------------------------------------
-- Suite: applications. An application is always restricted and never waits for approval. It
-- reads and saves under its grant, which it names on every save; it cannot approve, and its
-- saves name it and its accountable person.
-- -------------------------------------------------------------------
create function okb_tests.suite_16_applications() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $applications$
declare h uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); bad uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid(); other uuid:=gen_random_uuid();
 g uuid; req jsonb; v jsonb; hist jsonb; msg text;
begin
 begin
  insert into auth.users(id) values(h),(ap),(bad);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Applications test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  -- An application is never an administrator, and never waits for approval.
  msg:=null;
  begin insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(bad,bad,'Administrator application','application',h,'administrator',true);
  exception when check_violation then msg:='refused'; end;
  if msg is null then raise exception 'FAIL applications: an application became an administrator'; end if;
  msg:=null;
  begin insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,requires_human_approval,enabled)
   values(bad,bad,'Approving application','application',h,'restricted',true,true);
  exception when check_violation then msg:='refused'; end;
  if msg is null then raise exception 'FAIL applications: an application was set to wait for approval'; end if;
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ap,ap,'Applications test application','application',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_applications','Applications test scope','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(other,'auth_test_applications_other','Applications other scope','Rolled-back fixture',h);
  g:=(okb_private.provision_grant(h,gen_random_uuid(),ap,sc,array['evidence'],null,array['read','create'],null::timestamptz,'Application grant')->>'authorisation_id')::uuid;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',ap,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sc,'kind','evidence',
   'expected_previous_version_id',null,'title','Order checked','reason','Applications test','links','[]'::jsonb,
   'payload',jsonb_build_object('summary','Checked','source_reference',null,'source_date',null,'standing','observed','limitations','None'));
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_version(req)); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Supply the id of a grant or approval that covers this change' then raise exception 'FAIL applications: a save without a grant id: %',msg; end if;
  v:=pg_temp.raised(okb.okb_save_version(req,g));
  hist:=okb.okb_get_history((v->>'record_id')::uuid);
  if (hist->'items'->0->>'executor_actor_id')::uuid<>ap or (hist->'items'->0->>'accountable_human_id')::uuid<>h then
   raise exception 'FAIL applications: history %',hist; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),ap,req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid()),
    clock_timestamp()+interval '1 hour','Self-approval'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Administrator authority required' then raise exception 'FAIL applications: an application approved a change: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',other),g));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Scope or record unavailable' then raise exception 'FAIL applications: a save outside the grant''s scope: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT16',message='Rollback applications fixtures';
 exception when sqlstate 'PHT16' then null;
 end;
end $applications$;

-- -------------------------------------------------------------------
-- Suite: own record and paging. Each kind of actor reads its own record, with the name of the
-- person accountable for it; a page shorter than its limit offers no next page. A restricted actor
-- asking for grants with no executor gets only the grants and approvals given to them, and none
-- given to another actor, even one they are accountable for.
-- -------------------------------------------------------------------
create function okb_tests.suite_17_own_record_and_paging() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $own$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); g uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid();
 r jsonb; pg uuid; gg uuid; ga uuid;
begin
 begin
  insert into auth.users(id) values(h),(p),(g),(ap);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Own record administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Own record person','human',p,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(g,g,'Own record agent','agent',p,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ap,ap,'Own record application','application',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_own_record','Own record scope','Rolled-back fixture',h);
  pg:=(okb_private.provision_grant(h,gen_random_uuid(),p,sc,array['activity'],null,array['read'],null::timestamptz,'Own record read')->>'authorisation_id')::uuid;
  gg:=(okb_private.provision_grant(h,gen_random_uuid(),g,sc,array['evidence'],null,array['read'],null::timestamptz,'Own record agent read')->>'authorisation_id')::uuid;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_actor();
  ga:=(pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),g,jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',sc,
   'kind','evidence','expected_previous_version_id',null,'title','Own record approved letter','reason','Rolled-back fixture','links','[]'::jsonb,
   'payload',jsonb_build_object('summary','Account 12-34-56','source_reference',null,'source_date',null,'standing','stated','limitations','None')),
   clock_timestamp()+interval '1 hour','Own record approval'))->>'authorisation_id')::uuid;
  -- The administrator sees each actor's grants and approvals, asked for by executor. A built
  -- project holds other actors' rows too, so the whole list is not counted.
  if (okb.okb_get_authorisations(p)->'items'->0->>'authorisation_id')::uuid is distinct from pg
   or (select array_agg((i->>'authorisation_id')::uuid order by i->>'authorisation_id') from jsonb_array_elements(okb.okb_get_authorisations(g)->'items') i)
    is distinct from (select array_agg(x order by x::text) from unnest(array[gg,ga]) x) then
   execute 'reset role'; raise exception 'FAIL own grants: the administrator sees % and %',okb.okb_get_authorisations(p),okb.okb_get_authorisations(g); end if;
  execute 'reset role';
  if r->>'display_name'<>'Own record administrator' or r->>'authority_class'<>'administrator' or r->>'accountable_human_name'<>'Own record administrator' then
   raise exception 'FAIL own record: administrator %',r; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_actor();
  if r->>'actor_kind'<>'human' or r->>'authority_class'<>'restricted' or r->>'accountable_human_name'<>'Own record person' then
   execute 'reset role'; raise exception 'FAIL own record: person %',r; end if;
  r:=okb.okb_get_scopes();
  if jsonb_array_length(r->'items')<>1 or jsonb_typeof(r->'next_cursor') is distinct from 'null' then
   execute 'reset role'; raise exception 'FAIL paging: a short page of scopes offers a next page %',r; end if;
  r:=okb.okb_get_authorisations();
  if jsonb_array_length(r->'items')<>1 or (r->'items'->0->>'authorisation_id')::uuid is distinct from pg then
   execute 'reset role'; raise exception 'FAIL own grants: the person sees another actor''s grants %',r; end if;
  if jsonb_typeof(r->'next_cursor') is distinct from 'null' then
   execute 'reset role'; raise exception 'FAIL paging: a short page of grants offers a next page %',r; end if;
  r:=okb.okb_get_scopes(null,1);
  if jsonb_typeof(r->'next_cursor') is distinct from 'string' then
   execute 'reset role'; raise exception 'FAIL paging: a full page of scopes offers no next page %',r; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_authorisations();
  if (select array_agg((i->>'authorisation_id')::uuid order by i->>'authorisation_id') from jsonb_array_elements(r->'items') i)
   is distinct from (select array_agg(x order by x::text) from unnest(array[gg,ga]) x) then
   execute 'reset role'; raise exception 'FAIL own grants: the agent does not see exactly its grant and its approval %',r; end if;
  r:=okb.okb_get_actor();
  execute 'reset role';
  if r->>'actor_kind'<>'agent' or r->>'accountable_human_name'<>'Own record person' then raise exception 'FAIL own record: agent %',r; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ap,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_actor();
  execute 'reset role';
  if r->>'actor_kind'<>'application' or r->>'accountable_human_name'<>'Own record administrator' then raise exception 'FAIL own record: application %',r; end if;
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT17',message='Rollback own record fixtures';
 exception when sqlstate 'PHT17' then null;
 end;
end $own$;

-- -------------------------------------------------------------------
-- Suite: audit log. Each kind of event is listed once with its actor, newest first. A restricted
-- person sees only their readable records, their own grants and actor, and their read scopes'
-- files; an administrator sees the rest. Pages list every event once. The file log is append-only.
-- -------------------------------------------------------------------
create function okb_tests.suite_18_audit() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $audit$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid(); sc2 uuid:=gen_random_uuid();
 act uuid:=gen_random_uuid(); t0 timestamptz:=clock_timestamp(); t1 timestamptz; gp uuid; g2 uuid; req jsonb; delreq jsonb; appr jsonb;
 r jsonb; seen jsonb:='[]'::jsonb; cur text; got text[]; want text[]; msg text; n integer;
begin
 begin
  insert into auth.users(id) values(h),(p);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Audit test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Audit test person','human',p,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_audit','Audit test scope','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc2,'auth_test_audit_other','Audit other scope','Rolled-back fixture',h);
  gp:=(okb_private.provision_grant(h,gen_random_uuid(),p,sc,array['activity'],null,array['read','create','edit','delete'],null::timestamptz,'Audit test grant')->>'authorisation_id')::uuid;
  g2:=(okb_private.provision_grant(h,gen_random_uuid(),p,sc,array['evidence'],null,array['read'],null::timestamptz,'Audit spare grant')->>'authorisation_id')::uuid;

  -- The person uploads, replaces, moves and deletes a file, and saves an activity.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner,metadata) values('auth_test_audit','notes.md',p,'{"eTag":"a1"}');
  update storage.objects set metadata='{"eTag":"a2"}' where bucket_id='auth_test_audit' and name='notes.md';
  update storage.objects set name='notes-final.md' where bucket_id='auth_test_audit' and name='notes.md';
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',act,'scope_id',sc,'kind','activity','expected_previous_version_id',null,
   'title','Call the supplier','reason','Audit test','links','[]'::jsonb,
   'payload',jsonb_build_object('activity_kind','task','state','pending','description','Call','owner_actor_id',h,
    'completion_requirements','Called','completion_note','','baseline_start_at',null,'baseline_finish_at',null,
    'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb));
  perform pg_temp.raised(okb.okb_save_version(req,gp));
  delreq:=jsonb_set(okb.okb_preview_deletion(act)->'request','{reason}','"No longer needed"');
  execute 'reset role';

  -- The administrator approves the deletion, uploads in the other scope, and revokes the spare grant.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  appr:=pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),p,delreq,clock_timestamp()+interval '1 hour','Deletion approved'));
  insert into storage.objects(bucket_id,name,owner,metadata) values('auth_test_audit_other','budget.xlsx',h,'{"eTag":"b1"}');
  -- Storage's own sequences: a new file lands with no metadata, then gains it; an upsert clears it, then sets the new content's.
  insert into storage.objects(bucket_id,name,owner) values('auth_test_audit_other','draft.md',h);
  update storage.objects set metadata='{"eTag":"d1"}' where bucket_id='auth_test_audit_other' and name='draft.md';
  update storage.objects set metadata=null where bucket_id='auth_test_audit_other' and name='draft.md';
  update storage.objects set metadata='{"eTag":"d2"}' where bucket_id='auth_test_audit_other' and name='draft.md';
  execute 'reset role';
  -- Storage makes its own writes with no sign-in, and the person's id as the file's owner. The file log
  -- tells these apart by the missing sign-in, so they are made here the same way, as the checks' caller.
  perform set_config('request.jwt.claims','{}',true);
  insert into storage.objects(bucket_id,name,owner,owner_id) values('auth_test_audit_other','via-storage.md',p,p::text);
  update storage.objects set metadata='{"eTag":"s1"}' where bucket_id='auth_test_audit_other' and name='via-storage.md';
  update storage.objects set metadata=null where bucket_id='auth_test_audit_other' and name='via-storage.md';
  update storage.objects set metadata='{"eTag":"s2"}' where bucket_id='auth_test_audit_other' and name='via-storage.md';
  perform set_config('storage.allow_delete_query','true',true);
  delete from storage.objects where bucket_id='auth_test_audit_other' and name='via-storage.md';
  perform set_config('storage.allow_delete_query','',true);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_delete_record(delreq,(appr->>'authorisation_id')::uuid));
  perform set_config('storage.allow_delete_query','true',true);
  delete from storage.objects where bucket_id='auth_test_audit' and name='notes-final.md';
  perform set_config('storage.allow_delete_query','',true);
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_revoke_authorisation(g2,'Not needed'));
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  perform okb_tests.approve_fixture(h);
  update okb.actor set display_name='Audit test person renamed' where actor_id=p;
  perform set_config('okb.provisioning_actor','',true);
  -- An upload from outside OKB, such as the dashboard, has no actor and keeps its login.
  insert into storage.objects(bucket_id,name,metadata) values('auth_test_audit','from-dashboard.pdf','{"eTag":"c1"}');
  t1:=clock_timestamp()+interval '1 second';

  -- The person's view: every event they may read, newest first, each once, with its actor.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_audit(t0,t1);
  execute 'reset role';
  select array_agg(i->>'event' order by o) into got from jsonb_array_elements(r->'items') with ordinality x(i,o);
  want:=array['file_uploaded','actor_changed','grant_revoked','file_deleted','record_deleted','approval_given','record_saved',
   'file_moved','file_replaced','file_uploaded','grant_issued','grant_issued','scope_created','actor_created'];
  if got is distinct from want then raise exception 'FAIL audit: the person saw % not %',got,want; end if;
  if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event' like 'file\_%' and i->>'subject'<>'from-dashboard.pdf'
    and (i->>'actor_id')::uuid is distinct from p) then raise exception 'FAIL audit: a file event names the wrong actor %',r; end if;
  if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event' like 'file\_%'
    and i->>'attributed_by'<>case when i->>'subject'='from-dashboard.pdf' then 'none' else 'sign_in' end) then
   raise exception 'FAIL audit: a file event is attributed wrongly %',r; end if;
  if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event' in ('record_saved','record_deleted') and (i->>'actor_id')::uuid<>p)
   or exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event' in ('grant_issued','grant_revoked','approval_given','actor_changed') and (i->>'actor_id')::uuid<>h) then
   raise exception 'FAIL audit: a record or grant event names the wrong actor %',r; end if;
  if not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'subject'='from-dashboard.pdf' and i->'actor_id'='null'::jsonb and i->>'login'=session_user) then
   raise exception 'FAIL audit: an upload from outside OKB %',r; end if;
  if not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event'='file_moved' and i->>'previous_name'='notes.md' and i->>'subject'='notes-final.md')
   or not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event'='record_deleted' and i->>'reason'='No longer needed' and (i->>'approved_by_actor_id')::uuid=h)
   or not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event'='actor_changed' and i->>'field'='display_name' and i->>'new_value'='Audit test person renamed') then
   raise exception 'FAIL audit: an event lacks its details %',r; end if;

  -- Pages of five list the same events, each once.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  cur:=null; n:=0;
  loop
   r:=okb.okb_get_audit(t0,t1,cur,5);
   seen:=seen||(r->'items'); cur:=r->>'next_cursor'; n:=n+1;
   exit when cur is null or n>10;
  end loop;
  execute 'reset role';
  select array_agg(i->>'event' order by o) into got from jsonb_array_elements(seen) with ordinality x(i,o);
  if got is distinct from want then raise exception 'FAIL audit: pages of five gave %',got; end if;

  -- The administrator also sees the other scope's upload and their own actor.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_audit(t0,t1);
  execute 'reset role';
  if not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'subject'='budget.xlsx' and (i->>'actor_id')::uuid=h and i->>'scope_name'='Audit other scope')
   or not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event'='actor_created' and (i->>'changed_actor_id')::uuid=h) then
   raise exception 'FAIL audit: the administrator does not see every event %',r; end if;
  select array_agg(i->>'event' order by o desc) into got from jsonb_array_elements(r->'items') with ordinality x(i,o) where i->>'subject'='draft.md';
  if got is distinct from array['file_uploaded','file_replaced'] then
   raise exception 'FAIL audit: Storage''s create and upsert logged % for a new file and its replacement',got; end if;
  select array_agg(concat_ws(' ',i->>'event',i->>'attributed_by',case when (i->>'actor_id')::uuid=p then 'person' else i->>'actor_id' end) order by o desc) into got
   from jsonb_array_elements(r->'items') with ordinality x(i,o) where i->>'subject'='via-storage.md';
  if got is distinct from array['file_uploaded storage_owner person','file_replaced storage_owner person','file_deleted none'] then
   raise exception 'FAIL audit: Storage''s own writes logged %',got; end if;

  -- A period, a limit or a cursor out of range is refused.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform okb.okb_get_audit(t1,t0); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A period needs a start before its end' then execute 'reset role'; raise exception 'FAIL audit: a reversed period: %',msg; end if;
  msg:=null; begin perform okb.okb_get_audit(t0,t1,null,101); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Limit must be 1 through 100' then execute 'reset role'; raise exception 'FAIL audit: a limit of 101: %',msg; end if;
  msg:=null; begin perform okb.okb_get_audit(t0,t1,'yesterday'); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Invalid audit cursor' then execute 'reset role'; raise exception 'FAIL audit: a bad cursor: %',msg; end if;
  execute 'reset role';
  execute 'set local role anon';
  msg:=null; begin perform okb.okb_get_audit(t0,t1); exception when insufficient_privilege then msg:='refused'; end;
  execute 'reset role';
  if msg is null then raise exception 'FAIL audit: an anonymous caller read the log'; end if;
  perform set_config('request.jwt.claims','{}',true);

  -- The file log keeps every event.
  msg:=null; begin update okb.file_event set name='changed' where scope_id=sc; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The file log is append-only' then raise exception 'FAIL audit: the file log was changed: %',msg; end if;
  msg:=null; begin delete from okb.file_event where scope_id=sc; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The file log is append-only' then raise exception 'FAIL audit: the file log was deleted from: %',msg; end if;
  msg:=null; begin truncate okb.file_event; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The file log is append-only' then raise exception 'FAIL audit: the file log was truncated: %',msg; end if;
  raise exception using errcode='PHT18',message='Rollback audit fixtures';
 exception when sqlstate 'PHT18' then null;
 end;
end $audit$;

-- -------------------------------------------------------------------
-- Suite: reference data. okb_save_term saves a term, a class and a relationship between two
-- classes, each as a model record in the reference scope under the saver's grant there; a change
-- keeps the old row as the record's earlier version, and the audit log lists each save. A
-- relationship whose end is not a class, a saver with no grant there, and a class a relationship
-- uses made a plain term are refused. okb_save_dictionary saves a record kind with its class and
-- fields, and refuses one whose class is not a class. An approved request saved with
-- okb_save_version keeps the rows too, and a deleted term leaves the glossary.
-- -------------------------------------------------------------------
create function okb_tests.suite_19_reference() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $reference$
declare h uuid:=gen_random_uuid(); ed uuid:=gen_random_uuid(); ro uuid:=gen_random_uuid(); nx uuid:=gen_random_uuid(); ag uuid:=gen_random_uuid();
 sid uuid; v jsonb; r jsonb; msg text; rid uuid; t0 timestamptz; g okb.glossary_term; original_actors bigint; req jsonb; ok uuid; dv jsonb;
begin
 select count(*) into original_actors from okb.actor;
 begin
  insert into auth.users(id) values(h),(ed),(ro),(nx),(ag);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Reference test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ed,ed,'Reference test editor','human',ed,'restricted',true),(ro,ro,'Reference test reader','human',ro,'restricted',true),
    (nx,nx,'Reference test outsider','human',nx,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,requires_human_approval,enabled)
   values(ag,ag,'Reference test agent','agent',h,'restricted',true,true);
  perform set_config('okb.provisioning_actor','',true);
  select scope_id into sid from okb.scope where code='reference';
  if sid is null then
   insert into okb.scope(code,display_name,description,created_by) values('reference','Reference data','Rolled-back fixture',h) returning scope_id into sid;
  end if;
  perform okb_private.provision_grant(h,gen_random_uuid(),ed,sid,array['model'],null,array['read','create','edit'],null::timestamptz,'Reference edit');
  perform okb_private.provision_grant(h,gen_random_uuid(),ro,sid,array['model'],null,array['read'],null::timestamptz,'Reference read');
  perform okb_private.provision_grant(h,gen_random_uuid(),ag,sid,array['model'],null,array['read','create','edit'],null::timestamptz,'Reference agent');
  t0:=clock_timestamp();

  -- The editor saves a term with another name, two classes, and a relationship between them, its
  -- ends named in any case.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ed,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v:=pg_temp.raised(okb.okb_save_term('Reference test MoS','term','The note of a sale agreed, sent to both sides.','Reference test',array['Reference test memorandum of sale']));
  perform pg_temp.raised(okb.okb_save_term('Reference test vendor','class','A person selling a property.','Reference test'));
  perform pg_temp.raised(okb.okb_save_term('Reference test property','class','A home on the market.','Reference test'));
  dv:=pg_temp.raised(okb.okb_save_term('Reference test owns','relationship','Holds the title to.','Reference test',
   p_from_class=>'reference test VENDOR',p_to_class=>'Reference test property'));
  r:=okb.okb_get_reference('glossary');
  execute 'reset role';
  if (v->>'version_number')::int<>1 or (select kind from okb.record where record_id=(v->>'record_id')::uuid)<>'model'
   or (select scope_id from okb.record where record_id=(v->>'record_id')::uuid)<>sid then
   raise exception 'FAIL reference: a term is not a model record in the reference scope %',v; end if;
  select * into g from okb.glossary_term where term='Reference test MoS';
  if g.kind<>'term' or g.other_names<>array['Reference test memorandum of sale'] or g.version_id<>(v->>'version_id')::uuid or g.from_class is not null then
   raise exception 'FAIL reference: the saved term %',to_jsonb(g); end if;
  if (select kind from okb.glossary_term where term='Reference test vendor')<>'class' then raise exception 'FAIL reference: the saved class'; end if;
  select * into g from okb.glossary_term where term='Reference test owns';
  if g.kind<>'relationship' or g.from_class<>'Reference test vendor' or g.to_class<>'Reference test property' or g.version_id<>(dv->>'version_id')::uuid then
   raise exception 'FAIL reference: the saved relationship %',to_jsonb(g); end if;
  if not (r->'rows') @> '[{"term":"Reference test owns","kind":"relationship","from_class":"Reference test vendor","to_class":"Reference test property"}]' then
   raise exception 'FAIL reference: okb_get_reference does not list the relationship %',r; end if;

  -- Refused: a relationship to a term that is not a class, or to no term at all; a relationship with
  -- one end; ends on a class; a class a relationship uses made a plain term; and a name already used
  -- by another record.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ed,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test agreed','relationship','Agreed under.','Reference test',
   p_from_class=>'Reference test vendor',p_to_class=>'Reference test MoS')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'A relationship''s ends are classes, and "Reference test MoS" is not a class in the glossary' then
   execute 'reset role'; raise exception 'FAIL reference: a relationship to a plain term %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test agreed','relationship','Agreed under.','Reference test',
   p_from_class=>'Reference test nobody',p_to_class=>'Reference test property')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'A relationship''s ends are classes, and "Reference test nobody" is not a class in the glossary' then
   execute 'reset role'; raise exception 'FAIL reference: a relationship to no term %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test agreed','relationship','Agreed under.','Reference test',
   p_from_class=>'Reference test vendor')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A relationship names the class at each of its ends, as p_from_class and p_to_class' then
   execute 'reset role'; raise exception 'FAIL reference: a relationship with one end %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test buyer','class','A person buying.','Reference test',
   p_from_class=>'Reference test vendor',p_to_class=>'Reference test property')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Only a relationship names classes at its ends' then execute 'reset role'; raise exception 'FAIL reference: a class with ends %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test vendor','term','A seller.','Reference test')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from '"Reference test vendor" is the class at the end of a relationship or of a record kind, so it stays a class' then
   execute 'reset role'; raise exception 'FAIL reference: a class in use became a term %',msg; end if;
  execute 'reset role';
  if exists(select 1 from okb.glossary_term where term in ('Reference test agreed','Reference test buyer')) or (select kind from okb.glossary_term where term='Reference test vendor')<>'class' then
   raise exception 'FAIL reference: a refused save left a row'; end if;

  -- A change keeps the old row as the record's earlier version.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ed,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v:=pg_temp.raised(okb.okb_save_term('reference test mos','term','The note of a sale agreed, sent to buyer, seller and both solicitors.','Reference test correction',array['Reference test memorandum of sale']));
  execute 'reset role';
  if (v->>'version_number')::int<>2 or (select count(*) from okb.glossary_term where lower(term)='reference test mos')<>1
   or (select definition from okb.glossary_term where term='Reference test MoS')<>'The note of a sale agreed, sent to buyer, seller and both solicitors.' then
   raise exception 'FAIL reference: a changed term %',v; end if;
  if (select x.payload->'graph'->'nodes'->0->'attributes'->>'definition' from okb.record_version x where x.record_id=(v->>'record_id')::uuid and x.version_number=1)
   is distinct from 'The note of a sale agreed, sent to both sides.' then
   raise exception 'FAIL reference: the old row is not kept as the record''s first version'; end if;

  -- A reader with no create in the scope, and an actor with no grant there at all, are refused.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ro,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if jsonb_array_length(okb.okb_get_reference('glossary')->'rows')<4 then execute 'reset role'; raise exception 'FAIL reference: a reader does not read the glossary'; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test chain','term','A line of sales that hang on each other.','Reference test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is null or msg not like 'No grant of yours covers create on model records in %' then execute 'reset role'; raise exception 'FAIL reference: a reader saved a term %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_dictionary('reference_test_chain','Reference test property','A chain.','[]','Reference test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is null or msg not like 'No grant of yours covers create on model records in %' then execute 'reset role'; raise exception 'FAIL reference: a reader saved a record kind %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',nx,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test chain','term','A line of sales that hang on each other.','Reference test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is null or msg not like 'Scope unavailable%' then execute 'reset role'; raise exception 'FAIL reference: an outsider saved a term %',msg; end if;
  msg:=null; begin perform okb.okb_get_reference('glossary'); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Scope or record unavailable' then execute 'reset role'; raise exception 'FAIL reference: an outsider read the glossary %',msg; end if;
  execute 'reset role';
  if exists(select 1 from okb.glossary_term where term='Reference test chain') then raise exception 'FAIL reference: a refused term was saved'; end if;

  -- The data dictionary: a record kind with its class, a field holding a glossary term, and the
  -- system the field comes from; a record kind whose class is a plain term, or no term, is refused.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ed,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_save_term('Reference test Loop','term','The firm''s estate agency system.','Reference test'));
  dv:=pg_temp.raised(okb.okb_save_dictionary('reference_test_listing','reference test property','A property the firm is selling.',
   '[{"column":"memorandum","type":"text","required":false,"term":"Reference test MoS","meaning":"The sale''s memorandum.","sources":[{"system":"reference test loop","field":"Property.mos"}]},
     {"column":"asking_price","type":"integer","required":true,"meaning":"The price asked, in pounds."}]','Reference test'));
  msg:=null; begin perform pg_temp.raised(okb.okb_save_dictionary('reference_test_note','Reference test MoS','A note.','[]','Reference test')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'A record kind needs its glossary class, and "Reference test MoS" is not a class in the glossary' then
   execute 'reset role'; raise exception 'FAIL reference: a record kind whose class is a plain term %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_dictionary('reference_test_note',null,'A note.','[]','Reference test')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'A record kind needs its glossary class, and "" is not a class in the glossary' then
   execute 'reset role'; raise exception 'FAIL reference: a record kind with no class %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_save_dictionary('reference_test_listing','Reference test property','A property.',
   '[{"column":"chain","type":"text","required":false,"term":"Reference test nothing","meaning":"Its chain."}]','Reference test')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The field chain holds "Reference test nothing", which is not in the glossary' then
   execute 'reset role'; raise exception 'FAIL reference: a field holding no term %',msg; end if;
  r:=okb.okb_get_reference('dictionary');
  execute 'reset role';
  if (select class_term from okb.dictionary_table where table_name='reference_test_listing') is distinct from 'Reference test property'
   or (select record_id from okb.dictionary_table where table_name='reference_test_listing')<>(dv->>'record_id')::uuid then
   raise exception 'FAIL reference: the saved record kind %',r; end if;
  if (select string_agg(column_name||':'||type||':'||required||':'||coalesce(term,'-'),',' order by column_name) from okb.dictionary_column where table_name='reference_test_listing')
   <>'asking_price:integer:true:-,memorandum:text:false:Reference test MoS' then raise exception 'FAIL reference: the saved fields %',r; end if;
  if (select system||':'||field from okb.dictionary_source where table_name='reference_test_listing' and column_name='memorandum')<>'Reference test Loop:Property.mos' then
   raise exception 'FAIL reference: the saved source %',r; end if;
  if exists(select 1 from okb.dictionary_table where table_name='reference_test_note') then raise exception 'FAIL reference: a refused record kind was saved'; end if;
  if not (r->'tables') @> '[{"table":"reference_test_listing","class":"Reference test property"}]' then raise exception 'FAIL reference: okb_get_reference does not list the record kind %',r; end if;
  -- A record kind's class stays a class, and its fields given again replace its fields.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ed,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test property','term','A home.','Reference test')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from '"Reference test property" is the class at the end of a relationship or of a record kind, so it stays a class' then
   execute 'reset role'; raise exception 'FAIL reference: a record kind''s class became a term %',msg; end if;
  v:=pg_temp.raised(okb.okb_save_dictionary('reference_test_listing','Reference test property','A property the firm is selling.',
   '[{"column":"asking_price","type":"integer","required":true,"meaning":"The price asked, in pounds."}]','Reference test'));
  execute 'reset role';
  if (v->>'version_number')::int<>2 or (select string_agg(column_name,',') from okb.dictionary_column where table_name='reference_test_listing')<>'asking_price'
   or exists(select 1 from okb.dictionary_source where table_name='reference_test_listing') then
   raise exception 'FAIL reference: a record kind saved again %',v; end if;

  -- An agent whose every save needs a person's approval previews a term; an administrator approves
  -- that exact request, and the agent's save of it with okb_save_version adds the term.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_save_term('Reference test chain','term','A line of sales that hang on each other.','Reference test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is null or msg not like 'Every save by this actor needs a person''s approval%' then execute 'reset role'; raise exception 'FAIL reference: an agent saved without approval %',msg; end if;
  req:=pg_temp.raised(okb.okb_save_term('Reference test chain','term','A line of sales that hang on each other.','Reference test',p_preview=>true))->'request';
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  ok:=(okb_tests.okb_approve_change(gen_random_uuid(),ag,req,clock_timestamp()+interval '1 hour','Reference test approval')->>'authorisation_id')::uuid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  v:=okb_tests.okb_save_version(req,ok);
  if (select version_id from okb.glossary_term where term='Reference test chain') is distinct from (v->>'version_id')::uuid then
   raise exception 'FAIL reference: an approved save did not add its term %',v; end if;

  -- The audit log lists each save, by the editor, under the term's title.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 second');
  execute 'reset role';
  if (select count(*) from jsonb_array_elements(r->'items') x where x->>'event'='record_saved' and x->>'subject'='Glossary: Reference test MoS'
    and x->>'actor_name'='Reference test editor' and x->>'scope_id'=sid::text)<>2
   or not (r->'items') @> '[{"event":"record_saved","subject":"Glossary: Reference test owns","actor_name":"Reference test editor"}]'
   or not (r->'items') @> '[{"event":"record_saved","subject":"Data dictionary: reference_test_listing","actor_name":"Reference test editor","version_number":2}]'
   or not (r->'items') @> '[{"event":"record_saved","subject":"Glossary: Reference test chain","actor_name":"Reference test agent"}]' then
   raise exception 'FAIL reference: the audit log does not list each save %',r; end if;

  -- A term deleted for good, under an administrator's approval, leaves the glossary; a class still
  -- in use cannot be deleted.
  rid:=(select record_id from okb.glossary_term where term='Reference test chain');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  req:=jsonb_set(okb.okb_preview_deletion(rid)->'request','{reason}','"Reference test deletion"');
  ok:=(pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),h,req,clock_timestamp()+interval '1 hour','Reference test deletion'))->>'authorisation_id')::uuid;
  perform pg_temp.raised(okb.okb_delete_record(req,ok));
  execute 'reset role';
  if exists(select 1 from okb.glossary_term where term='Reference test chain') then raise exception 'FAIL reference: a deleted term is still in the glossary'; end if;
  rid:=(select record_id from okb.glossary_term where term='Reference test vendor');
  execute 'set local role authenticated';
  req:=jsonb_set(okb.okb_preview_deletion(rid)->'request','{reason}','"Reference test deletion"');
  ok:=(pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),h,req,clock_timestamp()+interval '1 hour','Reference test deletion'))->>'authorisation_id')::uuid;
  msg:=null; begin perform pg_temp.raised(okb.okb_delete_record(req,ok)); exception when foreign_key_violation then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'This term is still used by a relationship or the data dictionary: change those first, then delete it' then
   raise exception 'FAIL reference: a class in use was deleted %',msg; end if;

  -- A move of a term's record out of the reference scope is refused.
  if not (okb_private.move_facts(array[(select record_id from okb.glossary_term where term='Reference test owns')],sid)->'refused')
   @> '[{"reason":"The record holds a glossary term or a record kind of the data dictionary"}]' then
   raise exception 'FAIL reference: a move of a term''s record is not refused'; end if;

  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT19',message='Rollback reference fixtures';
 exception when sqlstate 'PHT19' then null;
 end;
 if (select count(*) from okb.actor)<>original_actors or exists(select 1 from okb.glossary_term where term like 'Reference test %') then
  raise exception 'FAIL reference fixture rollback'; end if;
end $reference$;


-- -------------------------------------------------------------------
-- Suite: finding records. okb_find_records lists each readable record once, at its latest version
-- at the cutoff, newest save first. A restricted person sees only the scopes and record kinds
-- their grants allow. Title words all match, in any case, and % and _ match only themselves.
-- Pages list every record once.
-- -------------------------------------------------------------------
create function okb_tests.suite_21_find_records() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $find$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid();
 graph uuid:=gen_random_uuid(); task uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); pct uuid:=gen_random_uuid();
 m jsonb; a jsonb; v1 jsonb; r jsonb; msg text; seen uuid[]:='{}'; cur bigint; pages int:=0;
begin
 begin
  insert into auth.users(id) values(h),(p);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Find test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Find test person','human',p,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sa,'auth_test_find_a','Find test scope A','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sb,'auth_test_find_b','Find test scope B','Rolled-back fixture',h);
  perform okb_private.provision_grant(h,gen_random_uuid(),p,sa,array['activity'],null,array['read'],null::timestamptz,'Find test read');

  m:=jsonb_build_object('model_kind','observed_current','source_version','1','source_status','draft','description','Find test',
   'graph',jsonb_build_object('format_version',1,'nodes',jsonb_build_array(jsonb_build_object('id','a','type','step','label','A','attributes','{}'::jsonb)),'edges','[]'::jsonb));
  a:=jsonb_build_object('activity_kind','task','state','pending','description','Find test','owner_actor_id',h,'completion_requirements','Done',
   'completion_note','','baseline_start_at',null,'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb);

  -- The administrator saves a model and a task in scope A and a model in scope B, then a second
  -- version of the first model.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v1:=pg_temp.raised(okb.okb_save_version(jsonb_build_object('request_id',gen_random_uuid(),'record_id',graph,'scope_id',sa,'kind','model','expected_previous_version_id',null,
   'title','Project Riverside plan graph','reason','Find test','links','[]'::jsonb,'payload',m)));
  perform pg_temp.raised(okb.okb_save_version(jsonb_build_object('request_id',gen_random_uuid(),'record_id',task,'scope_id',sa,'kind','activity','expected_previous_version_id',null,
   'title','Load the SKU list','reason','Find test','links','[]'::jsonb,'payload',a)));
  perform pg_temp.raised(okb.okb_save_version(jsonb_build_object('request_id',gen_random_uuid(),'record_id',other,'scope_id',sb,'kind','model','expected_previous_version_id',null,
   'title','Project Riverside plan graph in B','reason','Find test','links','[]'::jsonb,'payload',m)));
  perform pg_temp.raised(okb.okb_save_version(jsonb_build_object('request_id',gen_random_uuid(),'record_id',pct,'scope_id',sa,'kind','activity','expected_previous_version_id',null,
   'title','Raise prices 10%_now','reason','Find test','links','[]'::jsonb,'payload',a)));
  perform pg_temp.raised(okb.okb_save_version(jsonb_build_object('request_id',gen_random_uuid(),'record_id',graph,'scope_id',sa,'kind','model','expected_previous_version_id',v1->>'version_id',
   'title','Project Riverside plan graph, second draft','reason','Find test','links','[]'::jsonb,'payload',m)));

  -- The administrator finds the model by kind and two title words in another case, once, at its latest version.
  r:=okb.okb_find_records('model',sa,'PLAN graph');
  if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'record_id'<>graph::text or r->'items'->0->>'title'<>'Project Riverside plan graph, second draft'
   or (r->'items'->0->>'version_number')::int<>2 or r->'items'->0->>'saved_by'<>'Find test administrator' or r->'items'->0->>'scope_id'<>sa::text then
   execute 'reset role'; raise exception 'FAIL find: the administrator''s search for the model %',r; end if;
  -- Newest save first across the scope.
  r:=okb.okb_find_records(null,sa);
  if (select array_agg(i->>'record_id' order by o) from jsonb_array_elements(r->'items') with ordinality x(i,o))<>array[graph::text,pct::text,task::text] then
   execute 'reset role'; raise exception 'FAIL find: scope A is not listed newest save first %',r; end if;
  -- Before the second version, the model's first title.
  r:=okb.okb_find_records('model',sa,null,(v1->>'change_no')::bigint);
  if r->'items'->0->>'title'<>'Project Riverside plan graph' then execute 'reset role'; raise exception 'FAIL find: the cutoff %',r; end if;
  -- Every word must match, and % and _ match only themselves.
  if jsonb_array_length(okb.okb_find_records(null,sa,'graph missing')->'items')<>0 then execute 'reset role'; raise exception 'FAIL find: one word of two matched'; end if;
  r:=okb.okb_find_records(null,sa,'10%_');
  if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'record_id'<>pct::text or jsonb_array_length(okb.okb_find_records(null,sa,'%')->'items')<>1
   or jsonb_array_length(okb.okb_find_records(null,sa,'_')->'items')<>1 then
   execute 'reset role'; raise exception 'FAIL find: %% or _ matched more than itself %',r; end if;
  -- Pages of one list each record in the scope once.
  cur:=null;
  loop
   r:=okb.okb_find_records(null,sa,null,null,cur,1);
   exit when jsonb_array_length(r->'items')=0;
   seen:=seen||(r->'items'->0->>'record_id')::uuid;
   pages:=pages+1;
   exit when r->>'next_cursor' is null or pages>10;
   cur:=(r->>'next_cursor')::bigint;
  end loop;
  if cardinality(seen)<>3 or not seen @> array[graph,task,pct] then execute 'reset role'; raise exception 'FAIL find: pages listed %',seen; end if;
  -- Bad requests are refused.
  msg:=null; begin perform okb.okb_find_records('models'); exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'Kind must be activity, decision, model or evidence' then execute 'reset role'; raise exception 'FAIL find: a wrong kind: %',msg; end if;
  msg:=null; begin perform okb.okb_find_records(null,null,null,null,null,101); exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'Invalid records page' then execute 'reset role'; raise exception 'FAIL find: a page of 101: %',msg; end if;
  execute 'reset role';

  -- The person reads activities in scope A only: no model, and nothing in scope B.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_find_records();
  if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'kind'<>'activity' or (i->>'scope_id')::uuid<>sa)
   or (select count(*) from jsonb_array_elements(r->'items') i where (i->>'record_id')::uuid in (task,pct))<>2 then
   execute 'reset role'; raise exception 'FAIL find: the person sees %',r; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT21',message='Rollback find fixtures';
 exception when sqlstate 'PHT21' then null;
 end;
end $find$;

-- -------------------------------------------------------------------
-- Suite: sign-ins. A session opened and ended is logged as signed_in, then signed_out, with its
-- actor. An administrator reads every actor with a login and their sessions, and the two events
-- in the audit log; a restricted person is refused the first and sees neither event. The sign-in
-- log is append-only.
-- -------------------------------------------------------------------
create function okb_tests.suite_22_sign_ins() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $signins$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); t0 timestamptz:=clock_timestamp(); t1 timestamptz;
 r jsonb; item jsonb; got text[]; msg text;
begin
 begin
  insert into auth.users(id,email,created_at) values(h,'sign-in-admin@example.test',clock_timestamp()),(p,'sign-in-person@example.test',clock_timestamp());
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Sign-in test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Sign-in test person','human',p,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);

  -- Supabase Auth opens a session for the person.
  update auth.users set last_sign_in_at=clock_timestamp() where id=p;
  insert into auth.sessions(id,user_id,created_at,updated_at,refreshed_at,user_agent,ip)
   values(s,p,clock_timestamp(),clock_timestamp(),(clock_timestamp() at time zone 'UTC')::timestamp,'sign-in test','192.0.2.1');

  -- The administrator lists every actor with a login, the person with their open session.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_sign_ins();
  execute 'reset role';
  if jsonb_array_length(r->'items')<>(select count(*) from okb.actor where auth_user_id is not null) then
   raise exception 'FAIL sign-ins: % items for % actors with a login',jsonb_array_length(r->'items'),(select count(*) from okb.actor where auth_user_id is not null); end if;
  select i into item from jsonb_array_elements(r->'items') i where (i->>'actor_id')::uuid=p;
  if item->>'email'<>'sign-in-person@example.test' or (item->>'open_sessions')::int<>1 or item->'latest_session'->>'user_agent'<>'sign-in test'
   or item->'latest_session'->>'ip'<>'192.0.2.1' or item->>'last_active_at' is null or item->>'last_sign_in_at' is null then
   raise exception 'FAIL sign-ins: the person''s entry is %',item; end if;
  select i into item from jsonb_array_elements(r->'items') i where (i->>'actor_id')::uuid=h;
  if (item->>'open_sessions')::int<>0 or item->'latest_session'<>'null'::jsonb or item->'last_active_at'<>'null'::jsonb then
   raise exception 'FAIL sign-ins: the administrator''s entry is %',item; end if;

  -- The person is refused the list, and an anonymous caller cannot call it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform okb.okb_get_sign_ins(); exception when insufficient_privilege then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Administrator required' then raise exception 'FAIL sign-ins: a restricted person read the list: %',msg; end if;
  execute 'set local role anon';
  msg:=null; begin perform okb.okb_get_sign_ins(); exception when insufficient_privilege then msg:='refused'; end;
  execute 'reset role';
  if msg is null then raise exception 'FAIL sign-ins: an anonymous caller read the list'; end if;

  -- The person signs out.
  perform set_config('request.jwt.claims','{}',true);
  delete from auth.sessions where id=s;
  t1:=clock_timestamp()+interval '1 second';

  -- The administrator sees both events, newest first, with the person as their actor.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_audit(t0,t1);
  execute 'reset role';
  select array_agg(concat_ws(' ',i->>'event',i->>'subject',i->>'user_agent',i->>'ip') order by o) into got
   from jsonb_array_elements(r->'items') with ordinality x(i,o) where i->>'session_id'=s::text;
  if got is distinct from array['signed_out Sign-in test person sign-in test 192.0.2.1','signed_in Sign-in test person sign-in test 192.0.2.1'] then
   raise exception 'FAIL sign-ins: the administrator''s audit log holds %',got; end if;

  -- The person sees neither.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_audit(t0,t1);
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'event' in ('signed_in','signed_out')) then
   raise exception 'FAIL sign-ins: a restricted person''s audit log holds sign-ins %',r; end if;
  perform set_config('request.jwt.claims','{}',true);

  -- A session removed after its expiry ended by itself: logged as expired, with no sign-out.
  insert into auth.sessions(id,user_id,created_at,not_after) values(gen_random_uuid(),p,clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day');
  delete from auth.sessions where user_id=p and not_after is not null;
  if (select array_agg(event order by event_id) from okb.sign_in_event where auth_user_id=p and event_id>(select max(event_id) from okb.sign_in_event where session_id=s))
   is distinct from array['signed_in','session_expired'] then raise exception 'FAIL sign-ins: an expired session was not logged as expired'; end if;
  -- The sign-in log keeps every event.
  msg:=null; begin update okb.sign_in_event set user_agent='changed' where session_id=s; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The sign-in log is append-only' then raise exception 'FAIL sign-ins: the log was changed: %',msg; end if;
  msg:=null; begin delete from okb.sign_in_event where session_id=s; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The sign-in log is append-only' then raise exception 'FAIL sign-ins: the log was deleted from: %',msg; end if;
  msg:=null; begin truncate okb.sign_in_event; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The sign-in log is append-only' then raise exception 'FAIL sign-ins: the log was truncated: %',msg; end if;
  raise exception using errcode='PHT22',message='Rollback sign-in fixtures';
 exception when sqlstate 'PHT22' then null;
 end;
end $signins$;

create function okb_tests.suite_23_task_functions() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $tasks$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); rd uuid:=gen_random_uuid(); ag uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); s2 uuid:=gen_random_uuid();
 hidden jsonb; j jsonb; v jsonb; r jsonb; msg text; n bigint; appr jsonb; k text;
 plan text; task text; evidence text; blocker text; deliverable text;
begin
 begin
  insert into auth.users(id) values(h),(p),(rd),(ag);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Task test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Task test person','human',p,'restricted',true),(rd,rd,'Task test reader','human',rd,'restricted',true);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,requires_human_approval,enabled)
   values(ag,ag,'Task test agent','agent',h,'restricted',true,true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s,'auth_test_task','Task test scope','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s2,'auth_test_task_b','Task test scope B','Rolled-back fixture',h);
  perform okb_private.provision_grant(h,gen_random_uuid(),p,s,array['activity','decision','model','evidence'],null,
   array['read','create','edit','start','hold','complete','reopen','cancel','decide'],null::timestamptz,'Task test person');
  perform okb_private.provision_grant(h,gen_random_uuid(),rd,s,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Task test reader');
  perform okb_private.provision_grant(h,gen_random_uuid(),ag,s,array['activity'],null,array['read'],null::timestamptz,'Task test agent');

  -- The administrator saves a record in scope B, which the person cannot read.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  hidden:=pg_temp.raised(okb.okb_add_record('auth_test_task_b','evidence','Task test hidden evidence','Task test','{"summary":"Hidden","standing":"stated"}'));
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  -- A scope by its code, its name in another case, and its id; a parent by its title.
  plan:=pg_temp.raised(okb.okb_add_record('auth_test_task','activity','Task test plan','Task test','{"activity_kind":"plan","index":"1"}'))->>'record_id';
  v:=pg_temp.raised(okb.okb_add_record('task test SCOPE','activity','Task test task','Task test','{"index":"1.2","completion_requirements":"Done"}','Task test plan'));
  task:=v->>'record_id';
  evidence:=pg_temp.raised(okb.okb_add_record(s::text,'evidence','Task test evidence','Task test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  r:=okb.okb_show_record('task test TASK');
  if r->>'scope_name'<>'Task test scope' or r->'payload'->>'task_type'<>'work' or r->'payload'->>'state'<>'pending'
   or r->'links'->0->>'relation'<>'parent' or r->'links'->0->>'target_title'<>'Task test plan' then
   execute 'reset role'; raise exception 'FAIL task functions: the new task reads %',r; end if;
  -- A link names its target by the target's latest title and index, while it points at the version it was saved with.
  perform pg_temp.raised(okb.okb_change_record(plan,'Task test','{"index":"2"}','Task test plan, renamed'));
  r:=okb.okb_show_record(task);
  if r->'links'->0->>'target_title'<>'Task test plan, renamed' or r->'links'->0->>'target_index'<>'2'
   or r->'links'->0->>'target_version_id'=r->'links'->0->>'target_latest_version_id' then
   execute 'reset role'; raise exception 'FAIL task functions: a link to an older version reads %',r->'links'; end if;

  -- Each single-save function's preview saves nothing, and its request saves as previewed.
  foreach k in array array['add','change','state','link','assign','unlink'] loop
   execute 'reset role';
   select count(*) into n from okb.record_version x join okb.record y using(record_id) where y.scope_id=s;
   execute 'set local role authenticated';
   j:=case k
    when 'add' then pg_temp.raised(okb.okb_add_record('auth_test_task','decision','Task test decision','Task test','{"question":"Which?"}',null,true))
    when 'change' then pg_temp.raised(okb.okb_change_record(task,'Task test','{"description":"Changed"}','Task test task',true))
    when 'state' then pg_temp.raised(okb.okb_set_state(task,'in_progress','Task test',null,true))
    when 'link' then pg_temp.raised(okb.okb_link(task,evidence,'supports','Task test','A note',null,true))
    when 'assign' then pg_temp.raised(okb.okb_assign(task,'test reader','Task test',true))
    else pg_temp.raised(okb.okb_unlink(task,evidence,'supports','Task test',true)) end;
   execute 'reset role';
   if j->>'preview'<>'true' or (select count(*) from okb.record_version x join okb.record y using(record_id) where y.scope_id=s)<>n then raise exception 'FAIL task functions: % preview %',k,j; end if;
   execute 'set local role authenticated';
   v:=pg_temp.raised(okb.okb_save_version(j->'request',(j->>'authorisation_id')::uuid));
   if v->>'request_id'<>j->'request'->>'request_id' or v->'payload'<>j->'request'->'payload' or v->>'title'<>j->'request'->>'title' then
    execute 'reset role'; raise exception 'FAIL task functions: % saved % from %',k,v,j; end if;
  end loop;
  r:=okb.okb_show_record(task);
  if r->'payload'->>'state'<>'in_progress' or r->'payload'->>'description'<>'Changed' or r->'payload'->>'assignee_actor_id'<>rd::text
   or jsonb_array_length(r->'links')<>1 then execute 'reset role'; raise exception 'FAIL task functions: after the previews the task reads %',r; end if;

  -- A blocker and a deliverable take the task's index; clearing the blocker with its evidence completes it and leaves the task's blockers empty.
  blocker:=pg_temp.raised(okb.okb_add_blocker(task,'Task test blocker','Access granted','Task test'))->'blocker'->>'record_id';
  deliverable:=pg_temp.raised(okb.okb_add_deliverable(task,'Task test deliverable','The document','Task test'))->'deliverable'->>'record_id';
  if okb.okb_show_record(blocker)->'payload'->>'index'<>'1.2-B1' or okb.okb_show_record(deliverable)->'payload'->>'index'<>'1.2a'
   or jsonb_array_length(okb.okb_show_record(task)->'payload'->'blockers')<>1 then
   execute 'reset role'; raise exception 'FAIL task functions: blocker and deliverable %, %',okb.okb_show_record(blocker),okb.okb_show_record(task); end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_clear_blocker(blocker,null,evidence,'Task test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the completion note: how the blocker was cleared' or okb.okb_show_record(blocker)->'payload'->>'state'<>'pending' then
   execute 'reset role'; raise exception 'FAIL task functions: a blocker cleared with no note %',msg; end if;
  perform pg_temp.raised(okb.okb_clear_blocker(blocker,'Cleared',evidence,'Task test'));
  if okb.okb_show_record(blocker)->'payload'->>'state'<>'completed' or jsonb_array_length(okb.okb_show_record(task)->'payload'->'blockers')<>0
   or okb.okb_show_record(blocker)->'links' @> '[{"relation":"supports","target_title":"Task test evidence"}]' is not true then
   execute 'reset role'; raise exception 'FAIL task functions: the cleared blocker %',okb.okb_show_record(task); end if;

  -- A title that fits two records is refused, naming both.
  perform pg_temp.raised(okb.okb_add_record('auth_test_task','evidence','Task test evidence','Task test','{"summary":"Twice","standing":"stated"}'));
  msg:=null; begin perform okb.okb_show_record('Task test evidence'); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg not like 'More than one record has the title "Task test evidence": %' or (length(msg)-length(replace(msg,'Task test scope','')))/length('Task test scope')<>2 then
   execute 'reset role'; raise exception 'FAIL task functions: two records of one title %',msg; end if;
  -- A record the person cannot read is unavailable.
  msg:=null; begin perform okb.okb_show_record(hidden->>'record_id'); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Record unavailable' then execute 'reset role'; raise exception 'FAIL task functions: a hidden record %',msg; end if;
  execute 'reset role';

  -- A reader with no grant to edit is told which actions are missing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rd,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_set_state(task,'paused','Task test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'No grant of yours covers edit, hold on activity records in Task test scope. An administrator can grant it, or approve this exact change' then
   raise exception 'FAIL task functions: the reader''s refusal %',msg; end if;

  -- An agent whose every save needs an approval gets the preview, and saves it once an administrator approves it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_set_state(task,'paused','Task test')); exception when insufficient_privilege then msg:=sqlerrm; end;
  j:=pg_temp.raised(okb.okb_set_state(task,'paused','Task test',null,true));
  execute 'reset role';
  if msg is distinct from 'Every save by this actor needs a person''s approval. Save the preview''s request with an approval, as the okb:records skill''s section 5 describes' or j->'authorisation_id'<>'null'::jsonb then
   raise exception 'FAIL task functions: the agent''s refusal % and preview %',msg,j; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  appr:=pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),ag,j->'request',clock_timestamp()+interval '1 hour','Task test'));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v:=pg_temp.raised(okb.okb_save_version(j->'request',(appr->>'authorisation_id')::uuid));
  execute 'reset role';
  if v->'payload'->>'state'<>'paused' then raise exception 'FAIL task functions: the approved save %',v; end if;

  -- An evidence record's source and an external reference are a link, which may have a # part, or plain
  -- words, such as a name with a time. A refusal names the field and the rule, and a preview refuses
  -- what a save refuses.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  foreach k in array array['https://mail.google.com/mail/u/0/#inbox/FMfcgzQXJWDsKmRkLqTvBnPwXcHlMzNt','Charlotte Smith, email, 9 Oct 14:30'] loop
   j:=pg_temp.raised(okb.okb_add_record('auth_test_task','evidence','Task test source '||k,'Task test',jsonb_build_object('summary','Seen','standing','observed','source_reference',k),null,true));
   v:=pg_temp.raised(okb.okb_add_record('auth_test_task','evidence','Task test source '||k,'Task test',jsonb_build_object('summary','Seen','standing','observed','source_reference',k)));
   if j->>'preview'<>'true' or v->'payload'->>'source_reference' is distinct from k then
    execute 'reset role'; raise exception 'FAIL task functions: the source % saved % from preview %',k,v,j; end if;
  end loop;
  foreach k in array array['https://mail.google.com/mail/u/0/?ui=2#inbox/1|source_reference: a link has no ? part',
   'https://name:secret@example.com/x|source_reference: a link has no name or password before its host',
   'HTTPS://name:secret@example.com/f?token=1|source_reference: a link has no ? part',
   'http://example.com/f?token=1|source_reference: a link starts https://',
   '/etc/passwd|source_reference: plain words start with neither / nor \',
   'notes/../x|source_reference: plain words hold no .. path segment'] loop
   foreach n in array array[1,0]::bigint[] loop
    msg:=null;
    begin
     perform pg_temp.raised(okb.okb_add_record('auth_test_task','evidence','Task test refused source','Task test',
      jsonb_build_object('summary','Seen','standing','observed','source_reference',split_part(k,'|',1)),null,n=1));
    exception when invalid_parameter_value then msg:=sqlerrm; end;
    if msg is distinct from split_part(k,'|',2) then
     execute 'reset role'; raise exception 'FAIL task functions: the source % with preview % was refused with %',split_part(k,'|',1),n=1,msg; end if;
   end loop;
  end loop;
  v:=pg_temp.raised(okb.okb_change_record(task,'Task test','{"external_references":[{"label":"Mail","reference":"https://mail.google.com/mail/u/0/#inbox/FMfcgzQXJWDsKmRkLqTvBnPwXcHlMzNt"}]}'));
  if v->'payload'->'external_references'->0->>'reference' is distinct from 'https://mail.google.com/mail/u/0/#inbox/FMfcgzQXJWDsKmRkLqTvBnPwXcHlMzNt' then
   execute 'reset role'; raise exception 'FAIL task functions: the external reference saved %',v; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_change_record(task,'Task test','{"external_references":[{"label":"Form","reference":"https://example.com/f?token=1"}]}',null,true));
  exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'external_references.reference: a link has no ? part' then
   execute 'reset role'; raise exception 'FAIL task functions: the external reference with a ? part was refused with %',msg; end if;
  execute 'reset role';
  -- The check with no field's name, applies the same rules.
  msg:=null; begin perform okb_private.validate_reference('https://example.com/f?token=1'); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'reference: a link has no ? part' then raise exception 'FAIL task functions: the check with no field''s name refused with %',msg; end if;
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT23',message='Rollback task function fixtures';
 exception when sqlstate 'PHT23' then null;
 end;
end $tasks$;

-- -------------------------------------------------------------------
-- Suite: moving records. A person who is an administrator moves records to another scope with
-- their versions and links. The preview names a link to a record outside the move, a
-- record-specific grant, and who loses and who gains read access, and the move refuses what the
-- preview refuses or what has changed since. A retry returns the earlier move. Nothing but a move
-- changes a record's scope or the move log.
-- -------------------------------------------------------------------
create function okb_tests.suite_24_record_move() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $moves$
declare h uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); rb uuid:=gen_random_uuid(); sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid();
 model uuid; finding uuid; outsider uuid; j jsonb; r jsonb; msg text; n bigint; versions bigint; links bigint; t0 timestamptz:=clock_timestamp();
 g constant jsonb:='{"model_kind":"observed_current","description":"Move test","graph":{"format_version":1,"nodes":[{"id":"a","type":"step","label":"In","attributes":{}}],"edges":[]}}';
begin
 begin
  insert into auth.users(id) values(h),(ra),(rb);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Move test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ra,ra,'Move test reader A','human',ra,'restricted',true),(rb,rb,'Move test reader B','human',rb,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sa,'auth_test_move_a','Move test scope A','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sb,'auth_test_move_b','Move test scope B','Rolled-back fixture',h);
  perform okb_private.provision_grant(h,gen_random_uuid(),ra,sa,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Move test reader A');
  perform okb_private.provision_grant(h,gen_random_uuid(),rb,sb,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Move test reader B');

  -- A model, a finding that describes it, and a decision outside the move that the finding supports.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  model:=pg_temp.raised(okb.okb_add_record('auth_test_move_a','model','Move test model','Move test',g))->>'record_id';
  finding:=pg_temp.raised(okb.okb_add_record('auth_test_move_a','evidence','Move test finding','Move test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_link('Move test finding','Move test model','describes','Move test'));
  outsider:=pg_temp.raised(okb.okb_add_record('auth_test_move_a','decision','Move test decision','Move test','{"question":"Which?"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_link('Move test decision','Move test finding','supports','Move test'));

  -- The preview names the outside link, and the move refuses it.
  j:=okb.okb_preview_move(array['Move test model','move test FINDING'],'Move test scope B','Move test');
  if jsonb_array_length(j->'records')<>2 or j->'outside_links'<>jsonb_build_array(jsonb_build_object('record_id',finding,'linked_record_id',outsider,
    'linked_title','Move test decision','linked_scope_name','Move test scope A','relation','supports','direction','linked_from')) then
   execute 'reset role'; raise exception 'FAIL moves: the preview with an outside link %',j; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_move_records(j)); exception when check_violation then msg:=sqlerrm; end;
  if msg not like 'A record outside the move links to or from one in it.%' then execute 'reset role'; raise exception 'FAIL moves: a move with an outside link %',msg; end if;

  -- With the decision, the preview names no outside link, and who loses and gains access.
  j:=okb.okb_preview_move(array['Move test model',finding::text,'Move test decision'],'auth_test_move_b','Move test');
  execute 'reset role';
  if j->>'operation'<>'move' or j->>'from_scope_id'<>sa::text or j->>'to_scope_id'<>sb::text or jsonb_array_length(j->'records')<>3
   or j->'outside_links'<>'[]'::jsonb or j->'refused'<>'[]'::jsonb
   or j->'losing_access'<>jsonb_build_array(jsonb_build_object('actor_id',ra,'name','Move test reader A','record_ids',(select jsonb_agg(x order by x) from unnest(array[model,finding,outsider]) x)))
   or j->'gaining_access'<>jsonb_build_array(jsonb_build_object('actor_id',rb,'name','Move test reader B','record_ids',(select jsonb_agg(x order by x) from unnest(array[model,finding,outsider]) x))) then
   raise exception 'FAIL moves: the preview %',j; end if;
  select count(*) into versions from okb.record_version where record_id in (model,finding,outsider);
  select count(*) into links from okb.version_link l join okb.record_version v on v.version_id=l.source_version_id where v.record_id in (model,finding,outsider);

  -- A restricted person can neither preview nor move.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform okb.okb_preview_move(array[model::text],'auth_test_move_b'); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Only a person who is an administrator moves records' then execute 'reset role'; raise exception 'FAIL moves: a restricted preview %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_move_records(j)); exception when insufficient_privilege then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Only a person who is an administrator moves records' then raise exception 'FAIL moves: a restricted move %',msg; end if;

  -- The move keeps each record's id, versions and links, and logs each record once; a retry returns it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_move_records(j-'reason'||'{"reason":" "}')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the reason for the move, as p_reason when previewing it' then execute 'reset role'; raise exception 'FAIL moves: a blank reason %',msg; end if;
  r:=pg_temp.raised(okb.okb_move_records(j));
  if pg_temp.raised(okb.okb_move_records(j))<>r or jsonb_array_length(r->'records')<>3 or r->>'to_scope_name'<>'Move test scope B' then
   execute 'reset role'; raise exception 'FAIL moves: the move and its retry %',r; end if;
  execute 'reset role';
  if (select count(*) from okb.record where record_id in (model,finding,outsider) and scope_id=sb)<>3
   or (select count(*) from okb.record_version where record_id in (model,finding,outsider))<>versions
   or (select count(*) from okb.version_link l join okb.record_version v on v.version_id=l.source_version_id where v.record_id in (model,finding,outsider))<>links
   or (select count(*) from okb.record_move where request_id=(j->>'request_id')::uuid)<>3 then
   raise exception 'FAIL moves: after the move'; end if;

  -- The reader of the old scope loses the records; the reader of the new one reads them and their links, and sees the moves without the access lists.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform okb.okb_show_record(finding::text); exception when insufficient_privilege then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Record unavailable' then raise exception 'FAIL moves: the old scope''s reader reads %',msg; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rb,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_show_record(finding::text);
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  execute 'reset role';
  if r->>'scope_name'<>'Move test scope B' or r->'links'->0->>'target_title'<>'Move test model'
   or (select count(*) from jsonb_array_elements(j->'items') e where e->>'event'='record_moved' and e->>'from_scope_name'='Move test scope A' and not e ? 'losing_access')<>3 then
   raise exception 'FAIL moves: the new scope''s reader reads % and audits %',r,j; end if;

  -- A record-specific grant is refused, and a preview that has changed is refused.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  j:=pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),ra,sb,array['decision'],outsider,array['read'],null::timestamptz,'Move test'));
  r:=okb.okb_preview_move(array['Move test decision'],'auth_test_move_a','Move test');
  if r->'refused'<>jsonb_build_array(jsonb_build_object('record_id',outsider,'reason','A live grant or an unused approval names the record: '||(j->>'authorisation_id'))) then
   execute 'reset role'; raise exception 'FAIL moves: a record-specific grant %',r; end if;
  r:=okb.okb_preview_move(array['Move test model'],'auth_test_move_a','Move test');
  perform pg_temp.raised(okb.okb_change_record('Move test model','Move test','{}','Move test model, renamed'));
  msg:=null; begin perform pg_temp.raised(okb.okb_move_records(r)); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The move has changed; preview it again' then execute 'reset role'; raise exception 'FAIL moves: a changed move %',msg; end if;
  msg:=null; begin perform okb.okb_preview_move(array['Move test model, renamed'],'auth_test_move_b'); exception when invalid_parameter_value then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'The records are already in Move test scope B' then raise exception 'FAIL moves: a move to the same scope %',msg; end if;

  -- Nothing but a move changes a record's scope or the move log.
  msg:=null; begin update okb.record set scope_id=sa where record_id=model; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Saved versions and record identities are immutable' then raise exception 'FAIL moves: a direct scope change %',msg; end if;
  msg:=null; begin delete from okb.record_move where record_id=model; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Record moves are append-only; use okb_move_records' then raise exception 'FAIL moves: the log was deleted from %',msg; end if;
  msg:=null; begin truncate okb.record_move; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Record moves are append-only; use okb_move_records' then raise exception 'FAIL moves: the log was truncated %',msg; end if;
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT24',message='Rollback move fixtures';
 exception when sqlstate 'PHT24' then null;
 end;
end $moves$;

-- -------------------------------------------------------------------
-- Suite: renaming a scope. A person who is an administrator changes a scope's name or
-- description; its id, code, records and grants stay the same, and the audit log lists each change.
-- -------------------------------------------------------------------
create function okb_tests.suite_25_scope_rename() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $rename$
declare h uuid:=gen_random_uuid(); ga uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); rb uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); rec uuid; who uuid; gid uuid; r jsonb; j jsonb; msg text; t0 timestamptz:=clock_timestamp();
begin
 begin
  insert into auth.users(id) values(h),(ga),(ra),(rb);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Rename test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ga,ga,'Rename test agent administrator','agent',h,'administrator',true),
    (ra,ra,'Rename test reader A','human',ra,'restricted',true),(rb,rb,'Rename test reader B','human',rb,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sa,'auth_test_rename_a','Rename test scope A','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sb,'auth_test_rename_b','Rename test scope B','Rolled-back fixture',h);
  gid:=(okb_private.provision_grant(h,gen_random_uuid(),ra,sa,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Rename test reader A')->>'authorisation_id')::uuid;
  perform okb_private.provision_grant(h,gen_random_uuid(),rb,sb,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Rename test reader B');

  -- The administrator renames the scope by its code, then by its name, and changes its description.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  rec:=pg_temp.raised(okb.okb_add_record('auth_test_rename_a','evidence','Rename test finding','Rename test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  r:=pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a','Rename test scope One',null,'Rename test'));
  if r->>'scope_id'<>sa::text or r->>'code'<>'auth_test_rename_a' or r->>'old_name'<>'Rename test scope A' or r->>'name'<>'Rename test scope One'
   or r->>'description'<>'Rolled-back fixture' or r->>'changed_by'<>'Rename test administrator' or r->>'reason'<>'Rename test' then
   execute 'reset role'; raise exception 'FAIL renames: by code %',r; end if;
  r:=pg_temp.raised(okb.okb_rename_scope(' rename TEST scope one ','Rename test scope Two','A scope renamed twice','Rename test again'));
  if r->>'old_name'<>'Rename test scope One' or r->>'name'<>'Rename test scope Two' or r->>'old_description'<>'Rolled-back fixture'
   or r->>'description'<>'A scope renamed twice' then execute 'reset role'; raise exception 'FAIL renames: by name %',r; end if;
  r:=okb.okb_show_record(rec::text);
  if r->>'scope_name'<>'Rename test scope Two' or r->>'record_id'<>rec::text then execute 'reset role'; raise exception 'FAIL renames: the record after the rename %',r; end if;

  -- A rename with no reason, no change, nothing to change, or another scope's name or code is refused.
  msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a','Rename test scope Three',null,' ')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the reason for the change, as p_reason' then execute 'reset role'; raise exception 'FAIL renames: no reason %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a',null,null,'Rename test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the new name, as p_display_name, or the new description, as p_description' then execute 'reset role'; raise exception 'FAIL renames: nothing given %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a','Rename test scope Two','A scope renamed twice','Rename test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'The scope Rename test scope Two already has that name and description' then execute 'reset role'; raise exception 'FAIL renames: no change %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a',' RENAME TEST SCOPE B ',null,'Rename test')); exception when unique_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Another scope has the name or code "RENAME TEST SCOPE B": Rename test scope B (code auth_test_rename_b)' then execute 'reset role'; raise exception 'FAIL renames: another scope''s name %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a','Auth_Test_Rename_B',null,'Rename test')); exception when unique_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Another scope has the name or code "Auth_Test_Rename_B": Rename test scope B (code auth_test_rename_b)' then execute 'reset role'; raise exception 'FAIL renames: another scope''s code %',msg; end if;
  execute 'reset role';

  -- A restricted person and an agent that is an administrator are refused.
  foreach who in array array[ra,ga] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',who,'role','authenticated')::text,true);
   execute 'set local role authenticated';
   msg:=null; begin perform pg_temp.raised(okb.okb_rename_scope('auth_test_rename_a','Rename test scope Three',null,'Rename test')); exception when insufficient_privilege then msg:=sqlerrm; end;
   execute 'reset role';
   if msg is distinct from 'Only a person who is an administrator renames a scope' then raise exception 'FAIL renames: % renamed %',who,msg; end if;
  end loop;

  -- The administrator adds a scope. It gets its private bucket, and the audit log shows it with the reason.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_add_scope(' auth_test_add_a ',' Add test scope ','A scope added in a test','Add test'));
  if r->>'code'<>'auth_test_add_a' or r->>'name'<>'Add test scope' or r->>'description'<>'A scope added in a test'
   or r->>'created_by'<>'Rename test administrator' or r->>'reason'<>'Add test' then
   execute 'reset role'; raise exception 'FAIL adds: the scope %',r; end if;
  if not (okb.okb_get_audit(now()-interval '1 hour',now()+interval '1 hour',null,100)->'items'
   @> jsonb_build_array(jsonb_build_object('event','scope_created','scope_id',r->>'scope_id','reason','Add test'))) then
   execute 'reset role'; raise exception 'FAIL adds: no scope_created entry in the audit log'; end if;
  -- An add with no reason, a bad code, no name, or another scope's code or name is refused.
  msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('auth_test_add_b','Add test scope B','Rolled-back fixture',' ')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the reason for the change, as p_reason' then execute 'reset role'; raise exception 'FAIL adds: no reason %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('Add Test B','Add test scope B','Rolled-back fixture','Add test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A scope''s code is lower case letters, digits and underscores, starting with a letter, at most 63 characters' then execute 'reset role'; raise exception 'FAIL adds: a bad code %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('auth_test_add_b',' ','Rolled-back fixture','Add test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the scope''s name, at most 200 characters, as p_display_name' then execute 'reset role'; raise exception 'FAIL adds: no name %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('auth_test_add_a','Add test scope C','Rolled-back fixture','Add test')); exception when unique_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Another scope has the name or code "auth_test_add_a": Add test scope (code auth_test_add_a)' then execute 'reset role'; raise exception 'FAIL adds: another scope''s code %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('auth_test_add_c','ADD TEST SCOPE','Rolled-back fixture','Add test')); exception when unique_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Another scope has the name or code "ADD TEST SCOPE": Add test scope (code auth_test_add_a)' then execute 'reset role'; raise exception 'FAIL adds: another scope''s name %',msg; end if;
  execute 'reset role';
  if not exists(select 1 from storage.buckets where id='auth_test_add_a' and not public) then raise exception 'FAIL adds: no private bucket for the new scope'; end if;
  -- A restricted person and an agent that is an administrator are refused.
  foreach who in array array[ra,ga] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',who,'role','authenticated')::text,true);
   execute 'set local role authenticated';
   msg:=null; begin perform pg_temp.raised(okb.okb_add_scope('auth_test_add_d','Add test scope D','Rolled-back fixture','Add test')); exception when insufficient_privilege then msg:=sqlerrm; end;
   execute 'reset role';
   if msg is distinct from 'Only a person who is an administrator adds a scope' then raise exception 'FAIL adds: % added %',who,msg; end if;
  end loop;

  -- The scope keeps its id, code and grants, and the log holds one row for each field changed.
  if (select row(code,display_name,description) from okb.scope where scope_id=sa) is distinct from row('auth_test_rename_a'::text,'Rename test scope Two'::text,'A scope renamed twice'::text)
   or not exists(select 1 from okb.authorisation where authorisation_id=gid and scope_id=sa and revoked_at is null)
   or (select count(*) from okb.scope_change where scope_id=sa)<>3 then
   raise exception 'FAIL renames: the scope after its renames'; end if;

  -- The reader of the scope sees each change in the audit log; the reader of another scope sees none.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  execute 'reset role';
  if (select count(*) from jsonb_array_elements(j->'items') e where e->>'event'='scope_renamed' and e->>'scope_id'=sa::text)<>3
   or not exists(select 1 from jsonb_array_elements(j->'items') e where e->>'event'='scope_renamed' and e->>'field'='display_name'
    and e->>'old_value'='Rename test scope A' and e->>'new_value'='Rename test scope One' and e->>'subject'='Rename test scope One'
    and e->>'reason'='Rename test' and e->>'actor_name'='Rename test administrator' and e->>'scope_name'='Rename test scope Two') then
   raise exception 'FAIL renames: the scope''s reader audits %',j; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rb,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(j->'items') e where e->>'event'='scope_renamed' and e->>'scope_id'=sa::text) then
   raise exception 'FAIL renames: another scope''s reader audits %',j; end if;

  -- Nothing but a rename writes the log, and a scope's code stays fixed.
  msg:=null; begin update okb.scope_change set reason='Changed' where scope_id=sa; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope changes are append-only; use okb_rename_scope' then raise exception 'FAIL renames: the log was changed %',msg; end if;
  msg:=null; begin delete from okb.scope_change where scope_id=sa; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope changes are append-only; use okb_rename_scope' then raise exception 'FAIL renames: the log was deleted from %',msg; end if;
  msg:=null; begin truncate okb.scope_change; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope changes are append-only; use okb_rename_scope' then raise exception 'FAIL renames: the log was truncated %',msg; end if;
  msg:=null; begin insert into okb.scope_change(scope_id,field,old_value,new_value,changed_by_actor_id,reason) values(sa,'display_name','A','B',h,'Forged'); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope changes are append-only; use okb_rename_scope' then raise exception 'FAIL renames: a forged log row %',msg; end if;
  msg:=null; begin update okb.scope set code='auth_test_rename_c' where scope_id=sa; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope identity is fixed' then raise exception 'FAIL renames: a code change %',msg; end if;
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT25',message='Rollback rename fixtures';
 exception when sqlstate 'PHT25' then null;
 end;
end $rename$;

create function okb_tests.suite_26_own_records() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $own$
declare h uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); ag uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); f uuid:=gen_random_uuid();
 s uuid:=gen_random_uuid(); s2 uuid:=gen_random_uuid(); rid uuid; who uuid; r jsonb; j jsonb; msg text; gid uuid; issue uuid:=gen_random_uuid();
 t0 timestamptz:=clock_timestamp(); plan_c text; b1 text; b2 text; b3 text; b4 text; c1 text; e1 text;
 kinds text[]:=array['activity','evidence'];
begin
 begin
  insert into auth.users(id) values(h),(b),(c),(d),(ag),(e),(f);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Own test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(b,b,'Own test requester B','human',b,'restricted',true),(c,c,'Own test requester C','human',c,'restricted',true),
    (d,d,'Own test operations D','human',d,'restricted',true),(ag,ag,'Own test agent of B','agent',b,'restricted',true),
    (e,e,'Own test requester E','human',e,'restricted',true),(f,f,'Own test requester F','human',f,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s,'auth_test_own','Own test scope','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s2,'auth_test_own_b','Own test scope B','Rolled-back fixture',h);

  -- The administrator grants requesters B and C, and B's agent, the actions limited to their own records, and operations the same actions without the limit.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  foreach who in array array[b,c,ag] loop
   r:=pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),who,s,kinds,null,array['read','create','edit','start','cancel'],null,'Own test',true));
   if r->>'own_records'<>'true' then execute 'reset role'; raise exception 'FAIL own records: a limited grant % %',who,r; end if;
  end loop;
  r:=pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),d,s,kinds,null,array['read','create','edit','start','cancel'],null,'Own test'));
  if r->>'own_records'<>'false' then execute 'reset role'; raise exception 'FAIL own records: an unlimited grant %',r; end if;
  -- E reads every activity in the scope, and edits only the records that are E's own.
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),e,s,kinds,null,array['read'],null,'Own test'));
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),e,s,kinds,null,array['read','create','edit'],null,'Own test',true));
  perform pg_temp.raised(okb.okb_add_record('auth_test_own_b','evidence','Own test other scope evidence','Own test','{"summary":"Elsewhere","standing":"stated"}'));
  plan_c:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test plan C','Own test','{"activity_kind":"plan","index":"9"}'))->>'record_id';
  execute 'reset role';

  -- A limited grant is refused with delete, with a record, without read, and on a retry that differs.
  rid:=(select record_id from okb.record where scope_id=s and kind='activity' limit 1);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),b,s,kinds,null,array['read','delete'],null,'Own test',true)); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A grant limited to own records does not carry delete' then execute 'reset role'; raise exception 'FAIL own records: a limited grant with delete %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),b,s,array['activity'],rid,array['read'],null,'Own test',true)); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A grant limited to own records covers no single record' then execute 'reset role'; raise exception 'FAIL own records: a limited grant with a record %',msg; end if;
  msg:=null; begin perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),b,s,kinds,null,array['create'],null,'Own test',true)); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A grant limited to own records carries read' then execute 'reset role'; raise exception 'FAIL own records: a limited grant without read %',msg; end if;
  perform pg_temp.raised(okb.okb_grant_permission(issue,b,s2,kinds,null,array['read'],null,'Own test retry',true));
  msg:=null; begin perform pg_temp.raised(okb.okb_grant_permission(issue,b,s2,kinds,null,array['read'],null,'Own test retry',false)); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Issuance retry differs' then execute 'reset role'; raise exception 'FAIL own records: a retry without the limit %',msg; end if;
  execute 'reset role';

  -- Orderer B saves, starts and cancels a request, and the agent of B saves another, which is B's own.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_scopes();
  if not exists(select 1 from jsonb_array_elements(r->'items') x where x->>'code'='auth_test_own') then execute 'reset role'; raise exception 'FAIL own records: B lists the scope %',r; end if;
  b1:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request B1','Own test','{"activity_kind":"task","index":"1","completion_requirements":"Received"}'))->>'record_id';
  b3:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request B3','Own test','{"activity_kind":"task","index":"3","completion_requirements":"Received"}'))->>'record_id';
  b4:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request B4','Own test','{"activity_kind":"task","index":"7","completion_requirements":"Received"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_change_record(b1,'Own test','{"description":"Edited by B"}'));
  perform pg_temp.raised(okb.okb_set_state(b1,'in_progress','Own test'));
  perform pg_temp.raised(okb.okb_set_state(b4,'cancelled','Own test'));
  r:=okb.okb_show_record(b1);
  if r::text not like '%Edited by B%' or r::text not like '%in_progress%' then execute 'reset role'; raise exception 'FAIL own records: B reads its own record after changing it %',r; end if;
  r:=okb.okb_show_record(b4);
  if r::text not like '%cancelled%' then execute 'reset role'; raise exception 'FAIL own records: B cancelled its own record %',r; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  b2:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request B2','Own test','{"activity_kind":"task","index":"2","completion_requirements":"Received"}'))->>'record_id';
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_change_record(b2,'Own test','{"description":"Edited by B after its agent saved it"}'));
  j:=okb.okb_find_records(null,s);
  if (select array_agg(x->>'title' order by x->>'title') from jsonb_array_elements(j->'items') x) is distinct from array['Own test request B1','Own test request B2','Own test request B3','Own test request B4'] then
   execute 'reset role'; raise exception 'FAIL own records: B finds %',j; end if;
  execute 'reset role';

  -- Orderer C saves one, and sees only that one, wherever C looks.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  c1:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request C1','Own test','{"activity_kind":"task","index":"4","completion_requirements":"Received"}'))->>'record_id';
  j:=okb.okb_find_records(null,s);
  if (select array_agg(x->>'title') from jsonb_array_elements(j->'items') x) is distinct from array['Own test request C1'] then execute 'reset role'; raise exception 'FAIL own records: C finds %',j; end if;
  j:=okb.okb_get_progress(null,null,null,100,s);
  if exists(select 1 from jsonb_array_elements(j->'items') x where x->>'title' like 'Own test request B%') or not exists(select 1 from jsonb_array_elements(j->'items') x where x->>'title'='Own test request C1') then
   execute 'reset role'; raise exception 'FAIL own records: C reads progress %',j; end if;
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  if exists(select 1 from jsonb_array_elements(j->'items') x where x->>'event'='record_saved' and x->>'subject' like 'Own test request B%') or not exists(select 1 from jsonb_array_elements(j->'items') x where x->>'event'='record_saved' and x->>'subject'='Own test request C1') then
   execute 'reset role'; raise exception 'FAIL own records: C audits %',j; end if;
  if okb.okb_find_people(s)->'items'<>'[]'::jsonb then execute 'reset role'; raise exception 'FAIL own records: C finds people %',okb.okb_find_people(s); end if;
  -- C cannot read, edit, start, cancel or link to another's request, and cannot read the other scope.
  foreach msg in array array['show','change','start','cancel','link','parent'] loop
   begin
    perform case msg
     when 'show' then okb.okb_show_record(b1)
     when 'change' then pg_temp.raised(okb.okb_change_record(b1,'Own test','{"description":"Edited by C"}'))
     when 'start' then pg_temp.raised(okb.okb_set_state(b3,'in_progress','Own test'))
     when 'cancel' then pg_temp.raised(okb.okb_set_state(b1,'cancelled','Own test'))
     when 'link' then pg_temp.raised(okb.okb_link(c1,b1,'depends_on','Own test'))
     else pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request C2','Own test','{"activity_kind":"task","index":"5","completion_requirements":"Received"}',plan_c)) end;
    execute 'reset role'; raise exception 'FAIL own records: C did % on another''s record',msg;
   exception when insufficient_privilege then
    if sqlerrm not like 'Record unavailable%' then execute 'reset role'; raise exception 'FAIL own records: C % was refused with %',msg,sqlerrm; end if;
   end;
  end loop;
  execute 'reset role';

  -- E reads everything, and edits only what is E's own: the grant that carries edit is the limited one.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if jsonb_array_length(okb.okb_find_records(null,s)->'items')<>6 then execute 'reset role'; raise exception 'FAIL own records: E reads %',okb.okb_find_records(null,s); end if;
  e1:=pg_temp.raised(okb.okb_add_record('auth_test_own','activity','Own test request E1','Own test','{"activity_kind":"task","index":"6","completion_requirements":"Received"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_change_record(e1,'Own test','{"description":"Edited by E"}'));
  msg:=null; begin perform pg_temp.raised(okb.okb_change_record(c1,'Own test','{"description":"Edited by E"}')); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Action outside authority scope' then execute 'reset role'; raise exception 'FAIL own records: E edits another''s record %',msg; end if;
  execute 'reset role';

  -- Operations, with the same actions and no limit, reads and changes every request in the scope, and an administrator reads them all.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if jsonb_array_length(okb.okb_find_records(null,s)->'items')<>7 then execute 'reset role'; raise exception 'FAIL own records: operations reads %',okb.okb_find_records(null,s); end if;
  perform pg_temp.raised(okb.okb_change_record(c1,'Own test','{"description":"Edited by operations"}'));
  perform pg_temp.raised(okb.okb_set_state(b3,'in_progress','Own test'));
  execute 'reset role';

  -- The administrator reads every grant with its limit, and the audit log names the limit.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if (select count(*) from jsonb_array_elements(okb.okb_get_authorisations(b)->'items') x where x->>'own_records'='true')<>2
   or (select count(*) from jsonb_array_elements(okb.okb_get_authorisations(d)->'items') x where x->>'own_records'='true')<>0 then
   execute 'reset role'; raise exception 'FAIL own records: the grants list'; end if;
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  if (select count(*) from jsonb_array_elements(j->'items') x where x->>'event'='grant_issued' and x->>'own_records'='true' and x->>'scope_id' in (s::text,s2::text))<>5 then
   execute 'reset role'; raise exception 'FAIL own records: the audit log names the limit %',j; end if;
  execute 'reset role';

  -- The administrator login provisions requester F a grant limited to own records in scope B, and refuses one with delete.
  perform set_config('request.jwt.claims','{}',true);
  r:=okb_private.provision_grant(h,gen_random_uuid(),f,s2,kinds,null,array['read','create','edit','cancel'],null::timestamptz,'Own test provisioned',true);
  if r->>'own_records'<>'true' then raise exception 'FAIL own records: a provisioned limited grant %',r; end if;
  msg:=null; begin perform okb_private.provision_grant(h,gen_random_uuid(),f,s2,kinds,null,array['read','delete'],null::timestamptz,'Own test provisioned',true); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'A grant limited to own records does not carry delete' then raise exception 'FAIL own records: a provisioned limited grant with delete %',msg; end if;
  -- F saves a request in scope B and finds only that one, never the evidence the administrator saved there.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',f,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_add_record('auth_test_own_b','activity','Own test request F1','Own test','{"activity_kind":"task","index":"8","completion_requirements":"Received"}'));
  j:=okb.okb_find_records(null,s2);
  if (select array_agg(x->>'title') from jsonb_array_elements(j->'items') x) is distinct from array['Own test request F1'] then execute 'reset role'; raise exception 'FAIL own records: F finds %',j; end if;
  execute 'reset role';

  -- A limited grant opens no file in the scope, and an unlimited one does.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from okb_storage.usable_buckets('read') x where x='auth_test_own') or exists(select 1 from okb_storage.usable_buckets('create') x where x='auth_test_own') then
   execute 'reset role'; raise exception 'FAIL own records: B opens the scope''s files'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if not exists(select 1 from okb_storage.usable_buckets('read') x where x='auth_test_own') then execute 'reset role'; raise exception 'FAIL own records: operations opens the scope''s files'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT26',message='Rollback own records fixtures';
 exception when sqlstate 'PHT26' then null;
 end;
end $own$;
-- -------------------------------------------------------------------
-- Suite: deleting an empty scope. A person who is an administrator deletes a scope that holds no
-- record and no file; its grants and bucket go with it, and the history of its files, moves and
-- renames stays.
-- -------------------------------------------------------------------
create function okb_tests.suite_27_scope_delete() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $delete$
declare h uuid:=gen_random_uuid(); ga uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); p uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid(); sd uuid:=gen_random_uuid(); se uuid:=gen_random_uuid(); sx uuid:=gen_random_uuid();
 who uuid; rec uuid; r jsonb; j jsonb; prev jsonb; delreq jsonb; appr jsonb; msg text; reserved text; t0 timestamptz:=clock_timestamp();
begin
 begin
  insert into auth.users(id) values(h),(ga),(ra),(p);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Delete test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ga,ga,'Delete test agent administrator','agent',h,'administrator',true),
    (ra,ra,'Delete test reader','human',ra,'restricted',true),(p,p,'Delete test editor','human',p,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sa,'auth_test_delete_a','Delete test scope A','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sb,'auth_test_delete_b','Delete test scope B','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_delete_c','Delete test scope C','Rolled-back fixture',h);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sd,'auth_test_delete_d','Delete test scope D','Rolled-back fixture',h);
  perform okb_private.provision_grant(h,gen_random_uuid(),ra,sa,array['activity','decision','model','evidence'],null,array['read'],null::timestamptz,'Delete test reader');
  perform okb_private.provision_grant(h,gen_random_uuid(),p,sa,array['evidence'],null,array['read','create'],null::timestamptz,'Delete test editor');
  perform okb_private.provision_grant(h,gen_random_uuid(),p,sd,array['activity'],null,array['read','create','edit','delete'],null::timestamptz,'Delete test editor');
  if not exists(select 1 from okb.scope where code='reference') then
   insert into okb.scope(scope_id,code,display_name,description,created_by) values(sx,'reference','Reference','Rolled-back fixture',h);
  end if;

  -- A scope renamed before its deletion keeps that history after it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_rename_scope('auth_test_delete_a','Delete test scope One',null,'Delete test'));
  rec:=pg_temp.raised(okb.okb_add_record('auth_test_delete_b','evidence','Delete test finding','Delete test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  execute 'reset role';

  -- A record in the scope keeps it. So does a file in its bucket, and the name of a scope Setup needs.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_b','Delete test')); exception when foreign_key_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The scope Delete test scope B holds 1 records, 0 of them deleted; a scope is deleted only when it holds none' then
   execute 'reset role'; raise exception 'FAIL scope deletes: a scope with a record %',msg; end if;
  execute 'reset role';
  insert into storage.objects(bucket_id,name,owner_id) values('auth_test_delete_c','kept.pdf',h::text);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_c','Delete test')); exception when foreign_key_violation then msg:=sqlerrm; end;
  if msg is distinct from 'The scope holds 1 files; delete them first' then execute 'reset role'; raise exception 'FAIL scope deletes: a scope with a file %',msg; end if;
  foreach reserved in array array['general','routines','reference','plugins'] loop
   msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope(reserved,'Delete test')); exception when insufficient_privilege then msg:=sqlerrm; end;
   if msg is null or (msg not like 'The scope % is part of OKB''s setup and is not deleted' and msg not like 'Scope unavailable: no scope has%') then
    execute 'reset role'; raise exception 'FAIL scope deletes: the % scope %',reserved,msg; end if;
  end loop;
  msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_a',' ')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'Give the reason for the deletion, as p_reason' then execute 'reset role'; raise exception 'FAIL scope deletes: no reason %',msg; end if;
  execute 'reset role';

  -- A restricted person and an agent that is an administrator are refused.
  foreach who in array array[ra,ga] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',who,'role','authenticated')::text,true);
   execute 'set local role authenticated';
   msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_a','Delete test')); exception when insufficient_privilege then msg:=sqlerrm; end;
   execute 'reset role';
   if msg is distinct from 'Only a person who is an administrator deletes a scope' then raise exception 'FAIL scope deletes: % deleted %',who,msg; end if;
  end loop;

  -- The administrator deletes an empty scope by its name. The scope, its two grants and its bucket go.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_delete_scope(' delete TEST scope one ','Delete test'));
  execute 'reset role';
  if r->>'scope_id'<>sa::text or r->>'code'<>'auth_test_delete_a' or r->>'name'<>'Delete test scope One' or (r->>'grants_removed')::int<>2
   or r->>'deleted_by'<>'Delete test administrator' or r->>'reason'<>'Delete test' then
   raise exception 'FAIL scope deletes: the answer %',r; end if;
  if exists(select 1 from okb.scope where scope_id=sa) or exists(select 1 from okb.authorisation where scope_id=sa)
   or exists(select 1 from storage.buckets where id='auth_test_delete_a') then
   raise exception 'FAIL scope deletes: the scope, its grants or its bucket remain'; end if;
  if (select count(*) from okb.scope_deletion where scope_id=sa and code='auth_test_delete_a' and display_name='Delete test scope One'
       and description='Rolled-back fixture' and jsonb_array_length(grants_removed)=2 and reason='Delete test')<>1 then
   raise exception 'FAIL scope deletes: the deletion log %',(select jsonb_agg(to_jsonb(x)) from okb.scope_deletion x where x.scope_id=sa); end if;
  if not exists(select 1 from okb.scope_deletion x, jsonb_array_elements(x.grants_removed) g
   where x.scope_id=sa and g->>'executor'='Delete test reader' and g->'allowed_actions'='["read"]'::jsonb) then
   raise exception 'FAIL scope deletes: the grants removed'; end if;
  if (select count(*) from okb.scope_change where scope_id=sa)<>1 then raise exception 'FAIL scope deletes: the rename history'; end if;
  msg:=null;
  begin perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true); execute 'set local role authenticated';
   perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_a','Delete test again')); exception when insufficient_privilege then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Scope unavailable: no scope has the id, code or name "auth_test_delete_a"' then raise exception 'FAIL scope deletes: a second call %',msg; end if;

  -- The administrator reads the deletion in the audit log; a restricted person does not.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  execute 'reset role';
  if not exists(select 1 from jsonb_array_elements(j->'items') e where e->>'event'='scope_deleted' and e->>'subject'='Delete test scope One'
    and e->>'reason'='Delete test' and e->>'actor_name'='Delete test administrator' and e->>'code'='auth_test_delete_a'
    and e->>'deleted_scope_id'=sa::text and jsonb_array_length(e->'grants_removed')=2) then
   raise exception 'FAIL scope deletes: the administrator audits %',j; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  j:=okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute');
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(j->'items') e where e->>'event'='scope_deleted') then
   raise exception 'FAIL scope deletes: a restricted person audits %',j; end if;

  -- The code is free again for a new scope, which gets a bucket of its own.
  insert into okb.scope(code,display_name,description,created_by) values('auth_test_delete_a','Delete test scope Again','Rolled-back fixture',h);
  if not exists(select 1 from storage.buckets where id='auth_test_delete_a') then raise exception 'FAIL scope deletes: no bucket for the new scope'; end if;

  -- A scope whose only record was deleted still holds that record, and is not deleted.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  rec:=pg_temp.raised(okb.okb_add_record('auth_test_delete_d','activity','Delete test task','Delete test',
   '{"description":"Task","activity_kind":"task","state":"pending"}'))->>'record_id';
  prev:=okb.okb_preview_deletion(rec);
  delreq:=jsonb_set(prev->'request','{reason}','"Delete test"');
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  appr:=pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),p,delreq,clock_timestamp()+interval '1 hour','Delete test'));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_delete_record(delreq,(appr->>'authorisation_id')::uuid));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null; begin perform pg_temp.raised(okb.okb_delete_scope('auth_test_delete_d','Delete test')); exception when foreign_key_violation then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'The scope Delete test scope D holds 1 records, 1 of them deleted; a scope is deleted only when it holds none' then
   raise exception 'FAIL scope deletes: a scope with a deleted record %',msg; end if;

  -- A scope whose only record, saved under a grant, was moved out is deleted. Its moves stay, and the
  -- version keeps the id of the grant it was saved under.
  perform set_config('request.jwt.claims','{}',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(se,'auth_test_delete_e','Delete test scope E','Rolled-back fixture',h);
  perform okb_private.provision_grant(h,gen_random_uuid(),p,se,array['evidence'],null,array['read','create','edit'],null::timestamptz,'Delete test editor');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  rec:=pg_temp.raised(okb.okb_add_record('auth_test_delete_e','evidence','Delete test moved finding','Delete test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_move_records(okb.okb_preview_move(array[rec::text],'auth_test_delete_b','Delete test')));
  r:=pg_temp.raised(okb.okb_delete_scope('auth_test_delete_e','Delete test'));
  execute 'reset role';
  if (r->>'grants_removed')::int<>1 or exists(select 1 from okb.scope where scope_id=se) or exists(select 1 from okb.authorisation where scope_id=se)
   or (select count(*) from okb.record_move where from_scope_id=se)<>1
   or (select authorisation_id is null from okb.record_version where record_id=rec and version_number=1) then
   raise exception 'FAIL scope deletes: a scope whose records were moved out %',r; end if;

  -- Nothing but okb_delete_scope deletes a scope, a grant or a log row.
  msg:=null; begin delete from okb.scope where scope_id=sb; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Disable scopes; delete only an empty one, with okb_delete_scope' then raise exception 'FAIL scope deletes: a direct delete %',msg; end if;
  msg:=null; begin delete from okb.authorisation where scope_id=sb; exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Use authority functions' then raise exception 'FAIL scope deletes: a direct grant delete %',msg; end if;
  msg:=null; begin update okb.scope_deletion set reason='Changed' where scope_id=sa; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope deletions are append-only; use okb_delete_scope' then raise exception 'FAIL scope deletes: the log was changed %',msg; end if;
  msg:=null; begin delete from okb.scope_deletion where scope_id=sa; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope deletions are append-only; use okb_delete_scope' then raise exception 'FAIL scope deletes: the log was deleted from %',msg; end if;
  msg:=null; begin truncate okb.scope_deletion; exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope deletions are append-only; use okb_delete_scope' then raise exception 'FAIL scope deletes: the log was truncated %',msg; end if;
  msg:=null; begin insert into okb.scope_deletion(scope_id,code,display_name,description,grants_removed,deleted_by_actor_id,reason) values(sb,'x','x','x','[]',h,'Forged'); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Scope deletions are append-only; use okb_delete_scope' then raise exception 'FAIL scope deletes: a forged log row %',msg; end if;
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT26',message='Rollback scope delete fixtures';
 exception when sqlstate 'PHT26' then null;
 end;
end $delete$;

-- Suite 28: what the database advisors check, so a change cannot bring their findings back. Each
-- foreign key in okb has an index that starts with its columns. No table
-- there has two permissive policies for the same role and command.
create function okb_tests.suite_28_advisors() returns void language plpgsql set search_path = pg_catalog as $advisors$
declare missing text; doubled text;
begin
 select string_agg(c.conrelid::regclass::text||'.'||c.conname,', ' order by 1) into missing
 from pg_constraint c join pg_namespace n on n.oid=c.connamespace
 where c.contype='f' and n.nspname='okb'
  and not exists(select 1 from pg_index i where i.indrelid=c.conrelid
   and (i.indkey::int2[])[0:cardinality(c.conkey)-1]=c.conkey);
 if missing is not null then raise exception 'FAIL advisors: foreign keys without an index: %',missing; end if;
 select string_agg(t||' '||r||' '||m,', ' order by 1) into doubled from (
  select p.schemaname||'.'||p.tablename t, r, m
  from pg_policies p cross join lateral unnest(case when p.roles='{public}' then array['anon','authenticated','okb_identity','okb_reader','okb_writer'] else p.roles::text[] end) r
  cross join lateral unnest(case when p.cmd='ALL' then array['SELECT','INSERT','UPDATE','DELETE'] else array[p.cmd] end) m
  where p.schemaname='okb' and p.permissive='PERMISSIVE'
  group by 1,2,3 having count(*)>1) d;
 if doubled is not null then raise exception 'FAIL advisors: more than one permissive policy for: %',doubled; end if;
end $advisors$;

-- -------------------------------------------------------------------
-- Suite: activity owners. Every activity's owner is an enabled
-- person who can read activities in its scope, and OKB writes the owner's name.
-- -------------------------------------------------------------------
create function okb_tests.suite_29_owners() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $owners$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); ag uuid:=gen_random_uuid(); off uuid:=gen_random_uuid(); x uuid:=gen_random_uuid();
 s uuid:=gen_random_uuid(); gid uuid; req jsonb; v jsonb; r jsonb; msg text; who text; old_id uuid;
begin
 begin
  insert into auth.users(id) values(h),(p),(ag),(off),(x);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Owner test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Owner test Priya Reader','human',p,'restricted',true),(ag,ag,'Owner test agent','agent',h,'restricted',true),
    (off,off,'Owner test disabled','human',off,'restricted',true),(x,x,'Owner test outsider','human',x,'restricted',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s,'auth_test_owners','Owner test scope','Rolled-back fixture',h);
  gid:=(okb_private.provision_grant(h,gen_random_uuid(),ag,s,array['activity'],null,array['read','create','edit'],null::timestamptz,'Owner test')->>'authorisation_id')::uuid;
  perform okb_private.provision_grant(h,gen_random_uuid(),p,s,array['activity'],null,array['read'],null::timestamptz,'Owner test');
  perform okb_private.provision_grant(h,gen_random_uuid(),off,s,array['activity'],null,array['read'],null::timestamptz,'Owner test');
  update okb.actor set enabled=false where actor_id=off;
  perform set_config('okb.provisioning_actor','',true);

  -- The agent saves a task with no owner, owned by itself, by a disabled person and by a person
  -- who cannot read the scope, and each is refused.
  req:=jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',s,'kind','activity','expected_previous_version_id',null,
   'title','Owner test task','reason','Owner test','links','[]'::jsonb,
   'payload',jsonb_build_object('activity_kind','task','state','pending','description','Test','owner_label','Not a OKB person','completion_requirements','Done',
    'completion_note','','baseline_start_at',null,'baseline_finish_at',null,'forecast_start_at',null,'forecast_finish_at',null,'blockers','[]'::jsonb,'external_references','[]'::jsonb));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  foreach who in array array['none','agent','disabled','outsider'] loop
   msg:=null;
   begin
    perform pg_temp.raised(okb.okb_save_version(jsonb_set(req||jsonb_build_object('request_id',gen_random_uuid()),'{payload,owner_actor_id}',
     case who when 'none' then 'null'::jsonb when 'agent' then to_jsonb(ag) when 'disabled' then to_jsonb(off) else to_jsonb(x) end),gid));
   exception when check_violation then msg:=sqlerrm; end;
   if msg is distinct from 'Owner is not a person who can read this scope' then execute 'reset role'; raise exception 'FAIL owners: an owner who is % %',who,msg; end if;
  end loop;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid()),gid)); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Owner is not a person who can read this scope' then execute 'reset role'; raise exception 'FAIL owners: a save without owner_actor_id %',msg; end if;

  -- An enabled person who can read the scope owns it, and OKB writes their name over the one sent.
  v:=pg_temp.raised(okb.okb_save_version(jsonb_set(req,'{payload,owner_actor_id}',to_jsonb(p)),gid));
  if v->'payload'->>'owner_actor_id' is distinct from p::text or v->'payload'->>'owner_label' is distinct from 'Owner test Priya Reader' then
   execute 'reset role'; raise exception 'FAIL owners: the owner''s name %',v->'payload'; end if;

  -- An approval still matches its save when the owner's name changes between the two, and the
  -- save carries the new name.
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  req:=req||jsonb_build_object('request_id',gen_random_uuid(),'expected_previous_version_id',v->>'version_id','reason','Owner test rename');
  req:=jsonb_set(req,'{payload,owner_actor_id}',to_jsonb(p));
  gid:=(pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),ag,req,clock_timestamp()+interval '1 hour','Owner test rename'))->>'authorisation_id')::uuid;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('okb.provisioning_actor',h::text,true);
  update okb.actor set display_name='Owner test Priya Reader-Jones' where actor_id=p;
  perform set_config('okb.provisioning_actor','',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v:=pg_temp.raised(okb.okb_save_version(req,gid));
  if v->'payload'->>'owner_label' is distinct from 'Owner test Priya Reader-Jones' then
   execute 'reset role'; raise exception 'FAIL owners: a save after the owner''s name changed %',v->'payload'; end if;

  -- okb_set_owner finds the person by part of their name.
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_set_owner(v->>'record_id','administrator','Owner test'));
  if r->'payload'->>'owner_actor_id' is distinct from h::text or r->'payload'->>'owner_label' is distinct from 'Owner test administrator' then
   execute 'reset role'; raise exception 'FAIL owners: okb_set_owner %',r->'payload'; end if;
  r:=pg_temp.raised(okb.okb_set_owner(v->>'record_id','priya','Owner test'));
  if r->'payload'->>'owner_actor_id' is distinct from p::text then execute 'reset role'; raise exception 'FAIL owners: okb_set_owner by part of a name %',r->'payload'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_set_owner(v->>'record_id','outsider','Owner test')); exception when invalid_parameter_value then msg:=sqlerrm; end;
  if msg is distinct from 'No person who can read Owner test scope has a name with "outsider". An administrator can give them read in the scope' then
   execute 'reset role'; raise exception 'FAIL owners: okb_set_owner for a person who cannot read %',msg; end if;
  execute 'reset role';

  -- A version saved before the upgrade, with a name and no owner_actor_id, is listed by okb_find_unowned.
  -- The version is written as the agent's save under its grant, past the checks of a save today.
  old_id:=gen_random_uuid();
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ag,'role','authenticated')::text,true);
  execute 'set local role okb_writer';
  insert into okb.record(record_id,kind,scope_id,created_by,created_at) values(old_id,'activity',s,ag,clock_timestamp());
  insert into okb.record_version(version_id,record_id,version_number,previous_version_id,change_no,request_id,request_hash,recorded_at,
   executor_actor_id,accountable_human_id,authority_mode,authorisation_id,title,change_reason,payload)
  select gen_random_uuid(),old_id,1,null,nextval('okb.change_no_seq'::regclass),gen_random_uuid(),o.request_hash,clock_timestamp(),
   o.executor_actor_id,o.accountable_human_id,o.authority_mode,o.authorisation_id,'Owner test old task','Before the upgrade',
   (o.payload-'owner_actor_id')||'{"owner_label":"Owner test Priya Reader","index":"2"}'
  from okb.record_version o where o.record_id=(v->>'record_id')::uuid and o.version_number=1;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_find_unowned(s);
  execute 'reset role';
  if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'record_id' is distinct from old_id::text or r->'items'->0->>'index' is distinct from '2'
   or r->'items'->0->>'title' is distinct from 'Owner test old task' or r->'items'->0->>'owner_label' is distinct from 'Owner test Priya Reader' then
   raise exception 'FAIL owners: okb_find_unowned %',r; end if;

  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT29',message='Rollback owner fixtures';
 exception when sqlstate 'PHT29' then null;
 end;
end $owners$;




-- -------------------------------------------------------------------
-- Suite: permission checks. A restricted person holds a grant on a whole scope, one on a kind, one
-- on a single record, one on their own records, one revoked, one expired, one from a disabled
-- administrator and one in a disabled scope. Each read returns exactly the
-- records those grants allow, from the whole project: the readable records, found records, progress,
-- assigned tasks, the audit log, a record named by its title, and which scopes they read and see. A
-- linked save is saved with its links, and refused when it links to a record they cannot read. A
-- grant that has expired, one issued by an administrator who is disabled, and one in a disabled
-- scope give nothing. Upgrade 0057-fast-permission-checks.
-- -------------------------------------------------------------------
create function okb_tests.suite_33_permission_checks() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $permissions$
declare h uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); h2 uuid:=gen_random_uuid(); expiry timestamptz;
 sx uuid:=gen_random_uuid(); si uuid:=gen_random_uuid(); sg uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid(); sd uuid:=gen_random_uuid(); se uuid:=gen_random_uuid(); sn uuid:=gen_random_uuid();
 a1 uuid; a2 uuid; ea uuid; da uuid; b1 uuid; eb uuid; c1 uuid; c2 uuid; d1 uuid; d2 uuid; e1 uuid; n1 uuid; ev uuid[]:='{}'; ge uuid; dav uuid; ebv uuid;
 t0 timestamptz:=clock_timestamp(); want uuid[]; got uuid[]; r jsonb; req jsonb; msg text; k text; i int;
begin
 begin
  insert into auth.users(id) values(h),(p),(h2);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Permission check administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(p,p,'Permission check person','human',p,'restricted',true),(h2,h2,'Permission check second administrator','human',h2,'administrator',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values
   (sa,'auth_test_perm_a','Permission check whole scope','Rolled-back fixture',h),(sb,'auth_test_perm_b','Permission check evidence scope','Rolled-back fixture',h),
   (sc,'auth_test_perm_c','Permission check one record','Rolled-back fixture',h),(sd,'auth_test_perm_d','Permission check own records','Rolled-back fixture',h),
   (se,'auth_test_perm_e','Permission check revoked','Rolled-back fixture',h),(sn,'auth_test_perm_n','Permission check no grant','Rolled-back fixture',h),
   (sx,'auth_test_perm_x','Permission check expired','Rolled-back fixture',h),(si,'auth_test_perm_i','Permission check disabled issuer','Rolled-back fixture',h),
   (sg,'auth_test_perm_g','Permission check disabled scope','Rolled-back fixture',h);
  -- A grant that expires within the second, so it has expired by the reads.
  expiry:=clock_timestamp()+interval '1 second';
  perform okb_private.provision_grant(h,gen_random_uuid(),p,sx,array['activity'],null,array['read'],expiry,'Permission check expiry');
  perform okb_private.provision_grant(h2,gen_random_uuid(),p,si,array['activity'],null,array['read'],null::timestamptz,'Permission check second administrator');
  perform okb_private.provision_grant(h,gen_random_uuid(),p,sg,array['activity'],null,array['read'],null::timestamptz,'Permission check disabled scope');

  -- The administrator saves the records, uploads a file in each scope, and grants the person.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  a1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_a','activity','Permission check plan A1','Permission check','{"activity_kind":"plan","index":"1"}'))->>'record_id';
  a2:=pg_temp.raised(okb.okb_add_record('auth_test_perm_a','activity','Permission check task A2','Permission check','{"activity_kind":"task","index":"1.1","completion_requirements":"Done"}',a1::text))->>'record_id';
  ea:=pg_temp.raised(okb.okb_add_record('auth_test_perm_a','evidence','Permission check evidence EA','Permission check','{"summary":"Seen","standing":"stated"}'))->>'record_id';
  for i in 1..4 loop
   ev:=ev||(pg_temp.raised(okb.okb_add_record('auth_test_perm_a','evidence','Permission check evidence EA'||i,'Permission check','{"summary":"Seen","standing":"stated"}'))->>'record_id')::uuid;
  end loop;
  da:=pg_temp.raised(okb.okb_add_record('auth_test_perm_a','decision','Permission check decision DA','Permission check','{"question":"Which supplier?"}'))->>'record_id';
  b1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_b','activity','Permission check task B1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'))->>'record_id';
  eb:=pg_temp.raised(okb.okb_add_record('auth_test_perm_b','evidence','Permission check evidence EB','Permission check','{"summary":"Seen","standing":"stated"}'))->>'record_id';
  c1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_c','activity','Permission check task C1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'))->>'record_id';
  c2:=pg_temp.raised(okb.okb_add_record('auth_test_perm_c','activity','Permission check task C2','Permission check','{"activity_kind":"task","index":"2","completion_requirements":"Done"}'))->>'record_id';
  d2:=pg_temp.raised(okb.okb_add_record('auth_test_perm_d','activity','Permission check task D2','Permission check','{"activity_kind":"task","index":"2","completion_requirements":"Done"}'))->>'record_id';
  e1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_e','activity','Permission check task E1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'))->>'record_id';
  n1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_n','activity','Permission check task N1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'))->>'record_id';
  foreach k in array array['x','i','g'] loop
   perform pg_temp.raised(okb.okb_add_record('auth_test_perm_'||k,'activity','Permission check task '||upper(k)||'1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'));
  end loop;
  insert into storage.objects(bucket_id,name,owner,metadata) select 'auth_test_perm_'||x,'permission-check.md',h,'{"eTag":"p1"}' from unnest(array['a','b','c','d','e','n','x','i','g']) x;
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),p,sa,array['activity','evidence'],null,array['read','create','edit'],null,'Permission check'));
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),p,sb,array['evidence'],null,array['read'],null,'Permission check'));
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),p,sc,array['activity'],c1,array['read'],null,'Permission check'));
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),p,sd,array['activity'],null,array['read','create'],null,'Permission check',true));
  ge:=(pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),p,se,array['activity','decision','model','evidence'],null,array['read'],null,'Permission check'))->>'authorisation_id')::uuid;
  perform pg_temp.raised(okb.okb_revoke_authorisation(ge,'Permission check'));
  perform pg_temp.raised(okb.okb_change_record(a2::text,'Permission check',jsonb_build_object('assignee_actor_id',p)));
  perform pg_temp.raised(okb.okb_change_record(c1::text,'Permission check',jsonb_build_object('assignee_actor_id',p)));
  execute 'reset role';

  -- The person saves a record of their own in the own-records scope.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  d1:=pg_temp.raised(okb.okb_add_record('auth_test_perm_d','activity','Permission check task D1','Permission check','{"activity_kind":"task","index":"1","completion_requirements":"Done"}'))->>'record_id';
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('okb.provisioning_actor','',true);
  perform okb_private.provision_actor_enabled(h,h2,false);
  update okb.scope set enabled=false where scope_id=sg;
  perform pg_sleep(greatest(0,extract(epoch from expiry-clock_timestamp()))+0.05);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  want:=array(select x from unnest(array[a1,a2,ea,eb,c1,d1]||ev) x order by x);
  dav:=(select version_id from okb.record_version where record_id=da);
  ebv:=(select version_id from okb.record_version where record_id=eb);

  -- Each read returns exactly the records the grants allow.
  execute 'set local role okb_reader';
  got:=array(select x from okb_private.readable_records() x order by x);
  if got is distinct from want then execute 'reset role'; raise exception 'FAIL permission checks: the readable records are % and should be %',got,want; end if;
  got:=array(select x from okb_private.readable_records(sa,null,null,null,null) x order by x);
  if got is distinct from array(select x from unnest(array[a1,a2,ea]||ev) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the readable records in one scope are %',got; end if;
  got:=array(select x from okb_private.readable_records(null,'evidence',null,null,null) x order by x);
  if got is distinct from array(select x from unnest(array[ea,eb]||ev) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the readable evidence is %',got; end if;
  got:=array(select x from okb_private.readable_records(null,null,'permission CHECK task',null,null) x order by x);
  if got is distinct from array(select x from unnest(array[a2,c1,d1]) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the readable records by title are %',got; end if;
  got:=array(select x from okb_private.readable_records(null,null,null,t0,clock_timestamp()) x order by x);
  if got is distinct from want then execute 'reset role'; raise exception 'FAIL permission checks: the readable records saved in the period are %',got; end if;
  if exists(select 1 from okb_private.readable_records(null,null,null,t0-interval '1 day',t0)) then
   execute 'reset role'; raise exception 'FAIL permission checks: the person reads records saved before the fixtures'; end if;
  got:=array(select g from unnest(array[sa,sb,sc,sd,se,sn,sx,si,sg]) g where okb_private.can_read_scope(g));
  if got is distinct from array[sa,sb,sc] then execute 'reset role'; raise exception 'FAIL permission checks: the person reads the scopes % as a whole',got; end if;
  got:=array(select g from unnest(array[sa,sb,sc,sd,se,sn,sx,si,sg]) g where okb_private.can_see_scope(g));
  if got is distinct from array[sa,sb,sc,sd] then execute 'reset role'; raise exception 'FAIL permission checks: the person sees the scopes %',got; end if;
  got:=array(select distinct f.scope_id from okb.file_event f where f.scope_id in (sa,sb,sc,sd,se,sn,sx,si,sg) order by 1);
  if got is distinct from array(select x from unnest(array[sa,sb]) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the person sees the file events of the scopes %',got; end if;
  execute 'reset role';
  execute 'set local role authenticated';
  got:='{}'; r:=okb.okb_find_records(null,null,null,null,null,100);
  loop
   got:=got||array(select (x->>'record_id')::uuid from jsonb_array_elements(r->'items') x);
   exit when r->>'next_cursor' is null;
   r:=okb.okb_find_records(null,null,null,(r->>'cutoff')::bigint,(r->>'next_cursor')::bigint,100);
  end loop;
  got:=array(select x from unnest(got) x order by x);
  if got is distinct from want then execute 'reset role'; raise exception 'FAIL permission checks: the found records are % and should be %',got,want; end if;
  got:=array(select (x->>'record_id')::uuid from jsonb_array_elements(okb.okb_find_records('activity',null,'permission check',null,null,100)->'items') x order by 1);
  if got is distinct from array(select x from unnest(array[a1,a2,c1,d1]) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the found activities are %',got; end if;
  got:=array(select (x->>'record_id')::uuid from jsonb_array_elements(okb.okb_get_progress(null,null,null,100,sa)->'items') x order by 1);
  if got is distinct from array(select x from unnest(array[a1,a2]) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the progress of one scope lists %',got; end if;
  got:=array(select (x->>'record_id')::uuid from jsonb_array_elements(okb.okb_get_assigned(true)->'items') x order by 1);
  if got is distinct from array(select x from unnest(array[a2,c1]) x order by x) then execute 'reset role'; raise exception 'FAIL permission checks: the assigned tasks are %',got; end if;
  got:='{}'; r:=okb.okb_get_audit(t0,clock_timestamp(),null,100);
  loop
   got:=got||array(select (x->>'record_id')::uuid from jsonb_array_elements(r->'items') x where x->>'event'='record_saved');
   exit when r->>'next_cursor' is null;
   r:=okb.okb_get_audit(t0,clock_timestamp(),r->>'next_cursor',100);
  end loop;
  got:=array(select distinct x from unnest(got) x order by x);
  if got is distinct from want then execute 'reset role'; raise exception 'FAIL permission checks: the audit log lists saves of % and should list %',got,want; end if;
  if okb_task.record_id('Permission check task C1') is distinct from c1 then execute 'reset role'; raise exception 'FAIL permission checks: a readable record by its title'; end if;
  msg:=null; begin perform okb_task.record_id('Permission check task C2'); exception when insufficient_privilege then msg:=sqlerrm; end;
  if msg is distinct from 'Record unavailable: no record you can read has the title "Permission check task C2"' then
   execute 'reset role'; raise exception 'FAIL permission checks: a record the person cannot read, by its title: %',msg; end if;

  -- A linked save is saved with its links. A link to a decision they cannot read, or to a record in
  -- another scope, is refused.
  for i in 1..4 loop
   perform pg_temp.raised(okb.okb_link(a2::text,ev[i]::text,'supports','Permission check'));
  end loop;
  r:=pg_temp.raised(okb.okb_link(a2::text,ea::text,'supports','Permission check'));
  if r->>'authority_mode'<>'standing_permission' or jsonb_array_length(okb.okb_get_record(a2)->'links')<>6 then
   execute 'reset role'; raise exception 'FAIL permission checks: the linked save %',okb.okb_get_record(a2); end if;
  req:=pg_temp.raised(okb.okb_change_record(a2::text,'Permission check','{"description":"Linked"}',null,true));
  foreach k in array array['decision','other scope'] loop
   msg:=null;
   begin
    perform pg_temp.raised(okb.okb_save_version(jsonb_set(req->'request','{links}',(req->'request'->'links')||jsonb_build_array(jsonb_build_object('relation','supports','target_version_id',
     case k when 'decision' then dav else ebv end))),(req->>'authorisation_id')::uuid));
   exception when insufficient_privilege then msg:=sqlerrm;
   end;
   if msg is distinct from 'Link target unavailable' then execute 'reset role'; raise exception 'FAIL permission checks: a link to the % is %',k,coalesce(msg,'saved'); end if;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT33',message='Rollback permission check fixtures';
 exception when sqlstate 'PHT33' then null;
 end;
end $permissions$;

-- -------------------------------------------------------------------
-- Suite: private scopes. Only an administrator adds a scope; a private
-- one belongs to the person they name. An administrator sees its name and owner, and cannot read,
-- change, search, audit, grant in, approve in, move, rename or delete in it. The owner does each. A person the owner grants
-- does what the grant gives. The owner hands the scope on, and then holds nothing in it.
-- -------------------------------------------------------------------
create function okb_tests.suite_34_private_scopes() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $private$
declare h uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); q uuid:=gen_random_uuid(); sp uuid:=gen_random_uuid(); ag uuid:=gen_random_uuid();
 sc uuid; sc2 uuid; sq uuid; rid uuid; qid uuid; og uuid; r jsonb; req jsonb; delreq jsonb; appr jsonb; mv jsonb; msg text; n bigint;
 t0 timestamptz:=clock_timestamp();
begin
 if to_regclass('file_search.indexed_bucket') is null then
  raise exception 'FAIL private scopes: run the supabase-admin plugin''s file-search.sql and this skill''s file-search-scopes.sql first'; end if;
 begin
  insert into auth.users(id) values(h),(o),(q);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Private test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(o,o,'Private test owner','human',o,'restricted',true),(q,q,'Private test second','human',q,'restricted',true),
    (ag,null,'Private test agent','agent',h,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sp,'auth_test_private_public','Private test public scope','Rolled-back fixture',h);

  -- Only an administrator adds a scope, private or not. A private one opens to the owner they name.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_scope('auth_test_private_open','Private test open','Rolled-back fixture','Private test')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only a person who is an administrator adds a scope' then raise exception 'FAIL private scopes: a restricted person made a scope: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_scope('auth_test_private_own','Private test own','Rolled-back fixture','Private test',true)); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only a person who is an administrator adds a scope' then raise exception 'FAIL private scopes: a restricted person made a private scope: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_add_scope('auth_test_private','Private test scope','Rolled-back fixture','Private test',true,'Private test owner'));
  sc:=(r->>'scope_id')::uuid; og:=(r->>'owner_grant_id')::uuid;
  if r->>'is_private'<>'true' or r->>'owner_actor_id'<>o::text or og is null then raise exception 'FAIL private scopes: the person named does not own the scope: %',r; end if;
  sc2:=(pg_temp.raised(okb.okb_add_scope('auth_test_private_two','Private test scope two','Rolled-back fixture','Private test',true,'Private test owner'))->>'scope_id')::uuid;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  rid:=(pg_temp.raised(okb.okb_add_record('Private test scope','evidence','Private test note','Rolled-back fixture',
   '{"summary":"The pomegranate forecast","standing":"observed","limitations":"None"}'))->>'record_id')::uuid;
  insert into storage.objects(bucket_id,name,owner_id,metadata) values('auth_test_private','forecast.pdf',o::text,'{"eTag":"p1"}');
  execute 'reset role';
  if not exists(select 1 from storage.buckets where id='auth_test_private' and not public) then raise exception 'FAIL private scopes: the scope has no private bucket'; end if;
  perform file_search.record_file_text((select version_id from file_search.file_version where bucket_id='auth_test_private' and name='forecast.pdf' and state='waiting'),'extracted',
   '[{"ordinal":0,"place":"page 1","body":"The quarterly pomegranate forecast.","section":0}]'::jsonb,null,
   '[{"ordinal":0,"place":"page 1","body":"The quarterly pomegranate forecast."}]'::jsonb);

  -- The administrator sees the scope's name and owner, and nothing in it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select x into r from jsonb_array_elements(okb_task.scopes()) x where x->>'scope_id'=sc::text;
  if r->>'display_name'<>'Private test scope' or r->>'owner_name'<>'Private test owner' or r->>'is_private'<>'true' or r->'description'<>'null'::jsonb then
   raise exception 'FAIL private scopes: an administrator does not see the name and owner alone: %',r; end if;
  if jsonb_array_length(okb.okb_find_records(null,sc)->'items')<>0 or okb.okb_get_record(rid) is not null
   or okb.okb_preview_deletion(rid) is not null or jsonb_array_length(okb.okb_get_history(rid)->'items')<>0 then
   raise exception 'FAIL private scopes: an administrator reads a record in it'; end if;
  if exists(select 1 from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') x where x->>'scope_id'=sc::text) then
   raise exception 'FAIL private scopes: an administrator''s audit log shows it'; end if;
  if exists(select 1 from jsonb_array_elements(okb.okb_get_authorisations(null,null,100)->'items') x where x->>'scope_id'=sc::text) then
   raise exception 'FAIL private scopes: an administrator lists its grants'; end if;
  if jsonb_array_length(file_search.search('pomegranate',null,'auth_test_private')->'hits')<>0 then raise exception 'FAIL private scopes: an administrator found its file in search'; end if;
  select count(*) into n from storage.objects where bucket_id='auth_test_private';
  if n<>0 then raise exception 'FAIL private scopes: an administrator lists its files'; end if;
  msg:=null;
  begin insert into storage.objects(bucket_id,name,owner_id) values('auth_test_private','admin.pdf',h::text); exception when insufficient_privilege then msg:='refused'; end;
  if msg is null then raise exception 'FAIL private scopes: an administrator uploaded a file to it'; end if;
  msg:=null;
  begin perform okb.okb_get_unextracted('auth_test_private',10); exception when sqlstate '42501' then msg:='refused'; end;
  if msg is null then raise exception 'FAIL private scopes: an administrator listed its chunks for the graph'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_record('Private test scope','evidence','Administrator note','Rolled-back fixture','{"summary":"x","standing":"observed","limitations":"x"}'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'No grant of yours covers create on evidence records in Private test scope. Its owner can grant it%' then
   raise exception 'FAIL private scopes: an administrator saved a record in it: %',msg; end if;
  req:=jsonb_build_object('scope_id',sc,'request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'kind','evidence','expected_previous_version_id',null,
   'title','Administrator note','reason','Rolled-back fixture','links','[]'::jsonb,
   'payload',jsonb_build_object('summary','x','source_reference',null,'source_date',null,'standing','observed','limitations','x'));
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_version(req)); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Scope or record unavailable' then raise exception 'FAIL private scopes: an administrator approved their own save in it: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),h,sc,array['evidence'],null,array['read'],null,'Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the scope''s owner gives grants in a private scope' then raise exception 'FAIL private scopes: an administrator granted in it: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_revoke_authorisation(og,'Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the scope''s owner ends grants in a private scope' then raise exception 'FAIL private scopes: an administrator ended the owner''s grant: %',msg; end if;
  delreq:=jsonb_build_object('operation','delete','request_id',gen_random_uuid(),'record_id',rid,'scope_id',sc,'kind','evidence','reason','Rolled-back fixture','dependents','[]'::jsonb);
  msg:=null;
  begin perform pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),h,delreq,clock_timestamp()+interval '5 minutes','Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the scope''s owner approves changes in a private scope' then raise exception 'FAIL private scopes: an administrator approved a deletion in it: %',msg; end if;
  msg:=null;
  begin perform okb.okb_preview_move(array[rid::text],'Private test public scope'); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'Record unavailable%' then raise exception 'FAIL private scopes: an administrator previewed a move out of it: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_rename_scope('Private test scope','Renamed by an administrator',null,'Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the scope''s owner renames a private scope' then raise exception 'FAIL private scopes: an administrator renamed it: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_delete_scope('Private test scope','Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the scope''s owner deletes a private scope' then raise exception 'FAIL private scopes: an administrator deleted it: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  msg:=null;
  begin perform okb_private.provision_grant(h,gen_random_uuid(),h,sc,array['evidence'],null,array['read'],null::timestamptz,'Rolled-back fixture');
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'A private scope''s grants are given by its owner%' then raise exception 'FAIL private scopes: provisioning granted in it: %',msg; end if;

  -- A person the owner grants read reads, searches and lists files, and saves nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_find_actors('private test second');
  if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'actor_id'<>q::text then raise exception 'FAIL private scopes: the owner did not find the person to grant: %',r; end if;
  if exists(select 1 from jsonb_array_elements(okb.okb_find_actors('private test')->'items') x where x->>'actor_id'=ag::text) then
   raise exception 'FAIL private scopes: a restricted owner found another person''s agent'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_rename_scope('Private test public scope','Renamed by an owner',null,'Rolled-back fixture')); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'Scope unavailable%' then raise exception 'FAIL private scopes: a scope the owner cannot see was named to them: %',msg; end if;
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),q,sc,array['activity','decision','model','evidence'],null,array['read'],null,'Rolled-back fixture'));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform okb.okb_find_actors('private test'); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null then raise exception 'FAIL private scopes: a person who gives no grant found actors'; end if;
  if (select array_agg(x->>'title') from jsonb_array_elements(okb.okb_find_records(null,sc)->'items') x)<>array['Private test note'] then
   raise exception 'FAIL private scopes: the granted person does not read the record'; end if;
  if jsonb_array_length(file_search.search('pomegranate',null,'auth_test_private')->'hits')<>1 then raise exception 'FAIL private scopes: the granted person did not find the file'; end if;
  select count(*) into n from storage.objects where bucket_id='auth_test_private';
  if n<>1 then raise exception 'FAIL private scopes: the granted person does not list the file'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_record('Private test scope','evidence','Second note','Rolled-back fixture','{"summary":"x","standing":"observed","limitations":"x"}'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like '%Its owner can grant it%' then raise exception 'FAIL private scopes: a read grant saved a record: %',msg; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_authorisations(q);
  if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'scope_id'<>sc::text then raise exception 'FAIL private scopes: the owner does not list the grants of a person in their scope: %',r; end if;
  if exists(select 1 from jsonb_array_elements(okb.okb_get_authorisations()->'items') x where x->>'scope_id' not in (sc::text,sc2::text)) then
   raise exception 'FAIL private scopes: the owner lists a grant outside their scopes'; end if;
  -- The owner grants the administrator read: they read, and save nothing without an approval of the owner's.
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),h,sc,array['activity','decision','model','evidence'],null,array['read'],null,'Rolled-back fixture'));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if okb.okb_get_record(rid) is null then raise exception 'FAIL private scopes: a read grant from the owner does not let an administrator read'; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_record('Private test scope','evidence','Administrator note','Rolled-back fixture','{"summary":"x","standing":"observed","limitations":"x"}'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'No grant of yours covers create on evidence records in Private test scope. Its owner can grant it%' then
   raise exception 'FAIL private scopes: an administrator with read saved a record: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid()))); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is distinct from 'Supply the id of a grant or approval that covers this change' then
   raise exception 'FAIL private scopes: an administrator with read approved their own save: %',msg; end if;
  execute 'reset role';
  -- With create, they save.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),q,sc,array['evidence'],null,array['read','create'],null,'Rolled-back fixture'));
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  qid:=(pg_temp.raised(okb.okb_add_record('Private test scope','evidence','Second note','Rolled-back fixture','{"summary":"x","standing":"observed","limitations":"x"}'))->>'record_id')::uuid;
  if qid is null then raise exception 'FAIL private scopes: a create grant did not save'; end if;
  execute 'reset role';

  -- The owner deletes a record under their own approval, and moves one to another private scope they own.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  delreq:=(okb.okb_preview_deletion(rid)->'request')||jsonb_build_object('reason','Rolled-back fixture');
  appr:=pg_temp.raised(okb.okb_approve_change(gen_random_uuid(),o,delreq,clock_timestamp()+interval '5 minutes','Rolled-back fixture'));
  r:=pg_temp.raised(okb.okb_delete_record(delreq,(appr->>'authorisation_id')::uuid));
  execute 'reset role';
  if r->>'record_id'<>rid::text or (select issued_by_actor_id from okb.authorisation where authorisation_id=(r->>'authorisation_id')::uuid)<>o then
   raise exception 'FAIL private scopes: the owner did not delete under their own approval: %',r; end if;
  execute 'set local role authenticated';
  mv:=okb.okb_preview_move(array['Second note'],'Private test scope two','Rolled-back fixture');
  r:=pg_temp.raised(okb.okb_move_records(mv));
  if r->>'to_scope_id'<>sc2::text then raise exception 'FAIL private scopes: the owner did not move a record: %',r; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  perform okb_private.provision_grant(h,gen_random_uuid(),o,sp,array['evidence'],null,array['read'],null::timestamptz,'Rolled-back fixture');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform okb.okb_preview_move(array['Second note'],'Private test public scope'); exception when sqlstate '42501' then msg:=sqlerrm; end;
  if msg is null or msg not like 'Only the owner of a private scope moves records into or out of it%' then
   raise exception 'FAIL private scopes: a restricted owner moved a record to a scope that is not private: %',msg; end if;
  r:=pg_temp.raised(okb.okb_rename_scope('Private test scope','Private test scope renamed',null,'Rolled-back fixture'));
  if r->>'name'<>'Private test scope renamed' then raise exception 'FAIL private scopes: the owner did not rename it: %',r; end if;
  execute 'reset role';

  -- An administrator makes a private scope for another person, and holds nothing in it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_add_scope('auth_test_private_for','Private test for another','Rolled-back fixture','Private test',true,'Private test second'));
  sq:=(r->>'scope_id')::uuid;
  if r->>'owner_actor_id'<>q::text or r->>'is_private'<>'true' then raise exception 'FAIL private scopes: an administrator''s scope for another person: %',r; end if;
  execute 'reset role';
  if okb_private.scope_read_for(h,sq,null,null) or okb_private.scope_read_for(h,sc2,null,null) then
   raise exception 'FAIL private scopes: an administrator reads a private scope'; end if;
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_scope('sessions_auth_test_private','Private test sessions','Rolled-back fixture','Private test',true)); exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is null then raise exception 'FAIL private scopes: a private scope took a code kept for OKB''s own scopes'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_delete_scope('Private test for another','Rolled-back fixture'));
  if r->>'scope_id'<>sq::text then raise exception 'FAIL private scopes: the owner did not delete their empty scope: %',r; end if;
  if not exists(select 1 from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') x
   where x->>'event'='scope_deleted' and x->>'deleted_scope_id'=sq::text and x->>'description' is not null) then
   raise exception 'FAIL private scopes: the owner''s audit log does not show their scope''s deletion'; end if;
  execute 'reset role';

  -- Its privacy and owner change only as its owner hands it on.
  msg:=null;
  begin update okb.scope set is_private=false where scope_id=sc; exception when check_violation then msg:='refused'; end;
  if msg is null then raise exception 'FAIL private scopes: a scope stopped being private'; end if;
  msg:=null;
  begin update okb.scope set owner_actor_id=h where scope_id=sc; exception when check_violation then msg:='refused'; end;
  if msg is null then raise exception 'FAIL private scopes: a scope changed owner outside its handing on'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_hand_on_scope('Private test scope renamed','Private test second','Rolled-back fixture'));
  if r->>'owner_actor_id'<>q::text then raise exception 'FAIL private scopes: the scope was not handed on: %',r; end if;
  if exists(select 1 from jsonb_array_elements(okb.okb_get_scopes()->'items') x where x->>'scope_id'=sc::text) then
   raise exception 'FAIL private scopes: the old owner still sees the scope'; end if;
  execute 'reset role';
  if okb_private.authority_live(og) then raise exception 'FAIL private scopes: the old owner''s grant is still live'; end if;
  if exists(select 1 from okb.authorisation where scope_id=sc and issued_by_actor_id=o and revoked_at is null and consumed_version_id is null and consumed_deletion_id is null) then
   raise exception 'FAIL private scopes: a grant the old owner gave is not ended'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if not exists(select 1 from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') x
   where x->>'scope_id'=sc::text and x->>'event'='scope_handed_on' and x->>'subject'='Private test second') then
   raise exception 'FAIL private scopes: the new owner''s audit log does not show the handing on'; end if;
  perform pg_temp.raised(okb.okb_grant_permission(gen_random_uuid(),q,sc,array['evidence'],null,array['read'],null,'Rolled-back fixture'));
  if pg_temp.raised(okb.okb_add_record('Private test scope renamed','evidence','New owner note','Rolled-back fixture','{"summary":"x","standing":"observed","limitations":"x"}'))->>'record_id' is null then
   raise exception 'FAIL private scopes: the new owner does not save under their own grant'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select jsonb_agg(x->>'event') into r from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') x
   where x->>'scope_id' in (sc::text,sc2::text) and x->>'executor_actor_id' is distinct from h::text;
  if r is not null then raise exception 'FAIL private scopes: an administrator''s audit log shows a private scope''s events beyond their own grant: %',r; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT34',message='Rollback private scopes fixtures';
 exception when sqlstate 'PHT34' then null;
 end;
end $private$;

-- Refused changes are logged. A refused save answers the refusal, writes one log entry and changes
-- nothing else; a task function's refused preview, and a refusal part way through a task function's
-- saves, are logged and keep nothing. The audit log gives the entry to the refused actor and an
-- administrator, and a private scope's to its owner. Any other error is raised as before, and logs
-- nothing. Upgrade 0064-refusal-log.
create function okb_tests.suite_35_refusal_log() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $refusals$
declare h uuid:=gen_random_uuid(); rs uuid:=gen_random_uuid(); x uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); q uuid:=gen_random_uuid(); dis uuid:=gen_random_uuid();
 sc uuid:=gen_random_uuid(); ps uuid; g uuid; rid uuid:=gen_random_uuid(); task text; req jsonb; ans jsonb; e okb.refusal_event; items jsonb;
 n bigint; versions bigint; msg text; t0 timestamptz:=clock_timestamp();
begin
 begin
  insert into auth.users(id) values(h),(rs),(x),(o),(q),(dis);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Refusal test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(rs,rs,'Refusal test person','human',rs,'restricted',true),(x,x,'Refusal test other','human',x,'restricted',true),
    (o,o,'Refusal test owner','human',o,'restricted',true),(q,q,'Refusal test outsider','human',q,'restricted',true),
    (dis,dis,'Refusal test disabled','human',dis,'restricted',false);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_refusal','Refusal test scope','Rolled-back fixture',h);
  -- The person may create decisions without decide, and read and create activities without edit.
  perform okb_private.provision_grant(h,gen_random_uuid(),rs,sc,array['decision'],null,array['read','create'],null::timestamptz,'Refusal test person');
  perform okb_private.provision_grant(h,gen_random_uuid(),rs,sc,array['activity'],null,array['read','create'],null::timestamptz,'Refusal test person');
  perform okb_private.provision_grant(h,gen_random_uuid(),x,sc,array['decision','activity'],null,array['read'],null::timestamptz,'Refusal test other');
  g:=(select authorisation_id from okb.authorisation where executor_actor_id=rs and scope_id=sc and record_kinds=array['decision']);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  req:=pg_temp.raised(okb.okb_add_record('auth_test_refusal','decision','Refusal test decision','Rolled-back fixture','{"decision":"Log refusals"}',null,true))->'request'
   ||jsonb_build_object('request_id',gen_random_uuid(),'record_id',rid);
  perform pg_temp.raised(okb.okb_add_record('auth_test_refusal','activity','Refusal test plan','Rolled-back fixture','{"activity_kind":"plan","index":"1"}'));
  task:=pg_temp.raised(okb.okb_add_record('auth_test_refusal','activity','Refusal test task','Rolled-back fixture','{"activity_kind":"task","index":"1.1"}','Refusal test plan'))->>'record_id';
  ps:=(pg_temp.raised(okb.okb_add_scope('auth_test_refusal_private','Refusal test private scope','Rolled-back fixture','Private test',true,'Refusal test owner'))->>'scope_id')::uuid;
  execute 'reset role';

  -- A save the person's grant does not cover answers the refusal, logs it once and saves nothing.
  select count(*) into versions from okb.record_version;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_save_version(req,g);
  execute 'reset role';
  if ans is distinct from '{"refused":true,"problem":"Action outside authority scope"}'::jsonb then
   raise exception 'FAIL refusal log: a refused save answers %',ans; end if;
  select count(*) into n from okb.refusal_event where at>=t0;
  select * into e from okb.refusal_event where at>=t0 order by event_id desc limit 1;
  if n<>1 or e.actor_id is distinct from rs or e.auth_user_id is distinct from rs or e.function_name<>'okb_save_version' or e.scope_id is distinct from sc
   or e.kind is distinct from 'decision' or e.record_id is distinct from rid or e.problem<>'Action outside authority scope' then
   raise exception 'FAIL refusal log: a refused save logs %, %',n,to_jsonb(e); end if;
  if (select count(*) from okb.record_version)<>versions or exists(select 1 from okb.record where record_id=rid) then
   raise exception 'FAIL refusal log: a refused save kept a change'; end if;

  -- A task function's refused preview answers the refusal and is logged.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_add_record('Refusal test scope','decision','Refusal test decision','Rolled-back fixture','{"decision":"Log refusals"}',null,true);
  execute 'reset role';
  if ans->>'refused' is distinct from 'true' or ans->>'problem' not like 'No grant of yours covers create, decide on decision records in Refusal test scope. An administrator can grant it%' then
   raise exception 'FAIL refusal log: a refused preview answers %',ans; end if;
  select * into e from okb.refusal_event where at>=t0 order by event_id desc limit 1;
  if e.function_name<>'okb_add_record' or e.actor_id is distinct from rs or e.scope_id is distinct from sc or e.kind is distinct from 'decision' or e.record_id is not null
   or e.problem<>ans->>'problem' then raise exception 'FAIL refusal log: a refused preview logs %',to_jsonb(e); end if;

  -- A task function whose second save is refused keeps neither save.
  select count(*) into versions from okb.record_version;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_add_blocker(task,'Refusal test blocker','Something clears it','Rolled-back fixture');
  execute 'reset role';
  if ans->>'refused' is distinct from 'true' or ans->>'problem' not like 'No grant of yours covers edit on activity records in Refusal test scope.%' then
   raise exception 'FAIL refusal log: a task function refused part way answers %',ans; end if;
  if (select count(*) from okb.record_version)<>versions or exists(select 1 from okb.record_version where title='Refusal test blocker') then
   raise exception 'FAIL refusal log: a task function refused part way kept its first save'; end if;
  select * into e from okb.refusal_event where at>=t0 order by event_id desc limit 1;
  if e.function_name<>'okb_add_blocker' or e.record_id is distinct from task::uuid or e.scope_id is distinct from sc or e.kind is distinct from 'activity' then
   raise exception 'FAIL refusal log: a task function refused part way logs %',to_jsonb(e); end if;
  -- A task function's save raises a refusal its save answers, so the task function's other saves
  -- are undone with it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform okb_task.save(req,array['create'],false); exception when sqlstate '42501' then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Action outside authority scope' then raise exception 'FAIL refusal log: a task function''s refused save was not raised: %',msg; end if;
  select count(*) into n from okb.refusal_event where at>=t0;
  if n<>3 then raise exception 'FAIL refusal log: three refusals wrote % entries',n; end if;

  -- Any other error is raised as before, and logs nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid(),'nonsense',1),g); exception when sqlstate '22023' then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Missing or unknown JSON fields' then raise exception 'FAIL refusal log: a bad request was not raised as 22023: %',msg; end if;
  if (select count(*) from okb.refusal_event where at>=t0)<>3 then raise exception 'FAIL refusal log: a bad request was logged as a refusal'; end if;

  -- A refusal in a private scope, by a person who cannot see it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid(),'record_id',gen_random_uuid(),'scope_id',ps),null);
  execute 'reset role';
  if ans->>'refused' is distinct from 'true' then raise exception 'FAIL refusal log: a save in a private scope by an outsider answers %',ans; end if;

  -- The audit log: the administrator sees the person's refusals and none in the private scope; the
  -- person sees their own; another person sees none of them; the private scope's owner sees the
  -- outsider's, and the outsider sees their own without the scope.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select coalesce(jsonb_agg(i order by i->>'at'),'[]'::jsonb) into items from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i
   where i->>'event'='change_refused';
  execute 'reset role';
  if jsonb_array_length(items)<>3 or items->0->>'actor_name'<>'Refusal test person' or items->0->>'scope_name'<>'Refusal test scope'
   or items->0->>'function'<>'okb_save_version' or items->0->>'kind'<>'decision' or items->0->>'record_id'<>rid::text
   or items->0->>'problem'<>'Action outside authority scope' or items->0->>'subject'<>'Action outside authority scope'
   or items @> jsonb_build_array(jsonb_build_object('actor_name','Refusal test outsider')) then
   raise exception 'FAIL refusal log: an administrator''s audit log gives %',items; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i where i->>'event'='change_refused';
  execute 'reset role';
  if n<>3 then raise exception 'FAIL refusal log: the refused person''s audit log gives % refusals',n; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',x,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i where i->>'event'='change_refused';
  execute 'reset role';
  if n<>0 then raise exception 'FAIL refusal log: another person''s audit log gives % refusals',n; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select coalesce(jsonb_agg(i),'[]'::jsonb) into items from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i where i->>'event'='change_refused';
  execute 'reset role';
  if jsonb_array_length(items)<>1 or items->0->>'actor_name'<>'Refusal test outsider' or items->0->>'scope_id'<>ps::text then
   raise exception 'FAIL refusal log: the private scope''s owner''s audit log gives %',items; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select coalesce(jsonb_agg(i),'[]'::jsonb) into items from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i where i->>'event'='change_refused';
  execute 'reset role';
  if jsonb_array_length(items)<>1 or items->0->'scope_id'<>'null'::jsonb or items->0->'scope_name'<>'null'::jsonb then
   raise exception 'FAIL refusal log: the outsider''s audit log gives %',items; end if;

  -- Each function logs the scope, kind and record its call names: a record by its title, a scope by its
  -- name, a grant's scope, a move's source, and a grant's kinds.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  items:=jsonb_build_array(
   okb.okb_change_record('Refusal test task','Rolled-back fixture','{"description":"Changed"}'),
   okb.okb_rename_scope('Refusal test scope','Renamed',null,'Rolled-back fixture'),
   okb.okb_delete_scope('auth_test_refusal','Rolled-back fixture'),
   okb.okb_revoke_authorisation(g,'Rolled-back fixture'),
   okb.okb_move_records(jsonb_build_object('from_scope_id',sc)),
   okb.okb_grant_permission(gen_random_uuid(),x,sc,array['decision','activity'],null,array['read'],null,'Rolled-back fixture'));
  execute 'reset role';
  if exists(select 1 from jsonb_array_elements(items) i where i->>'refused' is distinct from 'true') then
   raise exception 'FAIL refusal log: a refused call answers %',items; end if;
  select jsonb_agg(jsonb_build_object('f',function_name,'s',scope_id,'k',kind,'r',record_id) order by event_id) into items
   from okb.refusal_event where at>=t0 and actor_id=rs and function_name not in ('okb_save_version','okb_add_record','okb_add_blocker');
  if items is distinct from jsonb_build_array(
   jsonb_build_object('f','okb_change_record','s',sc,'k','activity','r',task::uuid),
   jsonb_build_object('f','okb_rename_scope','s',sc,'k',null,'r',null),
   jsonb_build_object('f','okb_delete_scope','s',sc,'k',null,'r',null),
   jsonb_build_object('f','okb_revoke_authorisation','s',sc,'k',null,'r',null),
   jsonb_build_object('f','okb_move_records','s',sc,'k',null,'r',null),
   jsonb_build_object('f','okb_grant_permission','s',sc,'k','decision, activity','r',null)) then
   raise exception 'FAIL refusal log: the functions log %',items; end if;
  -- OKB's own functions that change data answer and log a refusal the same way: adding a scope, and
  -- saving a glossary term or a record kind of the data dictionary.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  items:=jsonb_build_array(
   okb.okb_add_scope('auth_test_refusal_added','Refusal test added scope','Rolled-back fixture','Rolled-back fixture'),
   okb.okb_save_term('Refusal test term','term','A word the test saves.','Rolled-back fixture'),
   okb.okb_save_dictionary('refusal_test_kind','Refusal test class','A kind the test saves.','[]','Rolled-back fixture'));
  execute 'reset role';
  if items->0 is distinct from '{"refused":true,"problem":"Only a person who is an administrator adds a scope"}'::jsonb
   or items->1->>'refused' is distinct from 'true' or items->2->>'refused' is distinct from 'true' then
   raise exception 'FAIL refusal log: OKB''s own functions answer %',items; end if;
  if exists(select 1 from okb.scope where code='auth_test_refusal_added')
   or (select array_agg(function_name order by event_id) from okb.refusal_event where at>=t0 and actor_id=rs
     and function_name in ('okb_add_scope','okb_save_term','okb_save_dictionary'))
    is distinct from array['okb_add_scope','okb_save_term','okb_save_dictionary'] then
   raise exception 'FAIL refusal log: OKB''s own functions log %, or kept the scope',
    (select jsonb_agg(to_jsonb(r)) from okb.refusal_event r where at>=t0 and actor_id=rs); end if;

  -- A disabled person is named by their sign-in, and the administrator sees who they are.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',dis,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_save_version(req||jsonb_build_object('request_id',gen_random_uuid()),g);
  execute 'reset role';
  select * into e from okb.refusal_event where at>=t0 order by event_id desc limit 1;
  if ans->>'refused' is distinct from 'true' or e.actor_id is distinct from dis or e.auth_user_id is distinct from dis then
   raise exception 'FAIL refusal log: a disabled person''s refusal logs %, answering %',to_jsonb(e),ans; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select i into ans from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i
   where i->>'event'='change_refused' and i->>'actor_id'=dis::text;
  execute 'reset role';
  if ans->>'actor_name' is distinct from 'Refusal test disabled' or ans->>'auth_user_id' is distinct from dis::text then
   raise exception 'FAIL refusal log: the administrator''s audit log gives the disabled person''s refusal as %',ans; end if;

  -- PostgreSQL's own refusal inside a body, such as a missing table grant, is raised as before and logged
  -- nowhere.
  select count(*) into n from okb.refusal_event where at>=t0;
  msg:=null;
  begin
   revoke insert on okb.record_version from okb_writer;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
   execute 'set local role authenticated';
   begin perform okb.okb_add_record('Refusal test scope','activity','Refusal test plan two','Rolled-back fixture','{"activity_kind":"plan","index":"2"}');
   exception when insufficient_privilege then msg:=sqlerrm; end;
   execute 'reset role';
   raise exception using errcode='PHT3R',message=coalesce(msg,'no error')||' | '||(select count(*) from okb.refusal_event where at>=t0)::text;
  exception when sqlstate 'PHT3R' then msg:=sqlerrm;
  end;
  if msg is distinct from 'permission denied for table record_version | '||n then
   raise exception 'FAIL refusal log: PostgreSQL''s own refusal reads %',msg; end if;

  -- The log is append-only, and no client writes it.
  msg:=null;
  begin update okb.refusal_event set problem='Changed' where at>=t0; exception when sqlstate '23514' then msg:=sqlerrm; end;
  if msg is distinct from 'The refusal log is append-only' then raise exception 'FAIL refusal log: an entry was changed: %',msg; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin insert into okb.refusal_event(function_name,problem) values('okb_save_version','Forged'); exception when insufficient_privilege then msg:='refused'; end;
  execute 'reset role';
  if msg is null then raise exception 'FAIL refusal log: a client wrote an entry'; end if;

  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT35',message='Rollback refusal log fixtures';
 exception when sqlstate 'PHT35' then null;
 end;
end $refusals$;

-- Access templates live in OKB. Every signed-in actor reads them. A restricted person's change is
-- refused and logged; an administrator's is saved and logged, and the audit log gives it as
-- access_template_changed with the old and new grants. A grant naming a scope that does not exist is
-- refused, and so is a template other than real_agent that changes the plugins scope. Applying basic
-- to a new person gives exactly its grants, and applying it again issues none. A basic person saves a
-- new decision in General.
create function okb_tests.suite_36_access_templates() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $templates$
declare h uuid:=gen_random_uuid(); rs uuid:=gen_random_uuid(); np uuid:=gen_random_uuid(); op uuid:=gen_random_uuid();
 sc uuid:=gen_random_uuid(); r jsonb; ans jsonb; items jsonb; basic jsonb; held jsonb; msg text; n bigint; t0 timestamptz:=clock_timestamp();
begin
 begin
  insert into auth.users(id) values(h),(rs),(np),(op);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Template test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(rs,rs,'Template test person','human',rs,'restricted',true),(np,np,'Template test newcomer','human',np,'restricted',true),
    (op,op,'Template test Real Agent','human',op,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(sc,'auth_test_template','Template test scope','Rolled-back fixture',h);
  -- Each scope basic and real_agent name, made for the run where this OKB lacks it.
  insert into okb.scope(code,display_name,description,created_by)
  select distinct g->>'scope','Template test '||(g->>'scope'),'Rolled-back fixture',h
  from okb.access_template t, jsonb_array_elements(t.grants) g
  where t.code in ('basic','real_agent') and not exists(select 1 from okb.scope s where s.code=g->>'scope');

  -- Every signed-in actor reads the templates, each grant naming its scope.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=okb.okb_get_access_templates();
  msg:=null;
  begin perform 1 from okb.access_template; exception when insufficient_privilege then msg:='refused'; end;
  execute 'reset role';
  if not (select array_agg(x->>'code') from jsonb_array_elements(r->'items') x) @> array['administrator','basic','real_agent'] then
   raise exception 'FAIL access templates: a restricted person reads %',r; end if;
  select x->'grants' into basic from jsonb_array_elements(r->'items') x where x->>'code'='basic';
  if exists(select 1 from jsonb_array_elements(basic) g where g->>'scope_name' is null) then raise exception 'FAIL access templates: a grant names no scope: %',basic; end if;
  if msg is null then raise exception 'FAIL access templates: a client read the table'; end if;

  -- A restricted person's change is refused, logged and keeps nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_save_access_template('basic','[]'::jsonb,null,null,'Rolled-back fixture');
  execute 'reset role';
  if ans is distinct from '{"refused":true,"problem":"Only a person who is an administrator changes an access template"}'::jsonb then
   raise exception 'FAIL access templates: a restricted person''s change answers %',ans; end if;
  if not exists(select 1 from okb.refusal_event where at>=t0 and actor_id=rs and function_name='okb_save_access_template') then
   raise exception 'FAIL access templates: a restricted person''s change was not logged'; end if;
  if (select jsonb_array_length(grants) from okb.access_template where code='basic')=0
   or exists(select 1 from okb.access_template_change where at>=t0) then raise exception 'FAIL access templates: a restricted person changed basic'; end if;

  -- An administrator's change is saved and logged; a scope that does not exist is refused, and so is
  -- a change that changes nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_access_template('auth_test_template',
   '[{"scope":"auth_test_missing","record_kinds":["decision"],"actions":["read"],"own_records":false}]','Template test','restricted','Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'There is no scope with the code auth_test_missing' then raise exception 'FAIL access templates: a missing scope is not refused: %',msg; end if;
  -- Only the real_agent template changes the plugins scope.
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_access_template('basic',
   '[{"scope":"plugins","record_kinds":["evidence"],"actions":["read","create"],"own_records":false}]',null,null,'Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'Only the real_agent template changes the plugins scope; the basic template only reads it' then
   raise exception 'FAIL access templates: basic may change the plugins scope: %',msg; end if;
  r:=pg_temp.raised(okb.okb_save_access_template('auth_test_template',
   '[{"scope":"auth_test_template","record_kinds":["evidence","decision"],"actions":["create","read"],"own_records":true}]','Template test','restricted','Rolled-back fixture'));
  if r->'old' is distinct from 'null'::jsonb or r->'new'->'grants' is distinct from
   '[{"scope":"auth_test_template","record_kinds":["decision","evidence"],"actions":["read","create"],"own_records":true}]'::jsonb then
   raise exception 'FAIL access templates: a new template saves %',r; end if;
  r:=pg_temp.raised(okb.okb_save_access_template('auth_test_template',
   '[{"scope":"auth_test_template","record_kinds":["decision"],"actions":["read"],"own_records":false}]',null,null,'Rolled-back fixture, changed'));
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_access_template('auth_test_template',null,'Template test',null,'Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'The auth_test_template access template already has that description, authority class and grants' then
   raise exception 'FAIL access templates: a change that changes nothing is not refused: %',msg; end if;
  select coalesce(jsonb_agg(i order by i->>'at'),'[]'::jsonb) into items from jsonb_array_elements(okb.okb_get_audit(t0,clock_timestamp()+interval '1 minute')->'items') i
   where i->>'event'='access_template_changed';
  execute 'reset role';
  if jsonb_array_length(items)<>2 or items->1->>'subject'<>'auth_test_template' or items->1->>'actor_id'<>h::text or items->1->>'reason'<>'Rolled-back fixture, changed'
   or items->1->'old_grants'<>'[{"scope":"auth_test_template","record_kinds":["decision","evidence"],"actions":["read","create"],"own_records":true}]'::jsonb
   or items->1->'new_grants'<>'[{"scope":"auth_test_template","record_kinds":["decision"],"actions":["read"],"own_records":false}]'::jsonb
   or items->0->'old_grants'<>'null'::jsonb then
   raise exception 'FAIL access templates: the audit log gives %',items; end if;
  msg:=null;
  begin update okb.access_template_change set reason='Changed' where at>=t0; exception when sqlstate '23514' then msg:=sqlerrm; end;
  if msg is distinct from 'The access template log is append-only' then raise exception 'FAIL access templates: a log entry was changed: %',msg; end if;

  -- Applying basic to a new person gives exactly its grants, and applying it again issues none. A
  -- restricted person applies no template.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rs,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  ans:=okb.okb_apply_access_template(np,'basic');
  execute 'reset role';
  if ans is distinct from '{"refused":true,"problem":"Only a person who is an administrator applies an access template"}'::jsonb then
   raise exception 'FAIL access templates: a restricted person''s apply answers %',ans; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_apply_access_template(np,'basic'));
  ans:=pg_temp.raised(okb.okb_apply_access_template(np,'basic'));
  execute 'reset role';
  select grants into basic from okb.access_template where code='basic';
  select coalesce(jsonb_agg(jsonb_build_object('scope',s.code,'record_kinds',to_jsonb(z.record_kinds),'actions',to_jsonb(z.allowed_actions),'own_records',z.own_records)
   order by s.code,z.own_records),'[]'::jsonb) into held
  from okb.authorisation z join okb.scope s on s.scope_id=z.scope_id where z.executor_actor_id=np;
  if held is distinct from (select jsonb_agg(g order by g->>'scope',(g->>'own_records')::boolean) from jsonb_array_elements(basic) g)
   or jsonb_array_length(r->'issued')<>jsonb_array_length(basic) or (r->>'already_held')::int<>0 then
   raise exception 'FAIL access templates: basic applied gives %, answering %, and should give %',held,r,basic; end if;
  if jsonb_array_length(ans->'issued')<>0 or (ans->>'already_held')::int<>jsonb_array_length(basic) then
   raise exception 'FAIL access templates: basic applied again answers %',ans; end if;
  if exists(select 1 from okb.authorisation where executor_actor_id=np and (issued_by_actor_id<>h or reason<>'The basic access template.')) then
   raise exception 'FAIL access templates: a template''s grant names another approver or reason'; end if;

  -- The person saves a new decision in General.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',np,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin
   r:=pg_temp.raised(okb.okb_add_record('general','decision','Template test purpose','Rolled-back fixture',
    '{"question":"Why?","decision":"Because","rationale":"Rolled-back fixture","decided_on":"2026-10-24"}'));
  exception when sqlstate '42501' then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is not null or r->>'record_id' is null then raise exception 'FAIL access templates: a basic person was refused a decision in General: %',coalesce(msg,r::text); end if;

  -- As the postgres login, bootstrap.sql step 3f's statement issues real_agent's grants in the
  -- administrator's name. A template that does not exist is refused.
  perform set_config('request.jwt.claims','{}',true);
  r:=okb_private.apply_access_template(h,op,'real_agent');
  select count(*) into n from okb.authorisation where executor_actor_id=op and issued_by_actor_id=h and reason='The real_agent access template.';
  if n<>(select jsonb_array_length(grants) from okb.access_template where code='real_agent') or jsonb_array_length(r->'issued')<>n then
   raise exception 'FAIL access templates: step 3f issued %, answering %',n,r; end if;
  msg:=null;
  begin perform okb_private.apply_access_template(h,op,'auth_test_none'); exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'There is no access template auth_test_none' then raise exception 'FAIL access templates: a missing template is not refused: %',msg; end if;

  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT36',message='Rollback access template fixtures';
 exception when sqlstate 'PHT36' then null;
 end;
end $templates$;

-- The Administration scope keeps the setup record and each access record. A project with an enabled
-- administrator who is a person has it. Only administrators, with their authority, and Real Agent, with the
-- real_agent template's read grant, work in it: no other template names it, every live grant there is read
-- alone, an administrator keeps a file and a record there with no grant, Real Agent's actor lists the file and
-- writes none, and a basic person neither lists nor writes there, nor reads the record. A workflow plugin's
-- scope, plugins_<workflow>, keeps its files as the plugins scope does: an administrator's authority reads them
-- and writes none, Real Agent's actor writes them with its own grant, a person granted read lists them, and a
-- person without the grant sees none.
create function okb_tests.suite_37_administration_and_plugin_scopes() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $administration$
declare h uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); rd uuid:=gen_random_uuid();
 sc uuid; ps uuid; n bigint; denied boolean; r jsonb; msg text; record_id text; original_actors bigint;
begin
 select scope_id into sc from okb.scope where code='administration';
 if sc is null and exists(select 1 from okb.actor where actor_kind='human' and authority_class='administrator' and enabled) then
  raise exception 'FAIL administration: a project with an administrator has no Administration scope'; end if;
 if sc is not null then
  select count(*) into n from okb.authorisation z join okb.actor x on x.actor_id=z.executor_actor_id
   where z.scope_id=sc and x.authority_class<>'administrator' and z.allowed_actions<>array['read'] and okb_private.authority_live(z.authorisation_id);
  if n<>0 then raise exception 'FAIL administration: % grant(s) in the Administration scope carry more than read',n; end if;
 end if;
 if exists(select 1 from okb.access_template t, jsonb_array_elements(t.grants) g where g->>'scope'='administration' and (t.code<>'real_agent' or g->'actions'<>'["read"]'::jsonb)) then
  raise exception 'FAIL administration: a template other than real_agent names the Administration scope, or real_agent changes it'; end if;
 select count(*) into original_actors from okb.actor;
 begin
  insert into auth.users(id) values(h),(ra),(p),(rd);
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Administration test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(ra,ra,'Administration test Real Agent','human',ra,'restricted',true),(p,p,'Administration test person','human',p,'restricted',true),
    (rd,rd,'Administration test reader','human',rd,'restricted',true);
  perform set_config('okb.provisioning_actor','',true);
  -- Each scope basic and real_agent name, made for the run where this OKB lacks it.
  insert into okb.scope(code,display_name,description,created_by)
  select distinct g->>'scope','Administration test '||(g->>'scope'),'Rolled-back fixture',h
  from okb.access_template t, jsonb_array_elements(t.grants) g
  where t.code in ('basic','real_agent') and not exists(select 1 from okb.scope s where s.code=g->>'scope');
  select scope_id into sc from okb.scope where code='administration';
  insert into okb.scope(code,display_name,description,created_by) values('plugins_auth_test','Administration test plugins','Rolled-back fixture',h) returning scope_id into ps;
  perform okb_private.apply_access_template(h,ra,'real_agent');
  perform okb_private.apply_access_template(h,p,'basic');
  perform okb_private.apply_access_template(h,rd,'basic');
  perform okb_private.provision_grant(h,gen_random_uuid(),ra,ps,array['evidence'],null,array['read','create','edit','delete'],null::timestamptz,'Administration test publisher');
  perform okb_private.provision_grant(h,gen_random_uuid(),rd,ps,array['evidence'],null,array['read'],null::timestamptz,'Administration test reader');
  if not exists(select 1 from okb.authorisation where executor_actor_id=ra and scope_id=sc and allowed_actions=array['read']) then
   raise exception 'FAIL administration: the real_agent template gives no read grant in Administration'; end if;
  if exists(select 1 from okb.authorisation where executor_actor_id=p and scope_id=sc) then
   raise exception 'FAIL administration: the basic template gives a grant in Administration'; end if;
  perform set_config('storage.allow_delete_query','true',true);

  -- An administrator keeps an access record's file and its record there with no grant.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner_id) values('administration','administration-test/access-for-test.md',h::text);
  select count(*) into n from storage.objects where bucket_id='administration' and name='administration-test/access-for-test.md';
  r:=pg_temp.raised(okb.okb_add_record('administration','evidence','Administration test: access for a person','Rolled-back fixture',
   '{"summary":"The person was given the basic template.","source_reference":"administration-test/access-for-test.md","source_date":"2026-10-24","standing":"observed","limitations":"Rolled-back fixture"}'));
  record_id:=r->>'record_id';
  execute 'reset role';
  if n<>1 or record_id is null then raise exception 'FAIL administration: an administrator does not keep a file and a record there: %, %',n,r; end if;

  -- Real Agent's actor lists the file and reads the record, and writes no file.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='administration';
  r:=okb.okb_show_record(record_id);
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('administration','administration-test/by-real-agent.md',ra::text);
  exception when insufficient_privilege then denied:=true; end;
  execute 'reset role';
  if n<>1 or r->>'record_id' is distinct from record_id or not denied then
   raise exception 'FAIL administration: Real Agent''s actor lists %, reads %, and its write was refused: %',n,r,denied; end if;

  -- A basic person neither lists nor writes there, nor reads the record.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='administration';
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('administration','administration-test/by-person.md',p::text);
  exception when insufficient_privilege then denied:=true; end;
  msg:=null;
  begin r:=okb.okb_show_record(record_id); exception when others then msg:=sqlerrm; end;
  execute 'reset role';
  if n<>0 or not denied then raise exception 'FAIL administration: a basic person lists % file(s) there, or wrote one',n; end if;
  if msg is null and r->>'record_id' is not null then raise exception 'FAIL administration: a basic person reads the record: %',r; end if;
  raise notice 'ok - the Administration scope: an administrator keeps a file and a record there, Real Agent''s actor reads them and writes none, and a basic person sees neither';

  -- A workflow plugin's scope: Real Agent's actor writes with its own grant, the administrator's authority writes nothing.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ra,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id,name,owner_id) values('plugins_auth_test','20261024-000000-0000000/MANIFEST',ra::text);
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='plugins_auth_test';
  denied:=false;
  begin insert into storage.objects(bucket_id,name,owner_id) values('plugins_auth_test','20261024-000001-0000000/MANIFEST',h::text);
  exception when insufficient_privilege then denied:=true; end;
  execute 'reset role';
  if n<>1 or not denied then raise exception 'FAIL plugin scopes: the administrator lists % file(s) in a workflow plugin''s scope, and was refused a write: %',n,denied; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rd,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='plugins_auth_test';
  execute 'reset role';
  if n<>1 then raise exception 'FAIL plugin scopes: a person granted read lists % file(s) in a workflow plugin''s scope',n; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='plugins_auth_test';
  execute 'reset role';
  if n<>0 then raise exception 'FAIL plugin scopes: a person without the grant lists % file(s) in a workflow plugin''s scope',n; end if;
  raise notice 'ok - a workflow plugin''s scope: Real Agent''s actor writes with its own grant, the administrator reads and writes nothing, a reader lists, and a person without the grant sees nothing';

  -- No scope takes the code of one of Real Agent's own plugins' scopes: okb_add_scope refuses it with its sentence, and
  -- the table refuses it to the postgres login too.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_add_scope('plugins_okb','Plugins: okb','Rolled-back fixture','Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'The code plugins_okb names one of Real Agent''s own plugins, which only the plugins scope keeps' then
   raise exception 'FAIL plugin scopes: okb_add_scope made, or refused another way, plugins_okb: %',msg; end if;
  msg:=null;
  begin insert into okb.scope(code,display_name,description,created_by) values('plugins_real_agent','Plugins: real-agent','Rolled-back fixture',h);
  exception when check_violation then msg:=sqlerrm; end;
  if msg is null then raise exception 'FAIL plugin scopes: the postgres login made plugins_real_agent'; end if;
  raise notice 'ok - no scope takes the code of one of Real Agent''s own plugins'' scopes, such as plugins_okb';

  -- No template but real_agent names Administration, and real_agent only reads it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_access_template('basic',
   '[{"scope":"administration","record_kinds":["evidence"],"actions":["read"],"own_records":false}]',null,null,'Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  if msg is distinct from 'Only administrators and Real Agent read the administration scope; the real_agent template reads it, and no template changes it' then
   execute 'reset role'; raise exception 'FAIL administration: basic may name the Administration scope: %',msg; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_save_access_template('real_agent',
   '[{"scope":"administration","record_kinds":["evidence"],"actions":["read","create"],"own_records":false}]',null,null,'Rolled-back fixture'));
  exception when sqlstate '22023' then msg:=sqlerrm; end;
  execute 'reset role';
  if msg is distinct from 'Only administrators and Real Agent read the administration scope; the real_agent template reads it, and no template changes it' then
   raise exception 'FAIL administration: real_agent may change the Administration scope: %',msg; end if;

  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT37',message='Rollback administration fixtures';
 exception when sqlstate 'PHT37' then null;
 end;
 if (select count(*) from okb.actor)<>original_actors then raise exception 'FAIL administration fixture rollback'; end if;
end $administration$;

create function okb_tests.suite_31_links_through_state() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $links$
declare h uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); r jsonb; j jsonb; msg text; item jsonb;
 task text; evidence text; task_b text;
begin
 begin
  insert into auth.users(id,email) values(h,'links-test@example.com');
  perform okb_tests.approve_fixture(null);
  insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,enabled)
   values(h,h,'Links test administrator','human',h,'administrator',true);
  perform okb_tests.approve_fixture(h);
  perform set_config('okb.provisioning_actor','',true);
  insert into okb.scope(scope_id,code,display_name,description,created_by) values(s,'auth_test_links','Links test scope','Rolled-back fixture',h);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';

  -- Evidence linked to a task once still supports it after two changes of state, and the task
  -- completes with no new link.
  task:=pg_temp.raised(okb.okb_add_record('auth_test_links','activity','Links test task','Links test','{"activity_kind":"task","completion_requirements":"Evidence linked"}'))->>'record_id';
  evidence:=pg_temp.raised(okb.okb_add_record('auth_test_links','evidence','Links test evidence','Links test','{"summary":"Seen","standing":"observed"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_link(evidence,task,'supports','Links test'));
  perform pg_temp.raised(okb.okb_set_state(task,'in_progress','Links test'));
  perform pg_temp.raised(okb.okb_set_state(task,'paused','Links test'));
  perform pg_temp.raised(okb.okb_set_state(task,'in_progress','Links test'));
  j:=okb.okb_get_progress(null,null,null,100,s);
  select x into item from jsonb_array_elements(j->'items') x where x->>'title'='Links test task';
  if (item->>'version_number')::int<>4 or jsonb_array_length(item->'evidence')<>1 or item->'evidence'->0->>'title'<>'Links test evidence' then
   execute 'reset role'; raise exception 'FAIL links through state: the progress read after two changes of state %',item; end if;
  -- The owner's new name changes the owner_label OKB sets, and the evidence still counts.
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('okb.provisioning_actor',h::text,true);
  update okb.actor set display_name='Links test administrator renamed' where actor_id=h;
  perform set_config('okb.provisioning_actor','',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',h,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  r:=pg_temp.raised(okb.okb_set_state(task,'completed','Links test','Seen'));
  if r->'payload'->>'state'<>'completed' or r->'payload'->>'owner_label'<>'Links test administrator renamed' then execute 'reset role'; raise exception 'FAIL links through state: completion after the owner''s rename %',r; end if;
  if okb.okb_show_record(task)->'links'<>'[]'::jsonb or (okb.okb_show_record(evidence)->>'version_number')::int<>2 then
   execute 'reset role'; raise exception 'FAIL links through state: completing added a link'; end if;
  raise notice 'ok - evidence linked once supports a task through two changes of state and its owner''s rename, and the task completes with no new link';

  -- A change to anything but the state, assignee or completion note needs the evidence again.
  task_b:=pg_temp.raised(okb.okb_add_record('auth_test_links','activity','Links test task B','Links test','{"activity_kind":"task","completion_requirements":"Evidence linked"}'))->>'record_id';
  perform pg_temp.raised(okb.okb_link(evidence,task_b,'supports','Links test'));
  perform pg_temp.raised(okb.okb_set_state(task_b,'in_progress','Links test'));
  perform pg_temp.raised(okb.okb_change_record(task_b,'Links test','{"description":"Changed"}'));
  j:=okb.okb_get_progress(null,null,null,100,s);
  select x into item from jsonb_array_elements(j->'items') x where x->>'title'='Links test task B';
  if item->'evidence'<>'[]'::jsonb then execute 'reset role'; raise exception 'FAIL links through state: a changed task kept its evidence %',item; end if;
  msg:=null;
  begin perform pg_temp.raised(okb.okb_set_state(task_b,'completed','Links test','Seen')); exception when check_violation then msg:=sqlerrm; end;
  if msg is distinct from 'Completion requires requirements, note, no blockers and supporting evidence' then
   execute 'reset role'; raise exception 'FAIL links through state: a changed task completed: %',msg; end if;
  raise notice 'ok - a task changed in more than its state needs its evidence linked again';
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  raise exception using errcode='PHT31',message='Rollback links through state fixtures';
 exception when sqlstate 'PHT31' then null;
 end;
end $links$;

-- The parts the checks run in, in order. Each part's suites finish in under 45 seconds: inside the
-- business analyst agent's statement_timeout, and inside the Supabase SQL Editor's limit, which is
-- over 70 seconds. Suite 23 runs in a part with only suite 35: its saves take longer as OKB grows.
create function okb_tests.part_list() returns table(part int, suites text[]) language sql immutable set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $parts$
 values
  (1,array['suite_01_smoke','suite_02_saves_and_approvals','suite_03_completion','suite_05_date']),
  (2,array['suite_06_history','suite_07_plan_boundary','suite_08_scoped_grants','suite_09_grant_expiry','suite_10_actor_history',
   'suite_11_provisioning','suite_12_grants','suite_13_files','suite_14_search','suite_15_record_deletion','suite_16_applications',
   'suite_17_own_record_and_paging','suite_18_audit','suite_19_reference','suite_21_find_records','suite_22_sign_ins']),
  (3,array['suite_23_task_functions','suite_35_refusal_log']),
  (4,array['suite_24_record_move','suite_25_scope_rename','suite_26_own_records','suite_27_scope_delete',
   'suite_28_advisors','suite_29_owners','suite_31_links_through_state','suite_33_permission_checks','suite_34_private_scopes','suite_36_access_templates',
   'suite_37_administration_and_plugin_scopes'])
$parts$;

-- The number of parts, and each part's suites.
create function okb_tests.parts() returns jsonb language sql stable set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $parts$
 select jsonb_build_object('parts',count(*),'suites',jsonb_object_agg(part::text,to_jsonb(suites) order by part)) from okb_tests.part_list()
$parts$;

-- Runs one part's suites, in order, under the checks' lock. A failure names its suite.
create function okb_tests.run_suites(p_part int) returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $run$
declare suites text[]; suite text;
begin
 -- The checks' own lock: two runs never overlap, and a run never waits for another.
 if not pg_try_advisory_xact_lock(19483,31001) then
  raise exception 'Another run of the checks is in progress. Try again when it has finished.';
 end if;
 select l.suites into suites from okb_tests.part_list() l where l.part=p_part;
 if suites is null then
  raise exception 'There is no part %. The checks run in parts 1 to %',p_part,(select count(*) from okb_tests.part_list()) using errcode='22023';
 end if;
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
 -- A function that changes data answers a permission refusal as {"refused": true, "problem": ...}.
 -- The suites call it through pg_temp.raised, which raises that refusal as the error it was, with
 -- OKB's message, as the supabase plugin's rpc does. Suite 35 checks the answer itself. A function
 -- in the run's own temporary schema, it serves the authenticated role in this session alone.
 execute $make$create or replace function pg_temp.raised(p_answer jsonb) returns jsonb language plpgsql set search_path=pg_catalog as $raised$
begin
 if jsonb_typeof(p_answer)='object' and p_answer->'refused'='true'::jsonb then
  raise exception '%',p_answer->>'problem' using errcode='42501';
 end if;
 return p_answer;
end $raised$ $make$;
 foreach suite in array suites loop
  begin
   execute format('select okb_tests.%I()',suite);
  exception when others then
   raise exception using errcode=sqlstate, message=suite||': '||sqlerrm;
  end;
 end loop;
end $run$;

-- One part. It ends in an error, so nothing it created is kept: its PASS message, or the suite and
-- check that failed.
create function okb_tests.run(p_part int) returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $run$
declare total int:=(select count(*) from okb_tests.part_list());
begin
 perform okb_tests.run_suites(p_part);
 if exists(select 1 from okb_tests.part_list() where part=p_part and 'suite_10_actor_history'=any(suites))
  and current_setting('okb.test_first_administrator',true) is distinct from 'checked' then
  raise exception 'PASS: part % of % passed, except the first-administrator and lockout checks, which need a project with no actors',p_part,total using errcode='PHT98';
 end if;
 raise exception 'PASS: part % of % passed',p_part,total using errcode='PHT98';
end $run$;

-- Every part in turn, in one call, for psql and the stand-in run.
create function okb_tests.run() returns void language plpgsql set search_path = pg_catalog, public, extensions, okb, okb_private, okb_storage, storage, auth, file_search, okb_tests as $run$
declare p int;
begin
 for p in select part from okb_tests.part_list() order by part loop
  perform okb_tests.run_suites(p);
 end loop;
 -- Reached only if every suite above succeeded.
 if current_setting('okb.test_first_administrator',true)='checked' then
  raise exception 'PASS: every suite passed' using errcode='PHT99';
 end if;
 raise exception 'PASS: every suite passed, except the first-administrator and lockout checks, which need a project with no actors' using errcode='PHT99';
end $run$;

revoke execute on all functions in schema okb_tests from public, anon, authenticated, service_role;

comment on function okb_tests.run() is 'okb_tests 1.5.1';
