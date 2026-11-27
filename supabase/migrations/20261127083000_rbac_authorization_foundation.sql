-- Kasbeman foundation: tenant-scoped RBAC and branch assignments
-- PostgreSQL 17 / Supabase Auth
-- Prepared for review only. Not applied to the hosted Supabase project.
-- Depends on 20261127080500_identity_tenancy_foundation.sql.

begin;

-- Global, stable permission catalogue. Authorization decisions never use user-editable metadata.
create table public.permissions (
  permission_key text primary key,
  module_key text not null,
  action_key text not null,
  label_fa text not null,
  description_fa text,
  is_sensitive boolean not null default false,
  created_at timestamptz not null default now(),
  constraint permissions_key_format check (permission_key ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),
  constraint permissions_module_action_unique unique (module_key, action_key)
);

insert into public.permissions
  (permission_key, module_key, action_key, label_fa, description_fa, is_sensitive)
values
  ('dashboard.read', 'dashboard', 'read', 'مشاهده داشبورد', 'مشاهده نمای کلی کسب‌وکار', false),
  ('business.settings.manage', 'business', 'settings_manage', 'مدیریت تنظیمات کسب‌وکار', 'تغییر تنظیمات عمومی کسب‌وکار', true),
  ('business.delete', 'business', 'delete', 'حذف کسب‌وکار', 'عملیات حساس و غیرقابل بازگشت حذف کسب‌وکار', true),
  ('business.ownership.transfer', 'business', 'ownership_transfer', 'انتقال مالکیت', 'انتقال مالکیت کسب‌وکار به عضو دیگر', true),
  ('billing.subscription.manage', 'billing', 'subscription_manage', 'مدیریت اشتراک', 'تغییر طرح و اشتراک کسب‌وکار', true),
  ('team.members.read', 'team', 'members_read', 'مشاهده اعضا', 'مشاهده فهرست اعضای کسب‌وکار', false),
  ('team.members.invite', 'team', 'members_invite', 'دعوت اعضا', 'ایجاد و مدیریت دعوت‌نامه اعضا', true),
  ('team.members.manage', 'team', 'members_manage', 'مدیریت عضویت', 'تغییر وضعیت عضویت اعضا', true),
  ('team.roles.read', 'team', 'roles_read', 'مشاهده نقش‌ها', 'مشاهده نقش‌ها و مجوزهای کسب‌وکار', false),
  ('team.roles.manage', 'team', 'roles_manage', 'مدیریت نقش‌ها', 'ایجاد و ویرایش نقش‌های سفارشی', true),
  ('team.roles.assign', 'team', 'roles_assign', 'تخصیص نقش', 'تخصیص نقش به اعضای فعال', true),
  ('team.owners.manage', 'team', 'owners_manage', 'مدیریت مالکان', 'تخصیص نقش مالک؛ مستقل از مدیریت عادی اعضا', true),
  ('branches.read', 'branches', 'read', 'مشاهده شعب', 'مشاهده شعب کسب‌وکار', false),
  ('branches.manage', 'branches', 'manage', 'مدیریت شعب', 'ایجاد و ویرایش شعب کسب‌وکار', true),
  ('crm.customers.read', 'crm', 'customers_read', 'مشاهده مشتریان', 'مشاهده پرونده مشتریان', false),
  ('crm.customers.create', 'crm', 'customers_create', 'ایجاد مشتری', 'ثبت مشتری جدید', false),
  ('crm.customers.update', 'crm', 'customers_update', 'ویرایش مشتری', 'ویرایش اطلاعات مشتریان', false),
  ('crm.customers.delete', 'crm', 'customers_delete', 'حذف مشتری', 'حذف پرونده مشتریان', true),
  ('sales.quotes.read', 'sales', 'quotes_read', 'مشاهده پیش‌فاکتورها', 'مشاهده پیش‌فاکتورهای فروش', false),
  ('sales.quotes.manage', 'sales', 'quotes_manage', 'مدیریت پیش‌فاکتورها', 'ایجاد و ویرایش پیش‌فاکتور', false),
  ('sales.orders.read', 'sales', 'orders_read', 'مشاهده سفارش‌ها', 'مشاهده سفارش‌های فروش', false),
  ('sales.orders.manage', 'sales', 'orders_manage', 'مدیریت سفارش‌ها', 'ایجاد و ویرایش سفارش فروش', false),
  ('sales.invoices.read', 'sales', 'invoices_read', 'مشاهده فاکتورها', 'مشاهده فاکتورهای فروش', false),
  ('sales.invoices.manage', 'sales', 'invoices_manage', 'مدیریت فاکتورها', 'ایجاد و ویرایش فاکتورهای فروش', true),
  ('finance.payments.read', 'finance', 'payments_read', 'مشاهده پرداخت‌ها', 'مشاهده دریافت‌ها و پرداخت‌ها', true),
  ('finance.payments.manage', 'finance', 'payments_manage', 'مدیریت پرداخت‌ها', 'ثبت و تخصیص پرداخت‌ها', true),
  ('inventory.items.read', 'inventory', 'items_read', 'مشاهده کالاها', 'مشاهده فهرست کالا و خدمات', false),
  ('inventory.items.manage', 'inventory', 'items_manage', 'مدیریت کالاها', 'ایجاد و ویرایش کالاها', false),
  ('inventory.stock.read', 'inventory', 'stock_read', 'مشاهده موجودی', 'مشاهده موجودی و گردش انبار', false),
  ('inventory.stock.manage', 'inventory', 'stock_manage', 'مدیریت موجودی', 'ثبت اصلاح و انتقال موجودی', true),
  ('purchases.orders.read', 'purchases', 'orders_read', 'مشاهده خریدها', 'مشاهده سفارش‌های خرید', false),
  ('purchases.orders.manage', 'purchases', 'orders_manage', 'مدیریت خریدها', 'ایجاد و ویرایش سفارش خرید', false),
  ('reports.read', 'reports', 'read', 'مشاهده گزارش‌ها', 'مشاهده گزارش‌های کسب‌وکار', false),
  ('reports.export', 'reports', 'export', 'خروجی گزارش‌ها', 'دریافت خروجی از گزارش‌ها', true),
  ('documents.read', 'documents', 'read', 'مشاهده اسناد', 'مشاهده اسناد و فایل‌ها', false),
  ('documents.manage', 'documents', 'manage', 'مدیریت اسناد', 'ایجاد و ویرایش اسناد', false)
