# کسبمن | Kasbeman

**کسب‌وکارت، یک قدم جلوتر**

پلتفرم یکپارچه و ماژولار مدیریت کسب‌وکار.

## Project status

The web workspace includes the initial Supabase Auth flow (email/password signup, login, email confirmation callback), a protected workspace dashboard, and atomic business creation. Identity/tenancy and RBAC foundation migrations have been applied to the hosted Supabase project; module-specific authorization and production deployment remain in progress.

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
- `docs/*`: architecture and security documentation.

## Getting started

1. Install Node.js 22.12+ and pnpm 10+.
2. Run `pnpm install` from the repository root.
3. Copy `/.env.example` to `apps/web/.env.local` and provide the Supabase project URL and publishable key.
4. Run `pnpm --filter @kasbeman/web dev`.

Do not put Supabase secret keys in browser-visible environment variables.

## Current limitations

This is an initial scaffold, not a deployed product. The hosted project has the identity/tenancy and RBAC foundation migrations applied. The web app still requires environment configuration and Supabase Auth redirect URL setup before live signup can be tested.
