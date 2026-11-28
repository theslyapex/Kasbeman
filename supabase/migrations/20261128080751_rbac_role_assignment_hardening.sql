-- Kasbeman RBAC role-assignment privilege hardening.
-- Generated migration scaffold with Supabase CLI v3.4.0.
-- Depends on 20261127085000_rbac_authorization_foundation.sql.
-- Review candidate only: do not apply to hosted Supabase without separate approval.

begin;

create or replace function private.can_assign_business_role(
  p_business_id uuid,
  p_user_id uuid,
  p_role_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and private.has_business_permission(p_business_id, 'team.roles.assign', null)
    and exists (
      select 1
      from public.business_members bm
      join public.roles r
        on r.business_id = bm.business_id
       and r.id = p_role_id
       and r.status = 'active'
      where bm.business_id = p_business_id
        and bm.user_id = p_user_id
        and bm.status = 'active'
        and (
          p_branch_id is null
          or exists (
            select 1
            from public.branches b
            where b.business_id = p_business_id
              and b.id = p_branch_id
              and b.status = 'active'
          )
        )
        and (
          r.role_key <> 'owner'
          or (
            p_branch_id is null
            and private.has_business_permission(p_business_id, 'team.owners.manage', null)
          )
        )
        -- Prevent privilege escalation: an actor may only assign a role whose
        -- permissions they themselves hold at the requested scope.
        and not exists (
          select 1
          from public.role_permissions rp
          where rp.business_id = p_business_id
            and rp.role_id = p_role_id
            and not private.has_business_permission(
              p_business_id,
              rp.permission_key,
              p_branch_id
            )
        )
    );
$$;

revoke all on function private.can_assign_business_role(uuid, uuid, uuid, uuid)
  from public, anon;
grant execute on function private.can_assign_business_role(uuid, uuid, uuid, uuid)
  to authenticated;

commit;
