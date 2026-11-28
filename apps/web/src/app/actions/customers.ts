"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CustomerActionResult = { error?: string; notice?: string };

const uuid = z.string().uuid();
const optionalText = (max: number) => z.string().trim().max(max).optional();
const createSchema = z.object({
  businessId: uuid,
  name: z.string().trim().min(2).max(160),
  phone: optionalText(32),
  email: optionalText(254).refine((value) => !value || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value), "ایمیل معتبر نیست."),
  companyName: optionalText(160),
  address: optionalText(500),
  notes: optionalText(2000),
});
const updateSchema = createSchema.extend({ customerId: uuid });
const statusSchema = z.object({
  businessId: uuid,
  customerId: uuid,
  status: z.enum(["active", "archived"]),
});

async function authenticatedClient() {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return { supabase: null, user: null };
  return { supabase, user: data.user };
}
function refresh(businessId: string) {
  revalidatePath(`/dashboard/${businessId}/customers`);
}

export async function createCustomerAction(input: unknown): Promise<CustomerActionResult> {
  const parsed = createSchema.safeParse(input);
  if (!parsed.success) return { error: "اطلاعات مشتری معتبر نیست؛ نام و ایمیل را بررسی کنید." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };

  const { error } = await supabase.from("customers").insert({
    business_id: parsed.data.businessId,
    created_by: user.id,
    name: parsed.data.name,
    phone: parsed.data.phone || null,
    email: parsed.data.email || null,
    company_name: parsed.data.companyName || null,
    address: parsed.data.address || null,
    notes: parsed.data.notes || null,
  });
  if (error) return { error: "ثبت مشتری انجام نشد؛ مجوز ایجاد و اطلاعات را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: "مشتری با موفقیت ثبت شد." };
}

export async function updateCustomerAction(input: unknown): Promise<CustomerActionResult> {
  const parsed = updateSchema.safeParse(input);
  if (!parsed.success) return { error: "اطلاعات ویرایش مشتری معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };

  const { data, error } = await supabase.from("customers").update({
    name: parsed.data.name,
    phone: parsed.data.phone || null,
    email: parsed.data.email || null,
    company_name: parsed.data.companyName || null,
    address: parsed.data.address || null,
    notes: parsed.data.notes || null,
  }).eq("business_id", parsed.data.businessId).eq("id", parsed.data.customerId)
    .select("id").maybeSingle();
  if (error || !data) return { error: "ویرایش انجام نشد؛ مجوز مشاهده و ویرایش را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: "پرونده مشتری به‌روزرسانی شد." };
}

export async function setCustomerStatusAction(input: unknown): Promise<CustomerActionResult> {
  const parsed = statusSchema.safeParse(input);
  if (!parsed.success) return { error: "درخواست تغییر وضعیت معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };

  const { data, error } = await supabase.from("customers")
    .update({ status: parsed.data.status })
    .eq("business_id", parsed.data.businessId)
    .eq("id", parsed.data.customerId)
    .select("id").maybeSingle();
  if (error || !data) return { error: "تغییر وضعیت انجام نشد؛ مجوز بایگانی یا بازگردانی را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: parsed.data.status === "archived" ? "مشتری بایگانی شد." : "مشتری دوباره فعال شد." };
}
