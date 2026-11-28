"use client";

import { useMemo, useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  createCustomerAction,
  setCustomerStatusAction,
  updateCustomerAction,
  type CustomerActionResult,
} from "@/app/actions/customers";

type Customer = {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  company_name: string | null;
  address: string | null;
  notes: string | null;
  status: "active" | "archived";
};

type CustomerFormValues = {
  name: string;
  phone: string;
  email: string;
  companyName: string;
  address: string;
  notes: string;
};

const emptyValues: CustomerFormValues = {
  name: "", phone: "", email: "", companyName: "", address: "", notes: "",
};

function formValues(form: HTMLFormElement): CustomerFormValues {
  const data = new FormData(form);
  return {
    name: String(data.get("name") ?? ""),
    phone: String(data.get("phone") ?? ""),
    email: String(data.get("email") ?? ""),
    companyName: String(data.get("companyName") ?? ""),
    address: String(data.get("address") ?? ""),
    notes: String(data.get("notes") ?? ""),
  };
}

export function CustomersPanel(props: {
  businessId: string;
  customers: Customer[];
  canRead: boolean;
  canCreate: boolean;
  canEdit: boolean;
  canArchive: boolean;
}) {
  const router = useRouter();
  const [busy, startTransition] = useTransition();
  const [result, setResult] = useState<CustomerActionResult>({});
  const [query, setQuery] = useState("");
  const [showArchived, setShowArchived] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  const visible = useMemo(() => props.customers.filter((customer) => {
    if (customer.status !== (showArchived ? "archived" : "active")) return false;
    const q = query.trim().toLocaleLowerCase();
    if (!q) return true;
    return [customer.name, customer.phone, customer.email, customer.company_name]
      .some((value) => value?.toLocaleLowerCase().includes(q));
  }), [props.customers, query, showArchived]);

  function run(action: () => Promise<CustomerActionResult>, after?: () => void) {
    startTransition(async () => {
      const response = await action();
      setResult(response);
      if (response.notice) {
        after?.();
        router.refresh();
      }
    });
  }

  function createCustomer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = formValues(form);
    run(
      () => createCustomerAction({ businessId: props.businessId, ...values }),
      () => { form.reset(); setShowCreate(false); },
    );
  }

  function updateCustomer(event: FormEvent<HTMLFormElement>, customerId: string) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = formValues(form);
    run(
      () => updateCustomerAction({ businessId: props.businessId, customerId, ...values }),
      () => setEditingId(null),
    );
  }

  function changeStatus(customer: Customer) {
    const nextStatus = customer.status === "active" ? "archived" : "active";
    const message = nextStatus === "archived"
      ? `پرونده «${customer.name}» بایگانی شود؟ سوابق آن حفظ خواهد شد.`
      : `پرونده «${customer.name}» دوباره فعال شود؟`;
    if (!window.confirm(message)) return;
    run(() => setCustomerStatusAction({
      businessId: props.businessId,
      customerId: customer.id,
      status: nextStatus,
    }));
  }

  return (
    <div className="customer-workspace">
      {result.error ? <p className="form-message error" role="alert">{result.error}</p> : null}
      {result.notice ? <p className="form-message notice" role="status">{result.notice}</p> : null}

      <section className="customer-toolbar">
        <div>
          <strong>{props.canRead ? `${visible.length} مشتری در این فهرست` : "دسترسی ثبت مشتری فعال است"}</strong>
          <span>{showArchived ? " · پرونده‌های بایگانی‌شده" : " · پرونده‌های فعال"}</span>
        </div>
        <div className="customer-toolbar-actions">
          {props.canArchive ? (
            <button type="button" className="secondary-action" disabled={busy}
              onClick={() => { setShowArchived((value) => !value); setResult({}); }}>
              {showArchived ? "نمایش مشتریان فعال" : "آرشیو مشتریان"}
            </button>
          ) : null}
          {props.canCreate ? (
            <button type="button" className="form-submit compact-submit"
              onClick={() => setShowCreate((value) => !value)}>
              {showCreate ? "بستن فرم" : "+ مشتری جدید"}
            </button>
          ) : null}
        </div>
      </section>

      {showCreate && props.canCreate ? (
        <section className="team-card customer-form-card">
          <h2>ثبت پرونده مشتری</h2>
          <form className="customer-form" onSubmit={createCustomer}>
            <CustomerFields values={emptyValues} />
            <button className="form-submit" type="submit" disabled={busy}>
              {busy ? "در حال ثبت..." : "ثبت مشتری"}
            </button>
          </form>
        </section>
      ) : null}

      {props.canRead ? (
        <section className="team-card customer-list-card">
          <div className="customer-list-heading">
            <div><h2>{showArchived ? "آرشیو مشتریان" : "فهرست مشتریان"}</h2><p>جست‌وجو در نام، شماره تماس، ایمیل و نام شرکت</p></div>
            <input aria-label="جست‌وجوی مشتری" placeholder="جست‌وجوی مشتری..." value={query}
              onChange={(event) => setQuery(event.target.value)} />
          </div>
          <div className="customer-list">
            {visible.map((customer) => (
              <article className="customer-card" key={customer.id}>
                {editingId === customer.id ? (
                  <form className="customer-form" onSubmit={(event) => updateCustomer(event, customer.id)}>
                    <CustomerFields values={{
                      name: customer.name,
                      phone: customer.phone ?? "",
                      email: customer.email ?? "",
                      companyName: customer.company_name ?? "",
                      address: customer.address ?? "",
                      notes: customer.notes ?? "",
                    }} />
                    <div className="customer-card-actions">
                      <button className="form-submit compact-submit" type="submit" disabled={busy}>ذخیره تغییرات</button>
                      <button className="secondary-action" type="button" onClick={() => setEditingId(null)}>انصراف</button>
                    </div>
                  </form>
                ) : (
                  <>
                    <div className="customer-card-heading">
                      <div>
                        <span className="customer-avatar">{customer.name.trim().slice(0, 1) || "م"}</span>
                        <div><h3>{customer.name}</h3><small>{customer.company_name || "مشتری حقیقی"}</small></div>
                      </div>
                      <span className={customer.status === "active" ? "customer-status" : "customer-status archived"}>
                        {customer.status === "active" ? "فعال" : "بایگانی‌شده"}
                      </span>
                    </div>
                    <div className="customer-contact-grid">
                      <div><small>شماره تماس</small><strong dir="auto">{customer.phone || "ثبت نشده"}</strong></div>
                      <div><small>ایمیل</small><strong dir="auto">{customer.email || "ثبت نشده"}</strong></div>
                    </div>
                    {customer.address ? <p className="customer-address">{customer.address}</p> : null}
                    {customer.notes ? <p className="customer-notes">{customer.notes}</p> : null}
                    <div className="customer-card-actions">
                      {props.canEdit ? <button type="button" className="secondary-action"
                        onClick={() => { setEditingId(customer.id); setResult({}); }}>ویرایش پرونده</button> : null}
                      {props.canArchive ? <button type="button" className="text-danger" disabled={busy}
                        onClick={() => changeStatus(customer)}>
                        {customer.status === "active" ? "بایگانی مشتری" : "بازگردانی مشتری"}
                      </button> : null}
                    </div>
                  </>
                )}
              </article>
            ))}
            {visible.length === 0 ? <p className="team-muted customer-empty">
              {showArchived ? "مشتری بایگانی‌شده‌ای پیدا نشد." : "هنوز مشتری‌ای ثبت نشده است."}
            </p> : null}
          </div>
        </section>
      ) : (
        <section className="team-card customer-no-read">
          <h2>مجوز مشاهده مشتریان فعال نیست</h2>
          <p>می‌توانی با مجوز ایجاد مشتری پرونده جدید ثبت کنی؛ برای دیدن فهرست، از مدیر کسب‌وکار بخواه مجوز crm.customers.read را به نقش تو اضافه کند.</p>
        </section>
      )}
    </div>
  );
}

function CustomerFields({ values }: { values: CustomerFormValues }) {
  return (
    <div className="customer-fields">
      <label className="field"><span>نام مشتری *</span><input name="name" required minLength={2} maxLength={160} defaultValue={values.name} placeholder="نام و نام خانوادگی یا نام مجموعه" /></label>
      <label className="field"><span>شماره تماس</span><input name="phone" maxLength={32} defaultValue={values.phone} inputMode="tel" dir="ltr" /></label>
      <label className="field"><span>ایمیل</span><input name="email" type="email" maxLength={254} defaultValue={values.email} dir="ltr" /></label>
      <label className="field"><span>نام شرکت</span><input name="companyName" maxLength={160} defaultValue={values.companyName} /></label>
      <label className="field customer-field-wide"><span>نشانی</span><input name="address" maxLength={500} defaultValue={values.address} /></label>
      <label className="field customer-field-wide"><span>یادداشت</span><textarea name="notes" rows={3} maxLength={2000} defaultValue={values.notes} /></label>
    </div>
  );
}
