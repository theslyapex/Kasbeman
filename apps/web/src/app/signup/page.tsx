import Link from "next/link";
import { redirect } from "next/navigation";
import { SignupForm } from "./signup-form";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { title: "ایجاد حساب" };

export default async function SignupPage() {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.auth.getUser();
  if (data.user) redirect("/dashboard");

  return (
    <main className="auth-shell">
      <Link className="brand auth-brand" href="/">
        <span className="brand-mark">ک</span><span>کسبمن</span>
      </Link>
      <section className="auth-panel">
        <span className="section-kicker">START WITH KASBEMAN</span>
        <h1 className="auth-title">حساب کسبمن بساز</h1>
        <p className="auth-description">با یک حساب، می‌توانی چند کسب‌وکار مستقل را مدیریت کنی.</p>
        <SignupForm />
      </section>
      <p className="auth-footnote">اطلاعات حساب تو برای ورود امن به کسبمن استفاده می‌شود.</p>
    </main>
  );
}
