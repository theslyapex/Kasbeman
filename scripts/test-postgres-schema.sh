#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap-supabase-auth.sql
psql -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261127081007_identity_tenancy_foundation.sql \
  -f supabase/migrations/20261127085000_rbac_authorization_foundation.sql \
  -f supabase/migrations/20261128093512_business_creation_rate_limit.sql \
  -f supabase/migrations/20261128093732_rbac_role_assignment_hardening.sql \
  -f supabase/migrations/20261128093746_membership_invitation_ownership_hardening.sql \
  -f supabase/migrations/20261128100000_add_missing_fk_indexes.sql \
  -f supabase/drafts/crm_core.sql \
  -f supabase/drafts/sales_inventory_core.sql \
  -f supabase/drafts/ticketing_core.sql \
  -f supabase/tests/sales-inventory-smoke.sql \
  -f supabase/tests/crm-customer-smoke.sql \
  -f supabase/tests/ticketing-smoke.sql \
  -f supabase/tests/business-creation-rate-limit-smoke.sql \
  -f supabase/tests/membership-invitation-smoke.sql \
  -f supabase/tests/fk-index-smoke.sql
