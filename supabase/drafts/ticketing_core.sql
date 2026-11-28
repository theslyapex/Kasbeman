-- Kasbeman ticketing module — SECURITY REVIEW DRAFT
-- NOT a production migration. Validate against the exact base schema in disposable PostgreSQL first.
-- Dependencies: businesses, branches, business_members, customers, roles, permissions,
-- role_permissions, auth.users, auth.uid(), and private.has_business_permission(uuid,text,uuid).

begin;

insert into public.permissions
  (permission_key, module_key, action_key, label_fa, description_fa, is_sensitive)
values
 ('tickets.read','tickets','read','مشاهده تیکت‌ها','مشاهده تیکت‌های محدوده مجاز',false),
 ('tickets.create','tickets','create','ایجاد تیکت','ثبت تیکت جدید',false),
 ('tickets.update','tickets','update','ویرایش تیکت','ویرایش اطلاعات عمومی تیکت',false),
 ('tickets.assign','tickets','assign','تخصیص تیکت','تخصیص به اعضای فعال کسب‌وکار',true),
 ('tickets.status.manage','tickets','status_manage','مدیریت وضعیت','تغییر وضعیت تیکت',true),
 ('tickets.delete','tickets','delete','بایگانی تیکت','بایگانی به جای حذف دائمی',true),
 ('tickets.comments.read','tickets','comments_read','مشاهده گفتگو','مشاهده پیام‌های قابل دسترس',false),
 ('tickets.comments.create','tickets','comments_create','ثبت پیام','ثبت پیام در تیکت',false),
 ('tickets.comments.internal.read','tickets','comments_internal_read','مشاهده یادداشت داخلی','مشاهده یادداشت‌های داخلی تیم',true),
 ('tickets.comments.internal.create','tickets','comments_internal_create','ثبت یادداشت داخلی','ثبت یادداشت داخلی برای تیم',true)
on conflict (permission_key) do nothing;

insert into public.role_permissions (business_id, role_id, permission_key)
select r.business_id, r.id, p.permission_key
from public.roles r
join public.permissions p on p.permission_key in (
 'tickets.read','tickets.create','tickets.update','tickets.assign',
 'tickets.status.manage','tickets.delete','tickets.comments.read','tickets.comments.create',
 'tickets.comments.internal.read','tickets.comments.internal.create'
)
where r.is_system and r.role_key in ('owner','admin')
on conflict do nothing;

create table public.tickets (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 branch_id uuid not null,
 ticket_number text not null,
 title text not null,
 description text not null,
 status text not null default 'open',
 priority text not null default 'normal',
 requester_user_id uuid references auth.users(id) on delete restrict,
 customer_id uuid,
 assignee_user_id uuid references auth.users(id) on delete restrict,
 due_at timestamptz,
 resolved_at timestamptz,
 archived_at timestamptz,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint tickets_business_id_id_unique unique (business_id,id),
 constraint tickets_number_unique unique (business_id,ticket_number),
 constraint tickets_branch_fkey foreign key (business_id,branch_id)
   references public.branches(business_id,id) on delete restrict,
 constraint tickets_customer_fkey foreign key (business_id,customer_id)
   references public.customers(business_id,id) on delete restrict,
 constraint tickets_title_length check (char_length(btrim(title)) between 3 and 200),
 constraint tickets_description_length check (char_length(btrim(description)) between 1 and 10000),
 constraint tickets_status_check check (status in ('open','in_progress','waiting','resolved','closed')),
 constraint tickets_priority_check check (priority in ('low','normal','high','urgent')),
 constraint tickets_archive_shape check (archived_at is null or status in ('resolved','closed'))
);
create index tickets_business_branch_status_idx on public.tickets(business_id,branch_id,status,created_at desc);
create index tickets_business_assignee_idx on public.tickets(business_id,assignee_user_id,status) where assignee_user_id is not null;
create index tickets_customer_idx on public.tickets(business_id,customer_id,created_at desc) where customer_id is not null;

