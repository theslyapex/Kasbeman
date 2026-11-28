import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { signOutAction } from "@/app/actions/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { CustomersPanel } from "./customers-panel";

export const dynamic = "force-dynamic";
export const metadata = { title: "مدیریت مشتریان" };

export default async function BusinessCustomersPage({
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

  const { data: assignments } = await supabase.from("member_role_assignments")
    .select("role_id").eq("business_id", businessId)
    .eq("user_id", auth.user.id).eq("status", "active").is("branch_id", null);
  const roleIds = [...new Set((assignments ?? []).map((item) => item.role_id))];
  const { data: rolePermissions } = roleIds.length
    ? await supabase.from("role_permissions").select("permission_key")
        .eq("business_id", businessId).in("role_id", roleIds)
    : { data: [] as { permission_key: string }[] };
  const permissions = new Set((rolePermissions ?? []).map((item) => item.permission_key));

  const { data: customerRows, error: customersError } = await supabase
    .from("customers")
    .select("id,name,phone,email,company_name,address,notes,status")
    .eq("business_id", businessId)
    .order("name")
    .limit(500);

  const missingSchema = customersError?.code === "42P01" || customersError?.code === "PGRST205";
  if (customersError && !missingSchema) {
    throw new Error("دریافت فهرست مشتریان انجام نشد.");
  }

  const canRead = permissions.has("crm.customers.read");
  const canCreate = permissions.has("crm.customers.create");
  const canEdit = canRead && permissions.has("crm.customers.update");
  const canArchive = canEdit && permissions.has("crm.customers.delete");

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/dashboard"><span className="brand-mark">ک</span><span>کسبمن</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">خروج از حساب</button></form>
      </header>
      <section className="dashboard-heading">
        <span className="section-kicker">CUSTOMER RELATIONSHIP MANAGEMENT</span>
        <h1>مدیریت مشتریان {business.name}</h1>
        <p>پرونده مشتریان، اطلاعات تماس و سوابق پایه ارتباط با مشتری در یک فضای یکپارچه</p>
        <div className="dashboard-shortcuts">
          <Link className="back-link" href="/dashboard">بازگشت به فضای کاری</Link>
          <Link className="back-link" href={`/dashboard/${businessId}/tickets`}>مرکز تیکت</Link>
          <Link className="back-link" href={`/dashboard/${businessId}/members`}>مدیریت اعضا</Link>
        </div>
      </section>
      {missingSchema ? (
        <p className="form-message error" role="alert">
          هسته CRM هنوز در این محیط پایگاه داده نصب نشده است. ابتدا migration مستقل CRM باید بررسی و اعمال شود.
        </p>
      ) : null}
      <CustomersPanel
        businessId={businessId}
        customers={canRead ? (customerRows ?? []) : []}
        canRead={canRead}
        canCreate={canCreate && !missingSchema}
        canEdit={canEdit}
        canArchive={canArchive}
        schemaReady={!missingSchema}
      />
    </main>
  );
}
