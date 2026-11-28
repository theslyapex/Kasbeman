"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type TeamActionResult = {
  error?: string;
  notice?: string;
  token?: string;
};

const invitationSchema = z.object({
  businessId: z.string().uuid(),
  email: z.string().trim().email().max(254),
  roleKey: z.enum(["admin", "member"]),
});

export async function createInvitationAction(formData: FormData): Promise<TeamActionResult> {
  const parsed = invitationSchema.safeParse({
    businessId: formData.get("businessId"),
    email: formData.get("email"),
    roleKey: formData.get("roleKey"),
  });
  if (!parsed.success) return { error: "ایمیل و نقش دعوت معتبر نیست." };

  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };

  const { data, error } = await supabase.rpc("create_business_invitation", {
    p_business_id: parsed.data.businessId,
    p_email: parsed.data.email.toLowerCase(),
    p_role_key: parsed.data.roleKey,
    p_expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
  if (error) return { error: "ساخت دعوت انجام نشد. مجوز و ایمیل را بررسی کنید." };

  const invitation = Array.isArray(data) ? data[0] : data;
  if (!invitation?.invitation_token) return { error: "توکن دعوت از سرور دریافت نشد." };

  revalidatePath(`/dashboard/${parsed.data.businessId}/members`);
  return {
    notice: "دعوت ساخته شد. توکن فقط همین یک‌بار نمایش داده می‌شود؛ آن را با فرد دعوت‌شده به اشتراک بگذارید.",
    token: invitation.invitation_token as string,
  };
}

export async function revokeInvitationAction(
  businessId: string,
  invitationId: string,
): Promise<TeamActionResult> {
  if (!z.string().uuid().safeParse(businessId).success ||
      !z.string().uuid().safeParse(invitationId).success) {
    return { error: "شناسه دعوت معتبر نیست." };
  }
  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };

  const { data, error } = await supabase.rpc("revoke_business_invitation", {
    p_business_id: businessId,
    p_invitation_id: invitationId,
  });
  if (error || data !== true) return { error: "لغو دعوت انجام نشد؛ ممکن است دعوت قبلاً تعیین تکلیف شده باشد." };

  revalidatePath(`/dashboard/${businessId}/members`);
  return { notice: "دعوت لغو شد." };
}

const transferSchema = z.object({
  businessId: z.string().uuid(),
  newOwnerUserId: z.string().uuid(),
});

export async function transferOwnershipAction(formData: FormData): Promise<TeamActionResult> {
  const parsed = transferSchema.safeParse({
    businessId: formData.get("businessId"),
    newOwnerUserId: formData.get("newOwnerUserId"),
  });
  if (!parsed.success) return { error: "عضو انتخاب‌شده معتبر نیست." };

  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };
  if (parsed.data.newOwnerUserId === auth.user.id) {
    return { error: "مالک جدید باید شخص دیگری باشد." };
  }

  const { error } = await supabase.rpc("transfer_business_ownership", {
    p_business_id: parsed.data.businessId,
    p_new_owner_user_id: parsed.data.newOwnerUserId,
  });
  if (error) return { error: "انتقال مالکیت انجام نشد. مجوز، وضعیت عضو و نقش‌های فعال بررسی شوند." };

  revalidatePath(`/dashboard/${parsed.data.businessId}/members`);
  revalidatePath("/dashboard");
  return { notice: "مالکیت منتقل شد. نقش مالک قبلی به مدیر تغییر یافت." };
}
