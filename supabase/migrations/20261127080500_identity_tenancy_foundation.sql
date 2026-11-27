-- Kasbeman foundation: identity and tenant isolation
-- PostgreSQL 17 / Supabase Auth
-- This migration is prepared for review only. It has NOT been applied to Supabase.

begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_path text,
  locale text not null default 'fa-IR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(display_name) between 1 and 120
  )
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  status text not null default 'active',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint businesses_name_length check (char_length(btrim(name)) between 2 and 160),
  constraint businesses_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'),
  constraint businesses_status_check check (status in ('active', 'suspended', 'archived')),
  constraint businesses_slug_unique unique (slug)
);

create table public.business_members (
  business_id uuid not null references public.businesses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete restrict,
  role_key text not null default 'owner',
  status text not null default 'active',
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id),
  constraint business_members_role_key_check check (role_key in ('owner', 'admin', 'member')),
  constraint business_members_status_check check (status in ('active', 'suspended', 'revoked'))
);

create index business_members_user_status_idx
  on public.business_members (user_id, status, business_id);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  name text not null,
  code text,
  is_primary boolean not null default false,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branches_name_length check (char_length(btrim(name)) between 2 and 120),
  constraint branches_status_check check (status in ('active', 'inactive', 'archived')),
  constraint branches_business_id_id_unique unique (business_id, id),
  constraint branches_code_unique_per_business unique (business_id, code)
);

create unique index branches_one_primary_per_business_idx
  on public.branches (business_id) where is_primary;

create table public.business_invitations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  email text not null,
  role_key text not null default 'member',
  status text not null default 'pending',
  invited_by uuid not null references auth.users (id) on delete restrict,
  token_hash text not null unique,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint invitations_email_normalized check (email = lower(btrim(email))),
  constraint invitations_role_key_check check (role_key in ('admin', 'member')),
  constraint invitations_status_check check (status in ('pending', 'accepted', 'revoked', 'expired')),
  constraint invitations_expiry_check check (expires_at > created_at)
);

create index business_invitations_business_status_idx
  on public.business_invitations (business_id, status, expires_at);
create unique index business_invitations_one_pending_email_idx
  on public.business_invitations (business_id, email) where status = 'pending';

-- Internal authorization helpers. SECURITY DEFINER is restricted to this
-- non-exposed schema, has an empty search_path, and uses fully-qualified names.
create or replace function private.is_business_member(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = (select auth.uid())
      and bm.status = 'active'
  );
$$;

create or replace function private.is_business_owner(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = (select auth.uid())
      and bm.status = 'active'
      and bm.role_key = 'owner'
  );
$$;

revoke all on function private.is_business_member(uuid) from public, anon;
revoke all on function private.is_business_owner(uuid) from public, anon;
grant execute on function private.is_business_member(uuid) to authenticated;
grant execute on function private.is_business_owner(uuid) to authenticated;

-- Profile creation is tied to the trusted Auth user row, never client metadata.
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), 120), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.branches enable row level security;
alter table public.business_invitations enable row level security;

create policy profiles_select_self
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_self
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_self
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy businesses_select_member
  on public.businesses for select to authenticated
  using ((select private.is_business_member(id)));

create policy businesses_update_owner
  on public.businesses for update to authenticated
  using ((select private.is_business_owner(id)))
  with check ((select private.is_business_owner(id)));

create policy business_members_select_same_business
  on public.business_members for select to authenticated
  using ((select private.is_business_member(business_id)));

create policy branches_select_member
  on public.branches for select to authenticated
  using ((select private.is_business_member(business_id)));

create policy branches_insert_owner
  on public.branches for insert to authenticated
  with check ((select private.is_business_owner(business_id)));

create policy branches_update_owner
  on public.branches for update to authenticated
  using ((select private.is_business_owner(business_id)))
  with check ((select private.is_business_owner(business_id)));

create policy business_invitations_select_owner
  on public.business_invitations for select to authenticated
  using ((select private.is_business_owner(business_id)));

create policy business_invitations_insert_owner
  on public.business_invitations for insert to authenticated
  with check (
    (select private.is_business_owner(business_id))
    and invited_by = (select auth.uid())
  );

create policy business_invitations_update_owner
  on public.business_invitations for update to authenticated
  using ((select private.is_business_owner(business_id)))
  with check ((select private.is_business_owner(business_id)));

-- Explicit Data API grants: RLS remains the row-level boundary.
revoke all on table public.profiles, public.businesses, public.business_members,
  public.branches, public.business_invitations from anon, authenticated;

grant select, insert, update on table public.profiles to authenticated;
grant select, update on table public.businesses to authenticated;
grant select on table public.business_members to authenticated;
grant select, insert, update on table public.branches to authenticated;
grant select, insert, update on table public.business_invitations to authenticated;

-- Business bootstrap is atomic: tenant + owner membership + primary branch.
create or replace function public.create_business(p_name text, p_slug text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_business_id uuid;
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

  return v_business_id;
end;
$$;

revoke all on function public.create_business(text, text) from public, anon;
grant execute on function public.create_business(text, text) to authenticated;

commit;