create or replace function private.guard_ticket_changes()
returns trigger language plpgsql set search_path=''
as $ticket_guard$
begin
 if tg_op='INSERT' then
   if new.status <> 'open' or new.resolved_at is not null or new.archived_at is not null then
     raise exception 'New tickets must start open and unarchived' using errcode='23514';
   end if;
   if new.assignee_user_id is not null
      and not private.has_business_permission(new.business_id,'tickets.assign',new.branch_id) then
     raise exception 'Ticket assignment permission required' using errcode='42501';
   end if;
   if new.requester_user_id is distinct from (select auth.uid()) then
     raise exception 'Requester must be the authenticated user' using errcode='42501';
   end if;
 else
   if new.id is distinct from old.id
      or new.business_id is distinct from old.business_id
      or new.branch_id is distinct from old.branch_id
      or new.ticket_number is distinct from old.ticket_number
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at
      or new.requester_user_id is distinct from old.requester_user_id then
     raise exception 'Ticket identity and ownership fields are immutable' using errcode='42501';
   end if;
   if (new.title is distinct from old.title
       or new.description is distinct from old.description
       or new.priority is distinct from old.priority
       or new.customer_id is distinct from old.customer_id
       or new.due_at is distinct from old.due_at)
      and not private.has_business_permission(new.business_id,'tickets.update',new.branch_id) then
     raise exception 'Ticket content update permission required' using errcode='42501';
   end if;
   if new.assignee_user_id is distinct from old.assignee_user_id
      and not private.has_business_permission(new.business_id,'tickets.assign',new.branch_id) then
     raise exception 'Ticket assignment permission required' using errcode='42501';
   end if;
   if new.status is distinct from old.status
      and not private.has_business_permission(new.business_id,'tickets.status.manage',new.branch_id) then
     raise exception 'Ticket status permission required' using errcode='42501';
   end if;
   if new.archived_at is distinct from old.archived_at
      and not private.has_business_permission(new.business_id,'tickets.delete',new.branch_id) then
     raise exception 'Ticket archive permission required' using errcode='42501';
   end if;
   if old.archived_at is not null and new.archived_at is null then
     raise exception 'Archived tickets cannot be restored by direct update' using errcode='42501';
   end if;
 end if;

 if new.assignee_user_id is not null and not exists (
   select 1 from public.business_members bm
   where bm.business_id=new.business_id
     and bm.user_id=new.assignee_user_id and bm.status='active'
 ) then
   raise exception 'Ticket assignee must be an active business member' using errcode='23514';
 end if;

 if new.status in ('resolved','closed') then
   new.resolved_at=coalesce(new.resolved_at,now());
 else
   new.resolved_at=null;
 end if;
 new.updated_at=now();
 return new;
end;
$ticket_guard$;
revoke all on function private.guard_ticket_changes() from public,anon,authenticated;
create trigger tickets_guard_changes before insert or update on public.tickets
 for each row execute function private.guard_ticket_changes();

create table public.ticket_comments (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 ticket_id uuid not null,
 author_user_id uuid not null references auth.users(id) on delete restrict,
 body text not null,
 visibility text not null default 'public',
 created_at timestamptz not null default now(),
 constraint ticket_comments_body_length check (char_length(btrim(body)) between 1 and 10000),
 constraint ticket_comments_visibility check (visibility in ('public','internal')),
 constraint ticket_comments_ticket_fkey foreign key (business_id,ticket_id)
   references public.tickets(business_id,id) on delete restrict
);
create index ticket_comments_ticket_idx on public.ticket_comments(business_id,ticket_id,created_at);

create table public.ticket_events (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 ticket_id uuid not null,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 event_type text not null,
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 constraint ticket_events_ticket_fkey foreign key (business_id,ticket_id)
   references public.tickets(business_id,id) on delete restrict,
 constraint ticket_events_type_length check (char_length(btrim(event_type)) between 1 and 64)
);
create index ticket_events_ticket_idx on public.ticket_events(business_id,ticket_id,created_at);

create or replace function private.ticket_event_append_only()
returns trigger language plpgsql set search_path=''
as $ticket_event_append_only$
begin
 raise exception 'Ticket events are append-only' using errcode='42501';
end;
$ticket_event_append_only$;
revoke all on function private.ticket_event_append_only() from public,anon,authenticated;
create trigger ticket_events_no_mutation before update or delete on public.ticket_events
 for each row execute function private.ticket_event_append_only();

create or replace function private.record_ticket_event()
returns trigger language plpgsql security definer set search_path=''
as $record_ticket_event$
declare
 v_actor uuid;
