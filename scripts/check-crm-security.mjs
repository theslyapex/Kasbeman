import { readFile } from "node:fs/promises";

const crm = await readFile("supabase/drafts/crm_core.sql", "utf8");
const sales = await readFile("supabase/drafts/sales_inventory_core.sql", "utf8");
const failures = [];

for (const policy of [
  "customers_select_authorized",
  "customers_insert_authorized",
  "customers_update_authorized",
]) {
  if (!crm.includes(`create policy ${policy} on public.customers`)) {
    failures.push(`CRM customer policy is missing: ${policy}`);
  }
}

if (!/alter table public\.customers enable row level security/i.test(crm)) {
  failures.push("customers: RLS is not enabled");
}
if (!/unique \(business_id, id\)/i.test(crm)) {
  failures.push("customers: tenant-scoped unique key is missing");
}
if (!/before update of business_id, status on public\.customers/i.test(crm)) {
  failures.push("customers: business/status guard trigger is missing");
}
if (!/private\.has_business_permission\([\s\S]*?'crm\.customers\.delete'/i.test(crm)) {
  failures.push("customers: archive status does not require crm.customers.delete");
}
if (!/grant select, insert on table public\.customers to authenticated/i.test(crm)) {
  failures.push("customers: expected authenticated select/insert grant is missing");
}
if (/grant [^;]*\bdelete\b[^;]* on (?:table )?public\.customers to authenticated/i.test(crm)) {
  failures.push("customers: authenticated has a direct DELETE grant");
}

const guardStart = crm.indexOf("create or replace function private.guard_customer_status_permission()");
const guardEnd = crm.indexOf("$customer_status_guard$;", guardStart);
const guard = crm.slice(guardStart, guardEnd);
if (guardStart < 0 || !/set search_path\s*=\s*''/i.test(guard)) {
  failures.push("customer status guard: missing function or empty search_path");
}
if (!/revoke all on function private\.guard_customer_status_permission\(\)[\s\S]*?from public, anon, authenticated/i.test(crm)) {
  failures.push("customer status guard: direct API execution is not revoked");
}

if (/create table public\.customers/i.test(sales)) {
  failures.push("sales/inventory draft still owns the customers table");
}
if (/create policy customers_(select|insert|update)_authorized/i.test(sales)) {
  failures.push("sales/inventory draft still owns CRM customer policies");
}

if (failures.length) {
  console.error(failures.map((failure) => `- ${failure}`).join("\\n"));
  process.exitCode = 1;
} else {
  console.log("CRM security structure checks passed: isolated schema, RLS, tenant key, granular archive guard and restricted grants.");
}
