-- 0004-invitation-codes
-- base: 5c4f0a6
-- An administrator adds a person with a one-time invitation code instead of Supabase's invitation email, which needs
-- a page for choosing a password and, for anyone outside the Supabase organisation, the project's own email server.
-- The invitation table keeps each code as its SHA-256 alone, with its email, its actor, who invited them, its expiry,
-- its wrong tries and whether it is used or replaced. provision_invited_actor makes an invited person's actor with no
-- Auth user, and provision_actor_sign_in links the Auth user okb-join makes to it, once. Nothing else changes, and no
-- existing actor or grant is touched.
-- Safe to run twice. Run as the postgres login.

-- ===================================================================
-- 8v. Invitation codes.
-- ===================================================================
-- An administrator adds a person before they have a sign-in: the okb-invite hosted function makes their actor with
-- no Auth user, gives their grants, and keeps a one-time invitation code for their email, as its SHA-256 alone. The
-- okb-join hosted function takes the email, the code and the password the person chooses: it makes their Auth user
-- and links it to the actor, once. Both run as the postgres login, and no client role reads this table.
set role okb_owner;
create table if not exists okb_private.invitation (
 invitation_id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references okb.actor(actor_id),
 email text not null check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
 code_sha256 text not null check (code_sha256 ~ '^[0-9a-f]{64}$'),
 invited_by_actor_id uuid not null references okb.actor(actor_id),
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 wrong_tries integer not null default 0 check (wrong_tries between 0 and 5),
 used_at timestamptz,
 replaced_at timestamptz,
 check (expires_at > created_at),
 check (used_at is null or replaced_at is null)
);
-- One open code per email: a new invitation replaces the unused one.
create unique index if not exists invitation_open_email_idx on okb_private.invitation(email) where used_at is null and replaced_at is null;
create index if not exists invitation_actor_idx on okb_private.invitation(actor_id);
alter table okb_private.invitation enable row level security;
revoke all on okb_private.invitation from public, anon, authenticated;
comment on table okb_private.invitation is 'One-time invitation codes, kept as their SHA-256 alone: okb-invite writes them and okb-join spends them.';

-- An invited person's actor, before they have a sign-in: a human, accountable to themselves, with no Auth user.
create or replace function okb_private.provision_invited_actor(p_approver_actor_id uuid, p_display_name text, p_authority_class text)
returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare id uuid:=gen_random_uuid(); previous_actor text;
begin
 if okb_private.request_auth_uid() is not null or not pg_has_role(session_user,'okb_owner','MEMBER') then
  raise exception 'Provisioning requires the administrator login without an Auth identity' using errcode='42501';
 end if;
 if p_approver_actor_id is null then raise exception 'Administrator approver required' using errcode='22023'; end if;
 previous_actor:=current_setting('okb.provisioning_actor',true);
 perform set_config('okb.provisioning_actor',p_approver_actor_id::text,true);
 insert into okb.actor(actor_id,auth_user_id,display_name,actor_kind,accountable_human_id,authority_class,requires_human_approval,enabled)
 values(id,null,p_display_name,'human',id,p_authority_class,false,true);
 perform set_config('okb.provisioning_actor',coalesce(previous_actor,''),true);
 return id;
exception when others then
 perform set_config('okb.provisioning_actor',coalesce(previous_actor,''),true);
 raise;
end $$;

-- Links an invited person's actor to the Auth user okb-join made for them, once, approved by the inviting administrator.
create or replace function okb_private.provision_actor_sign_in(p_approver_actor_id uuid, p_actor_id uuid, p_auth_user_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog as $$
declare previous_actor text;
begin
 if okb_private.request_auth_uid() is not null or not pg_has_role(session_user,'okb_owner','MEMBER') then
  raise exception 'Provisioning requires the administrator login without an Auth identity' using errcode='42501';
 end if;
 if p_approver_actor_id is null then raise exception 'Administrator approver required' using errcode='22023'; end if;
 if p_auth_user_id is null then raise exception 'Auth user id required' using errcode='22023'; end if;
 previous_actor:=current_setting('okb.provisioning_actor',true);
 perform set_config('okb.provisioning_actor',p_approver_actor_id::text,true);
 update okb.actor set auth_user_id=p_auth_user_id where actor_id=p_actor_id and auth_user_id is null and enabled;
 if not found then raise exception 'The invited actor is unavailable or already has a sign-in' using errcode='22023'; end if;
 perform set_config('okb.provisioning_actor',coalesce(previous_actor,''),true);
exception when others then
 perform set_config('okb.provisioning_actor',coalesce(previous_actor,''),true);
 raise;
end $$;
revoke all on function okb_private.provision_invited_actor(uuid,text,text), okb_private.provision_actor_sign_in(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function okb_private.provision_invited_actor(uuid,text,text), okb_private.provision_actor_sign_in(uuid,uuid,uuid) to okb_owner;
reset role;

insert into okb_private.schema_upgrade(id) values ('0004-invitation-codes') on conflict (id) do nothing;
