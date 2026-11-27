#!/usr/bin/env bash
set -euo pipefail

: "${PGDATABASE:?PGDATABASE is required}"
: "${PGUSER:?PGUSER is required}"

owner_id="10000000-0000-4000-8000-000000000001"
receipt_key="40000000-0000-4000-8000-000000000001"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

business_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.businesses WHERE slug = 'kasbeman-ci-tenant'")"
branch_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.branches WHERE business_id = '$business_id' AND is_primary")"
warehouse_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.warehouses WHERE business_id = '$business_id' AND branch_id = '$branch_id' AND is_default")"
second_branch_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.branches WHERE business_id = '$business_id' AND code = 'BR-02'")"
second_warehouse_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.warehouses WHERE business_id = '$business_id' AND branch_id = '$second_branch_id' AND is_default")"
product_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.products WHERE business_id = '$business_id' AND name = 'کالای آزمایشی'")"
customer_id="$(psql -X -v ON_ERROR_STOP=1 -Atq -c "SELECT id FROM public.customers WHERE business_id = '$business_id' AND name = 'مشتری آزمایشی'")"

for value in "$business_id" "$branch_id" "$warehouse_id" "$second_branch_id" "$second_warehouse_id" "$product_id" "$customer_id"; do
  if [[ -z "$value" ]]; then
    echo "Concurrency fixture lookup failed" >&2
    exit 1
  fi
done

create_sale() {
  local sale_number="$1"
  psql -X -v ON_ERROR_STOP=1 -Atq <<SQL
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
SELECT public.create_sale_draft(
  '$business_id'::uuid,
  '$branch_id'::uuid,
  '$warehouse_id'::uuid,
  '$sale_number',
  jsonb_build_array(jsonb_build_object(
    'product_id', '$product_id'::uuid,
    'quantity', 4,
    'discount_amount', 0,
    'tax_amount', 0
  )),
  '$customer_id'::uuid,
  NULL,
  'Concurrent PostgreSQL CI test'
);
RESET ROLE;
SQL
}

sale_a="$(create_sale 'CI-CONCURRENT-SALE-A')"
sale_b="$(create_sale 'CI-CONCURRENT-SALE-B')"

wait_until_sleeping() {
  local app_name="$1"
  for _ in $(seq 1 120); do
    if psql -X -Atq -c "SELECT 1 FROM pg_stat_activity WHERE application_name = '$app_name' AND state = 'active' AND query LIKE '%pg_sleep(2)%' LIMIT 1" | grep -q '^1$'; then
      return 0
    fi
    sleep 0.1
  done
  echo "Timed out waiting for $app_name to reach the concurrency barrier" >&2
  return 1
}

# Two separate sessions confirm sales that each need four units from five.
# Session A owns the balance row first; session B must re-check after A commits.
PGAPPNAME=kasbeman-sale-a psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/sale-a.log" 2>&1 <<SQL &
BEGIN;
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
SELECT 1 FROM public.stock_balances
 WHERE business_id = '$business_id' AND warehouse_id = '$warehouse_id'
   AND product_id = '$product_id' FOR UPDATE;
SELECT public.confirm_sale('$sale_a'::uuid);
SELECT pg_sleep(2);
COMMIT;
SQL
sale_a_pid=$!
wait_until_sleeping "kasbeman-sale-a"

PGAPPNAME=kasbeman-sale-b psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/sale-b.log" 2>&1 <<SQL &
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
DO \$\$
BEGIN
  BEGIN
    PERFORM public.confirm_sale('$sale_b'::uuid);
    RAISE EXCEPTION 'Competing sale unexpectedly consumed unavailable stock';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END
\$\$;
RESET ROLE;
SQL
sale_b_pid=$!
wait "$sale_a_pid"
wait "$sale_b_pid"

psql -X -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF (SELECT status FROM public.sales WHERE id = '$sale_a'::uuid) <> 'confirmed'
     OR (SELECT status FROM public.sales WHERE id = '$sale_b'::uuid) <> 'draft' THEN
    RAISE EXCEPTION 'Concurrent sale confirmation did not produce exactly one confirmed sale';
  END IF;
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = '$business_id'::uuid AND warehouse_id = '$warehouse_id'::uuid
        AND product_id = '$product_id'::uuid) <> 1 THEN
    RAISE EXCEPTION 'Concurrent sales produced an incorrect stock balance';
  END IF;
END
\$\$;
SQL

# Concurrent idempotent receipt retries must return one shared receipt id.
PGAPPNAME=kasbeman-receipt-a psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/receipt-a.log" 2>&1 <<SQL &
BEGIN;
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
SELECT id FROM public.sales WHERE id = '$sale_a'::uuid FOR UPDATE;
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('$business_id:$receipt_key', 0)
);
SELECT public.record_customer_receipt(
  '$sale_a'::uuid, 100, 'cash', '$receipt_key'::uuid
) AS receipt_id \gset
SELECT pg_sleep(2);
SELECT :'receipt_id';
COMMIT;
SQL
receipt_a_pid=$!
wait_until_sleeping "kasbeman-receipt-a"

