import Link from "next/link";
import { redirect } from "next/navigation";
import { LoginForm } from "./login-form";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { title: "ورود" };

export default async function LoginPage() {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.auth.getUser();
  if (data.user) redirect("/dashboard");

  return (
    <main className="auth-shell">
      <Link className="brand auth-brand" href="/">
        <span className="brand-mark">ک</span><span>کسبمن</span>
      </Link>
      <section className="auth-panel">
        <span className="section-kicker">KASBEMAN ACCOUNT</span>
        <h1 className="auth-title">خوش برگشتی</h1>
        <p className="auth-description">برای ورود به فضای مدیریت کسب‌وکارت اطلاعات حسابت را وارد کن.</p>
        <LoginForm />
      </section>
      <p className="auth-footnote">کسب‌وکارت، یک قدم جلوتر.</p>
    </main>
  );
}