on conflict (permission_key) do nothing;

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  role_key text not null,
  name text not null,
  description text,
  is_system boolean not null default false,
  status text not null default 'active',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roles_key_format check (role_key ~ '^[a-z][a-z0-9_-]{1,47}$'),
  constraint roles_name_length check (char_length(btrim(name)) between 2 and 80),
  constraint roles_status_check check (status in ('active', 'archived')),
  constraint roles_business_id_id_unique unique (business_id, id),
  constraint roles_business_key_unique unique (business_id, role_key)
);

create index roles_business_status_idx on public.roles (business_id, status);

create table public.role_permissions (
  business_id uuid not null,
  role_id uuid not null,
  permission_key text not null references public.permissions (permission_key) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (business_id, role_id, permission_key),
  constraint role_permissions_role_fkey
    foreign key (business_id, role_id)
    references public.roles (business_id, id) on delete cascade
);

create index role_permissions_permission_idx
  on public.role_permissions (permission_key, business_id, role_id);

create table public.member_role_assignments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  user_id uuid not null,
  role_id uuid not null,
  branch_id uuid,
  status text not null default 'active',
  assigned_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint member_role_assignments_status_check check (status in ('active', 'revoked')),
  constraint member_role_assignments_revocation_check
    check ((status = 'active' and revoked_at is null) or (status = 'revoked' and revoked_at is not null)),
  constraint member_role_assignments_member_fkey
    foreign key (business_id, user_id)
    references public.business_members (business_id, user_id) on delete restrict,
  constraint member_role_assignments_role_fkey
    foreign key (business_id, role_id)
    references public.roles (business_id, id) on delete restrict,
  constraint member_role_assignments_branch_fkey
    foreign key (business_id, branch_id)
    references public.branches (business_id, id) on delete restrict
);

