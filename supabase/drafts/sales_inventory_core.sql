-- Kasbeman sales and inventory core — REVIEW DRAFT
-- This is intentionally stored outside supabase/migrations until it has been
-- generated through the Supabase CLI and tested against a disposable database.
-- Do not apply this draft to production as-is.

begin;

insert into public.permissions
  (permission_key, module_key, action_key, label_fa, description_fa, is_sensitive)
values
  ('inventory.warehouses.read', 'inventory', 'warehouses_read', 'مشاهده انبارها', 'مشاهده انبارهای هر شعبه', false),
  ('inventory.warehouses.manage', 'inventory', 'warehouses_manage', 'مدیریت انبارها', 'ایجاد و ویرایش انبارها', true)
on conflict (permission_key) do nothing;

-- New warehouse permissions are granted to protected owner/admin roles only.
insert into public.role_permissions (business_id, role_id, permission_key)
select r.business_id, r.id, p.permission_key
from public.roles r
join public.permissions p
  on p.permission_key in ('inventory.warehouses.read', 'inventory.warehouses.manage')
where r.is_system and r.role_key in ('owner', 'admin')
on conflict do nothing;

-- Customer authorization uses the canonical crm.customers.* catalogue
-- from the RBAC foundation. Sales roles need customer read access to select
-- customers on invoices and review customer purchase history.
insert into public.role_permissions (business_id, role_id, permission_key)
select rp.business_id, rp.role_id, 'crm.customers.read'
from public.role_permissions rp
where rp.permission_key in ('sales.invoices.read', 'sales.invoices.manage',
                            'crm.customers.create', 'crm.customers.update')
on conflict do nothing;

-- Manage permissions imply read access because Postgres UPDATE and the
-- receipt transaction both need a matching SELECT policy.
insert into public.role_permissions (business_id, role_id, permission_key)
select rp.business_id, rp.role_id, 'sales.invoices.read'
from public.role_permissions rp
where rp.permission_key = 'sales.invoices.manage'
on conflict do nothing;

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sku text,
  barcode text,
  name text not null,
  description text,
  product_type text not null default 'goods',
  unit_name text not null default 'عدد',
  sale_price numeric(18,2) not null default 0,
  purchase_price numeric(18,2) not null default 0,
  status text not null default 'active',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_name_length check (char_length(btrim(name)) between 2 and 180),
  constraint products_type_check check (product_type in ('goods', 'service')),
  constraint products_unit_length check (char_length(btrim(unit_name)) between 1 and 24),
  constraint products_prices_nonnegative check (sale_price >= 0 and purchase_price >= 0),
  constraint products_status_check check (status in ('active', 'archived')),
  constraint products_business_id_id_unique unique (business_id, id)
);

create unique index products_sku_unique_per_business
  on public.products (business_id, lower(sku)) where sku is not null and btrim(sku) <> '';
create unique index products_barcode_unique_per_business
  on public.products (business_id, barcode) where barcode is not null and btrim(barcode) <> '';
create index products_business_status_name_idx
  on public.products (business_id, status, name);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  name text not null,
  code text not null,
  is_default boolean not null default false,
  status text not null default 'active',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouses_name_length check (char_length(btrim(name)) between 2 and 120),
  constraint warehouses_code_format check (code ~ '^[A-Za-z0-9_-]{2,24}$'),
  constraint warehouses_status_check check (status in ('active', 'inactive', 'archived')),
  constraint warehouses_business_id_id_unique unique (business_id, id),
  constraint warehouses_business_branch_id_unique unique (business_id, branch_id, id),
  constraint warehouses_branch_fkey
    foreign key (business_id, branch_id)
    references public.branches (business_id, id) on delete restrict,
  constraint warehouses_business_code_unique unique (business_id, code)
);

create unique index warehouses_one_default_per_branch_idx
  on public.warehouses (business_id, branch_id) where is_default;
create index warehouses_branch_status_idx
  on public.warehouses (business_id, branch_id, status);

-- Every active branch receives a default warehouse. The trigger also covers
-- branches created after this schema is installed.
insert into public.warehouses
  (business_id, branch_id, name, code, is_default, created_by)
select
  br.business_id,
  br.id,
  'انبار اصلی',
  'WH-' || upper(substr(replace(br.id::text, '-', ''), 1, 16)),
  true,
  b.created_by
from public.branches br
join public.businesses b on b.id = br.business_id
where br.status = 'active';

create or replace function private.create_default_warehouse_for_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_by uuid;
begin
  if new.status = 'active' then
    select b.created_by into v_created_by
    from public.businesses b
    where b.id = new.business_id;

    insert into public.warehouses
      (business_id, branch_id, name, code, is_default, created_by)
    values (
      new.business_id,
      new.id,
      'انبار اصلی',
      'WH-' || upper(substr(replace(new.id::text, '-', ''), 1, 16)),
      true,
      v_created_by
    );
  end if;
  return new;
