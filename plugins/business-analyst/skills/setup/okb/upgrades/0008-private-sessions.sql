-- 0008-private-sessions
-- base: 4b2baf2
-- An administrator makes one person's sessions scope private, owned by that
-- person, with okb_make_sessions_private, and its owner makes it ordinary again with okb_make_sessions_ordinary.
-- okb_add_scope makes a private sessions scope for the person its code names. The audit log gives
-- sessions_made_private and sessions_made_ordinary. The same text is in setup.sql. Safe to run twice. Run as the
-- postgres login.

-- ===================================================================
-- 8z. Private sessions, for named people.
-- ===================================================================
-- Each person's agent uploads the text of every session to the person's sessions scope, and an administrator reads
-- every scope that is not private, so administrators read every person's sessions. An administrator makes one
-- person's sessions scope private, owned by that person, on the firm's instruction, with
-- okb_make_sessions_private: each grant there ends, and the person holds one grant on evidence, issued in their own
-- name. An administrator then sees the scope's name and owner, and nothing in it. Its owner alone makes it ordinary
-- again, with okb_make_sessions_ordinary. okb_add_scope makes a private sessions scope for the person its code names.
-- The audit log gives sessions_made_private and sessions_made_ordinary.
set role okb_owner;
alter table okb.scope_change drop constraint if exists scope_change_field_check;
alter table okb.scope_change add constraint scope_change_field_check check (field in ('display_name','description','owner_actor_id','is_private'));

-- The sessions scope a change of privacy in this transaction is changing; set only by
-- okb_private.set_sessions_privacy.
create or replace function okb_private.changing_privacy() returns uuid
language sql stable set search_path=pg_catalog as $$
 select nullif(current_setting('okb.changing_privacy',true),'')::uuid
$$;
reset role;
revoke all on function okb_private.changing_privacy() from public, anon, authenticated;
grant execute on function okb_private.changing_privacy() to okb_writer, okb_reader;

-- Who may read which scope changes: whoever reads the scope, and an administrator, of a change to a
-- sessions scope's privacy.
drop policy if exists scope_change_reader_read on okb.scope_change;
create policy scope_change_reader_read on okb.scope_change for select to okb_reader
 using (okb_private.scope_read_for((select (okb_private.current_actor()).actor_id),scope_id,null,null)
  or (field='is_private' and (select (okb_private.current_actor()).authority_class)='administrator'));

set role okb_owner;
create or replace function okb_private.guard_scope() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 perform okb_private.lock_writes();
 if tg_op='DELETE' then
  if current_user='okb_owner' and old.scope_id=okb_private.deleting_scope() then return old; end if;
  raise exception 'Disable scopes; delete only an empty one, with okb_delete_scope' using errcode='23514';
 end if;
 -- A sessions scope becomes private, or ordinary again, only from okb_private.set_sessions_privacy.
 if tg_op='UPDATE' and current_user='okb_owner' and new.scope_id=okb_private.changing_privacy() and starts_with(new.code,'sessions_')
  and row(new.scope_id,new.code,new.created_by,new.created_at,new.created_reason) is not distinct from row(old.scope_id,old.code,old.created_by,old.created_at,old.created_reason) then
  return new;
 end if;
 if tg_op='UPDATE' and row(new.scope_id,new.code,new.created_by,new.created_at,new.created_reason,new.is_private) is distinct from row(old.scope_id,old.code,old.created_by,old.created_at,old.created_reason,old.is_private) then
  raise exception 'Scope identity is fixed' using errcode='23514';
 end if;
 if tg_op='UPDATE' and new.owner_actor_id is distinct from old.owner_actor_id
  and not (current_user='okb_owner' and new.scope_id=okb_private.handing_on_scope()) then
  raise exception 'A private scope changes owner only when its owner hands it on, with okb_hand_on_scope' using errcode='23514';
 end if;
 return new;
end $$;