create unique index member_role_assignments_business_scope_unique
  on public.member_role_assignments (business_id, user_id, role_id)
  where status = 'active' and branch_id is null;

create unique index member_role_assignments_branch_scope_unique
  on public.member_role_assignments (business_id, user_id, role_id, branch_id)
  where status = 'active' and branch_id is not null;

create index member_role_assignments_user_lookup_idx
  on public.member_role_assignments (business_id, user_id, status, branch_id);

-- Permission checks are evaluated against live membership and assignments, never stale JWT role claims.
create or replace function private.has_business_permission(
  p_business_id uuid,
  p_permission_key text,
  p_branch_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
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
    and exists (
      select 1
      from public.business_members bm
      join public.member_role_assignments mra
        on mra.business_id = bm.business_id
       and mra.user_id = bm.user_id
       and mra.status = 'active'
      join public.roles r
        on r.business_id = mra.business_id
       and r.id = mra.role_id
       and r.status = 'active'
      join public.role_permissions rp
        on rp.business_id = r.business_id
       and rp.role_id = r.id
       and rp.permission_key = p_permission_key
      where bm.business_id = p_business_id
        and bm.user_id = (select auth.uid())
        and bm.status = 'active'
        and (
          (p_branch_id is null and mra.branch_id is null)
          or
          (p_branch_id is not null and (mra.branch_id is null or mra.branch_id = p_branch_id))
        )
    );
$$;

-- Assignment gate: the target must already be an active member; owner grants require owner authority.
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
            select 1 from public.branches b
            where b.business_id = p_business_id
              and b.id = p_branch_id
              and b.status = 'active'
          )
        )
        and (
          r.role_key <> 'owner'
          or private.has_business_permission(p_business_id, 'team.owners.manage', null)
        )
    );
$$;

