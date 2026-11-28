import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { signOutAction } from "@/app/actions/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { TicketsPanel } from "./tickets-panel";

export const dynamic = "force-dynamic";
export const metadata = { title: "مدیریت تیکت‌ها" };

export default async function BusinessTicketsPage({ params }: { params: Promise<{ businessId: string }> }) {
  const { businessId } = await params;
  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) redirect("/login");

  const { data: business, error: businessError } = await supabase
    .from("businesses").select("id,name").eq("id",businessId).maybeSingle();
  if (businessError || !business) notFound();

  const { data: assignments } = await supabase.from("member_role_assignments")
    .select("role_id,branch_id").eq("business_id",businessId)
    .eq("user_id",auth.user.id).eq("status","active");
  const roleIds = [...new Set((assignments ?? []).map(x => x.role_id))];
  const { data: rolePermissions } = roleIds.length
    ? await supabase.from("role_permissions").select("role_id,permission_key")
        .eq("business_id",businessId).in("role_id",roleIds)
    : { data: [] as { role_id:string; permission_key:string }[] };

  const globalRoleIds = new Set((assignments ?? []).filter(x => !x.branch_id).map(x => x.role_id));
  const globalPermissions = new Set((rolePermissions ?? []).filter(x => globalRoleIds.has(x.role_id)).map(x => x.permission_key));
  const branchIds = [...new Set((assignments ?? []).flatMap(x => x.branch_id ? [x.branch_id] : []))];
  const branchPermissions: Record<string,string[]> = {};
  for (const branchId of branchIds) {
    const ids = new Set((assignments ?? []).filter(x => x.branch_id === branchId).map(x => x.role_id));
    branchPermissions[branchId] = (rolePermissions ?? []).filter(x => ids.has(x.role_id)).map(x => x.permission_key);
  }

  const [{ data: branches }, { data: members }, { data: customers }, { data: tickets }] = await Promise.all([
    supabase.from("branches").select("id,name,is_primary,status").eq("business_id",businessId)
      .eq("status","active").order("is_primary",{ascending:false}).order("name"),
    supabase.from("business_members").select("user_id,role_key,status").eq("business_id",businessId).eq("status","active"),
    supabase.from("customers").select("id,name").eq("business_id",businessId).eq("status","active").order("name").limit(300),
    supabase.from("tickets").select("id,business_id,branch_id,ticket_number,title,description,status,priority,requester_user_id,customer_id,assignee_user_id,due_at,resolved_at,archived_at,created_at,updated_at")
      .eq("business_id",businessId).is("archived_at",null).order("updated_at",{ascending:false}).limit(150),
  ]);

  const ticketIds = (tickets ?? []).map(t => t.id);
  const [{ data: comments }, { data: events }] = ticketIds.length ? await Promise.all([
    supabase.from("ticket_comments").select("id,ticket_id,author_user_id,body,visibility,created_at")
      .eq("business_id",businessId).in("ticket_id",ticketIds).order("created_at"),
    supabase.from("ticket_events").select("id,ticket_id,actor_user_id,event_type,payload,created_at")
      .eq("business_id",businessId).in("ticket_id",ticketIds).order("created_at",{ascending:false}).limit(400),
  ]) : [{data: [] as never[]},{data: [] as never[]}];

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/dashboard"><span className="brand-mark">ک</span><span>کسبمن</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">خروج از حساب</button></form>
      </header>
      <section className="dashboard-heading">
        <span className="section-kicker">CUSTOMER SUPPORT</span>
        <h1>مرکز تیکت {business.name}</h1>
        <p>درخواست‌ها، پیگیری‌ها و سوابق گفتگو در یک فضای یکپارچه</p>
        <div className="dashboard-shortcuts">
          <Link className="back-link" href="/dashboard">بازگشت به فضای کاری</Link>
          <Link className="back-link" href={\`/dashboard/\${businessId}/members\`}>مدیریت اعضا</Link>
        </div>
      </section>
      <TicketsPanel
        businessId={businessId}
        tickets={tickets ?? []}
        branches={(branches ?? []).map(x => ({id:x.id,name:x.name,isPrimary:x.is_primary}))}
        members={(members ?? []).map(x => ({id:x.user_id,roleKey:x.role_key}))}
        customers={customers ?? []}
        comments={comments ?? []}
        events={events ?? []}
        globalPermissions={[...globalPermissions]}
        branchPermissions={branchPermissions}
      />
    </main>
  );
}