create or replace function okb_private.guard_authorisation() returns trigger
language plpgsql set search_path=pg_catalog as $$
declare a okb.actor; own uuid;
begin
 -- Deleting an empty scope deletes its grants and approvals, only from okb_private.delete_scope.
 if tg_op='DELETE' and current_user='okb_owner' and old.scope_id=okb_private.deleting_scope() then return old; end if;
 -- A deletion empties the approval requests that carried its record's content.
 if tg_op='UPDATE' and current_user='okb_owner' and okb_private.deleting_record() is not null then
  if old.mode='explicit_approval' and okb_private.carries_record(old.request_payload,okb_private.deleting_record())
   and (to_jsonb(new)-array['request_payload','reason'])=(to_jsonb(old)-array['request_payload','reason'])
   and new.request_payload=okb_private.erased_request(old.request_payload,okb_private.deleting_record())
   and new.reason=(case when old.request_payload->>'record_id'=okb_private.deleting_record()::text then 'Deleted' else old.reason end) then
   return new;
  end if;
  raise exception 'A deletion empties only the approvals that carry its record' using errcode='42501';
 end if;
 -- Handing a private scope on ends each grant and unused approval its old owner gave there, only
 -- from okb_private.hand_on_scope.
 if tg_op='UPDATE' and current_user='okb_owner' and old.scope_id=okb_private.handing_on_scope() then
  if old.revoked_at is null and new.revoked_at is not null and new.revoked_by_actor_id=old.issued_by_actor_id
   and (to_jsonb(new)-array['revoked_at','revoked_by_actor_id','revocation_reason'])=(to_jsonb(old)-array['revoked_at','revoked_by_actor_id','revocation_reason']) then
   return new;
  end if;
  raise exception 'Handing a scope on ends only the grants its old owner gave' using errcode='42501';
 end if;
 -- Making a sessions scope private, or ordinary again, ends each grant there, only from
 -- okb_private.set_sessions_privacy. A sessions scope opens to its person with one grant on
 -- evidence, from its owner where it is private and from an administrator where it is not, only from
 -- okb_private.open_sessions_for.
 if tg_op in ('INSERT','UPDATE') and current_user='okb_owner' and new.scope_id=okb_private.changing_privacy() then
  if tg_op='UPDATE' and old.revoked_at is null and new.revoked_at is not null
   and (to_jsonb(new)-array['revoked_at','revoked_by_actor_id','revocation_reason'])=(to_jsonb(old)-array['revoked_at','revoked_by_actor_id','revocation_reason']) then
   return new;
  end if;
  if tg_op='INSERT' and new.executor_actor_id=new.accountable_human_id and new.mode='standing_permission' and new.record_id is null
   and not new.own_records and new.expires_at is null and new.record_kinds=array['evidence']
   and (new.issued_by_actor_id=okb_private.scope_owner(new.scope_id)
    or (okb_private.scope_owner(new.scope_id) is null and exists(select 1 from okb.actor i where i.actor_id=new.issued_by_actor_id
     and i.enabled and i.actor_kind='human' and i.authority_class='administrator'))) then
   return new;
  end if;
  raise exception 'Changing a sessions scope''s privacy ends its grants and opens it to its person alone' using errcode='42501';
 end if;
 -- A private scope opens to its owner with one full grant, issued in their own name, only from
 -- okb_private.open_scope_for.
 if tg_op='INSERT' and current_user='okb_owner' and new.scope_id=okb_private.opening_scope() then
  if new.issued_by_actor_id=okb_private.scope_owner(new.scope_id) and new.executor_actor_id=new.issued_by_actor_id
   and new.accountable_human_id=new.issued_by_actor_id and new.mode='standing_permission' and new.record_id is null
   and not new.own_records and new.expires_at is null then
   return new;
  end if;
  raise exception 'A private scope opens with one full grant to its owner' using errcode='42501';
 end if;
 if current_user<>'okb_writer' then raise exception 'Use authority functions' using errcode='42501'; end if;
 a:=okb_private.acting_actor();
 if tg_op='DELETE' then raise exception 'Authorisations are retained' using errcode='23514'; end if;
 -- In a private scope, its owner gives and ends every grant and approval; elsewhere, an administrator.
 own:=okb_private.scope_owner(new.scope_id);
 if tg_op='INSERT' then
  -- A private sessions scope holds its person's own grant alone, so the upload hook finds one
  -- sessions scope for each person.
  if own is not null and exists(select 1 from okb.scope s where s.scope_id=new.scope_id and starts_with(s.code,'sessions_')) then
   raise exception 'A private sessions scope holds its person''s own grant alone' using errcode='42501';
  end if;
  if new.issued_by_actor_id<>a.actor_id or (own is null and a.authority_class<>'administrator') or (own is not null and a.actor_id<>own) then
   raise exception '%',case when own is null then 'Administrator issuer required' else 'Only the scope''s owner gives grants and approvals in a private scope' end using errcode='42501';
  end if;
  if not exists(select 1 from okb.actor e join okb.actor h on h.actor_id=e.accountable_human_id
   where e.actor_id=new.executor_actor_id and h.actor_id=new.accountable_human_id and h.actor_kind='human' and e.enabled and h.enabled) then
   raise exception 'Invalid executor or accountable human' using errcode='23514';
  end if;
  if new.expires_at is null and new.mode='explicit_approval' then
   raise exception 'Exact approval requires expiry' using errcode='23514';
  end if;
  return new;
 end if;
 if (to_jsonb(new)-array['revoked_at','revoked_by_actor_id','revocation_reason','consumed_version_id','consumed_deletion_id'])
   is distinct from (to_jsonb(old)-array['revoked_at','revoked_by_actor_id','revocation_reason','consumed_version_id','consumed_deletion_id']) then
  raise exception 'Authority scope is immutable; revoke and issue another grant' using errcode='23514';
 end if;
 if row(new.revoked_at,new.revoked_by_actor_id,new.revocation_reason) is distinct from row(old.revoked_at,old.revoked_by_actor_id,old.revocation_reason) then
  if (own is null and a.authority_class<>'administrator') or (own is not null and a.actor_id<>own)
   or old.revoked_at is not null or new.revoked_at is null or new.revoked_by_actor_id<>a.actor_id then
   raise exception 'Invalid revocation' using errcode='42501';
  end if;
 end if;
 if new.consumed_version_id is distinct from old.consumed_version_id then
  if old.consumed_version_id is not null or new.consumed_version_id is null or old.mode<>'explicit_approval'
    or new.executor_actor_id<>a.actor_id or not okb_private.authority_live(new.authorisation_id)
    or not exists(select 1 from okb.record_version where version_id=new.consumed_version_id and authorisation_id=new.authorisation_id and executor_actor_id=a.actor_id) then
   raise exception 'Invalid approval consumption' using errcode='42501';
  end if;
 end if;
 if new.consumed_deletion_id is distinct from old.consumed_deletion_id then
  if old.consumed_deletion_id is not null or old.consumed_version_id is not null or new.consumed_deletion_id is null or old.mode<>'explicit_approval'
    or new.executor_actor_id<>a.actor_id or not okb_private.authority_live(new.authorisation_id)
    or not exists(select 1 from okb.record_deletion where deletion_id=new.consumed_deletion_id and authorisation_id=new.authorisation_id and executor_actor_id=a.actor_id) then
   raise exception 'Invalid approval consumption' using errcode='42501';
  end if;
 end if;
 return new;
