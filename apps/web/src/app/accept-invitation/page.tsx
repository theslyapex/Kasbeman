import Link from "next/link";
import { redirect } from "next/navigation";
import { AcceptInvitationForm } from "./accept-invitation-form";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const metadata = { title: "پذیرش دعوت‌نامه" };

export default async function AcceptInvitationPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token = "" } = await searchParams;
  if (!/^[0-9a-f]{64}$/.test(token)) {
    return <main className="auth-shell"><section className="auth-panel"><h1 className="auth-title">پیوند دعوت معتبر نیست</h1><p className="auth-description">ممکن است دعوت لغو یا منقضی شده باشد.</p><Link className="back-link" href="/dashboard">بازگشت</Link></section></main>;
  }
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) {
    return (
      <main className="auth-shell">
        <section className="auth-panel">
          <h1 className="auth-title">ابتدا وارد حساب شو</h1>
          <p className="auth-description">پس از ورود، به همین پیوند برگرد تا دعوت را با ایمیل تأییدشده حساب بپذیری. توکن دعوت در پیوند فعلی باقی می‌ماند.</p>
          <Link className="form-submit" href="/login">ورود به حساب</Link>
        </section>
      </main>
    );
  }

  return (
    <main className="auth-shell">
      <Link className="brand auth-brand" href="/dashboard"><span className="brand-mark">ک</span><span>کسبمن</span></Link>
      <section className="auth-panel">
        <span className="section-kicker">BUSINESS INVITATION</span>
        <h1 className="auth-title">پیوستن به کسب‌وکار</h1>
        <p className="auth-description">پس از تأیید، عضویت و نقش شما به‌صورت اتمیک ثبت می‌شود.</p>
        <AcceptInvitationForm token={token} />
      </section>
    </main>
  );
}