end;
$$;
revoke all on function private.create_default_warehouse_for_branch() from public, anon, authenticated;
create trigger branch_create_default_warehouse
  after insert on public.branches
  for each row execute function private.create_default_warehouse_for_branch();

create table public.stock_balances (
  business_id uuid not null,
  branch_id uuid not null,
  warehouse_id uuid not null,
  product_id uuid not null,
  quantity_on_hand numeric(18,3) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (business_id, warehouse_id, product_id),
  constraint stock_balances_nonnegative check (quantity_on_hand >= 0),
  constraint stock_balances_warehouse_fkey
    foreign key (business_id, branch_id, warehouse_id)
    references public.warehouses (business_id, branch_id, id) on delete restrict,
  constraint stock_balances_product_fkey
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create index stock_balances_branch_product_idx
  on public.stock_balances (business_id, branch_id, product_id);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  movement_type text not null,
  product_id uuid not null,
  quantity numeric(18,3) not null,
  from_branch_id uuid,
  from_warehouse_id uuid,
  to_branch_id uuid,
  to_warehouse_id uuid,
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint stock_movements_type_check check (movement_type in ('in', 'out', 'transfer')),
  constraint stock_movements_quantity_positive check (quantity > 0),
  constraint stock_movements_source_shape check (
    (movement_type = 'in' and from_warehouse_id is null and from_branch_id is null
      and to_warehouse_id is not null and to_branch_id is not null)
    or
    (movement_type = 'out' and to_warehouse_id is null and to_branch_id is null
      and from_warehouse_id is not null and from_branch_id is not null)
    or
    (movement_type = 'transfer' and from_warehouse_id is not null and from_branch_id is not null
      and to_warehouse_id is not null and to_branch_id is not null
      and from_warehouse_id <> to_warehouse_id)
  ),
  constraint stock_movements_product_fkey
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict,
  constraint stock_movements_from_warehouse_fkey
    foreign key (business_id, from_branch_id, from_warehouse_id)
    references public.warehouses (business_id, branch_id, id) on delete restrict,
  constraint stock_movements_to_warehouse_fkey
    foreign key (business_id, to_branch_id, to_warehouse_id)
    references public.warehouses (business_id, branch_id, id) on delete restrict
);

create index stock_movements_business_created_idx
  on public.stock_movements (business_id, created_at desc);
create index stock_movements_from_warehouse_idx
  on public.stock_movements (business_id, from_warehouse_id, created_at desc)
  where from_warehouse_id is not null;
create index stock_movements_to_warehouse_idx
  on public.stock_movements (business_id, to_warehouse_id, created_at desc)
  where to_warehouse_id is not null;
create unique index stock_movements_reference_unique
  on public.stock_movements (business_id, reference_type, reference_id, product_id, movement_type)
  where reference_type is not null and reference_id is not null;

-- Customer records belong to the business, not an individual branch.
-- Purchase totals are derived from confirmed sales and are not stored redundantly.
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  company_name text,
  address text,
  notes text,
  status text not null default 'active',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_name_length check (char_length(btrim(name)) between 2 and 160),
  constraint customers_phone_length check (phone is null or char_length(btrim(phone)) <= 32),
  constraint customers_email_length check (email is null or char_length(btrim(email)) <= 254),
  constraint customers_status_check check (status in ('active', 'archived')),
  constraint customers_business_id_id_unique unique (business_id, id)
);

create index customers_business_status_name_idx
  on public.customers (business_id, status, name);
create index customers_business_phone_idx
  on public.customers (business_id, phone) where phone is not null;

-- A customer profile editor must not gain archive/restore rights implicitly.
-- Status transitions are a separate destructive CRM operation.
create or replace function private.guard_customer_status_permission()
returns trigger
language plpgsql
set search_path = ''
as $
begin
  if new.status is distinct from old.status
     and not (select private.has_business_permission(
       new.business_id, 'crm.customers.delete', null
     )) then
    raise exception 'Insufficient permission to change customer archive status'
      using errcode = '42501';
  end if;
  return new;
end;
$;

revoke all on function private.guard_customer_status_permission()
  from public, anon, authenticated;

create trigger customers_status_permission_guard
  before update of status on public.customers
  for each row execute function private.guard_customer_status_permission();

-- Sales are branch- and warehouse-bound. Drafts may be edited; confirmation
-- atomically records stock-out movements and changes the sale state.
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  warehouse_id uuid not null,
  sale_number text not null,
  customer_id uuid,
  customer_name text,
  status text not null default 'draft',
  subtotal numeric(18,2) not null default 0,
  discount_total numeric(18,2) not null default 0,
  tax_total numeric(18,2) not null default 0,
  grand_total numeric(18,2) not null default 0,
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_number_length check (char_length(btrim(sale_number)) between 1 and 40),
  constraint sales_status_check check (status in ('draft', 'confirmed', 'cancelled')),
  constraint sales_amounts_nonnegative check (
    subtotal >= 0 and discount_total >= 0 and tax_total >= 0 and grand_total >= 0
    and discount_total <= subtotal
    and grand_total = subtotal - discount_total + tax_total
  ),
  constraint sales_business_id_id_unique unique (business_id, id),
  constraint sales_number_unique_per_business unique (business_id, sale_number),
  constraint sales_branch_warehouse_fkey
    foreign key (business_id, branch_id, warehouse_id)
    references public.warehouses (business_id, branch_id, id) on delete restrict,
  constraint sales_customer_fkey
    foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete restrict
);

