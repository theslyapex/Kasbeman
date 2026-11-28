import { readFile } from "node:fs/promises";

const file = "supabase/drafts/sales_inventory_core.sql";
const sql = await readFile(file, "utf8");
const failures = [];
const tables = [...sql.matchAll(/create table public\.([a-z_]+)\s*\(/gi)].map((match) => match[1]);
const policies = [...sql.matchAll(/create policy [a-z_]+ on public\.([a-z_]+)/gi)].map((match) => match[1]);
const rlsEnabled = [...sql.matchAll(/alter table public\.([a-z_]+) enable row level security/gi)].map((match) => match[1]);

for (const table of tables) {
  if (!rlsEnabled.includes(table)) failures.push(`${table}: RLS is not enabled`);
  if (!policies.includes(table)) failures.push(`${table}: no RLS policy is defined`);
}

const securityDefinerBlocks = [...sql.matchAll(/create or replace function ([\s\S]*?)\n\$\$;/gi)]
  .map((match) => match[1])
  .filter((block) => /security definer/i.test(block));
for (const block of securityDefinerBlocks) {
  if (!/set search_path\s*=\s*''/i.test(block)) {
    failures.push("SECURITY DEFINER function is missing an empty search_path");
  }
}

for (const rpc of ["record_customer_receipt", "reverse_customer_receipt", "confirm_sale"]) {
  const start = sql.toLowerCase().indexOf(`function public.${rpc}(`);
  if (start < 0) {
    failures.push(`${rpc}: expected RPC function is missing`);
    continue;
  }
  const block = sql.slice(start, sql.indexOf("$$;", start) + 3);
  if (!/security definer/i.test(block)) failures.push(`${rpc}: expected SECURITY DEFINER`);
  if (!/private\.has_business_permission/i.test(block)) failures.push(`${rpc}: missing live permission check`);
  const requiredPermissions = rpc === "confirm_sale"
    ? ["sales.invoices.manage", "inventory.stock.manage"]
    : ["finance.payments.manage"];
  for (const permission of requiredPermissions) {
    if (!block.includes(permission)) failures.push(`${rpc}: missing ${permission} check`);
  }
  if (!/set search_path\s*=\s*''/i.test(block)) failures.push(`${rpc}: missing empty search_path`);
}

const draftSaleStart = sql.toLowerCase().indexOf("function public.create_sale_draft(");
const draftSaleEnd = sql.indexOf("$$;", draftSaleStart);
const draftSaleFunction = sql.slice(draftSaleStart, draftSaleEnd + 3);
if (draftSaleStart < 0 || !draftSaleFunction.includes("set search_path = ''")) {
  failures.push("create_sale_draft: missing function definition or empty search_path");
}
if (/security definer/i.test(draftSaleFunction)) {
  failures.push("create_sale_draft: must remain invoker-security and rely on table RLS");
}
const salesInsertPolicyStart = sql.indexOf("create policy sales_insert_authorized");
const salesInsertPolicyEnd = sql.indexOf("create policy sale_items_select_authorized", salesInsertPolicyStart);
const salesInsertPolicy = sql.slice(salesInsertPolicyStart, salesInsertPolicyEnd);
const saleItemsInsertPolicyStart = sql.indexOf("create policy sale_items_insert_draft_authorized");
const saleItemsInsertPolicyEnd = sql.indexOf("create policy sale_items_update_draft_authorized", saleItemsInsertPolicyStart);
const saleItemsInsertPolicy = sql.slice(saleItemsInsertPolicyStart, saleItemsInsertPolicyEnd);
if (!salesInsertPolicy.includes("sales.invoices.manage") || !saleItemsInsertPolicy.includes("sales.invoices.manage")) {
  failures.push("create_sale_draft: required RLS insert policies are missing");
}

const immutableTables = ["customer_receipts", "customer_receipt_reversals"];
for (const table of immutableTables) {
  const grants = [...sql.matchAll(new RegExp(`grant ([^;]+) on (?:table )?public\\.${table} to authenticated\\s*;`, "gi"))];
  for (const grant of grants) {
    if (/\b(insert|update|delete|truncate|references|trigger)\b/i.test(grant[1])) {
      failures.push(`${table}: direct mutation grant found (${grant[1]})`);
    }
  }
}

if (!/grant select on table public\.customer_receipts to authenticated/i.test(sql)) {
  failures.push("customer_receipts: authenticated read grant is missing");
}
if (!/grant select on public\.customer_receipt_reversals to authenticated/i.test(sql)) {
  failures.push("customer_receipt_reversals: authenticated read grant is missing");
}
if (!/grant select on table public\.stock_balances to authenticated/i.test(sql)) {
  failures.push("stock_balances: authenticated read grant is missing");
}
if (!/grant select, insert on table public\.stock_movements to authenticated/i.test(sql)) {
  failures.push("stock_movements: expected controlled insert/read grant is missing");
}

if (failures.length) {
  console.error(failures.map((failure) => `- ${failure}`).join("\\n"));
  process.exitCode = 1;
} else {
  console.log(`Security structure checks passed for ${tables.length} public tables and ${securityDefinerBlocks.length} SECURITY DEFINER functions.`);
}

if (/sales\\.orders\\.(read|manage)/.test(sql)) {
  failures.push("sales/invoice policies still use legacy sales.orders permissions");
}
