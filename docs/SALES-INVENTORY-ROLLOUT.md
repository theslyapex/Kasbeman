# Sales & Inventory Core — Rollout Gate

Date: 2026-11-28  
Status: **Canonical migration, PostgreSQL 17 CI and local Supabase Auth/Data API integration passed; hosted rollout remains gated.**

## Canonical assets

- Reviewed source: `supabase/drafts/sales_inventory_core.sql`
- Canonical migration: `supabase/migrations/20261128124834_sales_inventory_core.sql`
- Smoke tests: `supabase/tests/sales-inventory-smoke.sql`
- Static security checker: `scripts/check-sales-inventory-security.mjs`
- Test runner: `scripts/test-postgres-schema.sh`

The canonical migration was generated using Supabase CLI 3.4.0 and is checked against the reviewed draft by CI. It is not applied to the hosted production project.

## Combined test environment

GitHub Actions starts an ephemeral PostgreSQL 17 service container for each run. The test runner bootstraps the Supabase Auth shim and applies the canonical migrations in dependency order:

1. Identity/tenancy and RBAC foundation
2. Membership and role-assignment hardening
3. CRM customer core
4. Ticketing core
5. Sales/inventory core
6. Sales/inventory, CRM, ticketing, membership and FK smoke tests

This is a disposable PostgreSQL environment; it does not connect to or modify the hosted Supabase project.

## Verified CI result

Commit: `f3b08c98a5725bc07b1e8fa80fc1a8c4f61786fc`  
Run: https://github.com/theslyapex/Kasbeman/actions/runs/46146525793

Verified successful steps:

- SQL delimiter and migration/draft parity/security structure checks for sales/inventory, CRM and ticketing.
- PostgreSQL 17 schema and tenant-isolation suite.
- RLS enabled on all public tables; no direct anon table grants; invoker-safe views.
- Tenant isolation, scoped role delegation and cross-tenant foreign-key protections.
- Sales, inventory, receipts and concurrency protections.
- CRM permission separation, archive guard, tenant isolation, RLS and trigger ACL.
- Ticket tenant/branch isolation, operation-level permissions, active assignee validation, internal-note confidentiality, immutable archive and append-only event history.
- Multi-connection concurrency: competing sale confirmations, same-key receipt retries and competing warehouse transfers.
- TypeScript, ESLint and Next.js production build.

## Real local Supabase integration

- Local Supabase CLI configuration: `supabase/config.toml`.
- Integration runner: `scripts/test-supabase-local.sh`.
- The canonical migration chain was reset and applied inside a disposable local Supabase stack.
- Real Auth signup/session, profile trigger, authenticated PostgREST profile read, `create_business` RPC and tenant-scoped business read passed.
- Existing sales/inventory, CRM, ticketing, RLS/RBAC, membership, FK and multi-connection concurrency suites also passed against that local Supabase PostgreSQL 17 instance.
- Commit: `110356d6ad3591b90290c2a34a09294ad20f3f1e`; run: https://github.com/theslyapex/Kasbeman/actions/runs/46147757682.

## Release blockers

- No live Supabase staging environment has been created; current verification uses ephemeral PostgreSQL 17 in GitHub Actions.
- Real Supabase Auth and Data API behavior has now been exercised against a local Supabase stack. Hosted staging behavior, production Auth configuration and generated client types still require separate verification.
- Web and mobile have not completed live end-to-end testing against these migrations.
- The canonical migration has not been applied to production. Production changes require explicit user approval.
- Keep changes on `foundation/bootstrap`; do not merge to `main` without explicit authorization.

## Conclusion

The database schema and security smoke tests for the combined CRM, ticketing and sales/inventory stack passed in both disposable PostgreSQL CI and a local Supabase stack with real Auth and Data API. This is a strong pre-staging validation, not a production deployment sign-off. No Supabase staging branch or additional paid environment was created, and no production data/schema was changed.
