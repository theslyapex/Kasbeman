# Database foundation: tenant-scoped RBAC

- Status: **applied** to the hosted Supabase project on 2026-11-27; transaction-tested before deployment
- Recorded Supabase migration version: `20261127085000`
- Target: PostgreSQL 17 / Supabase Auth
- Depends on: `20261127080500_identity_tenancy_foundation.sql`
- Migration: `supabase/migrations/20261127083000_rbac_authorization_foundation.sql`

## Scope

This migration adds a global permission catalogue, tenant-owned roles, role-to-permission grants, member role assignments, branch-scoped grants, live authorization helpers, and an internal authorization audit log.

It also replaces the temporary `business_members.role_key` authorization model with role assignments as the canonical permission source. The legacy column remains for compatibility and migration traceability; new authorization decisions must not rely on it.

## Data model

| Table | Scope | Purpose |
| --- | --- | --- |
| `public.permissions` | Global | Stable machine-readable permission catalogue and Persian labels |
| `public.roles` | Per business | System roles and tenant-defined custom roles |
| `public.role_permissions` | Per business + role | Explicit permission grants |
| `public.member_role_assignments` | Per business + member + optional branch | One or more roles assigned to an active member |
| `private.authorization_audit_log` | Internal | Before/after snapshots of role, permission, assignment, and membership-status changes |

Every tenant-owned relation carries `business_id`. Composite foreign keys prevent a role, member, or branch from another business being attached accidentally.

## Authorization rules

1. A valid `auth.uid()` is required.
2. The member must have `business_members.status = 'active'`.
3. At least one active role assignment must grant the requested permission.
4. A business-wide assignment (`branch_id IS NULL`) applies to the whole business.
5. A branch assignment applies only to that branch. It does not grant business-wide permission.
6. A branch-scoped check also verifies that the branch belongs to the requested business and is active.
7. Permission checks use live database rows, not user-editable metadata or stale JWT role claims.
8. Custom roles may only receive permissions the actor already possesses.
9. Only a caller with `team.owners.manage` may assign the owner role; owner assignment is business-wide only.
10. The generic member-management path cannot suspend or revoke an owner. Ownership transfer requires a separate workflow.

The internal helpers are in the non-exposed `private` schema, use `SECURITY DEFINER` with an empty `search_path`, fully qualified object names, and explicit execution grants.

## System roles

Each business receives three protected system roles:

- **مالک / owner:** all catalogue permissions, including ownership and sensitive business controls.
- **مدیر / admin:** operational and team-management permissions, excluding ownership transfer, business deletion, subscription management, and owner assignment.
- **عضو / member:** limited read-oriented access to dashboard, branches, customers, sales, inventory, reports, and documents.

System roles and their permission sets cannot be edited through the authenticated Data API. Custom roles are tenant-specific and are editable only by members with `team.roles.manage`.

This is an initial permission catalogue, not a claim that every future module has already been wired to these permissions. Each module migration must add RLS policies that call `private.has_business_permission(business_id, permission_key, branch_id)` for its own tables and operations.

## Membership and audit behavior

- Existing active memberships are backfilled from the temporary `role_key` into canonical role assignments.
- New business creation creates the tenant, owner membership, primary branch, three system roles, permission grants, and owner assignment atomically.
- Admins with `team.members.manage` may suspend or revoke non-owner memberships. They cannot change their own membership through this path or suspend an owner.
- Role assignments can be revoked but not reactivated in place. A future rejoin/reactivation flow must create a new assignment with its own audit event.
- Audit rows are stored in a private table with no direct `anon` or `authenticated` Data API grants. A scoped audit-read endpoint is intentionally deferred.

## Deliberate limitations

- Branch-scoped users cannot manage roles or assign roles yet; role administration currently requires business-wide `team.roles.manage` / `team.roles.assign`.
- Branch-specific permission enforcement becomes effective on module tables only after those tables include a tenant-safe branch reference and their RLS policies call the helper with that branch ID.
- Invitation acceptance, email delivery, invitation replay protection, ownership transfer, and a user-facing audit-log reader are separate workflows.
- The permission catalogue will expand as core modules are implemented; avoid treating missing catalogue entries as implicit access.
- The old `business_members.role_key` column remains transitional and should be removed only in a separately reviewed migration after application code has fully moved to RBAC.

## Transaction test coverage

The complete migration was executed inside a transaction and rolled back against the hosted project. The test included temporary Auth users and tenants, then verified:

- tenant A cannot read tenant B;
- owner receives the complete role-management permissions;
- a custom branch-scoped role grants permission only within its assigned branch;
- admin cannot assign the owner role;
- admin cannot grant a permission it does not possess;
- admin can suspend a non-owner member;
- admin cannot suspend an owner;
- suspended membership immediately loses effective permissions;
- rollback leaves no test Auth users, tenants, or RBAC schema objects behind.

This test validates the migration SQL and the tested authorization paths. It does not mean the migration has been applied or that every future module's RLS is already implemented.


## Hosted deployment verification (2026-11-27)

The migration was applied to Supabase project `xitrazjbemmkarawejfe`. Supabase recorded it as version `20261127085000` under name `rbac_authorization_foundation`.

Read-only verification confirmed:

- All four RBAC tables exist and have RLS enabled: `permissions`, `roles`, `role_permissions`, and `member_role_assignments`.
- The global permission catalogue contains 36 entries.
- No businesses, roles, role grants, or member-role assignments existed at verification time. This is expected because no test or production tenant data had been created.
- The permission helpers are in the private schema, use `SECURITY DEFINER` with an empty `search_path`, are executable by `authenticated`, and are not executable by `anon`.
- The authorization audit triggers exist for roles, role permissions, role assignments, and membership status changes.
- `public.create_business(text,text)` was replaced with the atomic bootstrap that also creates system roles, grants, and the owner's role assignment. It requires `auth.uid()`; execution is denied to `anon` and granted to `authenticated`.
- Migration history contains both the identity/tenancy foundation and this RBAC migration.

### Advisor results after deployment

- Health advisor: no findings.
- Security advisor: one warning for the intentionally callable `public.create_business` SECURITY DEFINER RPC. It is an authenticated-only endpoint, checks `auth.uid()`, validates inputs, and is required for atomic tenant bootstrap. This warning is documented rather than treated as a clean security scan.
- Security advisor also reports that `private.authorization_audit_log` has RLS enabled with no policies. This is intentional: it has no direct grants to `anon` or `authenticated`; an audited, scoped read path is deferred.
- Performance advisor reports six unindexed foreign keys: `business_invitations.invited_by`, `businesses.created_by`, `member_role_assignments.assigned_by`, `member_role_assignments.branch_id`, `member_role_assignments.role_id`, and `roles.created_by`. These are optimization findings, not migration failures; index additions should be handled in a new migration.
- The advisor also lists five indexes as unused because the database is currently empty. Reassess after representative tenant data and workloads exist.

The transaction tests completed before deployment cover tenant isolation, branch scope, role escalation prevention, owner protections, suspension behavior, and rollback. No persistent test users or tenants were created. Live authenticated end-to-end tests remain outstanding.

This migration establishes the shared RBAC foundation only. Future module tables still require their own tenant- and branch-aware RLS policies and tests.
