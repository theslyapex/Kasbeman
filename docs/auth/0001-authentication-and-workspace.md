# Authentication and first workspace

- Status: implemented on `foundation/bootstrap`; hosted application configuration and live end-to-end verification are pending.
- Provider: Supabase Auth email/password.
- Session model: cookie-based SSR using `@supabase/ssr` and the Next.js request proxy.

## Routes

| Route | Purpose |
| --- | --- |
| `/signup` | Create an Auth user with email and password |
| `/login` | Sign in with email and password |
| `/auth/callback` | Exchange the PKCE confirmation code for a cookie-backed session |
| `/dashboard` | Protected workspace; lists businesses visible under RLS |
| `/dashboard/new-business` | Calls the atomic `public.create_business` RPC |

## Security boundaries

- Credentials are submitted to server actions; passwords are never stored in application tables.
- The server validates email, password length, confirmation, business name, and slug with Zod.
- Authenticated server routes use `auth.getUser()` before returning user-specific data or creating a tenant.
- Business creation calls the database RPC through the user's cookie-authenticated Supabase client. It does not use a service-role key.
- Tenant authorization remains enforced by database RLS and the permission helpers; hiding UI is not treated as authorization.
- Callback navigation accepts only same-origin relative paths.
- The request proxy validates/refreshes claims and marks responses `private, no-store` to avoid shared caching of session responses.
- No secret key is used in browser code or in `NEXT_PUBLIC_*` variables.

## Required deployment configuration

1. Set `NEXT_PUBLIC_SUPABASE_URL` to the project URL.
2. Set `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to the project's publishable key.
3. Set `NEXT_PUBLIC_SITE_URL` to the canonical deployed origin, for example `https://kasbeman.ir` only after that domain is actually connected to this application.
4. In Supabase Auth URL Configuration, set the Site URL to the canonical origin and add the exact redirect URL `<origin>/auth/callback` to the allowed redirect URLs. Keep localhost callback URLs only for local development.
5. Configure the production host's environment variables and redeploy.

Email confirmation behavior depends on the project's Auth settings and email delivery configuration. With confirmation enabled, signup shows a notice and the user must follow the email link before a session is established.

## Verification still required

- CI typecheck, lint, and production build for the current branch head.
- A real signup and email-confirmation round trip on the deployed host.
- A real sign-in, sign-out, and session refresh round trip.
- Create a first business and verify that the Auth user receives one profile, one active owner membership, one primary branch, three system roles, the expected role permissions, and one owner assignment.
- Verify that a second account cannot list or access the first account's business.
- These live tests must use user-approved test accounts; no test accounts or persistent tenant records have been created by this implementation.
