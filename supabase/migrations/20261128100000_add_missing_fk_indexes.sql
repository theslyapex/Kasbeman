-- Candidate-only performance migration based on the 2026-11-28
-- read-only Supabase advisor and catalog review.
-- Do not apply to the hosted project without separate approval.

begin;

create index business_invitations_invited_by_idx
  on public.business_invitations (invited_by);

create index businesses_created_by_idx
  on public.businesses (created_by);

create index member_role_assignments_assigned_by_idx
  on public.member_role_assignments (assigned_by);

create index member_role_assignments_branch_fk_idx
  on public.member_role_assignments (business_id, branch_id);

create index member_role_assignments_role_fk_idx
  on public.member_role_assignments (business_id, role_id);

create index roles_created_by_idx
  on public.roles (created_by);

commit;
