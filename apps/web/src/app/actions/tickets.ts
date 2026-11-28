"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type TicketActionResult = { error?: string; notice?: string };

const uuid = z.string().uuid();
const createSchema = z.object({
  businessId: uuid, branchId: uuid,
  title: z.string().trim().min(3).max(200),
  description: z.string().trim().min(1).max(10000),
  priority: z.enum(["low", "normal", "high", "urgent"]),
  customerId: z.union([uuid, z.literal("")]).optional(),
  dueAt: z.union([z.string().datetime({ offset: true }), z.literal("")]).optional(),
});
const updateSchema = z.object({
  businessId: uuid, ticketId: uuid,
  title: z.string().trim().min(3).max(200).optional(),
  description: z.string().trim().min(1).max(10000).optional(),
  priority: z.enum(["low", "normal", "high", "urgent"]).optional(),
});
const workflowSchema = z.object({
  businessId: uuid, ticketId: uuid,
  status: z.enum(["open", "in_progress", "waiting", "resolved", "closed"]).optional(),
  assigneeUserId: z.union([uuid, z.literal(""), z.null()]).optional(),
  archive: z.boolean().optional(),
});
const commentSchema = z.object({
  businessId: uuid, ticketId: uuid,
  body: z.string().trim().min(1).max(10000),
  visibility: z.enum(["public", "internal"]),
});

async function authenticatedClient() {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return { supabase: null, user: null };
  return { supabase, user: data.user };
}
function refresh(businessId: string) { revalidatePath(\`/dashboard/\${businessId}/tickets\`); }

export async function createTicketAction(input: unknown): Promise<TicketActionResult> {
  const parsed = createSchema.safeParse(input);
  if (!parsed.success) return { error: "اطلاعات تیکت معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };
  const ticketNumber = \`TK-\${Date.now().toString(36).toUpperCase()}-\${randomUUID().slice(0, 6).toUpperCase()}\`;
  const { error } = await supabase.from("tickets").insert({
    business_id: parsed.data.businessId, branch_id: parsed.data.branchId,
    ticket_number: ticketNumber, title: parsed.data.title, description: parsed.data.description,
    priority: parsed.data.priority, requester_user_id: user.id, created_by: user.id,
    customer_id: parsed.data.customerId || null, due_at: parsed.data.dueAt || null,
  });
  if (error) return { error: "ثبت تیکت انجام نشد؛ دسترسی شعبه و اطلاعات را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: "تیکت با موفقیت ثبت شد." };
}

export async function updateTicketContentAction(input: unknown): Promise<TicketActionResult> {
  const parsed = updateSchema.safeParse(input);
  if (!parsed.success || (!parsed.data.title && !parsed.data.description && !parsed.data.priority)) return { error: "اطلاعات ویرایش معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };
  const patch = {
    ...(parsed.data.title !== undefined ? { title: parsed.data.title } : {}),
    ...(parsed.data.description !== undefined ? { description: parsed.data.description } : {}),
    ...(parsed.data.priority !== undefined ? { priority: parsed.data.priority } : {}),
  };
  const { data, error } = await supabase.from("tickets").update(patch)
    .eq("business_id", parsed.data.businessId).eq("id", parsed.data.ticketId).select("id").maybeSingle();
  if (error || !data) return { error: "ویرایش انجام نشد؛ مجوز و وضعیت تیکت را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: "تغییرات ذخیره شد." };
}

export async function updateTicketWorkflowAction(input: unknown): Promise<TicketActionResult> {
  const parsed = workflowSchema.safeParse(input);
  if (!parsed.success || (!parsed.data.status && parsed.data.assigneeUserId === undefined && parsed.data.archive !== true)) return { error: "عملیات تیکت معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };
  const patch = {
    ...(parsed.data.status ? { status: parsed.data.status } : {}),
    ...(parsed.data.assigneeUserId !== undefined ? { assignee_user_id: parsed.data.assigneeUserId || null } : {}),
    ...(parsed.data.archive === true ? { archived_at: new Date().toISOString() } : {}),
  };
  const { data, error } = await supabase.from("tickets").update(patch)
    .eq("business_id", parsed.data.businessId).eq("id", parsed.data.ticketId)
    .is("archived_at", null).select("id").maybeSingle();
  if (error || !data) return { error: "عملیات انجام نشد؛ مجوز مستقل این عملیات یا وضعیت تیکت را بررسی کنید." };
  refresh(parsed.data.businessId);
  return { notice: "عملیات با موفقیت انجام شد." };
}

export async function addTicketCommentAction(input: unknown): Promise<TicketActionResult> {
  const parsed = commentSchema.safeParse(input);
  if (!parsed.success) return { error: "متن پیام معتبر نیست." };
  const { supabase, user } = await authenticatedClient();
  if (!supabase || !user) return { error: "برای ادامه وارد حساب شوید." };
  const { error } = await supabase.from("ticket_comments").insert({
    business_id: parsed.data.businessId, ticket_id: parsed.data.ticketId,
    author_user_id: user.id, body: parsed.data.body, visibility: parsed.data.visibility,
  });
  if (error) return { error: "ثبت پیام انجام نشد؛ ممکن است مجوز ثبت این نوع پیام را نداشته باشید." };
  refresh(parsed.data.businessId);
  return { notice: "پیام ثبت شد." };
}
