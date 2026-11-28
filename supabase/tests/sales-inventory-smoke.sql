\set ON_ERROR_STOP on

-- Every application table in the exposed public schema must enforce RLS.
DO $$
DECLARE
  v_table record;
  v_privilege text;
BEGIN
  FOR v_table IN
    SELECT c.oid, c.relname, c.relrowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
  LOOP
    IF NOT v_table.relrowsecurity THEN
      RAISE EXCEPTION 'RLS is disabled on public table: %', v_table.relname;
    END IF;

    FOREACH v_privilege IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'] LOOP
      IF has_table_privilege('anon', v_table.oid, v_privilege) THEN
        RAISE EXCEPTION 'anon has % privilege on public table %',
          v_privilege, v_table.relname;
      END IF;
    END LOOP;
  END LOOP;

  -- Public views must not silently bypass the underlying table policies.
  FOR v_table IN
    SELECT c.relname, c.reloptions
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'v'
  LOOP
    IF NOT coalesce('security_invoker=true' = ANY(v_table.reloptions), false) THEN
      RAISE EXCEPTION 'Public view is not security_invoker: %', v_table.relname;
    END IF;
  END LOOP;
END
$$;

-- Function ACL regression checks. has_function_privilege() includes inherited
-- PUBLIC grants, so a true result for anon would catch an accidental PUBLIC EXECUTE.
DO $$
DECLARE
  v_function text;
  v_public_endpoints text[] := ARRAY[
    'public.create_business(text,text)',
    'public.create_sale_draft(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
    'public.confirm_sale(uuid)',
    'public.record_customer_receipt(uuid,numeric,text,uuid,text,text)',
    'public.reverse_customer_receipt(uuid,text)',
    'public.create_business_invitation(uuid,text,text,timestamptz)',
    'public.revoke_business_invitation(uuid,uuid)',
    'public.accept_business_invitation(text)',
    'public.transfer_business_ownership(uuid,uuid)'
  ];
  v_authenticated_helpers text[] := ARRAY[
    'private.has_business_permission(uuid,text,uuid)',
    'private.can_assign_business_role(uuid,uuid,uuid,uuid)',
    'private.can_manage_business_member(uuid,uuid)'
  ];
  v_internal_trigger_functions text[] := ARRAY[
    'private.create_default_warehouse_for_branch()',
    'private.apply_stock_movement()',
    'private.log_authorization_change()',
    'private.guard_business_member_lifecycle()',
    'private.guard_owner_role_assignment()',
    'private.guard_customer_status_permission()',
    'private.consume_operation_rate_limit(text,uuid)'
  ];
