# کسبمن | Kasbeman

**کسب‌وکارت، یک قدم جلوتر**

پلتفرم یکپارچه و ماژولار مدیریت کسب‌وکار.

## Project status

The web workspace includes the initial Supabase Auth flow (email/password signup, login, email confirmation callback), a protected workspace dashboard, and atomic business creation.

The identity/tenancy foundation migration is applied to the hosted Supabase project. The RBAC foundation migration is prepared and transaction-tested, but has **not** been applied to production. Module-specific authorization and production deployment remain in progress.

## Architecture principles

- Modular monolith for the initial product.
- Multi-business and multi-branch data isolation.
- PostgreSQL with explicit Row Level Security policies.
- Shared business capabilities with independently activated industry modules.
- API-first integration boundaries.
- Persian-first RTL experience with internationalization readiness.

## Workspace

- `apps/web`: Next.js web application.
- `apps/platform-admin`: separate platform control plane (reserved).
- `apps/mobile`: Flutter application (reserved).
- `packages/*`: shared TypeScript packages.
- `supabase/*`: database migrations, seed data, functions, and tests.
- `docs/*`: architecture, security, and deployment documentation.

## Getting started

1. Install Node.js 22.12+ and pnpm 10+.
2. Run `pnpm install` from the repository root.
3. Copy `/.env.example` to `apps/web/.env.local` and provide the Supabase project URL and publishable key.
4. Run `pnpm --filter @kasbeman/web dev`.

Do not put Supabase secret keys in browser-visible environment variables.

## Current limitations

This is an initial scaffold, not a deployed product. Only the identity/tenancy foundation migration has been applied to the hosted Supabase project; RBAC remains pending explicit production approval. The web app still requires environment configuration and Supabase Auth redirect URL setup before live signup can be tested. Cloudflare account access is available, but no Kasbeman Worker or domain zone is configured yet.
