\set ON_ERROR_STOP on

-- Ticketing security smoke tests; shares fixture variables with sales-inventory-smoke.sql.

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'ticket-branch-operator', 'اپراتور تیکت شعبه',
        'Branch-scoped reader, assigner and status manager', false, auth.uid())
RETURNING id AS ticket_operator_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
 (:'business_id'::uuid, :'ticket_operator_role_id'::uuid, 'tickets.read'),
 (:'business_id'::uuid, :'ticket_operator_role_id'::uuid, 'tickets.assign'),
 (:'business_id'::uuid, :'ticket_operator_role_id'::uuid, 'tickets.status.manage'),
 (:'business_id'::uuid, :'ticket_operator_role_id'::uuid, 'tickets.comments.read'),
 (:'business_id'::uuid, :'ticket_operator_role_id'::uuid, 'tickets.comments.create');

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'ticket-content-editor', 'ویرایشگر تیکت',
        'Can edit content but not workflow fields', false, auth.uid())
RETURNING id AS ticket_editor_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
 (:'business_id'::uuid, :'ticket_editor_role_id'::uuid, 'tickets.read'),
 (:'business_id'::uuid, :'ticket_editor_role_id'::uuid, 'tickets.update'),
 (:'business_id'::uuid, :'ticket_editor_role_id'::uuid, 'tickets.comments.read');

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'ticket-blind-assigner', 'تخصیص‌دهنده بدون مشاهده',
        'Assignment permission without ticket read access must not mutate rows', false, auth.uid())
RETURNING id AS ticket_blind_assigner_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'ticket_blind_assigner_role_id'::uuid, 'tickets.assign');
RESET ROLE;
INSERT INTO public.business_members (business_id,user_id,role_key,status)
VALUES (:'business_id'::uuid,'10000000-0000-4000-8000-000000000005','member','active');
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
INSERT INTO public.member_role_assignments
 (business_id,user_id,role_id,branch_id,status,assigned_by)
VALUES
 (:'business_id'::uuid,'10000000-0000-4000-8000-000000000002',
  :'ticket_operator_role_id'::uuid, :'branch_id'::uuid,'active',auth.uid()),
 (:'business_id'::uuid,'10000000-0000-4000-8000-000000000004',
  :'ticket_editor_role_id'::uuid,NULL,'active',auth.uid()),
 (:'business_id'::uuid,'10000000-0000-4000-8000-000000000005',
  :'ticket_blind_assigner_role_id'::uuid, :'branch_id'::uuid,'active',auth.uid());

INSERT INTO public.tickets
 (business_id,branch_id,ticket_number,title,description,priority,
  requester_user_id,customer_id,created_by)
VALUES
 (:'business_id'::uuid, :'branch_id'::uuid,'TK-CI-001','تیکت شعبه اصلی',
  'شرح اولیه برای آزمون امنیتی','normal',auth.uid(),:'customer_id'::uuid,auth.uid())
RETURNING id AS primary_ticket_id \gset

INSERT INTO public.tickets
 (business_id,branch_id,ticket_number,title,description,priority,
  requester_user_id,customer_id,created_by)
VALUES
 (:'business_id'::uuid, :'second_branch_id'::uuid,'TK-CI-002','تیکت شعبه دوم',
  'این تیکت نباید برای اپراتور شعبه اول دیده شود','high',
  auth.uid(),:'customer_id'::uuid,auth.uid())
RETURNING id AS second_ticket_id \gset

INSERT INTO public.ticket_comments
 (business_id,ticket_id,author_user_id,body,visibility)
VALUES
 (:'business_id'::uuid, :'primary_ticket_id'::uuid,auth.uid(),'پیام عمومی','public'),
 (:'business_id'::uuid, :'primary_ticket_id'::uuid,auth.uid(),'یادداشت محرمانه تیم','internal');

SELECT set_config('kasbeman.test_primary_ticket_id', :'primary_ticket_id', false);
SELECT set_config('kasbeman.test_second_ticket_id', :'second_ticket_id', false);

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000005';