BEGIN
  FOREACH v_function IN ARRAY v_public_endpoints LOOP
    IF has_function_privilege('anon', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous role can execute privileged endpoint: %', v_function;
    END IF;
    IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Authenticated role cannot execute expected endpoint: %', v_function;
    END IF;
  END LOOP;

  FOREACH v_function IN ARRAY v_authenticated_helpers LOOP
    IF has_function_privilege('anon', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous role can execute internal authorization helper: %', v_function;
    END IF;
    IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Authenticated role cannot execute required authorization helper: %', v_function;
    END IF;
  END LOOP;

  FOREACH v_function IN ARRAY v_internal_trigger_functions LOOP
    IF has_function_privilege('anon', v_function, 'EXECUTE')
       OR has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Internal trigger function is directly executable by API roles: %', v_function;
    END IF;
  END LOOP;
END
$$;

INSERT INTO auth.users (id, raw_user_meta_data) VALUES
  ('10000000-0000-4000-8000-000000000001', '{"full_name":"Kasbeman Test Owner"}'),
  ('10000000-0000-4000-8000-000000000002', '{"full_name":"Kasbeman Test Branch Member"}'),
  ('10000000-0000-4000-8000-000000000003', '{"full_name":"Kasbeman Test Unrelated User"}'),
  ('10000000-0000-4000-8000-000000000004', '{"full_name":"Kasbeman Test Assignment Target"}'),
  ('10000000-0000-4000-8000-000000000005', '{"full_name":"Kasbeman Test Invite Recipient"}'),
  ('10000000-0000-4000-8000-000000000006', '{"full_name":"Kasbeman Test Wrong Invite Recipient"}');

-- The business bootstrap RPC must reject missing authentication and malformed input
-- before creating any tenant rows. This endpoint intentionally remains available
-- to authenticated users, but is never callable by anon/PUBLIC (checked above).
RESET ROLE;
SET ROLE authenticated;
RESET request.jwt.claim.sub;

DO $create_business_auth_guard$
BEGIN
  BEGIN
    PERFORM public.create_business('بدون نشست', 'kasbeman-ci-no-session');
    RAISE EXCEPTION 'create_business accepted a request without auth.uid()';
  EXCEPTION WHEN SQLSTATE '28000' THEN
    NULL;
  END;
END
$create_business_auth_guard$;

SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

DO $create_business_input_guard$
BEGIN
  BEGIN
    PERFORM public.create_business('x', 'kasbeman-ci-short-name');
    RAISE EXCEPTION 'create_business accepted a too-short business name';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM public.create_business('نام معتبر', 'INVALID SLUG!');
    RAISE EXCEPTION 'create_business accepted a malformed slug';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM public.businesses
    WHERE slug IN ('kasbeman-ci-no-session', 'kasbeman-ci-short-name')
  ) THEN
    RAISE EXCEPTION 'Rejected create_business requests left tenant rows behind';
  END IF;
END
$create_business_input_guard$;

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

SELECT public.create_business('کسب‌وکار آزمایشی', 'kasbeman-ci-tenant') AS business_id \gset
SELECT id AS branch_id FROM public.branches WHERE business_id = :'business_id'::uuid AND is_primary \gset
SELECT id AS warehouse_id FROM public.warehouses WHERE business_id = :'business_id'::uuid AND is_default \gset

-- A separate authenticated user owns a second tenant; later assertions verify
-- that neither tenant can read or cross-link the other's rows.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
SELECT public.create_business('کسب‌وکار دوم آزمایشی', 'kasbeman-ci-other-tenant') AS other_business_id \gset
SELECT id AS other_branch_id
FROM public.branches
WHERE business_id = :'other_business_id'::uuid AND is_primary \gset
INSERT INTO public.products
  (business_id, name, product_type, sale_price, purchase_price, created_by)
VALUES
  (:'other_business_id'::uuid, 'کالای مستأجر دوم', 'goods', 15, 7, auth.uid())
RETURNING id AS other_product_id \gset
SELECT set_config('kasbeman.test_other_business_id', :'other_business_id', false);
SELECT set_config('kasbeman.test_other_branch_id', :'other_branch_id', false);
SELECT set_config('kasbeman.test_other_product_id', :'other_product_id', false);

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.customers (business_id, name, created_by)
VALUES (:'business_id'::uuid, 'مشتری آزمایشی', auth.uid())
RETURNING id AS customer_id \gset

INSERT INTO public.products (business_id, name, product_type, sale_price, purchase_price, created_by)
VALUES (:'business_id'::uuid, 'کالای آزمایشی', 'goods', 25, 10, auth.uid())
RETURNING id AS product_id \gset

INSERT INTO public.stock_movements (
  business_id, movement_type, product_id, quantity,
  to_branch_id, to_warehouse_id, created_by, note
) VALUES (
  :'business_id'::uuid, 'in', :'product_id'::uuid, 10,
  :'branch_id'::uuid, :'warehouse_id'::uuid, auth.uid(), 'CI seed stock'
);

INSERT INTO public.branches (business_id, name, code)
VALUES (:'business_id'::uuid, 'شعبه دوم', 'BR-02')
RETURNING id AS second_branch_id \gset
SELECT id AS second_warehouse_id
FROM public.warehouses
WHERE business_id = :'business_id'::uuid
  AND branch_id = :'second_branch_id'::uuid
  AND is_default \gset

INSERT INTO public.stock_movements (
  business_id, movement_type, product_id, quantity,
  to_branch_id, to_warehouse_id, created_by, note
) VALUES (
  :'business_id'::uuid, 'in', :'product_id'::uuid, 4,
  :'second_branch_id'::uuid, :'second_warehouse_id'::uuid, auth.uid(), 'CI branch scope seed'
);

RESET ROLE;
INSERT INTO public.business_members (business_id, user_id, role_key, status)
VALUES
  (:'business_id'::uuid, '10000000-0000-4000-8000-000000000002', 'member', 'active'),
  (:'business_id'::uuid, '10000000-0000-4000-8000-000000000004', 'member', 'active');

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'branch-stock-reader', 'مشاهده‌گر انبار شعبه دوم',
        'Branch-scoped stock read role for CI', false, auth.uid())
