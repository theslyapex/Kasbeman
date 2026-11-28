-- Exercises the configurable per-account business-creation throttle.
-- Run after sales-inventory-smoke.sql has created the CI Auth users.

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';

DO $business_creation_rate_limit$
DECLARE
  v_business_id uuid;
  v_attempt integer;
  v_created_count integer;
BEGIN
  FOR v_attempt IN 1..5 LOOP
    v_business_id := public.create_business(
      'آزمایش محدودیت ' || v_attempt,
      'kasbeman-ci-rate-limit-' || v_attempt
    );
    IF v_business_id IS NULL THEN
      RAISE EXCEPTION 'Business creation was rate-limited before the configured maximum';
    END IF;
  END LOOP;

  v_business_id := public.create_business(
    'ساخت بیش از حد مجاز',
    'kasbeman-ci-rate-limit-blocked'
  );
  IF v_business_id IS NOT NULL THEN
    RAISE EXCEPTION 'Business creation was not rate-limited after five attempts';
  END IF;

  SELECT count(*) INTO v_created_count
  FROM public.businesses
  WHERE created_by = auth.uid()
    AND slug LIKE 'kasbeman-ci-rate-limit-%';

  IF v_created_count <> 5 THEN
    RAISE EXCEPTION 'Expected five created businesses, found %', v_created_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.businesses
    WHERE slug = 'kasbeman-ci-rate-limit-blocked'
  ) THEN
    RAISE EXCEPTION 'Rate-limited request created a business row';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.operation_rate_limit_counters
    WHERE user_id = auth.uid()
      AND operation_key = 'business.create'
      AND attempt_count = 6
  ) THEN
    RAISE EXCEPTION 'Rate-limit counter did not persist the blocked attempt';
  END IF;
END
$business_creation_rate_limit$;

RESET ROLE;

DO $business_rate_limit_acl$
BEGIN
  IF has_table_privilege('anon', 'private.operation_rate_limit_policies', 'SELECT')
     OR has_table_privilege('authenticated', 'private.operation_rate_limit_policies', 'SELECT')
     OR has_table_privilege('anon', 'private.operation_rate_limit_counters', 'SELECT')
     OR has_table_privilege('authenticated', 'private.operation_rate_limit_counters', 'SELECT') THEN
    RAISE EXCEPTION 'API roles can directly read private rate-limit tables';
  END IF;

  IF has_function_privilege('anon', 'private.consume_operation_rate_limit(text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.consume_operation_rate_limit(text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'API roles can directly execute the internal rate-limit helper';
  END IF;

  IF NOT (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'private.operation_rate_limit_counters'::regclass
  ) OR NOT (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'private.operation_rate_limit_policies'::regclass
  ) THEN
    RAISE EXCEPTION 'Private rate-limit tables must have RLS enabled';
  END IF;
END
$business_rate_limit_acl$;

-- Expire the active window as the database owner, then verify the account can retry.
UPDATE private.operation_rate_limit_counters
SET window_started_at = clock_timestamp() - interval '11 minutes',
    attempt_count = 5,
    updated_at = clock_timestamp()
WHERE user_id = '10000000-0000-4000-8000-000000000006'
  AND operation_key = 'business.create';

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';

DO $business_rate_limit_window_reset$
DECLARE
  v_business_id uuid;
BEGIN
  v_business_id := public.create_business(
    'پس از پایان بازه',
    'kasbeman-ci-rate-limit-window-reset'
  );
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business creation did not resume after the rate-limit window expired';
  END IF;
END
$business_rate_limit_window_reset$;

RESET ROLE;
