# CRM Customer Core — Rollout Notes

## Current state

The customer foundation is isolated in `supabase/drafts/crm_core.sql`. It is a review draft, not a canonical Supabase migration and has not been applied to the hosted production project.

The sales/inventory draft now references the CRM-owned `public.customers` table but no longer creates that table or its policies. Ticketing continues to depend on the customer composite key `customers(business_id, id)`.

## Dependencies

- `public.businesses(id)` from the existing identity/tenancy foundation.
- `auth.users(id)` for the creator reference.
- `private.has_business_permission(uuid, text, uuid)` and the CRM permission catalogue keys from the existing RBAC foundation.
- Existing owner/admin role permission bootstrap already includes the full permission catalogue; default member receives customer read only.

## Security model

- Every customer row has a required `business_id`.
- Unique key `(business_id, id)` supports tenant-scoped foreign keys from future modules.
- RLS gates select, insert and update independently.
- Insert requires `crm.customers.create` and `created_by = auth.uid()`.
- Profile updates require both `crm.customers.read` and `crm.customers.update`.
- Status changes require `crm.customers.delete`; this permission is intentionally reused as archive/restore authority, not a direct DELETE grant.
- The trigger rejects business reassignment and has direct execute revoked from API roles.
- No direct DELETE grant is given to `authenticated` or `anon`.

## Test coverage

- `supabase/tests/crm-customer-smoke.sql`: read-only, create-only, profile editor, archive guard, owner archive, tenant isolation, RLS and trigger ACL.
- `scripts/check-crm-security.mjs`: static schema and permission checks.
- `scripts/test-postgres-schema.sh`: applies the CRM draft before sales/inventory and ticketing drafts on disposable PostgreSQL 17.
- Latest verified code CI: commit `59ec0eb25e85a982e371e9ff41eb58fcbae125f9`; PostgreSQL 17 schema/tenant tests, multi-connection concurrency, vinext, TypeScript, ESLint and production build all passed: https://github.com/theslyapex/Kasbeman/actions/runs/46144849198

## Required production rollout

1. Generate a new canonical migration with the Supabase CLI; do not edit previously applied migrations.
2. Review the generated migration against the exact hosted migration baseline and verify the existing CRM permission keys and helper signatures.
3. Run the full PostgreSQL 17 schema, tenant, permission and concurrency suite against a clean disposable database.
4. Apply to a staging Supabase project and verify authenticated owner/admin/member/editor/create-only behavior through the Data API.
5. Verify the dependent sales/inventory and ticketing migrations are sequenced after CRM and pass their integration tests.
6. Review the complete migration plan and obtain explicit approval before applying anything to production.

Do not create a placeholder customer table, disable RLS, relax composite foreign keys or bypass the permission guard to make downstream modules install.

## Release gate

No CRM migration has been applied to production. No live web/mobile E2E test is available yet. The public deployment remains unconfigured, and `main` remains untouched.