revoke all on function private.has_business_permission(uuid, text, uuid) from public, anon;
revoke all on function private.can_assign_business_role(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function private.has_business_permission(uuid, text, uuid) to authenticated;
grant execute on function private.can_assign_business_role(uuid, uuid, uuid, uuid) to authenticated;

-- Internal audit log: no direct Data API access. A later audited read path can expose scoped events.
create table private.authorization_audit_log (
  id bigint generated always as identity primary key,
  business_id uuid not null,
  actor_user_id uuid,
  target_user_id uuid,
  entity_type text not null,
  entity_id text,
  event_type text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index authorization_audit_business_created_idx
  on private.authorization_audit_log (business_id, created_at desc);

revoke all on table private.authorization_audit_log from public, anon, authenticated;
alter table private.authorization_audit_log enable row level security;

create or replace function private.log_authorization_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_before jsonb;
  v_after jsonb;
  v_business_id uuid;
  v_target_user_id uuid;
  v_entity_id text;
begin
  if tg_op = 'INSERT' then
    v_row := to_jsonb(new);
    v_after := v_row;
  elsif tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    v_before := to_jsonb(old);
    v_after := v_row;
  else
    v_row := to_jsonb(old);
    v_before := v_row;
  end if;

  v_business_id := nullif(v_row ->> 'business_id', '')::uuid;
  v_target_user_id := nullif(v_row ->> 'user_id', '')::uuid;
  v_entity_id := coalesce(
    v_row ->> 'id',
    v_row ->> 'role_id',
    v_row ->> 'permission_key',
    v_row ->> 'user_id'
  );

  insert into private.authorization_audit_log (
    business_id, actor_user_id, target_user_id,
    entity_type, entity_id, event_type, before_data, after_data
  ) values (
    v_business_id, (select auth.uid()), v_target_user_id,
    tg_table_name, v_entity_id, tg_op, v_before, v_after
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.log_authorization_change() from public, anon, authenticated;

create trigger roles_authorization_audit
  after insert or update or delete on public.roles
  for each row execute function private.log_authorization_change();

create trigger role_permissions_authorization_audit
  after insert or update or delete on public.role_permissions
  for each row execute function private.log_authorization_change();

create trigger member_role_assignments_authorization_audit
  after insert or update or delete on public.member_role_assignments
  for each row execute function private.log_authorization_change();

create trigger business_members_authorization_audit
  after update on public.business_members
  for each row
  when (old.status is distinct from new.status or old.role_key is distinct from new.role_key)
  execute function private.log_authorization_change();

-- Backfill protected system roles for every existing tenant.
insert into public.roles (business_id, role_key, name, description, is_system, created_by)
select b.id, v.role_key, v.name, v.description, true, b.created_by
from public.businesses b
cross join (values
  ('owner', 'مالک', 'دسترسی کامل و مدیریت مالکیت'),
  ('admin', 'مدیر', 'مدیریت عملیات بدون انتقال مالکیت یا حذف کسب‌وکار'),
  ('member', 'عضو', 'دسترسی پایه و محدود')
) as v(role_key, name, description)
on conflict (business_id, role_key) do nothing;

-- Owner gets the full catalogue. Admin cannot grant ownership, delete the tenant, or manage billing.
insert into public.role_permissions (business_id, role_id, permission_key)
select r.business_id, r.id, p.permission_key
from public.roles r
cross join public.permissions p
where r.is_system and r.role_key = 'owner'
on conflict do nothing;

insert into public.role_permissions (business_id, role_id, permission_key)
select r.business_id, r.id, p.permission_key
from public.roles r
join public.permissions p on p.permission_key not in (
  'business.delete',
  'business.ownership.transfer',
  'billing.subscription.manage',
  'team.owners.manage'
)
where r.is_system and r.role_key = 'admin'
on conflict do nothing;

insert into public.role_permissions (business_id, role_id, permission_key)
select r.business_id, r.id, p.permission_key
from public.roles r
join public.permissions p on p.permission_key in (
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
)
where r.is_system and r.role_key = 'member'
on conflict do nothing;

-- Map existing active memberships from the temporary role_key to the canonical RBAC model.
insert into public.member_role_assignments
  (business_id, user_id, role_id, status, assigned_by)
select bm.business_id, bm.user_id, r.id, 'active', bm.user_id
from public.business_members bm
join public.roles r
  on r.business_id = bm.business_id
 and r.role_key = case when bm.role_key in ('owner', 'admin') then bm.role_key else 'member' end
where bm.status = 'active'
on conflict do nothing;

-- Replace baseline owner-only policies with explicit permission checks.
drop policy if exists business_members_select_same_business on public.business_members;
create policy business_members_select_authorized
  on public.business_members for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.has_business_permission(business_id, 'team.members.read', null))
  );

drop policy if exists business_invitations_select_owner on public.business_invitations;
create policy business_invitations_select_authorized
  on public.business_invitations for select to authenticated
  using (
    (select private.has_business_permission(business_id, 'team.members.read', null))
    or (select private.has_business_permission(business_id, 'team.members.invite', null))
  );

drop policy if exists business_invitations_insert_owner on public.business_invitations;
create policy business_invitations_insert_authorized
  on public.business_invitations for insert to authenticated
  with check (
    (select private.has_business_permission(business_id, 'team.members.invite', null))
    and invited_by = (select auth.uid())
  );

drop policy if exists business_invitations_update_owner on public.business_invitations;
create policy business_invitations_update_authorized
  on public.business_invitations for update to authenticated
  using ((select private.has_business_permission(business_id, 'team.members.invite', null)))
  with check ((select private.has_business_permission(business_id, 'team.members.invite', null)));

drop policy if exists businesses_update_owner on public.businesses;
create policy businesses_update_authorized
  on public.businesses for update to authenticated
  using ((select private.has_business_permission(id, 'business.settings.manage', null)))
  with check ((select private.has_business_permission(id, 'business.settings.manage', null)));

drop policy if exists branches_insert_owner on public.branches;
create policy branches_insert_authorized
  on public.branches for insert to authenticated
  with check ((select private.has_business_permission(business_id, 'branches.manage', null)));

drop policy if exists branches_update_owner on public.branches;
create policy branches_update_authorized
  on public.branches for update to authenticated
  using ((select private.has_business_permission(business_id, 'branches.manage', null)))
  with check ((select private.has_business_permission(business_id, 'branches.manage', null)));

-- Read-only global catalogue.
alter table public.permissions enable row level security;
create policy permissions_select_authenticated
  on public.permissions for select to authenticated
  using ((select auth.uid()) is not null);

-- Tenant-scoped role management.
alter table public.roles enable row level security;
create policy roles_select_member
  on public.roles for select to authenticated
  using ((select private.is_business_member(business_id)));

create policy roles_insert_authorized
  on public.roles for insert to authenticated
  with check (
    not is_system
    and created_by = (select auth.uid())
    and (select private.has_business_permission(business_id, 'team.roles.manage', null))
  );

create policy roles_update_authorized
  on public.roles for update to authenticated
  using (
    not is_system
    and (select private.has_business_permission(business_id, 'team.roles.manage', null))
  )
  with check (
    not is_system
    and (select private.has_business_permission(business_id, 'team.roles.manage', null))
  );

create policy roles_delete_authorized
  on public.roles for delete to authenticated
  using (
    not is_system
    and (select private.has_business_permission(business_id, 'team.roles.manage', null))
  );

-- Role permission changes are restricted to custom roles and cannot grant a permission the actor lacks.
alter table public.role_permissions enable row level security;
create policy role_permissions_select_member
  on public.role_permissions for select to authenticated
  using ((select private.is_business_member(business_id)));

create policy role_permissions_insert_authorized
  on public.role_permissions for insert to authenticated
  with check (
    (select private.has_business_permission(business_id, 'team.roles.manage', null))
    and (select private.has_business_permission(business_id, permission_key, null))
    and exists (
      select 1 from public.roles r
      where r.business_id = role_permissions.business_id
        and r.id = role_permissions.role_id
        and not r.is_system
        and r.status = 'active'
    )
  );

create policy role_permissions_delete_authorized
  on public.role_permissions for delete to authenticated
  using (
    (select private.has_business_permission(business_id, 'team.roles.manage', null))
    and exists (
      select 1 from public.roles r
      where r.business_id = role_permissions.business_id
        and r.id = role_permissions.role_id
        and not r.is_system
    )
  );

-- Role assignments can only target active members and branches within the same tenant.
alter table public.member_role_assignments enable row level security;
create policy member_role_assignments_select_authorized
  on public.member_role_assignments for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.has_business_permission(business_id, 'team.members.read', null))
    or (select private.has_business_permission(business_id, 'team.roles.assign', null))
  );

