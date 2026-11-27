# Supabase workspace

Database migrations, deterministic seed data, Edge Functions, and database security tests belong here.

Rules:
- Never commit secrets or service-role credentials.
- Enable and test RLS for every exposed tenant table.
- Enforce active membership, permission, and business/branch scope.
- Prefer invoker security; tightly review any definer function.
- Keep migrations ordered, reviewed, and reversible where practical.

No schema migrations have been applied to the hosted project yet.