create index sales_business_branch_created_idx
  on public.sales (business_id, branch_id, created_at desc);
create index sales_business_status_created_idx
  on public.sales (business_id, status, created_at desc);
create index sales_business_customer_created_idx
  on public.sales (business_id, customer_id, created_at desc)
  where customer_id is not null;

alter table public.sales
  add constraint sales_business_id_id_customer_unique unique (business_id, id, customer_id);

create table public.customer_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  idempotency_key uuid not null,
  sale_id uuid not null,
  customer_id uuid not null,
  amount numeric(18,2) not null,
  payment_method text not null,
  reference text,
  notes text,
  received_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  constraint customer_receipts_amount_positive check (amount > 0),
  constraint customer_receipts_business_id_idempotency_key_unique unique (business_id, idempotency_key),
  constraint customer_receipts_method_check
    check (payment_method in ('cash', 'card', 'bank_transfer', 'cheque', 'other')),
  constraint customer_receipts_reference_length
    check (reference is null or char_length(btrim(reference)) <= 120),
  constraint customer_receipts_notes_length
    check (notes is null or char_length(btrim(notes)) <= 1000),
  constraint customer_receipts_sale_customer_fkey
    foreign key (business_id, sale_id, customer_id)
    references public.sales (business_id, id, customer_id) on delete restrict
);

create index customer_receipts_business_customer_date_idx
  on public.customer_receipts (business_id, customer_id, received_at desc);
create index customer_receipts_business_sale_idx
  on public.customer_receipts (business_id, sale_id, received_at desc);

alter table public.customer_receipts
  add constraint customer_receipts_business_id_id_unique unique (business_id, id);

-- Immutable full reversal record; one reversal maximum for each receipt.
create table public.customer_receipt_reversals (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  receipt_id uuid not null,
  sale_id uuid not null,
  customer_id uuid not null,
  amount numeric(18,2) not null,
  reason text not null,
  reversed_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  constraint customer_receipt_reversals_amount_positive check (amount > 0),
  constraint customer_receipt_reversals_reason_length check (char_length(btrim(reason)) between 3 and 500),
  constraint customer_receipt_reversals_one_per_receipt unique (business_id, receipt_id),
  constraint customer_receipt_reversals_receipt_fkey foreign key (business_id, receipt_id)
    references public.customer_receipts (business_id, id) on delete restrict,
  constraint customer_receipt_reversals_sale_customer_fkey foreign key (business_id, sale_id, customer_id)
    references public.sales (business_id, id, customer_id) on delete restrict
);
create index customer_receipt_reversals_customer_date_idx
  on public.customer_receipt_reversals (business_id, customer_id, reversed_at desc);
revoke all on public.customer_receipt_reversals from public, anon, authenticated;
grant select on public.customer_receipt_reversals to authenticated;

create or replace view public.customer_invoice_balance_summary
with (security_invoker = true)
as
select
  s.business_id,
  s.customer_id,
  s.id as sale_id,
  s.grand_total,
  coalesce(receipts.total_received, 0)::numeric(18,2) as total_received,
  greatest(s.grand_total - coalesce(receipts.total_received, 0), 0)::numeric(18,2) as balance_due
from public.sales s
left join lateral (
  select coalesce(sum(r.amount), 0) - coalesce(sum(rv.amount), 0) as total_received
  from public.customer_receipts r
  left join public.customer_receipt_reversals rv
    on rv.business_id = r.business_id and rv.receipt_id = r.id
  where r.business_id = s.business_id and r.sale_id = s.id
) receipts on true
where s.status = 'confirmed' and s.customer_id is not null;

create or replace view public.customer_purchase_summary
with (security_invoker = true)
as
select
  c.business_id,
  c.id as customer_id,
  count(s.id) filter (where s.status = 'confirmed') as purchase_count,
  coalesce(sum(s.grand_total) filter (where s.status = 'confirmed'), 0)::numeric(18,2)
    as total_purchases,
  coalesce(sum(ib.total_received), 0)::numeric(18,2) as total_received,
  coalesce(sum(ib.balance_due), 0)::numeric(18,2) as balance_due
from public.customers c
left join public.sales s
  on s.business_id = c.business_id and s.customer_id = c.id
left join public.customer_invoice_balance_summary ib
  on ib.business_id = s.business_id and ib.sale_id = s.id
