-- Kasbeman membership lifecycle and invitation hardening — REVIEW DRAFT
-- Applies only to disposable PostgreSQL CI. Production migrations remain untouched.
-- Requires identity/tenancy + RBAC foundation and role-assignment hardening.

begin;

-- A member-wide suspension/revocation immediately revokes all active role grants.
-- Owner memberships are immutable through this path; ownership transfer needs a
-- separate explicit workflow and must never be conflated with ordinary member management.
create or replace function private.guard_business_member_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'active' and new.status in ('suspended', 'revoked') then
    if exists (
      select 1
      from public.member_role_assignments mra
      join public.roles r
        on r.business_id = mra.business_id
       and r.id = mra.role_id
      where mra.business_id = old.business_id
        and mra.user_id = old.user_id
        and mra.status = 'active'
        and r.role_key = 'owner'
    ) then
      raise exception 'Owner membership must be transferred, not suspended or revoked'
        using errcode = '23514';
    end if;

    update public.member_role_assignments
    set status = 'revoked',
        revoked_at = coalesce(revoked_at, now())
    where business_id = old.business_id
      and user_id = old.user_id
      and status = 'active';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_business_member_lifecycle()
  from public, anon, authenticated;

drop trigger if exists business_member_lifecycle_guard on public.business_members;
create trigger business_member_lifecycle_guard
  before update of status on public.business_members
  for each row
  when (old.status is distinct from new.status)
  execute function private.guard_business_member_lifecycle();

-- A manager may not suspend a member whose active role grants permissions
-- beyond the manager's own business-wide authority.
create or replace function private.can_manage_business_member(
  p_business_id uuid,
  p_target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and (select auth.uid()) <> p_target_user_id
    and private.has_business_permission(p_business_id, 'team.members.manage', null)
    and exists (
      select 1 from public.business_members bm
      where bm.business_id = p_business_id
        and bm.user_id = p_target_user_id
        and bm.status = 'active'
    )
    and not exists (
      select 1
      from public.member_role_assignments mra
      join public.roles r
        on r.business_id = mra.business_id
       and r.id = mra.role_id
      where mra.business_id = p_business_id
        and mra.user_id = p_target_user_id
        and mra.status = 'active'
        and r.role_key = 'owner'
    )
    and not exists (
      select 1
      from public.member_role_assignments mra
      join public.role_permissions rp
        on rp.business_id = mra.business_id
       and rp.role_id = mra.role_id
      where mra.business_id = p_business_id
        and mra.user_id = p_target_user_id
        and mra.status = 'active'
        and not private.has_business_permission(
          p_business_id, rp.permission_key, null
        )
    );
$$;

revoke all on function private.can_manage_business_member(uuid, uuid)
  from public, anon;
grant execute on function private.can_manage_business_member(uuid, uuid)
  to authenticated;

-- Invitation token hashes are never readable through the Data API.
-- Invitation writes are only possible through the RPCs below.
drop policy if exists business_invitations_select_authorized on public.business_invitations;
create policy business_invitations_select_authorized
  on public.business_invitations for select to authenticated
  using (
    (select private.has_business_permission(business_id, 'team.members.read', null))
    or (select private.has_business_permission(business_id, 'team.members.invite', null))
  );

revoke all on table public.business_invitations from anon, authenticated;
grant select (
  id, business_id, email, role_key, status, invited_by,
  expires_at, accepted_at, created_at
) on public.business_invitations to authenticated;

create or replace function public.create_business_invitation(
  p_business_id uuid,
  p_email text,
  p_role_key text,
  p_expires_at timestamptz default (now() + interval '7 days')
)
returns table (
  invitation_id uuid,
  invitation_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_token text;
  v_role_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not private.has_business_permission(
    p_business_id, 'team.members.invite', null
  ) then
    raise exception 'Invitation permission required' using errcode = '42501';
  end if;

  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or char_length(v_email) > 254 then
    raise exception 'Invalid invitation email' using errcode = '22023';
  end if;

  if p_role_key not in ('admin', 'member') then
    raise exception 'Only admin or member roles can be invited'
      using errcode = '22023';
  end if;

  if p_expires_at <= now()
     or p_expires_at > now() + interval '30 days' then
    raise exception 'Invitation expiry must be within the next 30 days'
      using errcode = '22023';
  end if;

  select r.id into v_role_id
  from public.roles r
  where r.business_id = p_business_id
    and r.role_key = p_role_key
    and r.is_system
    and r.status = 'active';

  if v_role_id is null then
    raise exception 'Invited role is unavailable' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    where rp.business_id = p_business_id
      and rp.role_id = v_role_id
      and not private.has_business_permission(
        p_business_id, rp.permission_key, null
      )
  ) then
    raise exception 'You cannot invite a role with permissions beyond your own'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from auth.users u
    join public.business_members bm on bm.user_id = u.id
    where bm.business_id = p_business_id
      and bm.status = 'active'
      and lower(u.email) = v_email
  ) then
    raise exception 'This email already belongs to an active member'
      using errcode = '23505';
  end if;

  update public.business_invitations bi
  set status = 'expired'
  where bi.business_id = p_business_id
    and bi.email = v_email
    and bi.status = 'pending'
    and bi.expires_at <= now();

  v_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.business_invitations (
    business_id, email, role_key, status, invited_by, token_hash, expires_at
  ) values (
    p_business_id, v_email, p_role_key, 'pending', v_actor_id,
    pg_catalog.encode(extensions.digest(v_token, 'sha256'), 'hex'),
    p_expires_at
  )
  returning id, public.business_invitations.expires_at
  into invitation_id, expires_at;

  invitation_token := v_token;
  return next;
