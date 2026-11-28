# Local Supabase integration testing

Kasbeman can be tested against a real local Supabase stack without creating a hosted Supabase branch or using production credentials.

## Requirements

- Docker Engine/Desktop running
- Supabase CLI 2.67.1 or compatible
- PostgreSQL client (`psql`)
- `curl` and `jq`

## Run the complete local suite

From the repository root:

```bash
bash scripts/test-supabase-local.sh
```

The script:

1. Starts the local Supabase stack using `supabase/config.toml` (PostgreSQL 17 and local Auth/Data API; optional services are disabled to reduce resource use).
2. Resets the local database and applies every canonical migration from `supabase/migrations`.
3. Creates a disposable local Auth user through the actual GoTrue signup endpoint.
4. Verifies the Auth user endpoint, the Auth-to-profile trigger, authenticated PostgREST access, the `create_business` RPC and tenant-scoped business visibility.
5. Runs the existing RLS/RBAC, CRM, ticketing, sales/inventory, membership, FK and concurrency SQL tests against the local Supabase database.
6. Stops the local Supabase containers on exit.

The generated local API keys and test account are temporary. They are never uploaded to GitHub or used against the hosted project.

## GitHub Actions

The `Kasbeman Local Supabase CI` workflow runs this same script on relevant changes to the `foundation/**` branch and can also be started manually. It uses only ephemeral GitHub-hosted runner resources and requires no Supabase organization/project secrets.

## Verified run (2026-11-28)

- Commit: `110356d6ad3591b90290c2a34a09294ad20f3f1e`
- Run: https://github.com/theslyapex/Kasbeman/actions/runs/46147757682
- Result: **success**.
- Real local Auth signup and `/auth/v1/user` verification passed.
- The Auth user trigger created the profile; authenticated PostgREST profile read passed under RLS.
- Authenticated `create_business` RPC and tenant-scoped business read passed.
- The canonical migration chain, RLS/RBAC, CRM, ticketing, sales/inventory, membership, FK and multi-connection concurrency suites all passed against local Supabase PostgreSQL 17.
- The standard web/database CI also passed on the same commit: https://github.com/theslyapex/Kasbeman/actions/runs/46147757621

## Safety boundary

- This workflow only talks to localhost inside its isolated runner.
- It does not link to, pull from, push to, or modify the hosted Supabase project.
- It does not create a Supabase staging branch.
- Hosted migrations still require a separate explicit release decision and approval.
- The standalone PostgreSQL CI continues to use its Auth compatibility shim; the local Supabase workflow is the additional real Auth/Data API integration layer.