group by c.business_id, c.id;

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  sale_id uuid not null,
  product_id uuid not null,
  product_name_snapshot text not null,
  sku_snapshot text,
  quantity numeric(18,3) not null,
  unit_price numeric(18,2) not null,
  discount_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  line_total numeric(18,2) not null,
  created_at timestamptz not null default now(),
  constraint sale_items_quantity_positive check (quantity > 0),
  constraint sale_items_amounts_nonnegative check (
    unit_price >= 0 and discount_amount >= 0 and tax_amount >= 0 and line_total >= 0
    and discount_amount <= round(quantity * unit_price, 2)
    and line_total = round(quantity * unit_price, 2) - discount_amount + tax_amount
  ),
  constraint sale_items_name_length check (char_length(btrim(product_name_snapshot)) between 1 and 180),
  constraint sale_items_sale_fkey
    foreign key (business_id, sale_id)
    references public.sales (business_id, id) on delete cascade,
  constraint sale_items_product_fkey
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create index sale_items_sale_idx on public.sale_items (business_id, sale_id);
create index sale_items_product_idx on public.sale_items (business_id, product_id);

-- The trigger is the only writer to stock_balances. An insufficient issue
-- fails the transaction because stock_balances enforces non-negative quantity.
create or replace function private.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product_type text;
  v_product_status text;
begin
  select p.product_type, p.status
  into v_product_type, v_product_status
  from public.products p
  where p.business_id = new.business_id and p.id = new.product_id;

  if not found or v_product_type <> 'goods' or v_product_status <> 'active' then
    raise exception 'Only active stockable goods can have stock movements'
      using errcode = '22023';
  end if;

  if new.movement_type in ('out', 'transfer') and not exists (
    select 1
    from public.branches br
    join public.warehouses w
      on w.business_id = br.business_id
     and w.branch_id = br.id
     and w.id = new.from_warehouse_id
    where br.business_id = new.business_id
      and br.id = new.from_branch_id
      and br.status = 'active'
      and w.status = 'active'
  ) then
    raise exception 'Source branch or warehouse is inactive' using errcode = '22023';
  end if;

  if new.movement_type in ('in', 'transfer') and not exists (
    select 1
    from public.branches br
    join public.warehouses w
      on w.business_id = br.business_id
     and w.branch_id = br.id
     and w.id = new.to_warehouse_id
    where br.business_id = new.business_id
      and br.id = new.to_branch_id
      and br.status = 'active'
      and w.status = 'active'
  ) then
    raise exception 'Destination branch or warehouse is inactive' using errcode = '22023';
  end if;

  if new.movement_type in ('out', 'transfer') then
    -- Update an existing balance atomically. Avoid inserting a negative
    -- EXCLUDED row: PostgreSQL checks CHECK constraints before ON CONFLICT.
    update public.stock_balances
    set quantity_on_hand = quantity_on_hand - new.quantity,
        updated_at = now()
    where business_id = new.business_id
      and branch_id = new.from_branch_id
      and warehouse_id = new.from_warehouse_id
      and product_id = new.product_id
      and quantity_on_hand >= new.quantity;

    if not found then
      raise exception 'Insufficient stock for product % in warehouse %',
        new.product_id, new.from_warehouse_id
        using errcode = '23514';
    end if;
  end if;

  if new.movement_type in ('in', 'transfer') then
    insert into public.stock_balances
      (business_id, branch_id, warehouse_id, product_id, quantity_on_hand)
    values
      (new.business_id, new.to_branch_id, new.to_warehouse_id, new.product_id, new.quantity)
    on conflict (business_id, warehouse_id, product_id)
    do update set
      quantity_on_hand = public.stock_balances.quantity_on_hand + excluded.quantity_on_hand,
      updated_at = now();
  end if;

  return new;
end;
$$;

revoke all on function private.apply_stock_movement() from public, anon, authenticated;
create trigger stock_movement_apply_balance
  after insert on public.stock_movements
  for each row execute function private.apply_stock_movement();

-- Create a draft and all of its lines in one transaction. Prices are read
-- from the current product records; clients cannot submit arbitrary unit prices.
drop function if exists public.create_sale_draft(uuid, uuid, uuid, text, jsonb, uuid, text, text);

