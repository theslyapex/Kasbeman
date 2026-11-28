"use client";

import { useState, useTransition } from "react";
import {
  createInvitationAction,
  revokeInvitationAction,
  suspendBusinessMemberAction,
  transferOwnershipAction,
  type TeamActionResult,
} from "@/app/actions/team";

type Member = { user_id: string; role_key: string; status: string; joined_at: string };
type Invitation = { id: string; email: string; role_key: string; status: string; expires_at: string };

export function MembersPanel({
  businessId,
  members,
  invitations,
  canInvite,
  canTransfer,
  canManageMembers,
  currentUserId,
}: {
  businessId: string;
  members: Member[];
  invitations: Invitation[];
  canInvite: boolean;
  canTransfer: boolean;
  canManageMembers: boolean;
  currentUserId: string;
}) {
  const [busy, startTransition] = useTransition();
  const [result, setResult] = useState<TeamActionResult>({});
  const [token, setToken] = useState("");

  function run(action: () => Promise<TeamActionResult>) {
    startTransition(async () => {
      const response = await action();
      setResult(response);
      if (response.token) setToken(response.token);
    });
  }

  return (
    <div className="team-layout">
      {result.error ? <p className="form-message error" role="alert">{result.error}</p> : null}
      {result.notice ? <p className="form-message notice" role="status">{result.notice}</p> : null}

      {token ? (
        <section className="team-card">
          <h2>توکن دعوت</h2>
          <p>این توکن محرمانه است و فقط یک‌بار نمایش داده می‌شود. آن را فقط برای ایمیل دعوت‌شده ارسال کنید.</p>
          <code className="invite-token" dir="ltr">{typeof window !== "undefined" ? `${window.location.origin}/accept-invitation?token=${token}` : token}</code>
          <button className="secondary-action" type="button" onClick={() => navigator.clipboard.writeText(`${window.location.origin}/accept-invitation?token=${token}`)}>کپی پیوند دعوت</button>
        </section>
      ) : null}

      {canInvite ? (
        <section className="team-card">
          <h2>دعوت عضو جدید</h2>
          <form className="team-form" onSubmit={(event) => {
            event.preventDefault();
            const formData = new FormData(event.currentTarget);
            run(() => createInvitationAction(formData));
            event.currentTarget.reset();
          }}>
            <input type="hidden" name="businessId" value={businessId} />
            <label className="field"><span>ایمیل عضو</span><input name="email" type="email" required maxLength={254} placeholder="name@example.com" dir="ltr" /></label>
            <label className="field"><span>نقش هنگام پیوستن</span>
              <select name="roleKey" defaultValue="member">
                <option value="member">عضو</option>
                <option value="admin">مدیر</option>
              </select>
            </label>
            <button className="form-submit" disabled={busy} type="submit">{busy ? "در حال انجام..." : "ساخت دعوت‌نامه"}</button>
          </form>
        </section>
      ) : null}

      <section className="team-card">
        <h2>اعضای کسب‌وکار <span className="team-count">{members.length}</span></h2>
        <div className="team-list">
          {members.map((member) => (
            <article className="team-row" key={member.user_id}>
              <div><strong>{member.role_key === "owner" ? "مالک" : member.role_key === "admin" ? "مدیر" : "عضو"}</strong>
                <small dir="ltr">{member.user_id}</small></div>
              <div className="team-row-actions">
                <span className={member.status === "active" ? "business-status" : "team-muted"}>{member.status === "active" ? "فعال" : member.status === "suspended" ? "تعلیق‌شده" : member.status}</span>
                {canManageMembers && member.status === "active" && member.role_key !== "owner" && member.user_id !== currentUserId ? (
                  <button
                    className="text-danger"
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      if (!window.confirm("دسترسی این عضو به کسب‌وکار تعلیق شود؟ نقش‌های فعال او نیز لغو می‌شوند.")) return;
                      run(() => suspendBusinessMemberAction(businessId, member.user_id));
                    }}
                  >تعلیق عضو</button>
                ) : null}
              </div>
            </article>
          ))}
          {members.length === 0 ? <p className="team-muted">عضوی برای نمایش وجود ندارد.</p> : null}
        </div>
      </section>

      <section className="team-card">
        <h2>دعوت‌نامه‌ها</h2>
        <div className="team-list">
          {invitations.map((invite) => (
            <article className="team-row" key={invite.id}>
              <div><strong dir="ltr">{invite.email}</strong><small>{invite.role_key === "admin" ? "مدیر" : "عضو"} · انقضا: {new Date(invite.expires_at).toLocaleDateString("fa-IR")}</small></div>
              <div className="team-row-actions">
                <span className="team-muted">{invite.status === "pending" ? "در انتظار" : invite.status}</span>
                {invite.status === "pending" && canInvite ? <button className="text-danger" disabled={busy} type="button" onClick={() => run(() => revokeInvitationAction(businessId, invite.id))}>لغو</button> : null}
              </div>
            </article>
          ))}
          {invitations.length === 0 ? <p className="team-muted">دعوت‌نامه‌ای ثبت نشده است.</p> : null}
        </div>
      </section>

      {canTransfer ? (
        <section className="team-card team-danger-zone">
          <h2>انتقال مالکیت</h2>
          <p>مالک جدید باید عضو فعال همین کسب‌وکار باشد. پس از انتقال، نقش شما به مدیر تغییر می‌کند.</p>
          <form className="team-form" onSubmit={(event) => {
            event.preventDefault();
            if (!window.confirm("مالکیت این کسب‌وکار به عضو انتخاب‌شده منتقل شود؟ نقش شما به مدیر تغییر خواهد کرد.")) return;
            const formData = new FormData(event.currentTarget);
            run(() => transferOwnershipAction(formData));
          }}>
            <input type="hidden" name="businessId" value={businessId} />
            <label className="field"><span>مالک جدید</span>
              <select name="newOwnerUserId" required defaultValue="">
                <option value="" disabled>انتخاب عضو فعال</option>
                {members.filter((member) => member.status === "active" && member.role_key !== "owner").map((member) => (
                  <option value={member.user_id} key={member.user_id}>{member.role_key === "admin" ? "مدیر" : "عضو"} · {member.user_id.slice(0, 8)}</option>
                ))}
              </select>
            </label>
            <button className="danger-submit" disabled={busy || !members.some((member) => member.status === "active" && member.role_key !== "owner")} type="submit">انتقال مالکیت</button>
          </form>
        </section>
      ) : null}

      <p className="team-muted">برای بازگرداندن دسترسی عضو تعلیق‌شده، یک دعوت‌نامه جدید به همان ایمیل ارسال کنید؛ پذیرش دعوت توسط همان حساب تأییدشده، عضویت و نقش مناسب را دوباره فعال می‌کند. حذف دائمی عضویت از این صفحه ارائه نمی‌شود.</p>
    </div>
  );
}
