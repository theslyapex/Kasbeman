# کسبمن | Kasbeman

**کسب‌وکارت، یک قدم جلوتر**

پلتفرم یکپارچه و ماژولار مدیریت کسب‌وکار.

## Project status

The repository foundation is being established. Application code, database migrations, and deployments are not yet present.

## Architecture principles

- Modular monolith for the initial product.
- Multi-business and multi-branch data isolation.
- PostgreSQL with explicit Row Level Security policies.
- Shared business capabilities with independently activated industry modules.
- API-first integration boundaries.
- Persian-first RTL experience with internationalization readiness.

## Planned workspace

- `apps/web`: Next.js web application.
- `apps/platform-admin`: separate platform control plane.
- `apps/mobile`: Flutter application (separate toolchain).
- `packages/*`: shared TypeScript packages.
- `supabase/*`: database migrations, seed data, functions, and tests.
- `docs/*`: architecture, database, security, and API documentation.

## Current state

This repository is at the foundation stage. No production services or database schema have been deployed.
