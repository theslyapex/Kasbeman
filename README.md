# کسبمن | Kasbeman

**کسب‌وکارت، یک قدم جلوتر**

پلتفرم یکپارچه و ماژولار مدیریت کسب‌وکار.

## Product architecture

Kasbeman is developed as two separate client applications backed by one shared backend:

- **Web:** Next.js App Router in `apps/web`. The web product is an independent, responsive website and business workspace; it is not a Flutter Web application.
- **Mobile:** Flutter in `apps/mobile`, targeting Android and iOS. The mobile app consumes the same backend and business APIs as the web application.
- **Backend:** Supabase (PostgreSQL, Auth, Storage, and server-side functions where appropriate).
- **Source control:** Both applications and backend assets live in this GitHub monorepo.
- **Web hosting:** Cloudflare is the planned web runtime/edge platform. GitHub is the source repository and CI/CD source, not the application runtime.

The mobile app must not duplicate business rules. Authorization, tenant isolation, and critical business operations remain enforced by the shared backend.

## Project status

The web workspace includes the initial Supabase Auth flow (email/password signup, login, email confirmation callback), a protected workspace dashboard, and atomic business creation.

The identity/tenancy and RBAC foundation migrations are applied to the hosted Supabase project. The first sales/inventory database design is being prepared as a review draft and has **not** been applied to production.

## Architecture principles

- Modular monolith for the initial product.
- Multi-business and multi-branch data isolation.
- PostgreSQL with explicit Row Level Security policies.
- Shared business capabilities with independently activated industry modules.
- API-first integration boundaries.
- Persian-first RTL experience with internationalization readiness.
- Offline-capable mobile workflows using a local database, an outbox, idempotent synchronization, and explicit conflict handling.

## Workspace

- `apps/web`: Next.js web application.
- `apps/mobile`: Flutter Android/iOS application.
- `apps/platform-admin`: separate platform control plane (reserved).
- `packages/*`: shared TypeScript packages and API contracts for web-side tooling.
- `supabase/*`: database migrations, seed data, functions, and tests.
- `docs/*`: architecture, security, and deployment documentation.

Flutter and TypeScript do not share runtime code. They share backend contracts, API semantics, validation rules where practical, and documented domain behavior.

## Getting started

1. Install Node.js 22.12+ and pnpm 10+.
2. Run `pnpm install` from the repository root.
3. Copy `/.env.example` to `apps/web/.env.local` and provide the Supabase project URL and publishable key.
4. Run `pnpm --filter @kasbeman/web dev`.

The Flutter workspace uses its own Flutter/Dart toolchain and dependency lockfile. Do not hand-edit either lockfile.

Do not put Supabase secret keys in browser-visible environment variables.

## Current limitations

This is an initial scaffold, not a deployed product. Identity/tenancy and RBAC migrations are applied to the hosted Supabase project; sales/inventory schema is still under review. The web app still requires environment configuration and Supabase Auth redirect URL setup before live signup can be tested. Cloudflare account access is available, but no Kasbeman Worker or domain zone is configured yet. The Flutter app has an initial authenticated workspace, business selector, branch selector, and branch creation flow.
