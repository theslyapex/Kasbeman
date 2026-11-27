\set ON_ERROR_STOP on

INSERT INTO auth.users (id, raw_user_meta_data) VALUES
  ('10000000-0000-4000-8000-000000000001', '{"full_name":"Kasbeman Test Owner"}'),
  ('10000000-0000-4000-8000-000000000002', '{"full_name":"Kasbeman Test Outsider"}');

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
SELECT public.record_customer_receipt(:'sale_id'::uuid, 50, 'cash') AS receipt_id \gset

SELECT set_config('kasbeman.test_business_id', :'business_id', false);
SELECT set_config('kasbeman.test_warehouse_id', :'warehouse_id', false);
SELECT set_config('kasbeman.test_product_id', :'product_id', false);
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
$;

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
) AS insufficient_sale_id \\gset
SELECT set_config('kasbeman.test_insufficient_sale_id', :'insufficient_sale_id', false);

DO $
BEGIN
  BEGIN
    PERFORM public.confirm_sale(current_setting('kasbeman.test_insufficient_sale_id')::uuid);
    RAISE EXCEPTION 'Expected insufficient stock confirmation to fail';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
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
$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.businesses WHERE slug = 'kasbeman-ci-tenant') THEN
    RAISE EXCEPTION 'Tenant isolation failed: unrelated user can see another business';
  END IF;
  IF EXISTS (SELECT 1 FROM public.customers WHERE name = 'مشتری آزمایشی') THEN
    RAISE EXCEPTION 'Tenant isolation failed: unrelated user can see another tenant customer';
  END IF;
END
$$;

RESET ROLE;
SELECT 'PostgreSQL schema, sales, stock, receipts, reversals, and tenant-isolation tests passed.' AS result;
