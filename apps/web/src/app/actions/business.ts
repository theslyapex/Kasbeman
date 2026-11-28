"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type BusinessActionState = { error?: string };

const businessSchema = z.object({
  name: z.string().trim().min(2).max(160),
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/),
});

export async function createBusinessAction(
  _previousState: BusinessActionState,
  formData: FormData,
): Promise<BusinessActionState> {
  const parsed = businessSchema.safeParse({
    name: formData.get("name"),
    slug: formData.get("slug"),
  });

  if (!parsed.success) {
    return { error: "نام کسب‌وکار و شناسه لاتین معتبر وارد کنید. شناسه باید ۳ تا ۶۳ کاراکتر باشد." };
  }

  const supabase = await createSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) redirect("/login");

  const { data, error } = await supabase.rpc("create_business", {
    p_name: parsed.data.name,
    p_slug: parsed.data.slug,
  });

  if (error?.code === "23505") {
    return { error: "این شناسه قبلاً استفاده شده است؛ شناسه دیگری انتخاب کنید." };
  }
  if (error) {
    return { error: "ساخت کسب‌وکار انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید." };
  }
  if (data === null) {
    return { error: "در مدت کوتاهی چند کسب‌وکار ساخته‌اید. لطفاً حدود ۱۰ دقیقه دیگر دوباره تلاش کنید." };
  }

  redirect("/dashboard?created=1");
}