create or replace function public.create_sale_draft(
  p_business_id uuid,
  p_branch_id uuid,
  p_warehouse_id uuid,
  p_sale_number text,
  p_items jsonb,
  p_customer_id uuid default null,
  p_customer_name text default null,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_sale_id uuid;
  v_item_count integer;
  v_valid_count integer;
  v_subtotal numeric(18,2);
  v_discount numeric(18,2);
  v_tax numeric(18,2);
  v_total numeric(18,2);
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must contain at least one item' using errcode = '22023';
  end if;

  select count(*) into v_item_count
  from jsonb_to_recordset(p_items) as i(
    product_id uuid, quantity numeric, discount_amount numeric, tax_amount numeric
  );

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as i(
      product_id uuid, quantity numeric, discount_amount numeric, tax_amount numeric
    )
    where i.product_id is null or i.quantity is null or i.quantity <= 0
       or coalesce(i.discount_amount, 0) < 0 or coalesce(i.tax_amount, 0) < 0
  ) then
    raise exception 'Invalid sale item values' using errcode = '22023';
  end if;

  select count(*),
    coalesce(sum(round(i.quantity * p.sale_price, 2)), 0)::numeric(18,2),
    coalesce(sum(coalesce(i.discount_amount, 0)), 0)::numeric(18,2),
    coalesce(sum(coalesce(i.tax_amount, 0)), 0)::numeric(18,2)
  into v_valid_count, v_subtotal, v_discount, v_tax
  from jsonb_to_recordset(p_items) as i(
    product_id uuid, quantity numeric, discount_amount numeric, tax_amount numeric
  )
  join public.products p
    on p.business_id = p_business_id and p.id = i.product_id
   and p.status = 'active';

  if v_valid_count <> v_item_count then
    raise exception 'One or more products are unavailable' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as i(
      product_id uuid, quantity numeric, discount_amount numeric, tax_amount numeric
    )
    join public.products p on p.business_id = p_business_id and p.id = i.product_id
    where coalesce(i.discount_amount, 0) > round(i.quantity * p.sale_price, 2)
  ) then
    raise exception 'Item discount exceeds its amount' using errcode = '23514';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.business_id = p_business_id
      and c.id = p_customer_id
      and c.status = 'active'
  ) then
    raise exception 'Customer is unavailable for this business' using errcode = '22023';
  end if;

  v_total := v_subtotal - v_discount + v_tax;
  insert into public.sales (
    business_id, branch_id, warehouse_id, sale_number, customer_id, customer_name,
    subtotal, discount_total, tax_total, grand_total, notes, created_by
  ) values (
    p_business_id, p_branch_id, p_warehouse_id, p_sale_number, p_customer_id,
    coalesce(
      (select c.name from public.customers c
       where c.business_id = p_business_id and c.id = p_customer_id),
      nullif(btrim(p_customer_name), '')
    ),
    v_subtotal, v_discount, v_tax, v_total, nullif(btrim(p_notes), ''), v_user_id
  ) returning id into v_sale_id;

  insert into public.sale_items (
    business_id, sale_id, product_id, product_name_snapshot, sku_snapshot,
    quantity, unit_price, discount_amount, tax_amount, line_total
  )
  select
    p_business_id, v_sale_id, p.id, p.name, p.sku,
    i.quantity, p.sale_price, coalesce(i.discount_amount, 0),
    coalesce(i.tax_amount, 0),
    round(i.quantity * p.sale_price, 2) - coalesce(i.discount_amount, 0)
      + coalesce(i.tax_amount, 0)
  from jsonb_to_recordset(p_items) as i(
    product_id uuid, quantity numeric, discount_amount numeric, tax_amount numeric
  )
  join public.products p
    on p.business_id = p_business_id and p.id = i.product_id
   and p.status = 'active';

  return v_sale_id;
end;
$$;
revoke all on function public.create_sale_draft(uuid, uuid, uuid, text, jsonb, uuid, text, text)
  from public, anon;
grant execute on function public.create_sale_draft(uuid, uuid, uuid, text, jsonb, uuid, text, text)
  to authenticated;

-- Confirmation is deliberately a narrowly-scoped SECURITY DEFINER endpoint:
-- it checks the live user's sales + stock permissions before bypassing table RLS.
drop function if exists public.record_customer_receipt(uuid, numeric, text, text, text);

