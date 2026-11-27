\set ON_ERROR_STOP on

INSERT INTO auth.users (id, raw_user_meta_data) VALUES
  ('10000000-0000-4000-8000-000000000001', '{"full_name":"Kasbeman Test Owner"}'),
  ('10000000-0000-4000-8000-000000000002', '{"full_name":"Kasbeman Test Branch Member"}'),
  ('10000000-0000-4000-8000-000000000003', '{"full_name":"Kasbeman Test Unrelated User"}');

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

SELECT public.create_business('کسب‌وکار آزمایشی', 'kasbeman-ci-tenant') AS business_id \gset
SELECT id AS branch_id FROM public.branches WHERE business_id = :'business_id'::uuid AND is_primary \gset
SELECT id AS warehouse_id FROM public.warehouses WHERE business_id = :'business_id'::uuid AND is_default \gset

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
VALUES (:'business_id'::uuid, '10000000-0000-4000-8000-000000000002', 'member', 'active');

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.roles (business_id, role_key, name, description, is_system, created_by)
VALUES (:'business_id'::uuid, 'branch-stock-reader', 'مشاهده‌گر انبار شعبه دوم',
        'Branch-scoped stock read role for CI', false, auth.uid())
RETURNING id AS branch_reader_role_id \gset

INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES (:'business_id'::uuid, :'branch_reader_role_id'::uuid, 'inventory.stock.read');

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

SELECT set_config('kasbeman.test_business_id', :'business_id', false);
SELECT set_config('kasbeman.test_branch_id', :'branch_id', false);
SELECT set_config('kasbeman.test_warehouse_id', :'warehouse_id', false);
SELECT set_config('kasbeman.test_second_branch_id', :'second_branch_id', false);
SELECT set_config('kasbeman.test_second_warehouse_id', :'second_warehouse_id', false);
SELECT set_config('kasbeman.test_product_id', :'product_id', false);

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
SELECT public.record_customer_receipt(:'sale_id'::uuid, 50, 'cash') AS receipt_id \gset
SELECT set_config('kasbeman.test_receipt_id', :'receipt_id', false);
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
        AND product_id = current_setting('kasbeman.test_product_id')::uuid) <> 8 THEN
    RAISE EXCEPTION 'Failed sale confirmation changed stock balance';
  END IF;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

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
    RAISE EXCEPTION 'Stock-only role can see sales without sales.orders.read';
  END IF;
END
$$;

DO $$
BEGIN
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
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.businesses WHERE slug = 'kasbeman-ci-tenant') THEN
    RAISE EXCEPTION 'Active tenant member cannot see the business';
  END IF;
  IF EXISTS (SELECT 1 FROM public.customers WHERE name = 'مشتری آزمایشی') THEN
    RAISE EXCEPTION 'Branch-only member can see customers without CRM permission';
  END IF;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.businesses WHERE slug = 'kasbeman-ci-tenant') THEN
    RAISE EXCEPTION 'Unrelated user can see another tenant business';
  END IF;
  IF EXISTS (SELECT 1 FROM public.customers WHERE name = 'مشتری آزمایشی') THEN
    RAISE EXCEPTION 'Unrelated user can see another tenant customer';
  END IF;
END
$$;

RESET ROLE;
SELECT 'PostgreSQL 17: schema, sales, idempotent confirmation, stock transfers, duplicate-transfer protection, receipts, duplicate-reversal protection, insufficient-stock rollback, branch-scoped RBAC, read-only enforcement, and cross-tenant isolation passed.' AS result;
