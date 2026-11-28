# Ticketing Module — Production Rollout Gate

Date: 2026-11-28  
Status: **Implemented and CI-tested as a draft; production migration blocked by CRM dependency.**

## Current implementation

- Web: `/dashboard/[businessId]/tickets`
- Mobile: Flutter ticket center
- Database draft: `supabase/drafts/ticketing_core.sql`
- Security tests: `supabase/tests/ticketing-smoke.sql`
- PostgreSQL CI applies the sales/inventory draft before the ticketing draft, then runs the ticketing and tenant-isolation smoke tests.
- Latest verified CI commit: `8eef98764a486a1b37a0a91fbf8de18db1dbd9d8`
  - Web CI: https://github.com/theslyapex/Kasbeman/actions/runs/46143360986
  - Mobile CI: https://github.com/theslyapex/Kasbeman/actions/runs/46143360978

## Production dependency discovered

The hosted Supabase project `xitrazjbemmkarawejfe` currently contains these public base tables:

`branches`, `business_invitations`, `business_members`, `businesses`, `member_role_assignments`, `permissions`, `profiles`, `role_permissions`, `roles`.

It does **not** yet contain `customers`, `tickets`, `ticket_comments`, or `ticket_events`.

The ticketing draft currently:
- defines `tickets.customer_id` with a composite foreign key to `customers(business_id,id)`;
- relies on `customers` in the web ticket page and create-ticket flow;
- expects the CRM customer schema and its status/tenant constraints to exist first.

The sales/inventory core containing the customer table is still a draft, not an applied production migration. Therefore, a ticketing migration generated from the current draft is not independently deployable to the hosted project. Applying it before CRM would fail at the customer foreign key, and deploying the current web route before the required tables exist would result in failed queries.

## Required rollout order

1. Finalize and independently test the CRM/customer schema, including tenant-scoped unique key `(business_id,id)`, customer status, RLS, and grants.
2. Generate a canonical Supabase migration for the CRM/customer foundation and test it against a disposable PostgreSQL 17 database and the current hosted-schema baseline.
3. Generate the ticketing migration from `supabase/drafts/ticketing_core.sql` using Supabase CLI; do not hand-edit previously applied migrations.
4. Add the ticketing migration after the CRM migration in the local migration/test sequence.
5. Run the full PostgreSQL 17 schema, tenant-isolation, permission-negative, invitation lifecycle, and multi-connection concurrency suites.
6. Verify web and mobile against a disposable Supabase stack using authenticated users with owner, branch operator, editor, and restricted comment permissions.
7. Review the generated migration and deployment plan. Production application requires explicit user approval.

## Release blockers / safeguards

- No ticketing migration has been applied to production.
- No CRM/customer migration has been applied to production.
- Do not add a placeholder customer table to production merely to satisfy the ticket foreign key.
- Do not disable or weaken the customer foreign key, RLS, or permission guards to bypass the dependency.
- Keep all work on `foundation/bootstrap`; do not merge to `main` without explicit authorization.
- Recheck the hosted migration history immediately before any production rollout.

## Current conclusion

Ticketing implementation and CI coverage are in place, but the module is **not production-ready as a standalone deployment**. CRM/customer schema is the next backend prerequisite. The successful CI runs prove the combined draft stack works in disposable PostgreSQL 17; they do not prove that the ticket module can be applied to the current hosted production schema.