DO $ticket_blind_mutation$
DECLARE
 v_ticket uuid := current_setting('kasbeman.test_primary_ticket_id')::uuid;
 v_rows integer;
BEGIN
 IF EXISTS (SELECT 1 FROM public.tickets WHERE id=v_ticket) THEN
   RAISE EXCEPTION 'User without tickets.read can see a ticket';
 END IF;
 UPDATE public.tickets SET assignee_user_id='10000000-0000-4000-8000-000000000005'
 WHERE id=v_ticket;
 GET DIAGNOSTICS v_rows = ROW_COUNT;
 IF v_rows <> 0 THEN
   RAISE EXCEPTION 'Assignment-only user mutated a ticket without tickets.read';
 END IF;
END
$ticket_blind_mutation$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $ticket_branch_scope$
DECLARE
 v_primary uuid := current_setting('kasbeman.test_primary_ticket_id')::uuid;
 v_second uuid := current_setting('kasbeman.test_second_ticket_id')::uuid;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.tickets WHERE id=v_primary) THEN
   RAISE EXCEPTION 'Branch operator cannot read assigned-branch ticket';
 END IF;
 IF EXISTS (SELECT 1 FROM public.tickets WHERE id=v_second) THEN
   RAISE EXCEPTION 'Branch operator can read an unassigned-branch ticket';
 END IF;
 IF (SELECT count(*) FROM public.ticket_comments WHERE ticket_id=v_primary) <> 1 THEN
   RAISE EXCEPTION 'Internal ticket note leaked to a user without internal-read permission';
 END IF;
 IF (SELECT count(*) FROM public.ticket_events
     WHERE ticket_id=v_primary AND event_type='comment_added') <> 1 THEN
   RAISE EXCEPTION 'Internal-note activity metadata leaked to a user without internal-read permission';
 END IF;
END
$ticket_branch_scope$;

DO $ticket_internal_comment_denied$
BEGIN
 BEGIN
   INSERT INTO public.ticket_comments
    (business_id,ticket_id,author_user_id,body,visibility)
   VALUES
    (current_setting('kasbeman.test_business_id')::uuid,
     current_setting('kasbeman.test_primary_ticket_id')::uuid,
     auth.uid(),'نباید یادداشت داخلی ثبت شود','internal');
   RAISE EXCEPTION 'User created an internal note without internal-create permission';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$ticket_internal_comment_denied$;

DO $ticket_create_denied$
BEGIN
 BEGIN
   INSERT INTO public.tickets
    (business_id,branch_id,ticket_number,title,description,requester_user_id,created_by)
   VALUES
    (current_setting('kasbeman.test_business_id')::uuid,
     current_setting('kasbeman.test_branch_id')::uuid,
     'TK-CI-DENIED','نباید ثبت شود','بدون مجوز ایجاد',
     auth.uid(),auth.uid());
   RAISE EXCEPTION 'Ticket creation succeeded without tickets.create';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$ticket_create_denied$;

-- A second tenant owner cannot see the first tenant's ticket.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
DO $ticket_tenant_isolation$
BEGIN
 IF EXISTS (
   SELECT 1 FROM public.tickets
   WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid
 ) THEN
   RAISE EXCEPTION 'A second tenant can read another business ticket';
 END IF;
END
$ticket_tenant_isolation$;

-- Content editor may change descriptive fields but cannot assign, transition or archive.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';

UPDATE public.tickets
SET title='عنوان ویرایش‌شده توسط ویرایشگر'
WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;

DO $ticket_workflow_denials$
DECLARE
 v_ticket uuid := current_setting('kasbeman.test_primary_ticket_id')::uuid;