create or replace function public.record_customer_receipt(
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_idempotency_key uuid,
  p_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_sale public.sales%rowtype;
  v_existing public.customer_receipts%rowtype;
  v_received numeric(18,2);
  v_amount numeric(18,2);
  v_receipt_id uuid;
  v_reference text := nullif(btrim(p_reference), '');
  v_notes text := nullif(btrim(p_notes), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Receipt amount must be positive' using errcode = '22023';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required' using errcode = '22023';
  end if;
  v_amount := round(p_amount, 2);
  if p_payment_method not in ('cash', 'card', 'bank_transfer', 'cheque', 'other') then
    raise exception 'Unsupported payment method' using errcode = '22023';
  end if;

  select s.* into v_sale
  from public.sales s
  where s.id = p_sale_id
  for update;

  if not found or v_sale.customer_id is null then
    raise exception 'Customer invoice not found' using errcode = 'P0002';
  end if;
  if v_sale.status <> 'confirmed' then
    raise exception 'Only confirmed invoices can receive payments' using errcode = '22023';
  end if;
  if not (select private.has_business_permission(
    v_sale.business_id, 'finance.payments.manage', v_sale.branch_id
  )) then
    raise exception 'Insufficient permission to record a receipt' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_sale.business_id::text || ':' || p_idempotency_key::text, 0)
  );

  select r.* into v_existing
  from public.customer_receipts r
  where r.business_id = v_sale.business_id
    and r.idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.sale_id <> v_sale.id
       or v_existing.amount <> v_amount
       or v_existing.payment_method <> p_payment_method
       or v_existing.reference is distinct from v_reference
       or v_existing.notes is distinct from v_notes
       or v_existing.created_by <> v_user_id then
      raise exception 'Idempotency key was already used for a different receipt request'
        using errcode = '22023';
    end if;
    return v_existing.id;
  end if;

  select (coalesce(sum(r.amount), 0) - coalesce(sum(rv.amount), 0))::numeric(18,2)
    into v_received
  from public.customer_receipts r
  left join public.customer_receipt_reversals rv
    on rv.business_id = r.business_id and rv.receipt_id = r.id
  where r.business_id = v_sale.business_id and r.sale_id = v_sale.id;

  if v_received + v_amount > v_sale.grand_total then
    raise exception 'Receipt exceeds the remaining invoice balance' using errcode = '23514';
  end if;

  insert into public.customer_receipts (
    business_id, sale_id, customer_id, amount, payment_method,
    idempotency_key, reference, notes, created_by
  ) values (
    v_sale.business_id, v_sale.id, v_sale.customer_id, v_amount,
    p_payment_method, p_idempotency_key, v_reference, v_notes, v_user_id
  )
  returning id into v_receipt_id;

  return v_receipt_id;
end;
$$;

revoke all on function public.record_customer_receipt(uuid, numeric, text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.record_customer_receipt(uuid, numeric, text, uuid, text, text)
  to authenticated;

-- Record a full reversal as a new immutable accounting event.
create or replace function public.reverse_customer_receipt(p_receipt_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid := (select auth.uid());
  v_receipt public.customer_receipts%rowtype;
  v_sale public.sales%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_reversal_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 500 then
    raise exception 'A reversal reason between 3 and 500 characters is required' using errcode = '22023';
  end if;
  select r.* into v_receipt from public.customer_receipts r where r.id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found' using errcode = 'P0002'; end if;
  select s.* into v_sale from public.sales s
    where s.business_id = v_receipt.business_id and s.id = v_receipt.sale_id for update;
  if not found or v_sale.status <> 'confirmed' then
    raise exception 'Confirmed invoice not found' using errcode = 'P0002';
  end if;
  if not (select private.has_business_permission(v_sale.business_id, 'finance.payments.manage', v_sale.branch_id)) then
    raise exception 'Insufficient permission to reverse a receipt' using errcode = '42501';
  end if;
  if exists (select 1 from public.customer_receipt_reversals rv
    where rv.business_id = v_receipt.business_id and rv.receipt_id = v_receipt.id) then
    raise exception 'Receipt has already been reversed' using errcode = '23505';
  end if;
  insert into public.customer_receipt_reversals
    (business_id, receipt_id, sale_id, customer_id, amount, reason, created_by)
  values (v_receipt.business_id, v_receipt.id, v_receipt.sale_id, v_receipt.customer_id,
    v_receipt.amount, v_reason, v_user_id) returning id into v_reversal_id;
  return v_reversal_id;
end;
$$;
revoke all on function public.reverse_customer_receipt(uuid, text) from public, anon, authenticated;
grant execute on function public.reverse_customer_receipt(uuid, text) to authenticated;

create or replace function public.confirm_sale(p_sale_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_sale public.sales%rowtype;
  v_item record;
  v_available numeric(18,3);
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select * into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Sale not found or inaccessible' using errcode = 'P0002';
  end if;

  if not (select private.has_business_permission(
    v_sale.business_id, 'sales.invoices.manage', v_sale.branch_id
  )) or not (select private.has_business_permission(
    v_sale.business_id, 'inventory.stock.manage', v_sale.branch_id
  )) then
    raise exception 'Insufficient permission to confirm sale' using errcode = '42501';
  end if;

  if v_sale.status <> 'draft' then
    raise exception 'Only draft sales can be confirmed' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.branches br
    join public.warehouses w
      on w.business_id = br.business_id
     and w.branch_id = br.id
     and w.id = v_sale.warehouse_id
    where br.business_id = v_sale.business_id
      and br.id = v_sale.branch_id
      and br.status = 'active'
      and w.status = 'active'
  ) then
    raise exception 'The sale branch or warehouse is inactive' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.sale_items si
    join public.products p
      on p.business_id = si.business_id and p.id = si.product_id
    where si.business_id = v_sale.business_id
      and si.sale_id = v_sale.id
      and p.status <> 'active'
  ) then
    raise exception 'Archived products cannot be sold' using errcode = '22023';
  end if;

  if exists (
    select 1
    from (
      select
        coalesce(sum(round(si.quantity * si.unit_price, 2)), 0)::numeric(18,2) as subtotal,
        coalesce(sum(si.discount_amount), 0)::numeric(18,2) as discount_total,
        coalesce(sum(si.tax_amount), 0)::numeric(18,2) as tax_total,
        coalesce(sum(si.line_total), 0)::numeric(18,2) as grand_total
      from public.sale_items si
      where si.business_id = v_sale.business_id and si.sale_id = v_sale.id
    ) totals
    where totals.subtotal <> v_sale.subtotal
       or totals.discount_total <> v_sale.discount_total
       or totals.tax_total <> v_sale.tax_total
       or totals.grand_total <> v_sale.grand_total
  ) then
    raise exception 'Sale totals do not match its items' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.sale_items si
    where si.business_id = v_sale.business_id and si.sale_id = v_sale.id
  ) then
    raise exception 'A sale must contain at least one item' using errcode = '22023';
  end if;

  for v_item in
    select si.product_id, sum(si.quantity)::numeric(18,3) as quantity
    from public.sale_items si
    join public.products p
      on p.business_id = si.business_id and p.id = si.product_id
    where si.business_id = v_sale.business_id
      and si.sale_id = v_sale.id
      and p.product_type = 'goods'
    group by si.product_id
    order by si.product_id
  loop
    select sb.quantity_on_hand into v_available
    from public.stock_balances sb
    where sb.business_id = v_sale.business_id
      and sb.branch_id = v_sale.branch_id
      and sb.warehouse_id = v_sale.warehouse_id
      and sb.product_id = v_item.product_id
    for update;

    if coalesce(v_available, 0) < v_item.quantity then
      raise exception 'Insufficient stock for product %', v_item.product_id
        using errcode = '23514';
    end if;

    insert into public.stock_movements (
      business_id, movement_type, product_id, quantity,
      from_branch_id, from_warehouse_id, reference_type, reference_id,
      note, created_by
    ) values (
      v_sale.business_id, 'out', v_item.product_id, v_item.quantity,
      v_sale.branch_id, v_sale.warehouse_id, 'sale', v_sale.id,
      'خروج کالا بابت تأیید فروش', v_user_id
    );
  end loop;

  update public.sales
  set status = 'confirmed', confirmed_at = now(), updated_at = now()
  where id = v_sale.id and business_id = v_sale.business_id;

  return v_sale.id;
