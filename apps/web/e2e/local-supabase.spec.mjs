import { createRequire } from "node:module";

if (!process.env.PLAYWRIGHT_CLI_PATH) {
  throw new Error("PLAYWRIGHT_CLI_PATH is required.");
}

const require = createRequire(process.env.PLAYWRIGHT_CLI_PATH);
const { test, expect } = require("@playwright/test");

test("web signup, workspace, CRM customer and ticket flow against local Supabase", async ({ page }) => {
  const runId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const email = `kasbeman-web-e2e-${runId}@example.com`;
  const password = `Web-E2E-${runId}-Aa9!`;
  const businessName = "کسب‌وکار آزمایش وب";
  const businessSlug = `kasbeman-web-e2e-${runId}`;
  const customerName = "مشتری آزمایش وب";
  const ticketTitle = "پیگیری سفارش آزمایشی";
  const ticketComment = "پیام آزمایشی از رابط وب";

  await page.goto("/signup");
  await page.getByLabel("ایمیل").fill(email);
  await page.getByLabel("رمز عبور", { exact: true }).fill(password);
  await page.getByLabel("تکرار رمز عبور", { exact: true }).fill(password);
  await page.getByRole("button", { name: "ایجاد حساب کسبمن" }).click();

  await expect(page).toHaveURL(/dashboard(?:\?.*)?$/);
  await expect(page.getByRole("heading", { name: "فضای کاری تو" })).toBeVisible();
  await page.getByRole("link", { name: "ساخت اولین فضای کاری" }).click();

  await page.getByLabel("نام کسب‌وکار").fill(businessName);
  await page.getByLabel("شناسه لاتین کسب‌وکار").fill(businessSlug);
  await page.getByRole("button", { name: "ساخت فضای کاری" }).click();

  await expect(page).toHaveURL(/dashboard\?created=1$/);
  await expect(page.getByRole("heading", { name: businessName })).toBeVisible();
  await page.getByRole("link", { name: "مشتریان" }).click();

  await expect(page.getByRole("heading", { name: new RegExp(`مدیریت مشتریان ${businessName}`) })).toBeVisible();
  await page.getByRole("button", { name: "+ مشتری جدید" }).click();
  await page.getByLabel("نام مشتری *").fill(customerName);
  await page.getByLabel("شماره تماس").fill("09120000000");
  await page.getByLabel("ایمیل").fill(`customer-${runId}@example.com`);
  await page.getByRole("button", { name: "ثبت مشتری" }).click();
  await expect(page.getByRole("heading", { name: customerName })).toBeVisible();

  await page.getByRole("link", { name: "مرکز تیکت" }).click();
  await expect(page.getByRole("heading", { name: new RegExp(`مرکز تیکت ${businessName}`) })).toBeVisible();
  await page.getByRole("button", { name: "+ تیکت جدید" }).click();
  await page.getByLabel("عنوان").fill(ticketTitle);
  await page.getByLabel("شرح درخواست").fill("آزمون انتها به انتهای ثبت و پیگیری درخواست");
  await page.getByLabel("مشتری (اختیاری)").selectOption({ label: customerName });
  await page.getByRole("button", { name: "ثبت تیکت" }).click();
  await expect(page.getByRole("heading", { name: ticketTitle })).toBeVisible();

  await page.getByPlaceholder("پیام خود را بنویسید...").fill(ticketComment);
  await page.getByRole("button", { name: "ارسال پیام" }).click();
  await expect(page.getByText(ticketComment)).toBeVisible();

  await page.getByRole("button", { name: "خروج از حساب" }).click();
  await expect(page).toHaveURL(/login$/);
  await page.getByLabel("ایمیل").fill(email);
  await page.getByLabel("رمز عبور").fill(password);
  await page.getByRole("button", { name: "ورود به حساب" }).click();
  await expect(page).toHaveURL(/dashboard(?:\?.*)?$/);
  await expect(page.getByRole("heading", { name: businessName })).toBeVisible();
});