RETURNING id AS branch_reader_role_id \gset

INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
  (:'business_id'::uuid, :'branch_reader_role_id'::uuid, 'inventory.stock.read'),
  (:'business_id'::uuid, :'branch_reader_role_id'::uuid, 'inventory.items.read');

INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000002',
  :'branch_reader_role_id'::uuid,
  :'second_branch_id'::uuid,
  'active',
  auth.uid()
);

-- Item catalogue visibility is business-wide; stock visibility remains branch-scoped.
INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'global-item-reader', 'مشاهده‌گر کالاها',
        'Business-wide item read role for CI', false, auth.uid())
RETURNING id AS item_reader_role_id \gset

INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'item_reader_role_id'::uuid, 'inventory.items.read');

INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000002',
  :'item_reader_role_id'::uuid,
  NULL,
  'active',
  auth.uid()
);

-- CRM read access is independent from financial and sales access.
INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'customer-reader', 'مشاهده‌گر مشتریان',
        'CRM read-only role for CI', false, auth.uid())
RETURNING id AS customer_reader_role_id \gset

INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'customer_reader_role_id'::uuid, 'crm.customers.read');

INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000002',
  :'customer_reader_role_id'::uuid,
  NULL,
  'active',
  auth.uid()
);

-- A customer editor may update profile fields, but cannot archive or restore records.
INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'customer-editor', 'ویرایشگر مشتریان',
        'Can edit CRM profile fields but cannot archive customers', false, auth.uid())
RETURNING id AS customer_editor_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
  (:'business_id'::uuid, :'customer_editor_role_id'::uuid, 'crm.customers.read'),
  (:'business_id'::uuid, :'customer_editor_role_id'::uuid, 'crm.customers.update');
INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000004',
  :'customer_editor_role_id'::uuid,
  NULL,
  'active',
  auth.uid()
);

-- Sales read-only access must not imply draft editing, confirmation, or deletion.
INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'sales-reader', 'مشاهده‌گر فروش',
        'Read-only sales access for CI', false, auth.uid())
RETURNING id AS sales_reader_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'sales_reader_role_id'::uuid, 'sales.invoices.read');
INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000004',
  :'sales_reader_role_id'::uuid,
  NULL,
  'active',
  auth.uid()
);

-- A limited role assigner may delegate only permissions they personally hold.
INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'limited-role-assigner', 'تخصیص‌دهنده محدود',
        'Can assign roles, but has no finance permissions', false, auth.uid())
RETURNING id AS limited_assigner_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'limited_assigner_role_id'::uuid, 'team.roles.assign');
INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000002',
  :'limited_assigner_role_id'::uuid,
  NULL,
  'active',
  auth.uid()
);

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'target-stock-reader', 'مشاهده‌گر موجودی هدف',
        'Branch-only stock reader for assignment regression test', false, auth.uid())
RETURNING id AS target_stock_role_id \gset
INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'target_stock_role_id'::uuid, 'inventory.stock.read');
SELECT id AS admin_role_id
FROM public.roles
WHERE business_id = :'business_id'::uuid AND role_key = 'admin' \gset
SELECT set_config('kasbeman.test_admin_role_id', :'admin_role_id', false);

SELECT set_config('kasbeman.test_business_id', :'business_id', false);
SELECT set_config('kasbeman.test_branch_id', :'branch_id', false);
SELECT set_config('kasbeman.test_warehouse_id', :'warehouse_id', false);
SELECT set_config('kasbeman.test_second_branch_id', :'second_branch_id', false);
SELECT set_config('kasbeman.test_second_warehouse_id', :'second_warehouse_id', false);
SELECT set_config('kasbeman.test_product_id', :'product_id', false);
SELECT set_config('kasbeman.test_customer_id', :'customer_id', false);

