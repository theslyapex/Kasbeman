#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap-supabase-auth.sql
psql -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261127080500_identity_tenancy_foundation.sql \
  -f supabase/migrations/20261127083000_rbac_authorization_foundation.sql \
  -f supabase/drafts/sales_inventory_core.sql \
  -f supabase/tests/sales-inventory-smoke.sql
