"use server";

import { randomUUID } from "node:crypto";

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


export async function suspendBusinessMemberAction(
  businessId: string,
  targetUserId: string,
): Promise<TeamActionResult> {
  if (!z.string().uuid().safeParse(businessId).success ||
      !z.string().uuid().safeParse(targetUserId).success) {
    return { error: "شناسه عضو معتبر نیست." };
  }

  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };
  if (auth.user.id === targetUserId) {
    return { error: "امکان تعلیق عضویت حساب خودتان وجود ندارد." };
  }

  // The database RLS policy and lifecycle trigger enforce manager authority,
  // prevent owner suspension, and revoke active role assignments atomically.
  const { data, error } = await supabase
    .from("business_members")
    .update({ status: "suspended" })
    .eq("business_id", businessId)
    .eq("user_id", targetUserId)
    .eq("status", "active")
    .select("user_id")
    .maybeSingle();

  if (error || !data) {
    return { error: "تعلیق عضو انجام نشد؛ ممکن است عضو مالک باشد یا مجوز مدیریت عضویت را نداشته باشید." };
  }

  revalidatePath(`/dashboard/${businessId}/members`);
  revalidatePath("/dashboard");
  return { notice: "عضویت تعلیق شد و دسترسی‌های فعال او در دیتابیس لغو شدند." };
}


const customRoleSchema = z.object({
  businessId: z.string().uuid(),
  roleId: z.string().uuid().optional(),
  name: z.string().trim().min(2).max(80),
  description: z.string().trim().max(300).optional().default(""),
  permissionKeys: z.array(z.string().regex(/^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$/)).max(100),
});

async function getActorBusinessPermissions(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  businessId: string,
  userId: string,
): Promise<Set<string> | null> {
  const { data: assignments, error: assignmentError } = await supabase
    .from("member_role_assignments")
    .select("role_id")
    .eq("business_id", businessId)
    .eq("user_id", userId)
    .eq("status", "active")
    .is("branch_id", null);
  if (assignmentError) return null;

  const roleIds = (assignments ?? []).map((row) => row.role_id);
  if (!roleIds.length) return new Set();

  const { data: rows, error } = await supabase
    .from("role_permissions")
    .select("permission_key")
    .eq("business_id", businessId)
    .in("role_id", roleIds);
  if (error) return null;
  return new Set((rows ?? []).map((row) => row.permission_key));
}