PGAPPNAME=kasbeman-receipt-b psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/receipt-b.log" 2>&1 <<SQL &
BEGIN;
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
SELECT public.record_customer_receipt(
  '$sale_a'::uuid, 100, 'cash', '$receipt_key'::uuid
);
COMMIT;
SQL
receipt_b_pid=$!
wait "$receipt_a_pid"
wait "$receipt_b_pid"

receipt_a="$(grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$tmp_dir/receipt-a.log" | tail -n 1)"
receipt_b="$(grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$tmp_dir/receipt-b.log" | tail -n 1)"
if [[ -z "$receipt_a" || "$receipt_a" != "$receipt_b" ]]; then
  echo "Concurrent receipt retries did not return the same receipt id" >&2
  cat "$tmp_dir/receipt-a.log" "$tmp_dir/receipt-b.log" >&2
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF (SELECT count(*) FROM public.customer_receipts
      WHERE business_id = '$business_id'::uuid AND idempotency_key = '$receipt_key'::uuid) <> 1 THEN
    RAISE EXCEPTION 'Concurrent receipt retry inserted more than one row';
  END IF;
  IF (SELECT total_received FROM public.customer_invoice_balance_summary
      WHERE sale_id = '$sale_a'::uuid) <> 100 THEN
    RAISE EXCEPTION 'Concurrent receipt retry changed the received total incorrectly';
  END IF;
END
\$\$;
SQL

# Add stock, then race two independent transfers of eight units from thirteen.
psql -X -v ON_ERROR_STOP=1 -q <<SQL
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
INSERT INTO public.stock_movements (
  business_id, movement_type, product_id, quantity,
  to_branch_id, to_warehouse_id, created_by, note
) VALUES (
  '$business_id'::uuid, 'in', '$product_id'::uuid, 12,
  '$branch_id'::uuid, '$warehouse_id'::uuid, auth.uid(), 'Concurrency transfer fixture'
);
RESET ROLE;
SQL

PGAPPNAME=kasbeman-transfer-a psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/transfer-a.log" 2>&1 <<SQL &
BEGIN;
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
SELECT 1 FROM public.stock_balances
 WHERE business_id = '$business_id' AND warehouse_id = '$warehouse_id'
   AND product_id = '$product_id' FOR UPDATE;
INSERT INTO public.stock_movements (
  business_id, movement_type, product_id, quantity,
  from_branch_id, from_warehouse_id, to_branch_id, to_warehouse_id,
  reference_type, reference_id, created_by, note
) VALUES (
  '$business_id'::uuid, 'transfer', '$product_id'::uuid, 8,
  '$branch_id'::uuid, '$warehouse_id'::uuid,
  '$second_branch_id'::uuid, '$second_warehouse_id'::uuid,
  'ci_concurrent_transfer', '50000000-0000-4000-8000-000000000001',
  auth.uid(), 'Concurrent transfer A'
);
SELECT pg_sleep(2);
COMMIT;
SQL
transfer_a_pid=$!
wait_until_sleeping "kasbeman-transfer-a"

PGAPPNAME=kasbeman-transfer-b psql -X -v ON_ERROR_STOP=1 -Atq >"$tmp_dir/transfer-b.log" 2>&1 <<SQL &
SET ROLE authenticated;
SET request.jwt.claim.sub = '$owner_id';
DO \$\$
BEGIN
  BEGIN
    INSERT INTO public.stock_movements (
      business_id, movement_type, product_id, quantity,
      from_branch_id, from_warehouse_id, to_branch_id, to_warehouse_id,
      reference_type, reference_id, created_by, note
    ) VALUES (
      '$business_id'::uuid, 'transfer', '$product_id'::uuid, 8,
      '$branch_id'::uuid, '$warehouse_id'::uuid,
      '$second_branch_id'::uuid, '$second_warehouse_id'::uuid,
      'ci_concurrent_transfer', '50000000-0000-4000-8000-000000000002',
      auth.uid(), 'Concurrent transfer B'
    );
    RAISE EXCEPTION 'Competing transfer unexpectedly consumed unavailable stock';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END
\$\$;
RESET ROLE;
SQL
transfer_b_pid=$!
wait "$transfer_a_pid"
wait "$transfer_b_pid"

psql -X -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = '$business_id'::uuid AND warehouse_id = '$warehouse_id'::uuid
        AND product_id = '$product_id'::uuid) <> 5 THEN
    RAISE EXCEPTION 'Concurrent transfers produced an incorrect source balance';
  END IF;
  IF (SELECT quantity_on_hand FROM public.stock_balances
      WHERE business_id = '$business_id'::uuid AND warehouse_id = '$second_warehouse_id'::uuid
        AND product_id = '$product_id'::uuid) <> 15 THEN
    RAISE EXCEPTION 'Concurrent transfers produced an incorrect destination balance';
  END IF;
  IF (SELECT count(*) FROM public.stock_movements
      WHERE business_id = '$business_id'::uuid
        AND reference_type = 'ci_concurrent_transfer') <> 1 THEN
    RAISE EXCEPTION 'Concurrent transfers inserted an unexpected movement count';
  END IF;
END
\$\$;
SQL

echo "PostgreSQL 17 concurrency tests passed: competing sale confirmations, same-key receipt retries, and competing warehouse transfers."
