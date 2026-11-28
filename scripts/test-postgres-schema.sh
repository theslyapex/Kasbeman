#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap-supabase-auth.sql
psql -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261127081007_identity_tenancy_foundation.sql \
  -f supabase/migrations/20261127085000_rbac_authorization_foundation.sql \
  -f supabase/migrations/20261128080751_rbac_role_assignment_hardening.sql \
  -f supabase/migrations/20261128080753_membership_invitation_ownership_hardening.sql \
  -f supabase/migrations/20261128085653_add_missing_fk_indexes.sql \
  -f supabase/migrations/20261128093200_business_creation_rate_limit.sql \
  -f supabase/drafts/sales_inventory_core.sql \
  -f supabase/tests/sales-inventory-smoke.sql \
  -f supabase/tests/business-creation-rate-limit-smoke.sql \
  -f supabase/tests/membership-invitation-smoke.sql \
  -f supabase/tests/fk-index-smoke.sql
