"use client";

import { useState, useTransition } from "react";
import { createBranchAction, updateBranchAction, type TeamActionResult } from "@/app/actions/team";

type Branch = {
  id: string;
  name: string;
  code: string | null;
  is_primary: boolean;
  status: "active" | "inactive" | "archived";
};

export function BranchesPanel({
  businessId,
  branches,
  canManage,
}: {
  businessId: string;
  branches: Branch[];
  canManage: boolean;
}) {
  const [busy, startTransition] = useTransition();
  const [result, setResult] = useState<TeamActionResult>({});

  function run(action: () => Promise<TeamActionResult>) {
    startTransition(async () => setResult(await action()));
  }

  return (
    <section className="team-card">
      <div className="team-section-heading">
        <div>
          <h2>مدیریت شعب <span className="team-count">{branches.length}</span></h2>
          <p className="team-muted">اطلاعات و وضعیت هر شعبه را مدیریت کن. بایگانی به معنی حذف اطلاعات عملیاتی نیست.</p>
        </div>
      </div>
      {result.error ? <p className="form-message error" role="alert">{result.error}</p> : null}
      {result.notice ? <p className="form-message notice" role="status">{result.notice}</p> : null}

      {canManage ? (
        <form className="team-form branch-create-form" onSubmit={(event) => {
          event.preventDefault();
          const form = event.currentTarget;
          const data = new FormData(form);
          run(() => createBranchAction({
            businessId,
            name: String(data.get("name") ?? ""),
            code: String(data.get("code") ?? ""),
          }));
          form.reset();
        }}>
          <label className="field">
            <span>نام شعبه جدید</span>
            <input name="name" required minLength={2} maxLength={120} placeholder="مثلاً شعبه غرب" />
          </label>
          <label className="field">
            <span>کد شعبه (اختیاری)</span>
            <input name="code" maxLength={20} pattern="[A-Za-z0-9-]{2,20}" dir="ltr" placeholder="WEST-01" />
          </label>
          <button className="form-submit" type="submit" disabled={busy}>
            {busy ? "در حال ذخیره..." : "افزودن شعبه"}
          </button>
        </form>
      ) : null}

      <div className="team-list branch-list">
        {branches.map((branch) => (
          <form
            className="branch-row"
            key={branch.id}
            onSubmit={(event) => {
              event.preventDefault();
              const data = new FormData(event.currentTarget);
              run(() => updateBranchAction({
                businessId,
                branchId: branch.id,
                name: String(data.get("name") ?? ""),
                code: String(data.get("code") ?? ""),
                status: String(data.get("status") ?? branch.status) as Branch["status"],
              }));
            }}
          >
            <div className="branch-row-title">
              <strong>{branch.name}</strong>
              {branch.is_primary ? <span className="branch-primary-label">شعبه اصلی</span> : null}
              <span className={branch.status === "active" ? "business-status" : "team-muted"}>
                {branch.status === "active" ? "فعال" : branch.status === "inactive" ? "غیرفعال" : "بایگانی‌شده"}
              </span>
            </div>
            {canManage ? (
              <>
                <div className="branch-edit-fields">
                  <label className="field">
                    <span>نام</span>
                    <input name="name" required minLength={2} maxLength={120} defaultValue={branch.name} />
                  </label>
                  <label className="field">
                    <span>کد</span>
                    <input name="code" maxLength={20} pattern="[A-Za-z0-9-]{2,20}" dir="ltr" defaultValue={branch.code ?? ""} placeholder="بدون کد" />
                  </label>
                  <label className="field">
                    <span>وضعیت</span>
                    <select name="status" defaultValue={branch.status} disabled={branch.is_primary}>
                      <option value="active">فعال</option>
                      <option value="inactive">غیرفعال</option>
                      <option value="archived">بایگانی‌شده</option>
                    </select>
                  </label>
                </div>
                {branch.is_primary ? <small className="team-muted">شعبه اصلی قابل غیرفعال‌سازی یا بایگانی نیست.</small> : null}
                <div className="team-row-actions">
                  <button className="secondary-action" type="submit" disabled={busy}>ذخیره تغییرات</button>
                </div>
              </>
            ) : (
              <div className="branch-readonly-meta">
                {branch.code ? <small dir="ltr">{branch.code}</small> : null}
              </div>
            )}
          </form>
        ))}
        {branches.length === 0 ? <p className="team-muted">هنوز شعبه‌ای ثبت نشده است.</p> : null}
      </div>
    </section>
  );
}
