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

The web workspace includes the initial Supabase Auth flow (email/password signup, login, email confirmation callback), a protected workspace dashboard, and business creation.

The identity/tenancy foundation migration has been applied to the hosted Supabase project. The RBAC authorization migration exists in the repository but is **not confirmed as applied** to the hosted project. The sales/inventory database design remains a review draft and has **not** been applied to production.

The current repository is a development scaffold, not a deployed product. See [the project roadmap and progress report](docs/PROJECT-ROADMAP.md) for phase status, separate web/mobile progress, CI status, and live-testing gates.

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
- `docs/*`: architecture, security, roadmap, and deployment documentation.

Flutter and TypeScript do not share runtime code. They share backend contracts, API semantics, validation rules where practical, and documented domain behavior.

## Getting started

1. Install Node.js 22.12+ and pnpm 10+.
2. Run `pnpm install` from the repository root.
3. Copy `/.env.example` to `apps/web/.env.local` and provide the Supabase project URL and publishable key.
4. Run `pnpm --filter @kasbeman/web dev`.

The Flutter workspace uses its own Flutter/Dart toolchain and dependency lockfile. Do not hand-edit either lockfile.

Do not put Supabase secret keys in browser-visible environment variables.

## Current limitations

The web app still requires environment configuration and Supabase Auth redirect URL setup before live signup can be tested. No Kasbeman Cloudflare deployment or domain zone is configured yet. The Flutter app has an initial authenticated workspace, business selector, branch selector, and branch creation flow. Sales/inventory operations still depend on the database design being reviewed and safely applied.