end;
$$;

revoke all on function public.confirm_sale(uuid) from public, anon;
grant execute on function public.confirm_sale(uuid) to authenticated;

alter table public.customers enable row level security;
alter table public.customer_receipts enable row level security;
alter table public.customer_receipt_reversals enable row level security;
alter table public.products enable row level security;
alter table public.warehouses enable row level security;
alter table public.stock_balances enable row level security;
alter table public.stock_movements enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

create policy customers_select_authorized on public.customers
  for select to authenticated
  using ((select private.has_business_permission(business_id, 'crm.customers.read', null)));
create policy customers_insert_authorized on public.customers
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (select private.has_business_permission(business_id, 'crm.customers.create', null))
  );
create policy customers_update_authorized on public.customers
  for update to authenticated
  using ((select private.has_business_permission(business_id, 'crm.customers.update', null)))
  with check ((select private.has_business_permission(business_id, 'crm.customers.update', null)));

create policy customer_receipt_reversals_select_authorized on public.customer_receipt_reversals
  for select to authenticated using (exists (
    select 1 from public.sales s
    where s.business_id = customer_receipt_reversals.business_id
      and s.id = customer_receipt_reversals.sale_id
      and (select private.has_business_permission(s.business_id, 'sales.invoices.read', s.branch_id))
      and (
        (select private.has_business_permission(s.business_id, 'finance.payments.read', s.branch_id))
        or (select private.has_business_permission(s.business_id, 'finance.payments.manage', s.branch_id))
      )
  ));
create policy customer_receipts_select_authorized on public.customer_receipts
  for select to authenticated
  using (exists (
    select 1 from public.sales s
    where s.business_id = customer_receipts.business_id
      and s.id = customer_receipts.sale_id
      and (select private.has_business_permission(
        s.business_id, 'sales.invoices.read', s.branch_id
      ))
      and (
        (select private.has_business_permission(s.business_id, 'finance.payments.read', s.branch_id))
        or (select private.has_business_permission(s.business_id, 'finance.payments.manage', s.branch_id))
      )
  ));

create policy products_select_authorized on public.products
  for select to authenticated
  using ((select private.has_business_permission(business_id, 'inventory.items.read', null)));
create policy products_insert_authorized on public.products
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (select private.has_business_permission(business_id, 'inventory.items.manage', null))
  );
create policy products_update_authorized on public.products
  for update to authenticated
  using ((select private.has_business_permission(business_id, 'inventory.items.manage', null)))
  with check ((select private.has_business_permission(business_id, 'inventory.items.manage', null)));

create policy warehouses_select_authorized on public.warehouses
  for select to authenticated
  using ((select private.has_business_permission(business_id, 'inventory.warehouses.read', branch_id)));
