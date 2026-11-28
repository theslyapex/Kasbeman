\set ON_ERROR_STOP on

-- CRM customer foundation regression tests.
-- Runs after sales-inventory-smoke.sql, which creates the shared tenant fixtures.

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'crm-smoke-reader', 'CRM Reader',
        'Read-only CRM access', false, auth.uid())
RETURNING id AS crm_reader_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'crm_reader_role_id'::uuid, 'crm.customers.read');

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'crm-smoke-editor', 'CRM Editor',
        'May edit customer profile, but not archive', false, auth.uid())
RETURNING id AS crm_editor_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
 (:'business_id'::uuid, :'crm_editor_role_id'::uuid, 'crm.customers.read'),
 (:'business_id'::uuid, :'crm_editor_role_id'::uuid, 'crm.customers.update');

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'crm-smoke-creator', 'CRM Creator',
        'May create customer records', false, auth.uid())
RETURNING id AS crm_creator_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'crm_creator_role_id'::uuid, 'crm.customers.create');

INSERT INTO public.member_role_assignments
 (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES
 (:'business_id'::uuid, '10000000-0000-4000-8000-000000000002',
  :'crm_reader_role_id'::uuid, NULL, 'active', auth.uid()),
 (:'business_id'::uuid, '10000000-0000-4000-8000-000000000004',
  :'crm_editor_role_id'::uuid, NULL, 'active', auth.uid()),
 (:'business_id'::uuid, '10000000-0000-4000-8000-000000000002',
  :'crm_creator_role_id'::uuid, NULL, 'active', auth.uid());

-- Reader can see customers but cannot change or create them.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
DO $crm_reader$
DECLARE
 v_customer uuid := current_setting('kasbeman.test_customer_id')::uuid;
 v_rows integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = v_customer) THEN
   RAISE EXCEPTION 'CRM reader cannot see an authorized customer';
 END IF;
 UPDATE public.customers SET name='Reader must not edit'
 WHERE id=v_customer;
 GET DIAGNOSTICS v_rows = ROW_COUNT;
 IF v_rows <> 0 THEN
   RAISE EXCEPTION 'CRM reader unexpectedly updated a customer';
 END IF;
 BEGIN
   INSERT INTO public.customers (business_id, name, created_by)
   VALUES (current_setting('kasbeman.test_business_id')::uuid,
           'Unauthorized CRM insert', auth.uid());
   RAISE EXCEPTION 'CRM reader created a customer without create permission';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$crm_reader$;

-- Editor may update profile fields, but cannot archive without delete permission.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';
UPDATE public.customers
SET name='مشتری ویرایش‌شده در آزمون CRM', phone='09120000000'
WHERE id=current_setting('kasbeman.test_customer_id')::uuid;

DO $crm_editor_archive_guard$
DECLARE
 v_customer uuid := current_setting('kasbeman.test_customer_id')::uuid;
BEGIN
 BEGIN
   UPDATE public.customers SET status='archived' WHERE id=v_customer;
   RAISE EXCEPTION 'CRM editor archived a customer without crm.customers.delete';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF (SELECT status FROM public.customers WHERE id=v_customer) <> 'active' THEN
   RAISE EXCEPTION 'Denied CRM archive changed customer status';
 END IF;
 IF (SELECT name FROM public.customers WHERE id=v_customer)
    <> 'مشتری ویرایش‌شده در آزمون CRM' THEN
   RAISE EXCEPTION 'CRM editor profile update did not persist';
 END IF;
END
$crm_editor_archive_guard$;

-- Creator can insert but is not granted customer read or update privileges.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
UPDATE public.member_role_assignments SET status='revoked', revoked_at=now()
WHERE business_id=:'business_id'::uuid
  AND user_id='10000000-0000-4000-8000-000000000002'
  AND role_id IN (:'crm_reader_role_id'::uuid, :'customer_reader_role_id'::uuid)
  AND status='active';
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
INSERT INTO public.customers (business_id, name, created_by)
VALUES (current_setting('kasbeman.test_business_id')::uuid,
        'مشتری ایجادشده توسط نقش محدود', auth.uid());

DO $crm_creator_scope$
BEGIN
 IF EXISTS (
   SELECT 1 FROM public.customers
   WHERE name='مشتری ایجادشده توسط نقش محدود'
 ) THEN
   RAISE EXCEPTION 'Create-only CRM role unexpectedly has read access';
 END IF;
END
$crm_creator_scope$;

-- A user from another tenant cannot read this tenant's customer.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
DO $crm_tenant_isolation$
BEGIN
 IF EXISTS (
   SELECT 1 FROM public.customers
   WHERE id=current_setting('kasbeman.test_customer_id')::uuid
 ) THEN
   RAISE EXCEPTION 'Another tenant can read this business customer';
 END IF;
END
$crm_tenant_isolation$;

-- Owner can archive, and the structural controls remain enabled.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
UPDATE public.customers
SET status='archived'
WHERE id=current_setting('kasbeman.test_customer_id')::uuid;

DO $crm_structure$
DECLARE
 v_constraint boolean;
BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.customers'::regclass) THEN
   RAISE EXCEPTION 'RLS is disabled on customers';
 END IF;
 IF has_table_privilege('anon','public.customers','SELECT')
    OR has_table_privilege('anon','public.customers','INSERT')
    OR has_table_privilege('anon','public.customers','UPDATE')
    OR has_table_privilege('anon','public.customers','DELETE') THEN
   RAISE EXCEPTION 'anon has direct privileges on customers';
 END IF;
 IF has_function_privilege('anon','private.guard_customer_status_permission()','EXECUTE')
    OR has_function_privilege('authenticated','private.guard_customer_status_permission()','EXECUTE') THEN
   RAISE EXCEPTION 'API role can directly execute internal CRM trigger function';
 END IF;
 SELECT EXISTS (
   SELECT 1 FROM pg_constraint
   WHERE conrelid='public.customers'::regclass
     AND conname='customers_business_id_id_unique'
     AND contype='u'
 ) INTO v_constraint;
 IF NOT v_constraint THEN
   RAISE EXCEPTION 'Tenant-scoped customer unique key is missing';
 END IF;
END
$crm_structure$;

SELECT 'CRM customer tests passed: read/create/update/archive permission separation, tenant isolation, RLS, trigger ACLs and tenant-scoped key.' AS result;
