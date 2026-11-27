# Cloudflare Workers deployment plan

## Target architecture

- Source of truth: GitHub repository `theslyapex/Kasbeman`.
- Application runtime: Cloudflare Workers.
- Application framework: the existing Next.js App Router application in `apps/web`.
- Authentication and relational data: the existing Supabase project. Cloudflare is the application host and edge network, not a replacement for Supabase.
- Domain registrar: IRNIC for the future `.ir` domain.
- DNS, proxy, and edge TLS: Cloudflare after the domain is registered and its authoritative nameservers are delegated to Cloudflare.

## Adapter decision

Cloudflare currently recommends **vinext** as the default way to run Next.js applications on Workers. The project uses Next.js 16, which is within vinext's target range. However, vinext is still beta and explicitly warns about compatibility gaps, so it must pass a compatibility scan and runtime tests before it becomes the deployment path.

Do not deploy this repository using the dashboard's default `npx wrangler deploy` or `npx wrangler preview` commands yet. The repository has no Worker configuration, and those commands do not build this Next.js workspace.

Preferred evaluation path:
1. Run `vinext check` against `apps/web` and review every reported issue.
2. Initialize vinext for Cloudflare Workers in the app workspace, preserving the existing Next.js setup.
3. Update the root pnpm lockfile with pnpm; never hand-edit it.
4. Configure the Cloudflare Worker using the generated `cloudflare.config.ts` and the Cloudflare `cf` CLI workflow.
5. Build and run a preview before enabling production deployments.

If vinext compatibility testing reveals blockers in the app's required features, evaluate the Cloudflare OpenNext adapter as the fallback. OpenNext documents support for App Router, Route Handlers, SSR, Server Actions, and streaming. Do not mix the two adapters or maintain two competing deployment configurations.

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
- Do not use GitHub Pages for this application: the app requires server-side rendering and server actions.

## Safe rollout sequence

1. Run the vinext compatibility check and review its report.
2. Add the selected adapter and required Vite/Cloudflare dependencies to `apps/web`; update `pnpm-lock.yaml` using pnpm, never manually.
3. Generate and review the Cloudflare Worker config and Vite config; keep generated build output out of Git.
4. Run CI, then build and preview the Worker. Validate signup/login callback handling, Server Actions, Supabase cookie refresh, dashboard RLS reads, and business creation against a non-production test environment.
5. Connect GitHub to Cloudflare Workers Builds. Keep production deployment disabled until preview checks pass. Use the repository root for workspace installation and configure the app's build context carefully.
6. Add only required runtime variables in Cloudflare Worker settings: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL`. The Supabase publishable key is intended for client use. Never put a Supabase secret/service-role key in `NEXT_PUBLIC_*` or browser code.
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
- The vinext compatibility scan and initialization have not yet been run.
- The Cloudflare GitHub repository connection was initiated in the dashboard, but a successful preview deployment has not been verified.
- Supabase Auth production redirect configuration remains pending the final hostname.

## GitHub and production safety

Keep implementation changes on `foundation/bootstrap`. Do not merge to `main`, change DNS, create a production Worker, or alter Supabase production settings as part of this preparation step. Production deployment requires a verified preview and explicit approval.