BEGIN
 BEGIN
   UPDATE public.tickets SET status='in_progress' WHERE id=v_ticket;
   RAISE EXCEPTION 'Content editor changed ticket status without status.manage';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
   UPDATE public.tickets SET assignee_user_id='10000000-0000-4000-8000-000000000004'
   WHERE id=v_ticket;
   RAISE EXCEPTION 'Content editor assigned a ticket without tickets.assign';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
   UPDATE public.tickets SET archived_at=now() WHERE id=v_ticket;
   RAISE EXCEPTION 'Content editor archived a ticket without tickets.delete';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF (SELECT status FROM public.tickets WHERE id=v_ticket) <> 'open' THEN
   RAISE EXCEPTION 'Denied status change modified ticket state';
 END IF;
 IF (SELECT assignee_user_id FROM public.tickets WHERE id=v_ticket) IS NOT NULL THEN
   RAISE EXCEPTION 'Denied assignment modified ticket assignee';
 END IF;
 IF (SELECT archived_at FROM public.tickets WHERE id=v_ticket) IS NOT NULL THEN
   RAISE EXCEPTION 'Denied archive modified ticket state';
 END IF;
END
$ticket_workflow_denials$;

-- Branch operator may assign an active member and change status within their branch.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

UPDATE public.tickets
SET assignee_user_id='10000000-0000-4000-8000-000000000002'
WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;
UPDATE public.tickets
SET status='closed'
WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;

DO $ticket_invalid_assignee$
BEGIN
 BEGIN
   UPDATE public.tickets
   SET assignee_user_id='10000000-0000-4000-8000-000000000003'
   WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;
   RAISE EXCEPTION 'Ticket accepted an assignee outside the business';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END
$ticket_invalid_assignee$;

-- Owner archives the closed ticket; direct restore is forbidden even to the owner.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
UPDATE public.tickets
SET archived_at=now()
WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;

DO $ticket_archive_immutable$
BEGIN
 BEGIN
   UPDATE public.tickets SET archived_at=NULL
   WHERE id=current_setting('kasbeman.test_primary_ticket_id')::uuid;
   RAISE EXCEPTION 'Archived ticket was restored by direct update';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$ticket_archive_immutable$;

DO $ticket_event_integrity$
DECLARE
 v_ticket uuid := current_setting('kasbeman.test_primary_ticket_id')::uuid;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.ticket_events WHERE ticket_id=v_ticket AND event_type='created') THEN
   RAISE EXCEPTION 'Ticket creation event was not recorded';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ticket_events WHERE ticket_id=v_ticket AND event_type='status_changed') THEN
   RAISE EXCEPTION 'Ticket status event was not recorded';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ticket_events WHERE ticket_id=v_ticket AND event_type='assignee_changed') THEN
   RAISE EXCEPTION 'Ticket assignee event was not recorded';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ticket_events WHERE ticket_id=v_ticket AND event_type='archived') THEN
   RAISE EXCEPTION 'Ticket archive event was not recorded';
 END IF;
 IF (SELECT count(*) FROM public.ticket_events
     WHERE ticket_id=v_ticket AND event_type='comment_added') <> 2 THEN
   RAISE EXCEPTION 'Owner cannot see the full public and internal comment audit trail';
 END IF;
 IF EXISTS (SELECT 1 FROM public.ticket_events
     WHERE ticket_id=v_ticket AND event_type='comment_added' AND payload ? 'body') THEN
   RAISE EXCEPTION 'Comment body was copied into the event audit payload';
 END IF;
END
$ticket_event_integrity$;

DO $ticket_event_direct_write_denied$
BEGIN
 BEGIN
   INSERT INTO public.ticket_events
    (business_id,ticket_id,actor_user_id,event_type)
   VALUES
    (current_setting('kasbeman.test_business_id')::uuid,
     current_setting('kasbeman.test_primary_ticket_id')::uuid,auth.uid(),'forged_event');
   RAISE EXCEPTION 'API role inserted a forged ticket event';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$ticket_event_direct_write_denied$;

