# کسبمن | Kasbeman

**کسب‌وکارت، یک قدم جلوتر**

پلتفرم یکپارچه و ماژولار مدیریت کسب‌وکار.

## Project status

The repository foundation is being established. The web workspace skeleton is present; database migrations, authentication flows, and production deployments are not yet implemented.

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
3. Copy `/.env.example` to `/.env.local` inside `apps/web` and provide the Supabase project URL and publishable key.
4. Run `pnpm --filter @kasbeman/web dev`.

Do not put Supabase secret keys in browser-visible environment variables.

## Current limitations

This is an initial scaffold, not a deployed product. No database schema or migrations have been applied to the hosted Supabase project.
