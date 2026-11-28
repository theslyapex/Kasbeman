import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { signOutAction } from "@/app/actions/auth";
import { MembersPanel } from "./members-panel";
import { RolesPanel } from "./roles-panel";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const metadata = { title: "اعضای کسب‌وکار" };

export default async function BusinessMembersPage({
  params,
}: {
  params: Promise<{ businessId: string }>;
}) {
  const { businessId } = await params;
  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) redirect("/login");

  const { data: business, error: businessError } = await supabase
    .from("businesses").select("id,name").eq("id", businessId).maybeSingle();
  if (businessError || !business) notFound();

  const { data: members, error: membersError } = await supabase
    .from("business_members")
    .select("user_id,role_key,status,joined_at")
    .eq("business_id", businessId)
    .order("joined_at", { ascending: true });
  if (membersError) throw new Error("دریافت اعضای کسب‌وکار انجام نشد.");

  const { data: invitations, error: invitationsError } = await supabase
    .from("business_invitations")
    .select("id,email,role_key,status,expires_at")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })
    .limit(50);
  if (invitationsError && invitationsError.code !== "42501") {
    throw new Error("دریافت دعوت‌نامه‌ها انجام نشد.");
  }

  const { data: assignments } = await supabase
    .from("member_role_assignments")
    .select("role_id,branch_id")
    .eq("business_id", businessId)
    .eq("user_id", auth.user.id)
    .eq("status", "active")
    .is("branch_id", null);
  const roleIds = (assignments ?? []).map((item) => item.role_id);
  const { data: rolePermissions } = roleIds.length
    ? await supabase.from("role_permissions").select("permission_key").eq("business_id", businessId).in("role_id", roleIds)
    : { data: [] as { permission_key: string }[] };
  const permissionKeys = new Set((rolePermissions ?? []).map((item) => item.permission_key));

  const { data: roleRows, error: rolesError } = await supabase
    .from("roles")
    .select("id,role_key,name,description,is_system,status")
    .eq("business_id", businessId)
    .order("is_system", { ascending: false })
    .order("name");
  if (rolesError) throw new Error("دریافت نقش‌های کسب‌وکار انجام نشد.");

  const roleIdsForBusiness = (roleRows ?? []).map((role) => role.id);
  const { data: rolePermissionRows, error: rolePermissionError } = roleIdsForBusiness.length
    ? await supabase.from("role_permissions")
        .select("role_id,permission_key")
        .eq("business_id", businessId)
        .in("role_id", roleIdsForBusiness)
    : { data: [] as { role_id: string; permission_key: string }[], error: null };
  if (rolePermissionError) throw new Error("دریافت مجوزهای نقش‌ها انجام نشد.");

  const { data: permissionCatalogue, error: permissionCatalogueError } = await supabase
    .from("permissions")
    .select("permission_key,module_key,label_fa,description_fa,is_sensitive")
    .order("module_key")
    .order("action_key");
  if (permissionCatalogueError) throw new Error("دریافت فهرست مجوزها انجام نشد.");

  const roles = (roleRows ?? []).map((role) => ({
    ...role,
    permissionKeys: (rolePermissionRows ?? [])
      .filter((item) => item.role_id === role.id)
      .map((item) => item.permission_key),
  }));

  const canReadAssignments = permissionKeys.has("team.roles.assign") ||
    permissionKeys.has("team.members.read") || permissionKeys.has("team.members.manage");
  const canManageBranches = permissionKeys.has("branches.manage");
  const canReadBranches = permissionKeys.has("branches.read") || canManageBranches;
  const canLoadBranches = canReadAssignments || canReadBranches;
  const { data: branchRows } = canLoadBranches
    ? await supabase.from("branches")
        .select("id,name,code,is_primary,status")
        .eq("business_id", businessId)
        .order("is_primary", { ascending: false })
        .order("name")
    : { data: [] as { id: string; name: string; code: string | null; is_primary: boolean; status: string }[] };
  const branchNameById = new Map((branchRows ?? []).map((branch) => [branch.id, branch.name]));
  const { data: memberRoleRows } = canReadAssignments
    ? await supabase.from("member_role_assignments")
        .select("id,user_id,role_id,branch_id,status")
        .eq("business_id", businessId)
        .eq("status", "active")
    : { data: [] as { id: string; user_id: string; role_id: string; branch_id: string | null; status: string }[] };

  const roleNameById = new Map(roles.map((role) => [role.id, role.name]));
  const memberAssignments = (memberRoleRows ?? []).map((assignment) => ({
    ...assignment,
    roleName: roleNameById.get(assignment.role_id) ?? "نقش نامشخص",
    branchName: assignment.branch_id ? branchNameById.get(assignment.branch_id) ?? "شعبه" : null,
  }));
  const permissionLabelByKey = new Map((permissionCatalogue ?? []).map((permission) => [permission.permission_key, permission.label_fa]));
  const assignableRoles = roles
    .filter((role) => !role.is_system && role.status === "active")
    .map(({ id, name, description, permissionKeys }) => ({
      id, name, description,
      permissionLabels: permissionKeys.map((key) => permissionLabelByKey.get(key) ?? key),
    }));

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/dashboard"><span className="brand-mark">ک</span><span>کسبمن</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">خروج از حساب</button></form>
      </header>
      <section className="dashboard-heading">
        <span className="section-kicker">TEAM MANAGEMENT</span>
        <h1>اعضای {business.name}</h1>
        <p>مدیریت دسترسی، دعوت‌ها و مالکیت فضای کاری</p>
        <Link className="back-link" href="/dashboard">بازگشت به فهرست کسب‌وکارها</Link>
      </section>
      <MembersPanel
        businessId={businessId}
        members={members ?? []}
        invitations={invitations ?? []}
        memberAssignments={memberAssignments}
        assignableRoles={assignableRoles}
        branches={(branchRows ?? []).map(({ id, name, code, is_primary, status }) => ({
          id, name, code, is_primary,
          status: status as "active" | "inactive" | "archived",
        }))}
        canManageBranches={canManageBranches}
        canReadBranches={canReadBranches}
        canAssignRoles={permissionKeys.has("team.roles.assign")}
        canInvite={permissionKeys.has("team.members.invite")}
        canTransfer={permissionKeys.has("business.ownership.transfer")}
        canManageMembers={permissionKeys.has("team.members.manage")}
        currentUserId={auth.user.id}
      />
      <RolesPanel
        businessId={businessId}
        roles={roles}
        permissions={permissionCatalogue ?? []}
        manageablePermissionKeys={[...permissionKeys]}
        canManageRoles={permissionKeys.has("team.roles.manage")}
      />
    </main>
  );
}
