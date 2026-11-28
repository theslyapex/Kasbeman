"use client";

import { useActionState } from "react";
import { acceptInvitationAction, type AcceptInvitationState } from "@/app/actions/accept-invitation";

const initialState: AcceptInvitationState = {};

export function AcceptInvitationForm({ token }: { token: string }) {
  const [state, formAction, pending] = useActionState(acceptInvitationAction, initialState);
  return (
    <form action={formAction} className="auth-form">
      <input type="hidden" name="token" value={token} />
      <p className="form-message notice">برای پذیرش دعوت، با حسابی وارد شوید که ایمیل تأییدشده آن با ایمیل دعوت‌نامه مطابقت دارد.</p>
      {state.error ? <p className="form-message error" role="alert">{state.error}</p> : null}
      <button className="form-submit" type="submit" disabled={pending}>{pending ? "در حال پذیرش..." : "پذیرش دعوت‌نامه"}</button>
    </form>
  );
}
