"use client";

import Link from "next/link";
import { useActionState } from "react";
import { createBusinessAction, type BusinessActionState } from "@/app/actions/business";

const initialState: BusinessActionState = {};

export default function NewBusinessPage() {
  const [state, formAction, pending] = useActionState(createBusinessAction, initialState);
  return (
    <main className="auth-shell">
      <Link className="brand auth-brand" href="/dashboard">
        <span className="brand-mark">ک</span><span>کسبمن</span>
      </Link>
      <section className="auth-panel">
        <span className="section-kicker">NEW BUSINESS</span>
        <h1 className="auth-title">اولین فضای کاری</h1>
        <p className="auth-description">با ساخت کسب‌وکار، حساب تو به‌صورت اتمیک مالک آن می‌شود و شعبه اصلی و نقش‌های پایه ساخته می‌شوند.</p>
        <form action={formAction} className="auth-form">
          <label className="field">
            <span>نام کسب‌وکار</span>
            <input autoComplete="organization" maxLength={160} name="name" placeholder="مثلاً فروشگاه سپهر" required />
          </label>
          <label className="field">
            <span>شناسه لاتین کسب‌وکار</span>
            <input autoCapitalize="none" dir="ltr" maxLength={63} minLength={3} name="slug" pattern="[a-z0-9][a-z0-9-]{1,61}[a-z0-9]" placeholder="sepehr-store" required />
            <small>فقط حروف کوچک انگلیسی، عدد و خط تیره؛ این شناسه باید یکتا باشد.</small>
          </label>
          {state.error ? <p className="form-message error" role="alert">{state.error}</p> : null}
          <button className="form-submit" disabled={pending} type="submit">{pending ? "در حال ساخت..." : "ساخت فضای کاری"}</button>
          <Link className="back-link" href="/dashboard">بازگشت به فضای کاری</Link>
        </form>
      </section>
    </main>
  );
}
