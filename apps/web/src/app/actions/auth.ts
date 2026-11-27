"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AuthActionState = {
  error?: string;
  notice?: string;
};

const signInSchema = z.object({
  email: z.string().trim().email().max(254),
  password: z.string().min(1).max(128),
});

const signUpSchema = z.object({
  email: z.string().trim().email().max(254),
  password: z.string().min(10).max(128),
  confirmPassword: z.string().min(10).max(128),
});

export async function signInAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = signInSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!parsed.success) return { error: "ایمیل یا رمز عبور معتبر نیست." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);

  if (error) return { error: "ورود انجام نشد. ایمیل و رمز عبور را بررسی کنید." };

  redirect("/dashboard");
}

export async function signUpAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = signUpSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
  });

  if (!parsed.success) {
    return { error: "ایمیل معتبر و رمز عبور حداقل ۱۰ کاراکتری وارد کنید." };
  }

  if (parsed.data.password !== parsed.data.confirmPassword) {
    return { error: "تکرار رمز عبور با رمز اصلی یکسان نیست." };
  }

  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") ?? "https";
  const origin = host ? `${protocol}://${host}` : "http://localhost:3000";

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signUp({
    email: parsed.data.email.toLowerCase(),
    password: parsed.data.password,
    options: { emailRedirectTo: `${origin}/auth/callback?next=/dashboard` },
  });

  if (error) {
    return { error: "ثبت‌نام انجام نشد. ممکن است این ایمیل قبلاً ثبت شده باشد." };
  }

  if (!data.session) {
    return {
      notice: "حساب ساخته شد. برای فعال‌سازی، ایمیل تأیید ارسال‌شده را باز کنید؛ سپس وارد کسبمن شوید.",
    };
  }

  redirect("/dashboard");
}

export async function signOutAction(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/login");
}