end;
$$;

create or replace function public.revoke_business_invitation(
  p_business_id uuid,
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not private.has_business_permission(
    p_business_id, 'team.members.invite', null
  ) then
    raise exception 'Invitation permission required' using errcode = '42501';
  end if;

  update public.business_invitations
  set status = 'revoked'
  where business_id = p_business_id
    and id = p_invitation_id
    and status = 'pending';

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

create or replace function public.accept_business_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_email text;
  v_email_confirmed_at timestamptz;
  v_invitation public.business_invitations%rowtype;
  v_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invitation is invalid or no longer available'
      using errcode = '42501';
  end if;

  select lower(u.email), u.email_confirmed_at
  into v_email, v_email_confirmed_at
  from auth.users u
  where u.id = v_user_id;

  if v_email is null or v_email_confirmed_at is null then
    raise exception 'A verified email address is required'
      using errcode = '42501';
  end if;

  select bi.* into v_invitation
  from public.business_invitations bi
  where bi.token_hash = pg_catalog.encode(
    extensions.digest(p_token, 'sha256'), 'hex'
  )
    and bi.status = 'pending'
    and bi.expires_at > now()
  for update;

  if not found or v_invitation.email <> v_email then
    raise exception 'Invitation is invalid or no longer available'
      using errcode = '42501';
  end if;

  select r.id into v_role_id
  from public.roles r
  where r.business_id = v_invitation.business_id
    and r.role_key = v_invitation.role_key
    and r.is_system
    and r.status = 'active';

  if v_role_id is null then
    raise exception 'Invited role is no longer available'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.business_members bm
    where bm.business_id = v_invitation.business_id
      and bm.user_id = v_user_id
      and bm.status = 'active'
  ) then
    raise exception 'You are already an active member of this business'
      using errcode = '23505';
  end if;

  insert into public.business_members (business_id, user_id, role_key, status)
  values (v_invitation.business_id, v_user_id, v_invitation.role_key, 'active')
  on conflict (business_id, user_id) do update
    set role_key = excluded.role_key,
        status = 'active';

  insert into public.member_role_assignments (
    business_id, user_id, role_id, status, assigned_by
  ) values (
    v_invitation.business_id, v_user_id, v_role_id, 'active',
    v_invitation.invited_by
  );

  update public.business_invitations
  set status = 'accepted',
      accepted_at = now()
  where id = v_invitation.id
    and status = 'pending';

  return v_invitation.business_id;
end;
$$;

revoke all on function public.create_business_invitation(uuid, text, text, timestamptz)
  from public, anon;
revoke all on function public.revoke_business_invitation(uuid, uuid)
  from public, anon;
revoke all on function public.accept_business_invitation(text)
  from public, anon;

grant execute on function public.create_business_invitation(uuid, text, text, timestamptz)
  to authenticated;
grant execute on function public.revoke_business_invitation(uuid, uuid)
  to authenticated;
grant execute on function public.accept_business_invitation(text)
  to authenticated;

commit;
