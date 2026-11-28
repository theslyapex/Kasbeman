-- Applied to Supabase project xitrazjbemmkarawejfe on 2026-11-28.
-- Hosted migration history version: 20261128093512.
-- Configurable per-account anti-abuse throttle for business creation.
-- This is NOT a subscription-plan quota. It limits rapid repeated creation attempts per account.

begin;

create table private.operation_rate_limit_policies (
  operation_key text primary key,
  max_attempts integer not null check (max_attempts > 0),
  window_seconds integer not null check (window_seconds > 0),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint operation_rate_limit_policies_key_format
    check (operation_key ~ '^[a-z][a-z0-9_.-]{1,79}$')
);

insert into private.operation_rate_limit_policies
  (operation_key, max_attempts, window_seconds, enabled)
values
  ('business.create', 5, 600, true)
on conflict (operation_key) do nothing;

create table private.operation_rate_limit_counters (
  user_id uuid not null references auth.users (id) on delete cascade,
  operation_key text not null
    references private.operation_rate_limit_policies (operation_key) on delete cascade,
  window_started_at timestamptz not null,
  attempt_count integer not null check (attempt_count > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, operation_key)
);

alter table private.operation_rate_limit_policies enable row level security;
alter table private.operation_rate_limit_counters enable row level security;

revoke all on table private.operation_rate_limit_policies,
  private.operation_rate_limit_counters from public, anon, authenticated, service_role;

create or replace function private.consume_operation_rate_limit(
  p_operation_key text,
  p_user_id uuid
)
returns table (is_allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_attempts integer;
  v_window_seconds integer;
  v_enabled boolean;
  v_now timestamptz := clock_timestamp();
  v_window_started_at timestamptz;
  v_attempt_count integer;
  v_retry_after_seconds integer;
begin
  if p_user_id is null or p_user_id is distinct from (select auth.uid()) then
    raise exception 'Authenticated user context mismatch' using errcode = '28000';
  end if;

  select policy.max_attempts, policy.window_seconds, policy.enabled
    into v_max_attempts, v_window_seconds, v_enabled
  from private.operation_rate_limit_policies as policy
  where policy.operation_key = p_operation_key;

  if not found then
    raise exception 'Rate limit policy is not configured'
      using errcode = '55000';
  end if;

  if not v_enabled then
    return query select true, 0;
    return;
  end if;

  insert into private.operation_rate_limit_counters as counters
    (user_id, operation_key, window_started_at, attempt_count, updated_at)
  values
    (p_user_id, p_operation_key, v_now, 1, v_now)
  on conflict (user_id, operation_key) do update
  set
    window_started_at = case
      when counters.window_started_at
        + make_interval(secs => v_window_seconds) <= v_now
      then v_now
      else counters.window_started_at
    end,
    attempt_count = case
      when counters.window_started_at
        + make_interval(secs => v_window_seconds) <= v_now
      then 1
      else least(counters.attempt_count + 1, v_max_attempts + 1)
    end,
    updated_at = v_now
  returning counters.window_started_at, counters.attempt_count
    into v_window_started_at, v_attempt_count;

  if v_attempt_count > v_max_attempts then
    v_retry_after_seconds := greatest(
      1,
      ceil(extract(epoch from (
        v_window_started_at + make_interval(secs => v_window_seconds) - v_now
      )))::integer
    );
  else
    v_retry_after_seconds := 0;
  end if;

  return query
    select v_attempt_count <= v_max_attempts, v_retry_after_seconds;
end;
$$;

revoke all on function private.consume_operation_rate_limit(text, uuid)
  from public, anon, authenticated, service_role;

-- Replace the public RPC without changing its UUID return contract.
-- A NULL result means the authenticated account is temporarily rate-limited.
create or replace function public.create_business(p_name text, p_slug text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_business_id uuid;
  v_owner_role_id uuid;
  v_admin_role_id uuid;
  v_member_role_id uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_rate_limit_allowed boolean;
  v_retry_after_seconds integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if char_length(v_name) not between 2 and 160 then
    raise exception 'Business name must contain 2 to 160 characters' using errcode = '22023';
  end if;

  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$' then
    raise exception 'Invalid business slug' using errcode = '22023';
  end if;

  select result.is_allowed, result.retry_after_seconds
    into v_rate_limit_allowed, v_retry_after_seconds
  from private.consume_operation_rate_limit('business.create', v_user_id) as result;

  if not v_rate_limit_allowed then
    -- Return normally so the counter update commits with this transaction.
    -- Clients recognize NULL and show a retry-later message.
    return null;
  end if;

  insert into public.businesses (name, slug, created_by)
  values (v_name, v_slug, v_user_id)
  returning id into v_business_id;

  insert into public.business_members (business_id, user_id, role_key, status)
  values (v_business_id, v_user_id, 'owner', 'active');

  insert into public.branches (business_id, name, code, is_primary)
  values (v_business_id, 'شعبه اصلی', 'MAIN', true);

  insert into public.roles (business_id, role_key, name, description, is_system, created_by)
  values (v_business_id, 'owner', 'مالک', 'دسترسی کامل و مدیریت مالکیت', true, v_user_id)
  returning id into v_owner_role_id;

  insert into public.roles (business_id, role_key, name, description, is_system, created_by)
  values (v_business_id, 'admin', 'مدیر', 'مدیریت عملیات بدون انتقال مالکیت یا حذف کسب‌وکار', true, v_user_id)
  returning id into v_admin_role_id;

  insert into public.roles (business_id, role_key, name, description, is_system, created_by)
  values (v_business_id, 'member', 'عضو', 'دسترسی پایه و محدود', true, v_user_id)
  returning id into v_member_role_id;

  insert into public.role_permissions (business_id, role_id, permission_key)
  select v_business_id, v_owner_role_id, p.permission_key
  from public.permissions p;

  insert into public.role_permissions (business_id, role_id, permission_key)
  select v_business_id, v_admin_role_id, p.permission_key
  from public.permissions p
  where p.permission_key not in (
    'business.delete',
    'business.ownership.transfer',
    'billing.subscription.manage',
    'team.owners.manage'
  );

  insert into public.role_permissions (business_id, role_id, permission_key)
  select v_business_id, v_member_role_id, p.permission_key
  from public.permissions p
  where p.permission_key in (
    'dashboard.read',
    'branches.read',
    'crm.customers.read',
    'sales.quotes.read',
    'sales.orders.read',
    'sales.invoices.read',
    'inventory.items.read',
    'inventory.stock.read',
    'reports.read',
    'documents.read'
  );

  insert into public.member_role_assignments
    (business_id, user_id, role_id, status, assigned_by)
  values (v_business_id, v_user_id, v_owner_role_id, 'active', v_user_id);

  return v_business_id;
end;
$$;

revoke all on function public.create_business(text, text) from public, anon;
grant execute on function public.create_business(text, text) to authenticated;

commit;
