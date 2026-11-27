"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signUpAction, type AuthActionState } from "@/app/actions/auth";

const initialState: AuthActionState = {};

export function SignupForm() {
  const [state, formAction, pending] = useActionState(signUpAction, initialState);
  return (
    <form action={formAction} className="auth-form">
      <label className="field">
        <span>ایمیل</span>
        <input autoComplete="email" dir="ltr" name="email" placeholder="name@example.com" required type="email" />
      </label>
      <label className="field">
        <span>رمز عبور</span>
        <input autoComplete="new-password" minLength={10} name="password" placeholder="حداقل ۱۰ کاراکتر" required type="password" />
      </label>
      <label className="field">
        <span>تکرار رمز عبور</span>
        <input autoComplete="new-password" minLength={10} name="confirmPassword" placeholder="رمز عبور را دوباره وارد کنید" required type="password" />
      </label>
      {state.error ? <p className="form-message error" role="alert">{state.error}</p> : null}
      {state.notice ? <p className="form-message notice" role="status">{state.notice}</p> : null}
      <button className="form-submit" disabled={pending} type="submit">{pending ? "در حال ساخت حساب..." : "ایجاد حساب کسبمن"}</button>
      <p className="auth-switch">قبلاً حساب ساخته‌ای؟ <Link href="/login">ورود</Link></p>
    </form>
  );
}
