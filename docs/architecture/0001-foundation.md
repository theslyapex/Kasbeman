# ADR 0001: Kasbeman foundation

- Status: Proposed implementation baseline
- Date: 2026-11-27

## Context

Kasbeman is a Persian-first, multi-business SaaS platform with shared capabilities and industry-specific modules. The initial system must remain operable by a small team while preserving clear module boundaries.

## Decisions

1. Start with a modular monolith, not distributed microservices.
2. Use a pnpm/Turborepo workspace.
3. Build the web application with Next.js, React, and TypeScript.
4. Use Supabase Auth, PostgreSQL, and private Storage as managed platform capabilities.
5. Keep tenant authorization in database policies and trusted server-side domain services.
6. Separate the platform control plane from tenant business administration.
7. Keep Flutter mobile in a separate app/toolchain while sharing API contracts.
8. Treat module activation as an entitlement and configuration concern, not as a separate database per module.

## Tenant boundaries

- A user may belong to multiple businesses.
- A business owns its branches, members, settings, and operational data.
- Branches are scoped locations within a business, not independent tenants.
- Tenant-owned rows must carry business scope; branch scope is added where applicable.
- Database constraints and RLS must enforce consistency and isolation.

## Deferred decisions

- Hosting provider and production deployment topology.
- Final region selection after latency and legal review.
- Queue and cache provider.
- Mobile local database and sync implementation details.
- Production observability provider.

## Consequences

The first release is simpler to develop and deploy. Module boundaries, API contracts, and data ownership must be enforced through code review and tests to prevent the monolith from becoming tightly coupled.
