# Cloudflare Workers deployment plan

## Target architecture

- Source of truth: GitHub repository `theslyapex/Kasbeman`.
- Application runtime: Cloudflare Workers.
- Application framework: the existing Next.js App Router application in `apps/web`.
- Authentication and relational data: the existing Supabase project. Cloudflare is the application host and edge network, not a replacement for Supabase.
- Domain registrar: IRNIC for the future `.ir` domain.
- DNS, proxy, and edge TLS: Cloudflare after the domain is registered and its authoritative nameservers are delegated to Cloudflare.

## Adapter decision

The current app is already a Next.js 16 application with Server Actions, Route Handlers, and cookie-based Supabase SSR authentication. Preserve this framework and validate the Cloudflare OpenNext adapter before considering a framework migration. Cloudflare currently recommends vinext for new Next.js applications, while its OpenNext adapter documentation lists support for App Router, Route Handlers, SSR, Server Actions, and streaming. Do not switch to vinext solely to deploy the current app without a compatibility test.

Official references:
- Cloudflare Next.js framework guidance: https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/
- OpenNext Cloudflare setup: https://opennext.js.org/cloudflare/get-started
- Workers Builds: https://developers.cloudflare.com/workers/ci-cd/builds/

## Repository facts

- This repository is a pnpm workspace/monorepo.
- The Next.js app is in `apps/web`; the pnpm workspace and lockfile are at repository root.
- The app currently has no Cloudflare adapter or Wrangler configuration.
- Do not use GitHub Pages for this application: the app requires server-side rendering and server actions.

## Safe rollout sequence

1. Add and lock the OpenNext Cloudflare adapter and Wrangler as development dependencies in `apps/web`. Update `pnpm-lock.yaml` using pnpm; never hand-edit the lockfile.
2. Add the adapter's `open-next.config.ts`, Worker configuration, static asset cache headers, and ignore generated `.open-next` output.
3. Run the existing CI checks, then build and preview the Worker locally using the Workers runtime. Validate signup/login callback handling, Server Actions, Supabase cookie refresh, dashboard RLS reads, and business creation against a non-production test environment.
4. Connect the GitHub repository to Cloudflare Workers Builds. Keep the production branch unset until the preview build is verified. Use the repository root for pnpm workspace installation and configure the build root/commands carefully; Cloudflare documents limited monorepo/workspace support, so verify this with a preview before enabling production deploys.
5. Add only the required runtime variables in Cloudflare Worker settings: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL`. The Supabase publishable key is intended for client use. Never put a Supabase secret/service-role key in `NEXT_PUBLIC_*` or browser code.
6. After the domain is registered, add it as a Cloudflare zone, delegate the exact Cloudflare nameservers at IRNIC, wait for the zone to become active, and attach the hostname to the Worker.
7. Set Cloudflare SSL/TLS mode to Full (strict) when the origin topology supports it; for a Worker custom domain, use Cloudflare-managed edge TLS. Enable HTTPS redirects only after HTTPS has been verified.
8. Update Supabase Auth Site URL and allowed callback URL to the final canonical origin, then run approved end-to-end tests.

## Current Cloudflare account state (checked 2026-11-27)

- Cloudflare account connection is available.
- No Workers scripts were present.
- No DNS zones were present.
- No domain or Worker was created by this setup work.

## Current blockers

- The domain has not yet been registered/delegated.
- No Cloudflare Worker exists yet.
- The OpenNext adapter and Wrangler have not yet been installed or lockfile-pinned.
- No Cloudflare GitHub repository connection/build trigger exists yet.
- The production branch must not deploy until the preview build and auth flow are verified.
- Supabase Auth production redirect configuration remains pending the final hostname.

## GitHub and production safety

Keep implementation changes on `foundation/bootstrap`. Do not merge to `main`, change DNS, create a production Worker, or alter Supabase production settings as part of this preparation step. Production deployment requires a verified preview and explicit approval.
