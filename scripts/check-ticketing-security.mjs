import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const migrationNames = (await readdir("supabase/migrations"))
  .filter((name) => /^\d+_ticketing_core\.sql$/.test(name));
const failures = [];
if (migrationNames.length !== 1) {
  console.error("Expected exactly one canonical ticketing migration, found " + migrationNames.length + ".");
  process.exit(1);
}

const ticketing = await readFile(join("supabase/migrations", migrationNames[0]), "utf8");
const draft = await readFile("supabase/drafts/ticketing_core.sql", "utf8");
const sqlBody = (source) => {
  const start = source.indexOf("begin;");
  const end = source.lastIndexOf("commit;");
  return start >= 0 && end > start ? source.slice(start, end + "commit;".length).trim() : "";
};
if (!sqlBody(ticketing) || sqlBody(ticketing) !== sqlBody(draft)) {
  failures.push("Canonical ticketing migration SQL does not match the reviewed draft.");
}
if (/SECURITY REVIEW DRAFT|NOT a production migration/i.test(ticketing.slice(0, 500))) {
  failures.push("Canonical ticketing migration still has a draft header.");
}

for (const table of ["tickets", "ticket_comments", "ticket_events"]) {
  if (!new RegExp("alter table public\\." + table + " enable row level security", "i").test(ticketing)) {
    failures.push(table + ": RLS is not enabled");
  }
}
for (const policy of [
  "tickets_select_permission",
  "tickets_insert_permission",
  "tickets_update_permission",
  "ticket_comments_select_permission",
  "ticket_comments_insert_permission",
  "ticket_events_select_permission",
]) {
  if (!ticketing.includes("create policy " + policy + " on public.")) {
    failures.push("Missing policy: " + policy);
  }
}

if (!/foreign key \(business_id,customer_id\)\s+references public\.customers\(business_id,id\)/i.test(ticketing)) {
  failures.push("tickets: tenant-scoped customer foreign key is missing");
}
if (!/tickets_update_permission[\s\S]*?tickets\.read/i.test(ticketing)) {
  failures.push("tickets: update policy does not also require read permission");
}
if (!/tickets\.comments\.internal\.read/i.test(ticketing) ||
    !/tickets\.comments\.internal\.create/i.test(ticketing)) {
  failures.push("ticket comments: internal read/create permission separation is missing");
}
if (!/create trigger ticket_events_no_mutation before update or delete on public\.ticket_events/i.test(ticketing)) {
  failures.push("ticket_events: append-only trigger is missing");
}
if (!/jsonb_build_object\('visibility',new\.visibility\)/i.test(ticketing)) {
  failures.push("ticket comment audit event must store visibility metadata");
}
const commentAuditStart = ticketing.indexOf("create or replace function private.record_ticket_comment_event()");
const commentAuditEnd = ticketing.indexOf("$record_ticket_comment_event$;", commentAuditStart);
const commentAudit = ticketing.slice(commentAuditStart, commentAuditEnd);
if (commentAuditStart < 0 || /\bbody\b/i.test(commentAudit)) {
  failures.push("ticket comment audit function must not copy comment body into event payload");
}

for (const functionName of [
  "guard_ticket_changes",
  "ticket_event_append_only",
  "record_ticket_event",
  "record_ticket_comment_event",
]) {
  const start = ticketing.indexOf("create or replace function private." + functionName + "(");
  if (start < 0) {
    failures.push(functionName + ": function is missing");
    continue;
  }
  const next = ticketing.indexOf("revoke all on function private." + functionName + "()", start);
  const block = ticketing.slice(start, next < 0 ? start + 3000 : next);
  if (!/set search_path\s*=\s*''/i.test(block)) {
    failures.push(functionName + ": empty search_path is missing");
  }
  if (next < 0 || !/from public,anon,authenticated/i.test(ticketing.slice(next, next + 180))) {
    failures.push(functionName + ": direct API execution is not revoked");
  }
}

if (/grant [^;]*\bdelete\b[^;]* on (?:table )?public\.(tickets|ticket_comments|ticket_events) to authenticated/i.test(ticketing)) {
  failures.push("Ticket tables: authenticated has a direct DELETE grant");
}
if (/grant [^;]* on table public\.ticket_events to authenticated/i.test(ticketing) &&
    !/grant select on table public\.ticket_events to authenticated/i.test(ticketing)) {
  failures.push("ticket_events: only SELECT should be granted to authenticated");
}
if (/grant insert[^;]*public\.ticket_events to authenticated/i.test(ticketing)) {
  failures.push("ticket_events: client INSERT grant must remain revoked");
}

if (failures.length) {
  console.error(failures.map((failure) => "- " + failure).join("\n"));
  process.exitCode = 1;
} else {
  console.log("Ticketing security checks passed: canonical migration, tenant FK, RLS, permission separation, append-only audit and restricted grants.");
}