DO $$
BEGIN
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 10 THEN
    RAISE EXCEPTION 'Inbound movement did not increase stock';
  END IF;
END
$$;

SELECT public.create_sale_draft(
  :'business_id'::uuid,
  :'branch_id'::uuid,
  :'warehouse_id'::uuid,
  'CI-SALE-001',
  jsonb_build_array(jsonb_build_object(
    'product_id', :'product_id'::uuid,
    'quantity', 2,
    'discount_amount', 0,
    'tax_amount', 0
  )),
  :'customer_id'::uuid,
  NULL,
  'PostgreSQL CI smoke test'
) AS sale_id \gset

SELECT public.confirm_sale(:'sale_id'::uuid);
SELECT set_config('kasbeman.test_sale_id', :'sale_id', false);

-- Re-confirming a confirmed sale must fail without a second stock deduction.
DO $$
BEGIN
  BEGIN
    PERFORM public.confirm_sale(current_setting('kasbeman.test_sale_id')::uuid);
    RAISE EXCEPTION 'Confirmed sale was processed twice';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END
$$;
SELECT public.record_customer_receipt(
  :'sale_id'::uuid, 50, 'cash', '30000000-0000-4000-8000-000000000001'
) AS receipt_id \gset
SELECT set_config('kasbeman.test_receipt_id', :'receipt_id', false);
SELECT set_config('kasbeman.test_receipt_key', '30000000-0000-4000-8000-000000000001', false);
SELECT public.record_customer_receipt(
  :'sale_id'::uuid, 50, 'cash', '30000000-0000-4000-8000-000000000001'
) AS duplicate_receipt_id \gset
SELECT set_config('kasbeman.test_duplicate_receipt_id', :'duplicate_receipt_id', false);