end $$;

-- Opens a sessions scope to its person: one grant on evidence, with read, create, edit and delete,
-- issued by p_issuer, as okb-invite's and bootstrap.sql's is. Called only by add_scope and set_sessions_privacy.
create or replace function okb_private.open_sessions_for(p_scope uuid, p_person uuid, p_issuer uuid) returns uuid
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare kinds text[]:=array['evidence']; actions text[]:=array['read','create','edit','delete']; req jsonb; g uuid;
begin
 req:=jsonb_build_object('scope_id',p_scope,'operation','grant','executor',p_person,'kinds',kinds,'record',null,'actions',actions,'expiry',null,
  'reason','Their agent keeps the text of each session with them here.');
 perform set_config('okb.changing_privacy',p_scope::text,true);
 insert into okb.authorisation(scope_id,executor_actor_id,accountable_human_id,issued_by_actor_id,mode,issuance_request_id,issuance_hash,record_kinds,record_id,allowed_actions,own_records,expires_at,reason)
 values(p_scope,p_person,p_person,p_issuer,'standing_permission',gen_random_uuid(),
  encode(sha256(convert_to(jsonb_build_object('format',1,'request',req,'executor',p_person,'human',p_person)::text,'UTF8')),'hex'),
  kinds,null,actions,false,null,'Their agent keeps the text of each session with them here.') returning authorisation_id into g;
 perform set_config('okb.changing_privacy','',true);
 return g;
end $$;

