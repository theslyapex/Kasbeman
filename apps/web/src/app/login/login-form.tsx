"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signInAction, type AuthActionState } from "@/app/actions/auth";

const initialState: AuthActionState = {};

export function LoginForm() {
  const [state, formAction, pending] = useActionState(signInAction, initialState);
  return (
    <form action={formAction} className="auth-form">
      <label className="field">
        <span>ایمیل</span>
        <input autoComplete="email" dir="ltr" name="email" placeholder="name@example.com" required type="email" />
      </label>
      <label className="field">
        <span>رمز عبور</span>
        <input autoComplete="current-password" name="password" placeholder="رمز عبور حساب" required type="password" />
      </label>
      {state.error ? <p className="form-message error" role="alert">{state.error}</p> : null}
      <button className="form-submit" disabled={pending} type="submit">{pending ? "در حال ورود..." : "ورود به حساب"}</button>
      <p className="auth-switch">هنوز حساب نداری؟ <Link href="/signup">ایجاد حساب</Link></p>
    </form>
  );
}
