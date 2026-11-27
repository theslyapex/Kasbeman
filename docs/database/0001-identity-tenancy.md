# Database foundation: identity and tenancy

- Status: design draft; not applied to any database
- Target: PostgreSQL 17 / Supabase Auth
- Scope: global user identity, businesses, branches, memberships, and invitations. Role/permission tables are a follow-up migration and are not represented by the temporary `role_key` field as a complete RBAC system.

## Goals

1. A single Auth user can participate in multiple independent businesses.
2. Every tenant-owned record is scoped by `business_id`; branch-scoped records additionally carry `branch_id`.
3. Branches are locations inside a business, never independent tenants.
4. Membership, role assignment, and permission checks are enforced by PostgreSQL RLS, not only by the UI.
5. The platform control plane remains separate from tenant administration.

## Proposed relations

| Relation | Purpose | Important invariants |
| --- | --- | --- |
| `public.profiles` | User-facing profile linked 1:1 to `auth.users` | `id = auth.users.id`; no authorization data in user-editable metadata |
| `public.businesses` | Tenant root | Stable UUID; creator/owner identity; lifecycle state; normalized slug uniqueness policy |
| `public.branches` | Business locations | Composite uniqueness on `(business_id, id)`; branch always belongs to exactly one business |
| `public.business_members` | Active or suspended membership | Composite key `(business_id, user_id)`; membership state gates all tenant access |
| `public.business_invitations` | Pending invitations | Normalized email, expiry, inviter, optional role and branch scope; acceptance must be atomic and single-use |
| `public.permissions` | Global permission catalogue | Stable machine keys such as `crm.customers.read`; labels can be localized separately |
| `public.roles` | Business-specific roles | Composite uniqueness `(business_id, id)`; system roles are protected from tenant edits |
| `public.role_permissions` | Permission grants to roles | FK to the role and permission catalogue; unique role/permission pair |
| `public.member_role_assignments` | Assign roles to members | Business-wide assignment when `branch_id IS NULL`; otherwise restricted to that branch |

## Migration boundary\n\nThe first executable migration establishes profiles, business tenants, active/suspended/revoked memberships, branches, invitations, tenant membership helper functions, the atomic business bootstrap RPC, and baseline RLS. It does **not** yet implement custom roles, a permission catalogue, branch-level role assignments, invitation acceptance, or a full audit log. Those require a separately reviewed authorization migration; do not treat `role_key` in this first migration as a complete permission engine.\n\n## Relational constraints

- Use UUID primary keys for tenant entities.
- Use composite foreign keys containing `business_id` wherever a relation connects two tenant-owned entities. This prevents accidentally attaching a branch, role, or assignment from another business.
- Index every foreign key and the columns used by RLS predicates, especially `(business_id, user_id, status)`, `(business_id, branch_id)`, and role-assignment lookup columns.
- Keep timestamps as `timestamptz`; use database-generated UTC timestamps.
- Use explicit lifecycle states and constraints rather than loosely interpreted booleans.
- Do not hard-delete membership or invitation history as an ordinary account-management action; record revocation and preserve an audit trail.
- Business creation must be one atomic server-side operation: create tenant, initial owner membership, default roles, and owner role assignment together. A partially initialized tenant must never be visible.

## Authorization model

The authorization decision for a tenant-owned row is the conjunction of:

1. The caller has a valid authenticated identity: `(select auth.uid()) IS NOT NULL`.
2. The caller has an active membership in the row's `business_id`.
3. The caller has the permission required for the operation.
4. If the row is branch-scoped, the caller has either a business-wide grant or a grant for that exact branch.

A missing or revoked membership must deny access even if a JWT remains valid. Do not copy membership or role state into long-lived JWT claims as the source of truth.

### RLS implementation requirements

- Enable RLS on every table in an exposed schema.
- Define explicit policies per table and operation; do not use a blanket `TO authenticated USING (true)`.
- UPDATE requires a SELECT policy and both `USING` and `WITH CHECK`.
- Use `(select auth.uid())` in policy expressions where appropriate.
- Avoid recursive RLS policy chains. If a narrowly scoped helper is required to evaluate membership/permission, place it in a non-exposed schema, use a fixed empty or tightly controlled `search_path`, fully qualify object names, check `auth.uid()` inside the function, revoke default PUBLIC execution, and grant only the minimum required role. Prefer SECURITY INVOKER everywhere else.
- Views must use `security_invoker = true` on PostgreSQL 15+ unless a documented security review justifies another approach.
- Never authorize using `raw_user_meta_data` / `user_metadata`.
- Never expose Supabase secret or service-role credentials to browser/mobile code.

## Data API privileges

Do not assume that creating a table in `public` automatically makes it accessible through Supabase's Data API. Supabase changed the default exposure behavior for new projects in 2026. The migration must explicitly grant only the required schema/table privileges to the intended Postgres roles, alongside RLS. If a table is not meant to be reached from browser/mobile clients, keep it in a non-exposed schema and do not grant API roles access.

## Required security tests before applying

- User A cannot read, update, delete, or infer rows belonging to business B.
- A user who belongs to two businesses can switch tenant context without cross-tenant leakage.
- Suspended or revoked members lose access immediately, including when their JWT has not yet refreshed.
- Branch-scoped users cannot read or mutate another branch's records.
- A branch-wide grant works only for branches in the same business.
- A user cannot self-assign a higher role or change their own permission grants.
- Invitations cannot be replayed, accepted after expiry, or used by a different email identity.
- A tenant cannot edit protected system roles or the global permission catalogue.
- Anonymous requests receive no private tenant data.
- Every exposed table has RLS enabled and reviewed grants.

## Decisions intentionally deferred

- Final default role names and their exact permission matrix.
- Whether a business may have more than one owner and the owner-transfer workflow.
- Slug scope (global vs. per-account) and reserved words.
- Invitation delivery channel and rate limits.
- Audit-event retention and immutable export strategy.

These choices must be settled before the first production migration. This document is a design baseline, not executable SQL and not evidence that any hosted schema has changed.