begin
 v_actor := coalesce(auth.uid(), new.created_by);
 if tg_op='INSERT' then
   insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
   values (new.business_id,new.id,v_actor,'created',
     jsonb_build_object('status',new.status,'priority',new.priority,'assignee_user_id',new.assignee_user_id));
 else
   if new.status is distinct from old.status then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'status_changed',
       jsonb_build_object('from',old.status,'to',new.status));
   end if;
   if new.priority is distinct from old.priority then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'priority_changed',
       jsonb_build_object('from',old.priority,'to',new.priority));
   end if;
   if new.assignee_user_id is distinct from old.assignee_user_id then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'assignee_changed',
       jsonb_build_object('from',old.assignee_user_id,'to',new.assignee_user_id));
   end if;
   if new.archived_at is distinct from old.archived_at and new.archived_at is not null then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'archived','{}'::jsonb);
   end if;
   if new.title is distinct from old.title then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'title_changed','{}'::jsonb);
   end if;
   if new.description is distinct from old.description then
     insert into public.ticket_events(business_id,ticket_id,actor_user_id,event_type,payload)
     values (new.business_id,new.id,v_actor,'description_changed','{}'::jsonb);
   end if;
 end if;
 return new;
end;
$record_ticket_event$;
revoke all on function private.record_ticket_event() from public,anon,authenticated;
create trigger tickets_record_event after insert or update on public.tickets
 for each row execute function private.record_ticket_event();

alter table public.tickets enable row level security;
alter table public.ticket_comments enable row level security;
alter table public.ticket_events enable row level security;

create policy tickets_select_permission on public.tickets for select to authenticated
 using (private.has_business_permission(business_id,'tickets.read',branch_id));
create policy tickets_insert_permission on public.tickets for insert to authenticated
 with check (created_by=(select auth.uid())
  and requester_user_id=(select auth.uid())
  and private.has_business_permission(business_id,'tickets.create',branch_id));
create policy tickets_update_permission on public.tickets for update to authenticated
 using (private.has_business_permission(business_id,'tickets.update',branch_id)
     or private.has_business_permission(business_id,'tickets.assign',branch_id)
     or private.has_business_permission(business_id,'tickets.status.manage',branch_id)
     or private.has_business_permission(business_id,'tickets.delete',branch_id))
 with check (private.has_business_permission(business_id,'tickets.update',branch_id)
     or private.has_business_permission(business_id,'tickets.assign',branch_id)
     or private.has_business_permission(business_id,'tickets.status.manage',branch_id)
     or private.has_business_permission(business_id,'tickets.delete',branch_id));

create policy ticket_comments_select_permission on public.ticket_comments for select to authenticated
 using (exists(select 1 from public.tickets t
  where t.business_id=ticket_comments.business_id and t.id=ticket_comments.ticket_id
  and private.has_business_permission(t.business_id,'tickets.read',t.branch_id)
  and private.has_business_permission(t.business_id,'tickets.comments.read',t.branch_id)
  and (ticket_comments.visibility='public'
       or private.has_business_permission(t.business_id,'tickets.comments.internal.read',t.branch_id))));
create policy ticket_comments_insert_permission on public.ticket_comments for insert to authenticated
 with check (author_user_id=(select auth.uid()) and exists(select 1 from public.tickets t
  where t.business_id=ticket_comments.business_id and t.id=ticket_comments.ticket_id
  and private.has_business_permission(t.business_id,'tickets.read',t.branch_id)
  and private.has_business_permission(t.business_id,'tickets.comments.create',t.branch_id)
  and (ticket_comments.visibility='public'
       or private.has_business_permission(t.business_id,'tickets.comments.internal.create',t.branch_id))));

create policy ticket_events_select_permission on public.ticket_events for select to authenticated
 using (exists(select 1 from public.tickets t
  where t.business_id=ticket_events.business_id and t.id=ticket_events.ticket_id
  and private.has_business_permission(t.business_id,'tickets.read',t.branch_id)));

revoke all on table public.tickets,public.ticket_comments,public.ticket_events from anon,authenticated;
grant select on public.tickets to authenticated;
grant insert (business_id,branch_id,ticket_number,title,description,priority,
              requester_user_id,customer_id,due_at,created_by)
 on public.tickets to authenticated;
grant update (title,description,priority,customer_id,due_at,assignee_user_id,status,archived_at)
 on public.tickets to authenticated;
grant select on public.ticket_comments to authenticated;
grant insert (business_id,ticket_id,author_user_id,body,visibility)
 on public.ticket_comments to authenticated;
grant select on public.ticket_events to authenticated;

commit;