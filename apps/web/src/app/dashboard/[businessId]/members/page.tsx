import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { signOutAction } from "@/app/actions/auth";
import { MembersPanel } from "./members-panel";
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
        canInvite={permissionKeys.has("team.members.invite")}
        canTransfer={permissionKeys.has("business.ownership.transfer")}
      />
    </main>
  );
}