create policy member_role_assignments_insert_authorized
  on public.member_role_assignments for insert to authenticated
  with check (
    assigned_by = (select auth.uid())
    and status = 'active'
    and revoked_at is null
    and (select private.can_assign_business_role(business_id, user_id, role_id, branch_id))
  );

create policy member_role_assignments_revoke_authorized
  on public.member_role_assignments for update to authenticated
  using (
    status = 'active'
    and (select private.has_business_permission(business_id, 'team.members.manage', null))
    and exists (
      select 1 from public.roles r
      where r.business_id = member_role_assignments.business_id
        and r.id = member_role_assignments.role_id
        and r.role_key <> 'owner'
    )
  )
  with check (
    status = 'revoked'
    and revoked_at is not null
    and (select private.has_business_permission(business_id, 'team.members.manage', null))
  );

-- Explicit grants: public-schema tables are not assumed to be Data API exposed.
revoke all on table public.permissions, public.roles, public.role_permissions,
  public.member_role_assignments from anon, authenticated;

grant select on table public.permissions to authenticated;
grant select, insert, delete on table public.roles to authenticated;
grant update (name, description, status) on table public.roles to authenticated;
grant select, insert, delete on table public.role_permissions to authenticated;
grant select, insert on table public.member_role_assignments to authenticated;
grant update (status, revoked_at) on table public.member_role_assignments to authenticated;

-- Rebuild the business bootstrap so every new tenant starts with protected system roles and an owner assignment.
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