DO $ticket_event_mutation_denied$
BEGIN
 BEGIN
   UPDATE public.ticket_events SET event_type='forged_update'
   WHERE ticket_id=current_setting('kasbeman.test_primary_ticket_id')::uuid;
   RAISE EXCEPTION 'API role modified append-only ticket event history';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
   DELETE FROM public.ticket_events
   WHERE ticket_id=current_setting('kasbeman.test_primary_ticket_id')::uuid;
   RAISE EXCEPTION 'API role deleted append-only ticket event history';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$ticket_event_mutation_denied$;

DO $ticket_security_structure$
DECLARE
 v_function text;
BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.tickets'::regclass) OR
    NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.ticket_comments'::regclass) OR
    NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.ticket_events'::regclass) THEN
   RAISE EXCEPTION 'RLS must be enabled on every ticketing table';
 END IF;
 IF has_table_privilege('anon','public.tickets','SELECT') OR
    has_table_privilege('anon','public.ticket_comments','SELECT') OR
    has_table_privilege('anon','public.ticket_events','SELECT') THEN
   RAISE EXCEPTION 'anon has direct access to a ticketing table';
 END IF;
 FOREACH v_function IN ARRAY ARRAY[
   'private.guard_ticket_changes()',
   'private.record_ticket_event()',
   'private.record_ticket_comment_event()',
   'private.ticket_event_append_only()'
 ] LOOP
   IF has_function_privilege('anon',v_function,'EXECUTE') OR
      has_function_privilege('authenticated',v_function,'EXECUTE') THEN
     RAISE EXCEPTION 'API role can execute internal ticket trigger function: %',v_function;
   END IF;
 END LOOP;
END
$ticket_security_structure$;

SELECT 'Ticketing security smoke tests passed: tenant and branch isolation, granular operation permissions, active assignee validation, internal-note confidentiality, immutable archive, and trigger-only append-only event history.' AS result;


-- New tenants created after this schema is installed receive ticket permissions
-- through the existing create_business bootstrap (not only through this draft's backfill).
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';
SELECT public.create_business('کسب‌وکار مجوز تیکت', 'kasbeman-ci-ticket-perms') AS ticket_permission_business_id \gset
SELECT set_config('kasbeman.test_ticket_permission_business_id', :'ticket_permission_business_id', false);

DO $ticket_default_roles$
BEGIN
 IF NOT EXISTS (
   SELECT 1
   FROM public.roles r
   JOIN public.role_permissions rp
     ON rp.business_id=r.business_id AND rp.role_id=r.id
   WHERE r.business_id=current_setting('kasbeman.test_ticket_permission_business_id')::uuid
     AND r.role_key='owner' AND rp.permission_key='tickets.read'
 ) THEN
   RAISE EXCEPTION 'New tenant owner role did not receive ticket permissions';
 END IF;
 IF NOT EXISTS (
   SELECT 1
   FROM public.roles r
   JOIN public.role_permissions rp
     ON rp.business_id=r.business_id AND rp.role_id=r.id
   WHERE r.business_id=current_setting('kasbeman.test_ticket_permission_business_id')::uuid
     AND r.role_key='admin' AND rp.permission_key='tickets.read'
 ) THEN
   RAISE EXCEPTION 'New tenant admin role did not receive ticket permissions';
 END IF;
 IF EXISTS (
   SELECT 1
   FROM public.roles r
   JOIN public.role_permissions rp
     ON rp.business_id=r.business_id AND rp.role_id=r.id
   WHERE r.business_id=current_setting('kasbeman.test_ticket_permission_business_id')::uuid
     AND r.role_key='member' AND rp.permission_key='tickets.delete'
 ) THEN
   RAISE EXCEPTION 'Default member role unexpectedly received ticket archive permission';
 END IF;
END
$ticket_default_roles$;

-- Release the temporary blind-assigner fixture so the following invitation
-- smoke test can use the same auth identity as a pending invitee.
RESET ROLE;
UPDATE public.business_members
SET status='revoked'
WHERE business_id=current_setting('kasbeman.test_business_id')::uuid
  AND user_id='10000000-0000-4000-8000-000000000005'
  AND status='active';
