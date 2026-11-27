# Security baseline

1. Never expose Supabase secret/service-role keys to browser or mobile clients.
2. Treat the publishable key as public; it does not replace authorization.
3. Enable RLS on every table exposed through Supabase APIs.
4. Policies must verify active business membership, required permission, and branch scope.
5. Do not use user-editable user_metadata for authorization decisions.
6. For UPDATE access, define and test both USING and WITH CHECK, plus required SELECT access.
7. Prefer SECURITY INVOKER. Review SECURITY DEFINER functions individually, with a fixed search_path and minimal grants.
8. Keep Storage buckets private by default and authorize file access through tenant ownership.
9. Record privileged and sensitive actions in append-oriented audit logs.
10. Test cross-tenant access, revoked membership, branch isolation, privilege escalation, and file access.

This is an engineering baseline, not a claim of legal or regulatory certification.
