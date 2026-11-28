"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AcceptInvitationState = { error?: string };

export async function acceptInvitationAction(
  _previous: AcceptInvitationState,
  formData: FormData,
): Promise<AcceptInvitationState> {
  const parsed = z.string().regex(/^[0-9a-f]{64}$/).safeParse(formData.get("token"));
  if (!parsed.success) return { error: "پیوند دعوت معتبر نیست." };

  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "ابتدا وارد حسابی شوید که ایمیل دعوت‌نامه برای آن صادر شده است." };

  const { error } = await supabase.rpc("accept_business_invitation", {
    p_token: parsed.data,
  });
  if (error) return { error: "پذیرش دعوت انجام نشد. ایمیل تأییدشده حساب باید با ایمیل دعوت‌نامه یکسان باشد." };

  revalidatePath("/dashboard");
  redirect("/dashboard");
}