DO $$
BEGIN
  IF current_setting('kasbeman.test_receipt_id') <>
     current_setting('kasbeman.test_duplicate_receipt_id') THEN
    RAISE EXCEPTION 'Retry returned a different receipt id';
  END IF;
  IF (SELECT count(*) FROM public.customer_receipts
      WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 1 THEN
    RAISE EXCEPTION 'Idempotent retry inserted a duplicate receipt';
  END IF;
  IF (SELECT total_received FROM public.customer_invoice_balance_summary
      WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 50 THEN
    RAISE EXCEPTION 'Idempotent retry changed the received total';
  END IF;
END
$$;

DO $$
BEGIN
  BEGIN
    PERFORM public.record_customer_receipt(
      current_setting('kasbeman.test_sale_id')::uuid,
      25,
      'cash',
      current_setting('kasbeman.test_receipt_key')::uuid
    );
    RAISE EXCEPTION 'Idempotency key accepted a different request payload';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  IF (SELECT count(*) FROM public.customer_receipts
      WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 1 THEN
    RAISE EXCEPTION 'Mismatched idempotency retry changed receipt count';
  END IF;
END
$$;

SELECT set_config('kasbeman.test_sale_id', :'sale_id', false);

DO $$
BEGIN
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 8 THEN
    RAISE EXCEPTION 'Stock confirmation did not deduct the expected quantity';
  END IF;
  IF (SELECT total_received FROM public.customer_invoice_balance_summary
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 50 THEN
    RAISE EXCEPTION 'Receipt was not reflected in the invoice balance summary';
  END IF;
END
$$;

SELECT public.reverse_customer_receipt(:'receipt_id'::uuid, 'CI reversal test');

-- A receipt can have only one immutable reversal record.
DO $$
BEGIN
  BEGIN
    PERFORM public.reverse_customer_receipt(current_setting('kasbeman.test_receipt_id')::uuid, 'Duplicate reversal must fail');
    RAISE EXCEPTION 'Receipt reversal was accepted twice';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END
$$;

-- Transfer stock between branches as one atomic movement.
INSERT INTO public.stock_movements (
  business_id, movement_type, product_id, quantity,
  from_branch_id, from_warehouse_id, to_branch_id, to_warehouse_id,
  reference_type, reference_id, created_by, note
) VALUES (
  :'business_id'::uuid, 'transfer', :'product_id'::uuid, 3,
  :'branch_id'::uuid, :'warehouse_id'::uuid,
  :'second_branch_id'::uuid, :'second_warehouse_id'::uuid,
  'ci_transfer', '20000000-0000-4000-8000-000000000001',
  auth.uid(), 'CI inter-branch transfer'
);

DO $$
BEGIN
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 5 THEN
    RAISE EXCEPTION 'Transfer did not deduct source warehouse stock';
  END IF;
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_second_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 7 THEN
    RAISE EXCEPTION 'Transfer did not add destination warehouse stock';
  END IF;
END
$$;

-- Replaying the same reference must not apply the transfer a second time.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.stock_movements (
      business_id, movement_type, product_id, quantity,
      from_branch_id, from_warehouse_id, to_branch_id, to_warehouse_id,
      reference_type, reference_id, created_by, note
    ) VALUES (
      current_setting('kasbeman.test_business_id')::uuid, 'transfer', current_setting('kasbeman.test_product_id')::uuid, 3,
      current_setting('kasbeman.test_branch_id')::uuid, current_setting('kasbeman.test_warehouse_id')::uuid,
      current_setting('kasbeman.test_second_branch_id')::uuid, current_setting('kasbeman.test_second_warehouse_id')::uuid,
      'ci_transfer', '20000000-0000-4000-8000-000000000001',
      auth.uid(), 'duplicate CI transfer'
    );
    RAISE EXCEPTION 'Duplicate stock transfer reference was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END
$$;

DO $$
BEGIN
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 5
     OR
     (SELECT quantity_on_hand FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_second_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 7 THEN
    RAISE EXCEPTION 'Duplicate transfer changed warehouse balances';
  END IF;
END
$$;

DO $$
BEGIN
  IF (SELECT total_received FROM public.customer_invoice_balance_summary
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 0 THEN
    RAISE EXCEPTION 'Receipt reversal was not reflected in the invoice balance summary';
  END IF;
  IF (SELECT balance_due FROM public.customer_invoice_balance_summary
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND sale_id = current_setting('kasbeman.test_sale_id')::uuid) <> 50 THEN
    RAISE EXCEPTION 'Invoice balance was not restored after receipt reversal';
  END IF;
END
$$;

SELECT public.create_sale_draft(
  :'business_id'::uuid,
  :'branch_id'::uuid,
  :'warehouse_id'::uuid,
  'CI-SALE-002',
  jsonb_build_array(jsonb_build_object(
    'product_id', :'product_id'::uuid,
    'quantity', 9,
    'discount_amount', 0,
    'tax_amount', 0
  )),
  :'customer_id'::uuid,
  NULL,
  'Insufficient stock rollback test'
) AS insufficient_sale_id \gset
SELECT set_config('kasbeman.test_insufficient_sale_id', :'insufficient_sale_id', false);

DO $$
BEGIN
  BEGIN
    PERFORM public.confirm_sale(current_setting('kasbeman.test_insufficient_sale_id')::uuid);
    RAISE EXCEPTION 'Expected insufficient stock confirmation to fail';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  IF (SELECT status FROM public.sales
      WHERE id = current_setting('kasbeman.test_insufficient_sale_id')::uuid) <> 'draft' THEN
    RAISE EXCEPTION 'Failed sale confirmation did not roll back sale status';
  END IF;
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
        AND warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 5 THEN
    RAISE EXCEPTION 'Failed sale confirmation changed stock balance';
  END IF;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

-- A branch-limited assignment within the actor's own permissions is allowed.
INSERT INTO public.member_role_assignments
  (business_id, user_id, role_id, branch_id, status, assigned_by)
VALUES (
  :'business_id'::uuid,
  '10000000-0000-4000-8000-000000000004',
  :'target_stock_role_id'::uuid,
  :'second_branch_id'::uuid,
  'active',
  auth.uid()
);

-- The same actor must not be able to delegate the broader system admin role.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.member_role_assignments
      (business_id, user_id, role_id, branch_id, status, assigned_by)
    VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000004',
      current_setting('kasbeman.test_admin_role_id')::uuid,
      NULL,
      'active',
      auth.uid()
    );
    RAISE EXCEPTION 'Limited role assigner escalated a target member to admin';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

DO $$
BEGIN
  IF (SELECT count(*) FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_second_warehouse_id')::uuid) <> 1 THEN
    RAISE EXCEPTION 'Branch-scoped stock reader cannot see assigned branch stock';
  END IF;
  IF EXISTS (SELECT 1 FROM public.stock_balances
      WHERE warehouse_id = current_setting('kasbeman.test_warehouse_id')::uuid) THEN
    RAISE EXCEPTION 'Branch-scoped stock reader can see stock from an unassigned branch';
  END IF;
  IF EXISTS (SELECT 1 FROM public.sales) THEN
    RAISE EXCEPTION 'Member without sales.invoices.read can see sales';
  END IF;
  IF (SELECT count(*) FROM public.products
      WHERE id = current_setting('kasbeman.test_product_id')::uuid) <> 1 THEN
    RAISE EXCEPTION 'inventory.items.read did not grant business-wide product visibility';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE name = 'مشتری آزمایشی') THEN
    RAISE EXCEPTION 'crm.customers.read did not grant customer visibility';
  END IF;

  UPDATE public.customers
  SET name = 'ویرایش غیرمجاز توسط مشاهده‌گر'
  WHERE id = current_setting('kasbeman.test_customer_id')::uuid;
  IF FOUND THEN
    RAISE EXCEPTION 'CRM read-only role unexpectedly updated a customer';
  END IF;
END
$permission_enforcement_test$;

DO $permission_enforcement_test$
BEGIN
  BEGIN
    INSERT INTO public.customers (business_id, name, created_by)
    VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      'Unauthorized customer creation',
      auth.uid()
    );
    RAISE EXCEPTION 'CRM read-only role unexpectedly created a customer';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.products (
      business_id, name, product_type, sale_price, purchase_price, created_by
    ) VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      'Unauthorized product creation', 'goods', 10, 5, auth.uid()
    );
    RAISE EXCEPTION 'Item read-only role unexpectedly created a product';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.stock_movements (
      business_id, movement_type, product_id, quantity,
      to_branch_id, to_warehouse_id, created_by, note
    ) VALUES (
      current_setting('kasbeman.test_business_id')::uuid, 'in',
      current_setting('kasbeman.test_product_id')::uuid, 1,
      current_setting('kasbeman.test_second_branch_id')::uuid,
      current_setting('kasbeman.test_second_warehouse_id')::uuid,
      auth.uid(), 'must be denied: read-only role'
    );
    RAISE EXCEPTION 'Read-only branch role unexpectedly inserted a stock movement';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';

DO $permission_enforcement_test$
BEGIN
  UPDATE public.customers
  SET name = 'مشتری ویرایش‌شده توسط ویرایشگر'
  WHERE id = current_setting('kasbeman.test_customer_id')::uuid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer editor could not update allowed profile fields';
  END IF;

  BEGIN
    UPDATE public.customers SET status = 'archived'
    WHERE id = current_setting('kasbeman.test_customer_id')::uuid;
    RAISE EXCEPTION 'Customer editor archived a customer without delete permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF (SELECT status FROM public.customers
      WHERE id = current_setting('kasbeman.test_customer_id')::uuid) <> 'active' THEN
    RAISE EXCEPTION 'Denied customer archive changed the persisted status';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.sales) THEN
    RAISE EXCEPTION 'sales.invoices.read did not grant sales visibility';
  END IF;

  UPDATE public.sales SET notes = 'unauthorized draft edit'
  WHERE id = current_setting('kasbeman.test_insufficient_sale_id')::uuid;
  IF FOUND THEN
    RAISE EXCEPTION 'Sales read-only role unexpectedly updated a draft sale';
  END IF;

  BEGIN
    DELETE FROM public.sales
    WHERE id = current_setting('kasbeman.test_insufficient_sale_id')::uuid;
    RAISE EXCEPTION 'Sales read-only role unexpectedly deleted a sale';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.confirm_sale(
      current_setting('kasbeman.test_insufficient_sale_id')::uuid
    );
    RAISE EXCEPTION 'Sales read-only role unexpectedly confirmed a sale';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$permission_enforcement_test$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';


-- Finance-only receipt data must not be readable by stock-only or CRM-only members.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.customer_receipts
    WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid
  ) THEN
    RAISE EXCEPTION 'Member without finance.payments.read can see customer receipts';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.customer_invoice_balance_summary
    WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid
  ) THEN
    RAISE EXCEPTION 'Member without finance.payments.read can see invoice payment balances';
  END IF;
  BEGIN
    PERFORM public.record_customer_receipt(
      current_setting('kasbeman.test_sale_id')::uuid,
      1,
      'cash',
      '40000000-0000-4000-8000-000000000001'
    );
    RAISE EXCEPTION 'Member without finance.payments.manage recorded a receipt';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.confirm_sale(
      current_setting('kasbeman.test_insufficient_sale_id')::uuid
    );
    RAISE EXCEPTION 'Member without sales.invoices.manage confirmed a sale';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.create_sale_draft(
      current_setting('kasbeman.test_business_id')::uuid,
      current_setting('kasbeman.test_second_branch_id')::uuid,
      current_setting('kasbeman.test_second_warehouse_id')::uuid,
      'CI-DENIED-SALE-001',
      jsonb_build_array(jsonb_build_object(
        'product_id', current_setting('kasbeman.test_product_id')::uuid,
        'quantity', 1,
        'discount_amount', 0,
        'tax_amount', 0
      )),
      NULL,
      NULL,
      'Must be denied to a stock-only role'
    );
    RAISE EXCEPTION 'Member without sales.invoices.manage created a sale';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.reverse_customer_receipt(
      current_setting('kasbeman.test_receipt_id')::uuid,
      'Unauthorized reversal test'
    );
    RAISE EXCEPTION 'Member without finance.payments.manage reversed a receipt';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.businesses WHERE slug = 'kasbeman-ci-tenant') THEN
    RAISE EXCEPTION 'Active tenant member cannot see the business';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE name = 'مشتری آزمایشی') THEN
    RAISE EXCEPTION 'CRM reader cannot see an authorized customer';
  END IF;
  IF EXISTS (SELECT 1 FROM public.customer_receipts
      WHERE sale_id = current_setting('kasbeman.test_sale_id')::uuid) THEN
    RAISE EXCEPTION 'CRM reader can see financial receipts without finance permission';
  END IF;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

