"use client";

import { useMemo, useState, useTransition } from "react";
import {
  archiveCustomRoleAction,
  saveCustomRoleAction,
  type TeamActionResult,
} from "@/app/actions/team";

type Permission = {
  permission_key: string;
  module_key: string;
  label_fa: string;
  description_fa: string | null;
  is_sensitive: boolean;
};
type Role = {
  id: string;
  role_key: string;
  name: string;
  description: string | null;
  is_system: boolean;
  status: string;
  permissionKeys: string[];
};

const moduleLabels: Record<string, string> = {
  dashboard: "داشبورد",
  business: "کسب‌وکار",
  billing: "اشتراک و مالی",
  team: "اعضا و دسترسی",
  branches: "شعب",
  crm: "ارتباط با مشتری",
  sales: "فروش",
  finance: "امور مالی",
  inventory: "انبار",
  purchases: "خرید",
  reports: "گزارش‌ها",
  documents: "اسناد",
};

export function RolesPanel({
  businessId,
  roles,
  permissions,
  manageablePermissionKeys,
  canManageRoles,
}: {
  businessId: string;
  roles: Role[];
  permissions: Permission[];
  manageablePermissionKeys: string[];
  canManageRoles: boolean;
}) {
  const [busy, startTransition] = useTransition();
  const [result, setResult] = useState<TeamActionResult>({});
  const [editingRoleId, setEditingRoleId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [selected, setSelected] = useState<string[]>([]);
  const manageable = useMemo(() => new Set(manageablePermissionKeys), [manageablePermissionKeys]);
  const groups = useMemo(() => {
    const grouped = new Map<string, Permission[]>();
    for (const permission of permissions) {
      const current = grouped.get(permission.module_key) ?? [];
      current.push(permission);
      grouped.set(permission.module_key, current);
    }
    return [...grouped.entries()];
  }, [permissions]);

  function resetEditor() {
    setEditingRoleId(null);
    setName("");
    setDescription("");
    setSelected([]);
  }

  function editRole(role: Role) {
    setEditingRoleId(role.id);
    setName(role.name);
    setDescription(role.description ?? "");
    setSelected(role.permissionKeys);
    setResult({});
  }

  function save() {
    if (!name.trim() || name.trim().length < 2) {
      setResult({ error: "نام نقش باید حداقل دو نویسه باشد." });
      return;
    }
    startTransition(async () => {
      const response = await saveCustomRoleAction({
        businessId,
        roleId: editingRoleId ?? undefined,
        name: name.trim(),
        description: description.trim(),
        permissionKeys: selected,
      });
      setResult(response);
      if (response.notice) resetEditor();
    });
  }

  function archive(role: Role) {
    if (!window.confirm(`نقش «${role.name}» بایگانی شود؟ دسترسی‌های این نقش غیرفعال می‌شوند.`)) return;
    startTransition(async () => {
      const response = await archiveCustomRoleAction(businessId, role.id);
      setResult(response);
      if (response.notice && editingRoleId === role.id) resetEditor();
    });
  }

  return (
    <section className="team-card">
      <h2>نقش‌ها و مجوزهای سفارشی</h2>
      <p className="team-muted">برای هر نقش، فقط مجوزهایی را انتخاب کنید که خودتان در این کسب‌وکار در اختیار دارید. نقش‌های سیستمی مالک، مدیر و عضو قابل تغییر نیستند.</p>

      {result.error ? <p className="form-message error" role="alert">{result.error}</p> : null}
      {result.notice ? <p className="form-message notice" role="status">{result.notice}</p> : null}

      <div className="team-list">
        {roles.map((role) => (
          <article className="team-row" key={role.id}>
            <div>
              <strong>{role.name}{role.is_system ? " · سیستمی" : ""}</strong>
              <small>{role.description || (role.is_system ? "نقش پایه کسب‌وکار" : "بدون توضیحات")} · {role.permissionKeys.length} مجوز</small>
              {role.status === "archived" ? <small className="team-muted">بایگانی‌شده</small> : null}
            </div>
            <div className="team-row-actions">
              {role.is_system ? <span className="team-muted">محافظت‌شده</span> : role.status === "active" ? (
                <>
                  {canManageRoles ? <button type="button" disabled={busy} onClick={() => editRole(role)}>ویرایش</button> : null}
                  {canManageRoles ? <button type="button" className="text-danger" disabled={busy} onClick={() => archive(role)}>بایگانی</button> : null}
                </>
              ) : <span className="team-muted">غیرفعال</span>}
            </div>
          </article>
        ))}
      </div>

      {canManageRoles ? (
        <div className="team-form" style={{ marginTop: 22 }}>
          <h3>{editingRoleId ? "ویرایش نقش سفارشی" : "ساخت نقش سفارشی"}</h3>
          <label className="field">
            <span>نام نقش</span>
            <input value={name} onChange={(event) => setName(event.target.value)} maxLength={80} placeholder="مثلاً مسئول فروش" />
          </label>
          <label className="field">
            <span>توضیحات (اختیاری)</span>
            <input value={description} onChange={(event) => setDescription(event.target.value)} maxLength={300} placeholder="شرح مسئولیت این نقش" />
          </label>

          <h3>مجوزهای نقش</h3>
          <p className="team-muted">مجوزهای حساس با علامت «حساس» مشخص شده‌اند. انتخاب مجوزی که خودتان ندارید امکان‌پذیر نیست.</p>
          {groups.map(([moduleKey, items]) => (
            <div className="team-permission-group" key={moduleKey}>
              <h4>{moduleLabels[moduleKey] ?? moduleKey}</h4>
              <div className="team-permission-list">
                {items.map((permission) => {
                  const checked = selected.includes(permission.permission_key);
                  const canGrant = manageable.has(permission.permission_key);
                  return (
                    <label className="team-permission" key={permission.permission_key}>
                      <input
                        type="checkbox"
                        checked={checked}
                        disabled={!canGrant && !checked}
                        onChange={(event) => {
                          if (event.target.checked && !canGrant) return;
                          setSelected((current) => event.target.checked
                            ? [...new Set([...current, permission.permission_key])]
                            : current.filter((key) => key !== permission.permission_key));
                        }}
                      />
                      <span>
                        <strong>{permission.label_fa}</strong>
                        {permission.is_sensitive ? <small> · حساس</small> : null}
                        {permission.description_fa ? <small>{permission.description_fa}</small> : null}
                      </span>
                    </label>
                  );
                })}
              </div>
            </div>
          ))}
          <div className="team-row-actions">
            <button type="button" className="form-submit" disabled={busy} onClick={save}>
              {busy ? "در حال ذخیره..." : editingRoleId ? "ذخیره تغییرات نقش" : "ایجاد نقش"}
            </button>
            {editingRoleId ? <button type="button" disabled={busy} onClick={resetEditor}>انصراف از ویرایش</button> : null}
          </div>
        </div>
      ) : <p className="team-muted">برای تغییر نقش‌ها به مجوز «مدیریت نقش‌ها» نیاز دارید.</p>}
    </section>
  );
}
