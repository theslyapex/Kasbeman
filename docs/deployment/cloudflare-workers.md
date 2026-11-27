# Cloudflare Workers deployment plan

## Product architecture

Kasbeman has two distinct client applications and one shared backend:

- **Web application:** Next.js App Router in `apps/web`. This remains a real web application with responsive desktop/mobile layouts. It is not being rewritten in Flutter Web.
- **Mobile application:** Flutter for Android and iOS in `apps/mobile`. It will use the same Supabase project and documented backend contracts as the web application.
- **Shared backend:** Supabase Auth, PostgreSQL, Row Level Security, Storage, and server-side functions where appropriate.
- **Source of truth:** GitHub monorepo `theslyapex/Kasbeman`. GitHub stores source and runs CI; it is not itself the runtime for the Next.js server application.

Flutter and Next.js are separate clients. Do not duplicate authorization or business rules in either client; enforce tenant isolation and permissions in PostgreSQL/RLS and trusted server-side operations.

## Cloudflare role

Cloudflare is the planned host/runtime and edge-security layer for the Next.js web application. GitHub Pages alone is not a suitable host for the current web workspace because the application uses server-side rendering and Server Actions. A static marketing site could be hosted separately, but that is not a replacement for the authenticated business workspace.

The Flutter app is distributed as Android/iOS builds; it is not deployed to Cloudflare Workers. It communicates with the shared Supabase backend.

## Next.js-on-Workers adapter decision

The web app remains Next.js. The adapter is only a deployment compatibility layer; it does not change the product architecture or turn the website into a Flutter app.

Cloudflare currently recommends **vinext** as the default way to run Next.js applications on Workers. The project uses Next.js 16, which is within vinext's target range. However, vinext is still beta and compatibility scanning is not a full runtime guarantee. Keep adapter selection separate from application architecture and validate a preview before production.

Current conservative evaluation choices:
- CDN cache: none.
- Data cache: none.
- Image optimization: none.

The proposed noninteractive initialization command, to be run from the Next.js app directory after confirming the Cloudflare build context, is:

```bash
pnpm dlx vinext init --platform=cloudflare --name=kasbeman --cdn-cache=none --data-cache=none --image-optimization=none
```

This command has **not** been executed from this workspace. Do not claim that a Worker adapter has been initialized or deployed. Run it in a real project checkout with pnpm so the root lockfile can be regenerated correctly. Never hand-edit `pnpm-lock.yaml`.

If vinext compatibility testing reveals blockers in the app's required features, evaluate the Cloudflare OpenNext adapter as the fallback. Do not mix the two adapters or maintain two competing deployment configurations.

Official references:
- Cloudflare Next.js guide: https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/
- Cloudflare vinext migration guide: https://developers.cloudflare.com/workers/static-assets/migration-guides/vercel-to-workers/nextjs/
- vinext compatibility and migration notes: https://github.com/cloudflare/vinext
- Cloudflare OpenNext adapter (fallback): https://developers.cloudflare.com/workers/framework-guides/web-apps/opennext/
- Workers Builds: https://developers.cloudflare.com/workers/ci-cd/builds/

## Repository facts

- This repository is a pnpm workspace/monorepo.
- The Next.js app is in `apps/web`; the pnpm workspace and lockfile are at repository root.
- The app currently has no Cloudflare adapter or Cloudflare Worker configuration.
- The Flutter app is a separate planned workspace at `apps/mobile`; no Flutter project has been generated yet.
- Do not use GitHub Pages for the authenticated Next.js application because it requires server-side rendering and server actions.

## Safe rollout sequence

1. Keep the existing Next.js application as the web client; do not convert it to Flutter Web.
2. Bootstrap the Flutter Android/iOS client in `apps/mobile`, then connect it to the shared Supabase backend using the same authorization model and API contracts.
3. Complete the vinext compatibility review and initialize the Cloudflare adapter in a real checkout; update the root pnpm lockfile using pnpm.
4. Build and run a preview before production. Validate signup/login callback handling, Server Actions, Supabase cookie refresh, dashboard RLS reads, and business creation against a non-production test environment.
5. Connect GitHub to Cloudflare Workers Builds. Keep production deployment disabled until preview checks pass. Use the repository root for workspace installation and configure the app's build context carefully.
6. Add only required runtime variables in Cloudflare Worker settings: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL`. Never put a Supabase secret/service-role key in `NEXT_PUBLIC_*` or browser code.
7. After the domain is registered, add it as a Cloudflare zone, delegate the exact Cloudflare nameservers at IRNIC, wait for the zone to become active, and attach the hostname to the Worker.
8. Set Cloudflare SSL/TLS mode appropriately for the final topology. For a Worker custom domain, use Cloudflare-managed edge TLS. Enable HTTPS redirects only after HTTPS has been verified.
9. Update Supabase Auth Site URL and allowed callback URL to the final canonical origin, then run approved end-to-end tests.

## Current Cloudflare account state (checked 2026-11-27)

- Cloudflare account connection is available.
- No Workers scripts were present at the time of the account check.
- No DNS zones were present at the time of the account check.
- No production domain or Worker was created by this preparation work.

## Current blockers

- The domain has not yet been registered/delegated.
- No Cloudflare Worker has been deployed yet.
- The vinext compatibility scan and initialization have not yet been run in the actual app workspace.
- The Cloudflare GitHub repository connection was initiated in the dashboard, but a successful preview deployment has not been verified.
- Supabase Auth production redirect configuration remains pending the final hostname.
- Flutter project bootstrap and mobile-specific auth/sync implementation remain pending.

## GitHub and production safety

Keep implementation changes on `foundation/bootstrap`. Do not merge to `main`, change DNS, create a production Worker, or alter Supabase production settings as part of this preparation step. Production deployment requires a verified preview and explicit approval.
