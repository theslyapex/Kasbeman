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

for (const rpc of ["create_sale_draft", "record_customer_receipt", "reverse_customer_receipt", "confirm_sale"]) {
  const start = sql.toLowerCase().indexOf(`function public.${rpc}(`);
  if (start < 0) {
    failures.push(`${rpc}: expected RPC function is missing`);
    continue;
  }
  const block = sql.slice(start, sql.indexOf("$$;", start) + 3);
  if (!/security definer/i.test(block)) failures.push(`${rpc}: expected SECURITY DEFINER`);
  if (!/private\.has_business_permission/i.test(block)) failures.push(`${rpc}: missing live permission check`);
  if (!/set search_path\s*=\s*''/i.test(block)) failures.push(`${rpc}: missing empty search_path`);
}

const immutableTables = ["customer_receipts", "customer_receipt_reversals", "stock_movements"];
for (const table of immutableTables) {
  const grants = [...sql.matchAll(new RegExp(`grant ([^;]+) on (?:table )?public\\.${table} to authenticated\\s*;`, "gi"))];
  for (const grant of grants) {
    if (/\\b(insert|update|delete|truncate|references|trigger)\\b/i.test(grant[1])) {
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