export async function saveCustomRoleAction(input: {
  businessId: string;
  roleId?: string;
  name: string;
  description?: string;
  permissionKeys: string[];
}): Promise<TeamActionResult> {
  const parsed = customRoleSchema.safeParse(input);
  if (!parsed.success) return { error: "اطلاعات نقش یا مجوزهای انتخاب‌شده معتبر نیست." };

  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };

  const actorPermissions = await getActorBusinessPermissions(
    supabase, parsed.data.businessId, auth.user.id,
  );
  if (!actorPermissions?.has("team.roles.manage")) {
    return { error: "مجوز مدیریت نقش‌ها را ندارید." };
  }
  if (parsed.data.permissionKeys.some((key) => !actorPermissions.has(key))) {
    return { error: "فقط می‌توانید مجوزهایی را به نقش بدهید که خودتان در همین کسب‌وکار دارید." };
  }

  const uniqueKeys = [...new Set(parsed.data.permissionKeys)];
  const rolePayload = {
    name: parsed.data.name,
    description: parsed.data.description || null,
  };

  let roleId = parsed.data.roleId;
  if (roleId) {
    if (!z.string().uuid().safeParse(roleId).success) return { error: "شناسه نقش معتبر نیست." };
    const { data: role, error: roleError } = await supabase
      .from("roles")
      .select("id,is_system,status")
      .eq("business_id", parsed.data.businessId)
      .eq("id", roleId)
      .maybeSingle();
    if (roleError || !role || role.is_system || role.status !== "active") {
      return { error: "این نقش سفارشی قابل ویرایش نیست." };
    }
    const { error: updateError } = await supabase
      .from("roles")
      .update(rolePayload)
      .eq("business_id", parsed.data.businessId)
      .eq("id", roleId);
    if (updateError) return { error: "ویرایش اطلاعات نقش انجام نشد." };

    const { data: currentRows, error: currentError } = await supabase
      .from("role_permissions")
      .select("permission_key")
      .eq("business_id", parsed.data.businessId)
      .eq("role_id", roleId);
    if (currentError) return { error: "دریافت مجوزهای فعلی نقش انجام نشد." };
    const currentKeys = new Set((currentRows ?? []).map((row) => row.permission_key));
    const additions = uniqueKeys.filter((key) => !currentKeys.has(key));
    const removals = [...currentKeys].filter((key) => !uniqueKeys.includes(key));

    if (additions.length) {
      const { error: insertError } = await supabase.from("role_permissions").insert(
        additions.map((permission_key) => ({
          business_id: parsed.data.businessId,
          role_id: roleId,
          permission_key,
        })),
      );
      if (insertError) return { error: "افزودن مجوزها انجام نشد؛ تغییرات قبلی حفظ شدند." };
    }
    if (removals.length) {
      const { error: deleteError } = await supabase
        .from("role_permissions")
        .delete()
        .eq("business_id", parsed.data.businessId)
        .eq("role_id", roleId)
        .in("permission_key", removals);
      if (deleteError) {
        if (additions.length) {
          await supabase.from("role_permissions").delete()
            .eq("business_id", parsed.data.businessId)
            .eq("role_id", roleId)
            .in("permission_key", additions);
        }
        return { error: "حذف برخی مجوزها انجام نشد؛ تغییرات جدید برگردانده شدند." };
      }
    }
  } else {
    const roleKey = `custom_${randomUUID().replace(/-/g, "").slice(0, 24)}`;
    const { data: role, error: insertRoleError } = await supabase
      .from("roles")
      .insert({
        business_id: parsed.data.businessId,
        role_key: roleKey,
        ...rolePayload,
        is_system: false,
        created_by: auth.user.id,
      })
      .select("id")
      .single();
    if (insertRoleError || !role) return { error: "ساخت نقش سفارشی انجام نشد." };
    roleId = role.id;

    if (uniqueKeys.length) {
      const { error: permissionsError } = await supabase.from("role_permissions").insert(
        uniqueKeys.map((permission_key) => ({
          business_id: parsed.data.businessId,
          role_id: roleId,
          permission_key,
        })),
      );
      if (permissionsError) {
        await supabase.from("roles").delete()
          .eq("business_id", parsed.data.businessId)
          .eq("id", roleId);
        return { error: "ثبت مجوزهای نقش انجام نشد؛ نقش ناقص حذف شد." };
      }
    }
  }

  revalidatePath(`/dashboard/${parsed.data.businessId}/members`);
  return { notice: "نقش سفارشی و مجوزهای آن ذخیره شد." };
}

export async function archiveCustomRoleAction(
  businessId: string,
  roleId: string,
): Promise<TeamActionResult> {
  if (!z.string().uuid().safeParse(businessId).success ||
      !z.string().uuid().safeParse(roleId).success) {
    return { error: "شناسه نقش معتبر نیست." };
  }
  const supabase = await createSupabaseServerClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) return { error: "برای ادامه وارد حساب شوید." };
  const actorPermissions = await getActorBusinessPermissions(supabase, businessId, auth.user.id);
  if (!actorPermissions?.has("team.roles.manage")) {
    return { error: "مجوز مدیریت نقش‌ها را ندارید." };
  }

  const { data, error } = await supabase
    .from("roles")
    .update({ status: "archived" })
    .eq("business_id", businessId)
    .eq("id", roleId)
    .eq("is_system", false)
    .eq("status", "active")
    .select("id")
    .maybeSingle();
  if (error || !data) return { error: "بایگانی نقش انجام نشد؛ نقش ممکن است سیستمی یا قبلاً بایگانی شده باشد." };

  revalidatePath(`/dashboard/${businessId}/members`);
  return { notice: "نقش بایگانی شد؛ دسترسی‌های آن دیگر در بررسی مجوزها مؤثر نیستند." };
}
