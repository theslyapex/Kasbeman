import Link from "next/link";
import { redirect } from "next/navigation";
import { signOutAction } from "@/app/actions/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type DashboardPageProps = { searchParams: Promise<{ created?: string }> };

export const dynamic = "force-dynamic";
export const metadata = { title: "فضای کاری" };

export default async function DashboardPage({ searchParams }: DashboardPageProps) {
  const supabase = await createSupabaseServerClient();
  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError || !authData.user) redirect("/login");

  const { data: businesses, error } = await supabase
    .from("businesses")
    .select("id, name, slug, created_at")
    .order("created_at", { ascending: false });

  if (error) throw new Error("دریافت فهرست کسب‌وکارها انجام نشد.");
  const params = await searchParams;

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/">
          <span className="brand-mark">ک</span><span>کسبمن</span>
        </Link>
        <form action={signOutAction}><button className="signout-button" type="submit">خروج از حساب</button></form>
      </header>

      <section className="dashboard-heading">
        <span className="section-kicker">YOUR WORKSPACE</span>
        <h1>فضای کاری تو</h1>
        <p>{authData.user.email}</p>
      </section>

      {params.created === "1" ? <p className="form-message notice">کسب‌وکار با موفقیت ساخته شد و نقش مالک برای حساب تو ثبت شد.</p> : null}

      <section className="business-section">
        <div className="business-section-heading">
          <div><h2>کسب‌وکارهای من</h2><p>هر کسب‌وکار فضای داده، اعضا و تنظیمات مستقل دارد.</p></div>
          <Link className="form-submit compact-submit" href="/dashboard/new-business">ساخت کسب‌وکار</Link>
        </div>

        {businesses && businesses.length > 0 ? (
          <div className="business-list">
            {businesses.map((business) => (
              <article className="business-item" key={business.id}>
                <span className="business-symbol">ک</span>
                <div className="business-meta"><h3>{business.name}</h3><span dir="ltr">{business.slug}</span></div>
                <Link className="business-manage-link" href={`/dashboard/${business.id}/members`}>مدیریت اعضا</Link>
                <Link className="business-manage-link" href={`/dashboard/${business.id}/tickets`}>تیکت‌ها</Link>
                <Link className="business-manage-link" href={`/dashboard/${business.id}/customers`}>مشتریان</Link>
                <span className="business-status">فعال</span>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-business">
            <span className="empty-mark">+</span>
            <h3>هنوز کسب‌وکاری نساخته‌ای</h3>
            <p>اولین فضای کاری‌ات را بساز تا مدیریت را شروع کنیم.</p>
            <Link className="form-submit compact-submit" href="/dashboard/new-business">ساخت اولین کسب‌وکار</Link>
          </div>
        )}
      </section>
    </main>
  );
}