DO $$
DECLARE
  v_business_id uuid := current_setting('kasbeman.test_business_id')::uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.businesses
    WHERE id = current_setting('kasbeman.test_other_business_id')::uuid
  ) THEN
    RAISE EXCEPTION 'User cannot see their own tenant';
  END IF;
  IF EXISTS (SELECT 1 FROM public.businesses WHERE id = v_business_id) THEN
    RAISE EXCEPTION 'User can see another tenant business';
  END IF;
  IF EXISTS (SELECT 1 FROM public.business_members WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.branches WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.business_invitations WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.roles WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.role_permissions WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.member_role_assignments WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.customers WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.products WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.warehouses WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.stock_balances WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.stock_movements WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.sales WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.sale_items WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.customer_receipts WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.customer_receipt_reversals WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.customer_invoice_balance_summary WHERE business_id = v_business_id)
     OR EXISTS (SELECT 1 FROM public.customer_purchase_summary WHERE business_id = v_business_id) THEN
    RAISE EXCEPTION 'User can see rows belonging to another tenant';
  END IF;
END
$$;

RESET ROLE;

-- Composite tenant foreign keys must reject cross-tenant branch and product links.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.warehouses
      (business_id, branch_id, name, code, created_by)
    VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      current_setting('kasbeman.test_other_branch_id')::uuid,
      'Cross-tenant warehouse', 'X-TENANT', '10000000-0000-4000-8000-000000000001'
    );
    RAISE EXCEPTION 'Warehouse accepted a branch from another tenant';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END
$$;

SELECT 'PostgreSQL 17: RLS enabled on all public tables, no anon table grants, invoker-safe views, tenant isolation across all business tables, scoped role delegation, cross-tenant foreign keys, sales/inventory, receipts and concurrency protections passed.' AS result;