create policy warehouses_insert_authorized on public.warehouses
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (select private.has_business_permission(business_id, 'inventory.warehouses.manage', branch_id))
  );
create policy warehouses_update_authorized on public.warehouses
  for update to authenticated
  using ((select private.has_business_permission(business_id, 'inventory.warehouses.manage', branch_id)))
  with check ((select private.has_business_permission(business_id, 'inventory.warehouses.manage', branch_id)));

create policy stock_balances_select_authorized on public.stock_balances
  for select to authenticated
  using ((select private.has_business_permission(business_id, 'inventory.stock.read', branch_id)));

create policy stock_movements_select_authorized on public.stock_movements
  for select to authenticated
  using (
    (from_branch_id is not null and (select private.has_business_permission(business_id, 'inventory.stock.read', from_branch_id)))
    or
    (to_branch_id is not null and (select private.has_business_permission(business_id, 'inventory.stock.read', to_branch_id)))
  );
create policy stock_movements_insert_authorized on public.stock_movements
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (
      (movement_type = 'in' and (select private.has_business_permission(business_id, 'inventory.stock.manage', to_branch_id)))
      or
      (movement_type = 'out' and (select private.has_business_permission(business_id, 'inventory.stock.manage', from_branch_id)))
      or
      (movement_type = 'transfer'
        and (select private.has_business_permission(business_id, 'inventory.stock.manage', from_branch_id))
        and (select private.has_business_permission(business_id, 'inventory.stock.manage', to_branch_id)))
    )
  );

create policy sales_select_authorized on public.sales
  for select to authenticated
  using ((select private.has_business_permission(business_id, 'sales.invoices.read', branch_id)));
create policy sales_insert_authorized on public.sales
  for insert to authenticated
  with check (
    status = 'draft'
    and created_by = (select auth.uid())
    and (select private.has_business_permission(business_id, 'sales.invoices.manage', branch_id))
  );
create policy sales_update_draft_authorized on public.sales
  for update to authenticated
  using (
    status = 'draft'
    and (select private.has_business_permission(business_id, 'sales.invoices.manage', branch_id))
  )
  with check (
    status = 'draft'
    and (select private.has_business_permission(business_id, 'sales.invoices.manage', branch_id))
  );

create policy sale_items_select_authorized on public.sale_items
  for select to authenticated
  using (exists (
    select 1 from public.sales s
    where s.business_id = sale_items.business_id
      and s.id = sale_items.sale_id
      and (select private.has_business_permission(s.business_id, 'sales.invoices.read', s.branch_id))
  ));
create policy sale_items_insert_draft_authorized on public.sale_items
  for insert to authenticated
  with check (exists (
    select 1 from public.sales s
    where s.business_id = sale_items.business_id
      and s.id = sale_items.sale_id
      and s.status = 'draft'
      and (select private.has_business_permission(s.business_id, 'sales.invoices.manage', s.branch_id))
  ));
create policy sale_items_update_draft_authorized on public.sale_items
  for update to authenticated
  using (exists (
    select 1 from public.sales s
    where s.business_id = sale_items.business_id
      and s.id = sale_items.sale_id
      and s.status = 'draft'
      and (select private.has_business_permission(s.business_id, 'sales.invoices.manage', s.branch_id))
  ))
  with check (exists (
    select 1 from public.sales s
    where s.business_id = sale_items.business_id
      and s.id = sale_items.sale_id
      and s.status = 'draft'
      and (select private.has_business_permission(s.business_id, 'sales.invoices.manage', s.branch_id))
  ));
create policy sale_items_delete_draft_authorized on public.sale_items
  for delete to authenticated
  using (exists (
    select 1 from public.sales s
    where s.business_id = sale_items.business_id
      and s.id = sale_items.sale_id
      and s.status = 'draft'
      and (select private.has_business_permission(s.business_id, 'sales.invoices.manage', s.branch_id))
  ));

revoke all on table public.customer_receipts from anon, authenticated;

revoke all on table public.customers, public.products, public.warehouses, public.stock_balances,
  public.stock_movements, public.sales, public.sale_items from anon, authenticated;

grant select, insert on table public.customers to authenticated;
grant select on table public.customer_receipts to authenticated;
grant select on public.customer_invoice_balance_summary to authenticated;
grant update (name, phone, email, company_name, address, notes, status)
  on table public.customers to authenticated;
grant select on public.customer_purchase_summary to authenticated;
grant select, insert on table public.products to authenticated;
grant update (sku, barcode, name, description, product_type, unit_name, sale_price, purchase_price, status)
  on table public.products to authenticated;
grant select, insert on table public.warehouses to authenticated;
grant update (name, code, is_default, status) on table public.warehouses to authenticated;
grant select on table public.stock_balances to authenticated;
grant select, insert on table public.stock_movements to authenticated;
grant select, insert, update on table public.sales to authenticated;
grant select, insert, update, delete on table public.sale_items to authenticated;

commit;