-- Adds a scope, with its bucket, and opens a private one to its owner: a private sessions scope
-- with one grant on evidence, and any other with a full grant. okb_add_scope calls it after every check.
create or replace function okb_private.add_scope(p_code text, p_display_name text, p_description text, p_private boolean, p_owner uuid, p_creator uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare s okb.scope; g uuid;
begin
 insert into okb.scope(code,display_name,description,created_by,created_reason,is_private,owner_actor_id)
 values(p_code,p_display_name,p_description,p_creator,p_reason,p_private,case when p_private then p_owner end) returning * into s;
 if p_private and starts_with(p_code,'sessions_') then
  g:=okb_private.open_sessions_for(s.scope_id,p_owner,p_owner);
 elsif p_private then
  g:=okb_private.open_scope_for(s.scope_id,p_owner);
 end if;
 return jsonb_build_object('scope_id',s.scope_id,'code',s.code,'name',s.display_name,'description',s.description,
  'created_at',s.created_at,'created_by',okb_private.actor_name(p_creator),'reason',p_reason,
  'is_private',s.is_private,'owner_actor_id',s.owner_actor_id,'owner_name',okb_private.actor_name(s.owner_actor_id),'owner_grant_id',g);
end $$;

-- The sessions scopes of a person: the scope whose code names their Auth user id, and each scope
-- whose code starts sessions_ where they hold a live grant with create on the whole scope.
create or replace function okb_private.sessions_scopes(p_person uuid) returns setof uuid
language sql stable security definer set search_path=pg_catalog as $$
 select s.scope_id from okb.scope s join okb.actor p on p.actor_id=p_person
 where s.code='sessions_'||replace(p.auth_user_id::text,'-','')
  or (starts_with(s.code,'sessions_') and exists(select 1 from okb.authorisation z where z.scope_id=s.scope_id and z.executor_actor_id=p_person
   and z.mode='standing_permission' and z.record_id is null and not z.own_records and 'create'=any(z.allowed_actions)
   and okb_private.authority_live(z.authorisation_id)))
$$;

-- Makes a sessions scope private, owned by p_person, or ordinary again. Ends each grant and unused
-- approval there, opens the scope to p_person with a grant p_issuer gives, and logs the change.
-- make_sessions_private and make_sessions_ordinary call it after every check.
create or replace function okb_private.set_sessions_privacy(p_scope uuid, p_private boolean, p_person uuid, p_executor uuid, p_issuer uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path=pg_catalog as $$
declare o okb.scope; n okb.scope; g uuid; ended integer;
begin
 select * into o from okb.scope where scope_id=p_scope for update;
 if o.is_private=p_private then
  raise exception 'The scope % is already %',o.display_name,case when p_private then 'private' else 'ordinary' end using errcode='22023';
 end if;
 perform set_config('okb.changing_privacy',p_scope::text,true);
 update okb.authorisation set revoked_at=clock_timestamp(),revoked_by_actor_id=p_executor,
  revocation_reason=case when p_private then 'The sessions were made private: ' else 'The sessions were made ordinary: ' end||p_reason
 where scope_id=p_scope and revoked_at is null and consumed_version_id is null and consumed_deletion_id is null;
 get diagnostics ended=row_count;
 update okb.scope set is_private=p_private,owner_actor_id=case when p_private then p_person end where scope_id=p_scope returning * into n;
 g:=okb_private.open_sessions_for(p_scope,p_person,p_issuer);
 perform set_config('okb.changing_privacy','',true);
 perform set_config('okb.renaming_scope',p_scope::text,true);
 insert into okb.scope_change(scope_id,field,old_value,new_value,changed_by_actor_id,reason)
 values(p_scope,'is_private',o.is_private::text,p_private::text,p_executor,p_reason);
 perform set_config('okb.renaming_scope','',true);
 return jsonb_build_object('scope_id',n.scope_id,'code',n.code,'name',n.display_name,'is_private',n.is_private,
  'owner_actor_id',n.owner_actor_id,'owner_name',okb_private.actor_name(n.owner_actor_id),
  'person_actor_id',p_person,'person_name',okb_private.actor_name(p_person),'grants_ended',ended,
  'grant_id',g,'issued_by',okb_private.actor_name(p_issuer),
  'changed_at',clock_timestamp(),'changed_by',okb_private.actor_name(p_executor),'reason',p_reason);
end $$;
reset role;
revoke all on function okb_private.open_sessions_for(uuid,uuid,uuid), okb_private.sessions_scopes(uuid),
 okb_private.set_sessions_privacy(uuid,boolean,uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function okb_private.sessions_scopes(uuid), okb_private.set_sessions_privacy(uuid,boolean,uuid,uuid,uuid,text) to okb_writer;

grant create on schema okb_private to okb_writer;
set role okb_writer;
-- Checks a new scope and adds it. A private scope's code starts sessions_ only when it names its owner's Auth user id.
create or replace function okb_private.add_scope(p_code text, p_display_name text, p_description text, p_reason text default null,
 p_private boolean default false, p_owner text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; c text:=btrim(coalesce(p_code,'')); n text:=btrim(coalesce(p_display_name,'')); d text:=btrim(coalesce(p_description,''));
 private boolean:=coalesce(p_private,false); o uuid; people jsonb; clash okb.scope;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator adds a scope' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for the change, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 if not private and p_owner is not null then raise exception 'Only a private scope has an owner' using errcode='22023'; end if;
 if c !~ '^[a-z][a-z0-9_]{0,62}$' then
  raise exception 'A scope''s code is lower case letters, digits and underscores, starting with a letter, at most 63 characters' using errcode='22023';
 end if;
 if private and (c in ('general','routines','reference','plugins') or starts_with(c,'plugins_')) then
  raise exception 'The code % is kept for OKB''s own scopes',c using errcode='22023';
 end if;
 if c in ('plugins_real_agent','plugins_okb','plugins_business_analyst','plugins_project') then
  raise exception 'The code % names one of Real Agent''s own plugins, which only the plugins scope keeps',c using errcode='22023';
 end if;
 if n='' or length(n)>200 then raise exception 'Give the scope''s name, at most 200 characters, as p_display_name' using errcode='22023'; end if;
 if d='' or length(d)>4000 then raise exception 'Give what the scope covers, at most 4000 characters, as p_description' using errcode='22023'; end if;
 select * into clash from okb.scope x where c=x.code or lower(n) in (lower(btrim(x.display_name)),lower(x.code)) limit 1;
 if found then
  raise exception 'Another scope has the name or code "%": % (code %)',case when c=clash.code then c else n end,clash.display_name,clash.code using errcode='23505';
 end if;
 if private then
  if p_owner is null then
   o:=a.actor_id;
  else
   people:=okb_private.named_people((select coalesce(jsonb_agg(jsonb_build_object('actor_id',x.actor_id,'display_name',x.display_name)),'[]'::jsonb)
    from okb.actor x where x.actor_kind='human' and x.enabled),p_owner);
   if jsonb_array_length(people)=0 then raise exception 'No enabled person has a name with "%"',p_owner using errcode='22023'; end if;
   if jsonb_array_length(people)>1 then
    raise exception 'More than one person fits "%": %',p_owner,(select string_agg(x->>'display_name',', ') from jsonb_array_elements(people) x) using errcode='22023';
   end if;
   o:=(people->0->>'actor_id')::uuid;
  end if;
 end if;
 if private and starts_with(c,'sessions_') and c is distinct from (select 'sessions_'||replace(x.auth_user_id::text,'-','') from okb.actor x where x.actor_id=o) then
  raise exception 'The code % is kept for OKB''s own scopes. A private sessions scope''s code is sessions_ and its owner''s Auth user id with its hyphens removed',c using errcode='22023';
 end if;
 return okb_private.add_scope(c,n,d,private,o,a.actor_id,btrim(p_reason));
end $$;

create or replace function okb_private.make_sessions_private(p_person text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; people jsonb; p uuid; hits uuid[]; sc okb.scope;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 if a.actor_kind<>'human' or a.authority_class<>'administrator' then
  raise exception 'Only a person who is an administrator makes a person''s sessions private' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for making the sessions private, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 if btrim(coalesce(p_person,''))='' then raise exception 'Name the person whose sessions are made private, as p_person' using errcode='22023'; end if;
 people:=okb_private.named_people((select coalesce(jsonb_agg(jsonb_build_object('actor_id',x.actor_id,'display_name',x.display_name)),'[]'::jsonb)
  from okb.actor x where x.actor_kind='human' and x.enabled),p_person);
 if jsonb_array_length(people)=0 then raise exception 'No enabled person has a name with "%"',p_person using errcode='22023'; end if;
 if jsonb_array_length(people)>1 then
  raise exception 'More than one person fits "%": %',p_person,(select string_agg(x->>'display_name',', ') from jsonb_array_elements(people) x) using errcode='22023';
 end if;
 p:=(people->0->>'actor_id')::uuid;
 select array_agg(distinct x) into hits from okb_private.sessions_scopes(p) x;
 if hits is null then
  raise exception '% has no sessions scope. Make it as adding the person does',people->0->>'display_name' using errcode='22023';
 end if;
 if cardinality(hits)>1 then
  raise exception '% has more than one sessions scope: %',people->0->>'display_name',
   (select string_agg(format('%s (code %s)',x.display_name,x.code),'; ' order by x.code) from okb.scope x where x.scope_id=any(hits)) using errcode='22023';
 end if;
 select * into sc from okb.scope where scope_id=hits[1];
 if sc.is_private then raise exception 'The scope % is already private',sc.display_name using errcode='22023'; end if;
 return okb_private.set_sessions_privacy(sc.scope_id,true,p,a.actor_id,p,btrim(p_reason));
end $$;

create or replace function okb_private.make_sessions_ordinary(p_reason text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare a okb.actor; sc okb.scope; issuer uuid;
begin
 perform okb_private.lock_writes(); a:=okb_private.current_actor();
 select s.* into sc from okb.scope s where s.is_private and s.owner_actor_id=a.actor_id and starts_with(s.code,'sessions_')
  order by s.code='sessions_'||replace(a.auth_user_id::text,'-','') desc, s.code limit 1;
 if not found or a.actor_kind<>'human' then
  raise exception 'Only the owner of a private sessions scope makes it ordinary' using errcode='42501';
 end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'Give the reason for making the sessions ordinary, as p_reason' using errcode='22023'; end if;
 if length(btrim(p_reason))>4000 then raise exception 'A reason is at most 4000 characters' using errcode='22023'; end if;
 select x.actor_id into issuer from okb.actor x
  where x.enabled and x.actor_kind='human' and x.authority_class='administrator'
  order by x.actor_id=sc.created_by desc,
   x.actor_id is not distinct from (select c.changed_by_actor_id from okb.scope_change c where c.scope_id=sc.scope_id and c.field='is_private' and c.new_value='true'
    order by c.event_id desc limit 1) desc,
   x.actor_id limit 1;
 if issuer is null then
  raise exception 'OKB has no enabled administrator to give the grant in %',sc.display_name using errcode='22023';
 end if;
 return okb_private.set_sessions_privacy(sc.scope_id,false,a.actor_id,a.actor_id,issuer,btrim(p_reason));
end $$;
reset role;
revoke create on schema okb_private from okb_writer;
revoke all on function okb_private.make_sessions_private(text,text), okb_private.make_sessions_ordinary(text) from public, anon, authenticated;

grant create on schema okb to okb_writer;
set role okb_writer;
-- Makes a person's sessions scope private, owned by them, and ends each grant there. Only a person who is an
-- administrator makes it, on the firm's instruction.
create or replace function okb.okb_make_sessions_private(p_person text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare m text; c text;
begin
 return okb_private.make_sessions_private(p_person,p_reason);
exception when insufficient_privilege then
 get stacked diagnostics m=message_text, c=pg_exception_context;
 if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
 return okb_private.log_refusal('okb_make_sessions_private',m,null,null,null);
end $$;

-- Makes the caller's private sessions scope ordinary again, so administrators read it.
create or replace function okb.okb_make_sessions_ordinary(p_reason text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog set "TimeZone" to 'UTC' as $$
declare m text; c text;
begin
 return okb_private.make_sessions_ordinary(p_reason);
exception when insufficient_privilege then
 get stacked diagnostics m=message_text, c=pg_exception_context;
 if split_part(c,E'\n',1) not like '%at RAISE' then raise; end if;
 return okb_private.log_refusal('okb_make_sessions_ordinary',m,null,null,null);
end $$;
reset role;
revoke create on schema okb from okb_writer;
revoke all on function okb.okb_make_sessions_private(text,text), okb.okb_make_sessions_ordinary(text) from public, anon;
grant execute on function okb.okb_make_sessions_private(text,text), okb.okb_make_sessions_ordinary(text) to authenticated;

-- The audit log, with each change of a sessions scope's privacy, as sessions_made_private and sessions_made_ordinary.
grant create on schema okb to okb_reader;
set role okb_reader;
-- What happened from p_from until p_to, newest first, as far as the caller may read. Each item
-- names its time, event, scope, actor and subject, with the ids that lead to the full entry. A
-- private scope's handing on is scope_handed_on, and an administrator sees no description of a
-- deleted private scope, nor its grants, unless they deleted it. A refused change is change_refused,
-- for the refused actor, an administrator, and a private scope's owner, with the scope only for a
-- reader who can see it. A change to an access template is access_template_changed. A scope's making
-- is scope_created, with the reason it was added. A change of the second factor is second_factor_set,
-- for administrators. Each batch graph-reader sent and closed is graph_batch_sent and graph_batch_saved, for
-- administrators.
create or replace function okb.okb_get_audit(p_from timestamptz, p_to timestamptz, p_cursor text default null, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare a okb.actor; c_at bigint; c_key text; result jsonb;
begin
 a:=okb_private.read_actor();
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Limit must be 1 through 100' using errcode='22023'; end if;
 if p_from is null or p_to is null or p_from>=p_to then raise exception 'A period needs a start before its end' using errcode='22023'; end if;
 if p_cursor is not null then
  if p_cursor !~ '^[0-9]+/[a-z]:[0-9a-f-]+$' then raise exception 'Invalid audit cursor' using errcode='22023'; end if;
  c_at:=split_part(p_cursor,'/',1)::bigint; c_key:=split_part(p_cursor,'/',2);
 end if;
 with events as (
  select v.recorded_at at,'v:'||v.version_id::text k,'record_saved' event,r.scope_id,v.executor_actor_id actor_id,v.title subject,v.change_reason reason,
   jsonb_build_object('record_id',v.record_id,'kind',r.kind,'version_id',v.version_id,'version_number',v.version_number,
    'authorisation_id',v.authorisation_id,'accountable_human_id',v.accountable_human_id,'accountable_human_name',okb_private.actor_name(v.accountable_human_id)) details
  from okb_private.audit_versions(p_from,p_to) v cross join lateral (select v.kind,v.scope_id) r
  union all
  select d.deleted_at,'d:'||d.deletion_id::text,'record_deleted',d.scope_id,d.executor_actor_id,d.kind,d.reason,
   jsonb_build_object('record_id',d.record_id,'kind',d.kind,'deletion_id',d.deletion_id,'authorisation_id',d.authorisation_id,
    'accountable_human_id',d.accountable_human_id,'accountable_human_name',okb_private.actor_name(d.accountable_human_id),
    'approved_by_actor_id',z.issued_by_actor_id,'approved_by_name',okb_private.actor_name(z.issued_by_actor_id),'content_sha256',d.content_sha256)
  from okb.record_deletion d left join okb.authorisation z on z.authorisation_id=d.authorisation_id
  where d.deleted_at>=p_from and d.deleted_at<p_to
  union all
  select m.moved_at,'m:'||m.move_id::text,'record_moved',m.to_scope_id,m.executor_actor_id,
   coalesce(case when okb_private.can_read_record(m.record_id) then
    (select v.title from okb.record_version v where v.record_id=m.record_id order by v.change_no desc limit 1) end,m.kind),m.reason,
   jsonb_build_object('record_id',m.record_id,'kind',m.kind,'move_id',m.move_id,'request_id',m.request_id,
    'from_scope_id',m.from_scope_id,'from_scope_name',okb_private.scope_name(m.from_scope_id),
    'to_scope_id',m.to_scope_id,'to_scope_name',okb_private.scope_name(m.to_scope_id))
   ||case when a.authority_class='administrator' then jsonb_build_object('losing_access',m.losing_access,'gaining_access',m.gaining_access) else '{}'::jsonb end
  from okb.record_move m where m.moved_at>=p_from and m.moved_at<p_to
  union all
  select c.at,'c:'||lpad(c.event_id::text,19,'0'),case c.field when 'owner_actor_id' then 'scope_handed_on'
    when 'is_private' then case when c.new_value='true' then 'sessions_made_private' else 'sessions_made_ordinary' end else 'scope_renamed' end,c.scope_id,c.changed_by_actor_id,
   case c.field when 'owner_actor_id' then okb_private.actor_name(c.new_value::uuid) when 'is_private' then okb_private.scope_name(c.scope_id) else c.new_value end,c.reason,
   jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value)
   ||case when c.field='owner_actor_id' then jsonb_build_object('old_owner_name',okb_private.actor_name(c.old_value::uuid),
    'new_owner_name',okb_private.actor_name(c.new_value::uuid)) else '{}'::jsonb end
  from okb.scope_change c where c.at>=p_from and c.at<p_to
  union all
  select s.created_at,'o:'||s.scope_id::text,'scope_created',s.scope_id,s.created_by,s.display_name,coalesce(s.created_reason,'Made at setup'),
   jsonb_build_object('code',s.code,'description',s.description,'is_private',s.is_private,'owner_name',okb_private.actor_name(s.owner_actor_id))
  from okb.scope s where s.created_at>=p_from and s.created_at<p_to
  union all
  select x.at,'x:'||lpad(x.event_id::text,19,'0'),'scope_deleted',null::uuid,x.deleted_by_actor_id,x.display_name,x.reason,
   jsonb_build_object('deleted_scope_id',x.scope_id,'code',x.code,'is_private',x.is_private,
    'description',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.description end,
    'grants_removed',case when x.is_private and x.deleted_by_actor_id<>a.actor_id then null else x.grants_removed end)
  from okb.scope_deletion x where x.at>=p_from and x.at<p_to
  union all
  select z.issued_at,'g:'||z.authorisation_id::text,case when z.mode='explicit_approval' then 'approval_given' else 'grant_issued' end,z.scope_id,z.issued_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,
    'record_kinds',z.record_kinds,'record_id',z.record_id,'own_records',z.own_records,'expires_at',z.expires_at)
  from okb.authorisation z where z.issued_at>=p_from and z.issued_at<p_to
  union all
  select z.revoked_at,'r:'||z.authorisation_id::text,'grant_revoked',z.scope_id,z.revoked_by_actor_id,
   okb_private.actor_name(z.executor_actor_id),z.revocation_reason,
   jsonb_build_object('authorisation_id',z.authorisation_id,'executor_actor_id',z.executor_actor_id,'allowed_actions',z.allowed_actions,'record_kinds',z.record_kinds)
  from okb.authorisation z where z.revoked_at>=p_from and z.revoked_at<p_to
  union all
  select c.changed_at,'a:'||c.change_id::text,case when c.old_value is null then 'actor_created' else 'actor_changed' end,null::uuid,c.changed_by_actor_id,
   okb_private.actor_name(c.actor_id),null::text,
   jsonb_build_object('changed_actor_id',c.actor_id)||case when c.old_value is null then '{}'::jsonb
    else jsonb_build_object('field',c.field,'old_value',c.old_value,'new_value',c.new_value) end
  from okb.actor_change c where c.changed_at>=p_from and c.changed_at<p_to and (c.old_value is not null or c.field='actor_id')
  union all
  select f.at,'f:'||lpad(f.event_id::text,19,'0'),'file_'||f.event,f.scope_id,f.actor_id,f.name,null::text,
   jsonb_build_object('object_id',f.object_id,'previous_name',f.previous_name,'attributed_by',f.attributed_by,'login',f.login)
  from okb.file_event f where f.at>=p_from and f.at<p_to
  union all
  select s.at,'s:'||lpad(s.event_id::text,19,'0'),s.event,null::uuid,s.actor_id,okb_private.actor_name(s.actor_id),null::text,
   jsonb_build_object('session_id',s.session_id,'auth_user_id',s.auth_user_id,'user_agent',s.user_agent,'ip',s.ip)
  from okb.sign_in_event s where s.at>=p_from and s.at<p_to
  union all
  select n.at,'n:'||lpad(n.event_id::text,19,'0'),'change_refused',
   case when a.authority_class='administrator' or okb_private.can_see_scope(n.scope_id) or okb_private.scope_owner(n.scope_id)=a.actor_id then n.scope_id end,
   n.actor_id,n.problem,null::text,
   jsonb_build_object('function',n.function_name,'kind',n.kind,'record_id',n.record_id,'problem',n.problem,'auth_user_id',n.auth_user_id)
  from okb.refusal_event n where n.at>=p_from and n.at<p_to
  union all
  select t.at,'t:'||lpad(t.event_id::text,19,'0'),'access_template_changed',null::uuid,t.changed_by_actor_id,t.code,t.reason,
   jsonb_build_object('code',t.code,'old_grants',t.old_value->'grants','new_grants',t.new_value->'grants',
    'old_description',t.old_value->>'description','new_description',t.new_value->>'description',
    'old_authority_class',t.old_value->>'authority_class','new_authority_class',t.new_value->>'authority_class')
  from okb.access_template_change t where t.at>=p_from and t.at<p_to
  union all
  select q2.at,'h:'||lpad(q2.event_id::text,19,'0'),'second_factor_set',null::uuid,q2.changed_by_actor_id,q2.new_value,q2.reason,
   jsonb_build_object('old_value',q2.old_value,'new_value',q2.new_value)
  from okb.sign_in_setting_change q2 where q2.at>=p_from and q2.at<p_to and a.authority_class='administrator'
  union all
  select g.at,g.k,g.event,null::uuid,g.actor_id,g.subject,null::text,g.details
  from okb_private.graph_batch_events(p_from,p_to) g where a.authority_class='administrator'),
 keyed as (select e.*,(extract(epoch from e.at)*1000000)::bigint micros from events e),
 page as (select * from keyed where p_cursor is null or (micros,k)<(c_at,c_key) order by micros desc,k desc limit p_limit)
 select jsonb_build_object(
  'items',coalesce(jsonb_agg(jsonb_build_object('at',p.at,'event',p.event,'scope_id',p.scope_id,'scope_name',okb_private.scope_name(p.scope_id),
    'actor_id',p.actor_id,'actor_name',okb_private.actor_name(p.actor_id),'subject',p.subject,'reason',p.reason)||p.details order by p.micros desc,p.k desc),'[]'::jsonb),
  'next_cursor',case when count(*)=p_limit then (array_agg(p.micros::text||'/'||p.k order by p.micros,p.k))[1] end) into result
 from page p;
 return result;
end $$;
reset role;
revoke create on schema okb from okb_reader;
notify pgrst, 'reload schema';

insert into okb_private.schema_upgrade(id) values ('0008-private-sessions') on conflict (id) do nothing;
