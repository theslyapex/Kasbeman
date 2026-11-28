#!/usr/bin/env bash
set -euo pipefail

if [[ "${KASBEMAN_LOCAL_SUPABASE:-0}" != "1" ]]; then
  # Standalone PostgreSQL CI needs a small Auth compatibility shim and applies
  # the reviewed migrations itself. Local Supabase already has real Auth and
  # migrations applied by `supabase db reset`, so it must skip this bootstrap.
  psql -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap-supabase-auth.sql
  psql -v ON_ERROR_STOP=1 \
    -f supabase/migrations/20261127081007_identity_tenancy_foundation.sql \
    -f supabase/migrations/20261127085000_rbac_authorization_foundation.sql \
    -f supabase/migrations/20261128093512_business_creation_rate_limit.sql \
    -f supabase/migrations/20261128093732_rbac_role_assignment_hardening.sql \
    -f supabase/migrations/20261128093746_membership_invitation_ownership_hardening.sql \
    -f supabase/migrations/20261128100000_add_missing_fk_indexes.sql \
    -f supabase/migrations/20261128124155_crm_customer_core.sql \
    -f supabase/migrations/20261128124535_ticketing_core.sql \
    -f supabase/migrations/20261128124834_sales_inventory_core.sql
fi

psql -v ON_ERROR_STOP=1 \
  -f supabase/tests/sales-inventory-smoke.sql \
  -f supabase/tests/crm-customer-smoke.sql \
  -f supabase/tests/ticketing-smoke.sql \
  -f supabase/tests/business-creation-rate-limit-smoke.sql \
  -f supabase/tests/membership-invitation-smoke.sql \
  -f supabase/tests/fk-index-smoke.sql
