-- Kasbeman CRM core — REVIEW DRAFT
-- Customer foundation is intentionally separate from sales/inventory and ticketing.
-- Generate a canonical migration with Supabase CLI only after review.
-- Do not apply this draft to production as-is.

begin;

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
create index customers_business_email_idx
  on public.customers (business_id, lower(email)) where email is not null;

create or replace function private.guard_customer_status_permission()
returns trigger
language plpgsql
set search_path = ''
as $customer_status_guard$
begin
  if new.business_id is distinct from old.business_id then
    raise exception 'Customer business cannot be changed'
      using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not (select private.has_business_permission(
       new.business_id, 'crm.customers.delete', null
     )) then
    raise exception 'Insufficient permission to change customer archive status'
      using errcode = '42501';
  end if;
  return new;
end;
$customer_status_guard$;

revoke all on function private.guard_customer_status_permission()
  from public, anon, authenticated;

create trigger customers_status_permission_guard
  before update of business_id, status on public.customers
  for each row execute function private.guard_customer_status_permission();

alter table public.customers enable row level security;

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
  using (
    (select private.has_business_permission(business_id, 'crm.customers.read', null))
    and (select private.has_business_permission(business_id, 'crm.customers.update', null))
  )
  with check (
    (select private.has_business_permission(business_id, 'crm.customers.read', null))
    and (select private.has_business_permission(business_id, 'crm.customers.update', null))
  );

revoke all on table public.customers from public, anon, authenticated;
grant select, insert on table public.customers to authenticated;
grant update (name, phone, email, company_name, address, notes, status)
  on table public.customers to authenticated;

commit;
