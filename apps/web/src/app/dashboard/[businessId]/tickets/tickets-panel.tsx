"use client";

import { useMemo, useState, useTransition } from "react";
import {
  addTicketCommentAction, createTicketAction, updateTicketContentAction,
  updateTicketWorkflowAction, type TicketActionResult,
} from "@/app/actions/tickets";

type Ticket = {
  id:string; business_id:string; branch_id:string; ticket_number:string; title:string;
  description:string; status:string; priority:string; requester_user_id:string;
  customer_id:string|null; assignee_user_id:string|null; due_at:string|null;
  resolved_at:string|null; archived_at:string|null; created_at:string; updated_at:string;
};
type Branch = {id:string;name:string;isPrimary:boolean};
type Member = {id:string;roleKey:string};
type Customer = {id:string;name:string};
type Comment = {id:string;ticket_id:string;author_user_id:string;body:string;visibility:string;created_at:string};
type Event = {id:string;ticket_id:string;actor_user_id:string;event_type:string;payload:Record<string,unknown>;created_at:string};

const statusLabels:Record<string,string> = {open:"باز",in_progress:"در حال انجام",waiting:"در انتظار",resolved:"حل‌شده",closed:"بسته"};
const priorityLabels:Record<string,string> = {low:"کم",normal:"عادی",high:"زیاد",urgent:"فوری"};
const eventLabels:Record<string,string> = {
 created:"تیکت ثبت شد", status_changed:"وضعیت تغییر کرد", assignee_changed:"مسئول تغییر کرد",
 archived:"تیکت بایگانی شد", comment_added:"پیام جدید ثبت شد", content_updated:"محتوای تیکت ویرایش شد",
};

export function TicketsPanel(props:{
 businessId:string;tickets:Ticket[];branches:Branch[];members:Member[];customers:Customer[];
 comments:Comment[];events:Event[];globalPermissions:string[];branchPermissions:Record<string,string[]>;
}) {
 const [busy,startTransition]=useTransition();
 const [result,setResult]=useState<TicketActionResult>({});
 const [selectedId,setSelectedId]=useState<string|null>(props.tickets[0]?.id??null);
 const [filter,setFilter]=useState("all");
 const [query,setQuery]=useState("");
 const [comment,setComment]=useState("");
 const [commentVisibility,setCommentVisibility]=useState<"public"|"internal">("public");
 const [showCreate,setShowCreate]=useState(false);
 const [editTitle,setEditTitle]=useState("");
 const [editDescription,setEditDescription]=useState("");
 const [editPriority,setEditPriority]=useState("normal");
 const [showEdit,setShowEdit]=useState(false);
 const [newBranch,setNewBranch]=useState(props.branches.find(x=>x.isPrimary)?.id??props.branches[0]?.id??"");
 const [newPriority,setNewPriority]=useState("normal");

 const selected=props.tickets.find(t=>t.id===selectedId)??null;
 const permissionsFor=(branchId:string)=>new Set([...props.globalPermissions,...(props.branchPermissions[branchId]??[])]);
 const selectedPermissions=selected?permissionsFor(selected.branch_id):new Set<string>();
 const visible=useMemo(()=>props.tickets.filter(t=>
   (filter==="all"||t.status===filter) &&
   (query.trim()===""||[t.ticket_number,t.title,t.description].some(v=>v.toLowerCase().includes(query.trim().toLowerCase())))
 ),[props.tickets,filter,query]);
 const comments=selected?props.comments.filter(c=>c.ticket_id===selected.id):[];
 const events=selected?props.events.filter(e=>e.ticket_id===selected.id):[];
 const canCreate=props.branches.some(b=>permissionsFor(b.id).has("tickets.create"));
 const canEdit=selectedPermissions.has("tickets.update");
 const canAssign=selectedPermissions.has("tickets.assign");
 const canStatus=selectedPermissions.has("tickets.status.manage");
 const canArchive=selectedPermissions.has("tickets.delete");
 const canComment=selectedPermissions.has("tickets.comments.create");
 const canInternalRead=selectedPermissions.has("tickets.comments.internal.read");
 const canInternalCreate=selectedPermissions.has("tickets.comments.internal.create");

 function run(action:()=>Promise<TicketActionResult>,after?:()=>void) {
   startTransition(async()=>{const r=await action();setResult(r);if(r.notice)after?.();});
 }
 function beginEdit(t:Ticket) {setEditTitle(t.title);setEditDescription(t.description);setEditPriority(t.priority);setShowEdit(true);}
 function saveEdit() {
   if(!selected)return;
   run(()=>updateTicketContentAction({businessId:props.businessId,ticketId:selected.id,title:editTitle,description:editDescription,priority:editPriority}),()=>setShowEdit(false));
 }
 function submitComment() {
   if(!selected||!comment.trim())return;
   run(()=>addTicketCommentAction({businessId:props.businessId,ticketId:selected.id,body:comment,visibility:commentVisibility}),()=>setComment(""));
 }

 return <div className="ticket-workspace">
  {result.error?<p className="form-message error" role="alert">{result.error}</p>:null}
  {result.notice?<p className="form-message notice" role="status">{result.notice}</p>:null}
  <section className="ticket-toolbar">
   <div><strong>{props.tickets.length} تیکت فعال</strong><span> · فهرست بر اساس آخرین تغییر</span></div>
   {canCreate?<button className="form-submit compact-submit" type="button" onClick={()=>setShowCreate(v=>!v)}>+ تیکت جدید</button>:null}
  </section>
  {showCreate&&canCreate?<section className="team-card">
   <h2>ثبت درخواست جدید</h2>
   <form className="team-form" onSubmit={e=>{e.preventDefault();const form=e.currentTarget;const f=new FormData(form);run(()=>createTicketAction({businessId:props.businessId,branchId:String(f.get("branchId")),title:String(f.get("title")),description:String(f.get("description")),priority:newPriority,customerId:String(f.get("customerId")??"")}),()=>{setShowCreate(false);form.reset();});}}>
    <label className="field"><span>عنوان</span><input name="title" required minLength={3} maxLength={200}/></label>
    <label className="field"><span>شرح درخواست</span><textarea name="description" required maxLength={10000} rows={4}/></label>
    <div className="ticket-form-grid">
     <label className="field"><span>شعبه</span><select name="branchId" value={newBranch} onChange={e=>setNewBranch(e.target.value)} required>{props.branches.map(b=><option key={b.id} value={b.id}>{b.name}{b.isPrimary?" · اصلی":""}</option>)}</select></label>
     <label className="field"><span>اولویت</span><select value={newPriority} onChange={e=>setNewPriority(e.target.value)}><option value="low">کم</option><option value="normal">عادی</option><option value="high">زیاد</option><option value="urgent">فوری</option></select></label>
     <label className="field"><span>مشتری (اختیاری)</span><select name="customerId" defaultValue=""><option value="">بدون مشتری</option>{props.customers.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    </div>
    <button className="form-submit" disabled={busy||!newBranch} type="submit">{busy?"در حال ثبت...":"ثبت تیکت"}</button>
   </form>
  </section>:null}

  <div className="ticket-layout">
   <section className="team-card ticket-list-card">
    <div className="ticket-list-tools">
     <input aria-label="جست‌وجوی تیکت" placeholder="جست‌وجو در تیکت‌ها..." value={query} onChange={e=>setQuery(e.target.value)}/>
     <select aria-label="فیلتر وضعیت" value={filter} onChange={e=>setFilter(e.target.value)}>
      <option value="all">همه وضعیت‌ها</option>{Object.entries(statusLabels).map(([k,v])=><option key={k} value={k}>{v}</option>)}
     </select>
    </div>
    <div className="ticket-list">
     {visible.map(t=><button type="button" className={"ticket-list-item"+(selected?.id===t.id?" selected":"")} key={t.id} onClick={()=>{setSelectedId(t.id);setShowEdit(false);setResult({});}}>
      <span className="ticket-item-top"><b>{t.ticket_number}</b><small>{statusLabels[t.status]??t.status}</small></span>
      <strong>{t.title}</strong><span className="ticket-item-bottom"><small>{priorityLabels[t.priority]??t.priority}</small><small>{new Date(t.updated_at).toLocaleDateString("fa-IR")}</small></span>
     </button>)}
     {visible.length===0?<p className="team-muted ticket-empty">تیکتی با این مشخصات پیدا نشد.</p>:null}
    </div>
   </section>

   <section className="team-card ticket-detail-card">
    {selected?<>
     <div className="ticket-detail-heading">
      <div><span className="section-kicker">{selected.ticket_number}</span><h2>{selected.title}</h2><p>{props.branches.find(b=>b.id===selected.branch_id)?.name??"شعبه"}</p></div>
      <span className={"ticket-priority priority-"+selected.priority}>{priorityLabels[selected.priority]??selected.priority}</span>
     </div>
     <p className="ticket-description">{selected.description}</p>
     <div className="ticket-meta-grid">
      <div><small>وضعیت</small><strong>{statusLabels[selected.status]??selected.status}</strong></div>
      <div><small>اولویت</small><strong>{priorityLabels[selected.priority]??selected.priority}</strong></div>
      <div><small>ثبت‌کننده</small><strong dir="ltr">{selected.requester_user_id.slice(0,8)}…</strong></div>
      <div><small>مسئول</small><strong>{props.members.find(m=>m.id===selected.assignee_user_id)?.roleKey??(selected.assignee_user_id?"عضو":"تخصیص‌نیافته")}</strong></div>
     </div>
     <div className="ticket-actions">
      {canEdit?<button type="button" className="secondary-action" onClick={()=>beginEdit(selected)}>ویرایش محتوا</button>:null}
      {canStatus?<select aria-label="تغییر وضعیت تیکت" value={selected.status} disabled={busy} onChange={e=>run(()=>updateTicketWorkflowAction({businessId:props.businessId,ticketId:selected.id,status:e.target.value}))}>{Object.entries(statusLabels).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select>:null}
      {canAssign?<select aria-label="تخصیص مسئول" value={selected.assignee_user_id??""} disabled={busy} onChange={e=>run(()=>updateTicketWorkflowAction({businessId:props.businessId,ticketId:selected.id,assigneeUserId:e.target.value}))}><option value="">بدون مسئول</option>{props.members.map(m=><option key={m.id} value={m.id}>{m.roleKey} · {m.id.slice(0,8)}</option>)}</select>:null}
      {canArchive&&selected.status!=="open"&&selected.status!=="in_progress"&&selected.status!=="waiting"?<button type="button" className="text-danger" disabled={busy} onClick={()=>{if(window.confirm("این تیکت بایگانی شود؟"))run(()=>updateTicketWorkflowAction({businessId:props.businessId,ticketId:selected.id,archive:true}));}}>بایگانی</button>:null}
     </div>
     {showEdit&&canEdit?<div className="ticket-edit-form">
      <label className="field"><span>عنوان</span><input value={editTitle} onChange={e=>setEditTitle(e.target.value)} maxLength={200}/></label>
      <label className="field"><span>شرح</span><textarea rows={4} value={editDescription} onChange={e=>setEditDescription(e.target.value)} maxLength={10000}/></label>
      <label className="field"><span>اولویت</span><select value={editPriority} onChange={e=>setEditPriority(e.target.value)}><option value="low">کم</option><option value="normal">عادی</option><option value="high">زیاد</option><option value="urgent">فوری</option></select></label>
      <div className="ticket-actions"><button className="form-submit compact-submit" type="button" disabled={busy} onClick={saveEdit}>ذخیره تغییرات</button><button type="button" className="secondary-action" onClick={()=>setShowEdit(false)}>انصراف</button></div>
     </div>:null}
     <div className="ticket-conversation">
      <h3>گفتگو و یادداشت‌ها</h3>
      {comments.filter(c=>c.visibility==="public"||canInternalRead).map(c=><article className={"ticket-comment "+(c.visibility==="internal"?"internal":"")} key={c.id}>
       <div><b>{c.visibility==="internal"?"یادداشت داخلی":"پیام"}</b><small>{new Date(c.created_at).toLocaleString("fa-IR")}</small></div><p>{c.body}</p>
      </article>)}
      {comments.length===0?<p className="team-muted">هنوز پیامی ثبت نشده است.</p>:null}
      {canComment?<form className="ticket-comment-form" onSubmit={e=>{e.preventDefault();submitComment();}}>
       <textarea value={comment} onChange={e=>setComment(e.target.value)} rows={3} maxLength={10000} placeholder="پیام خود را بنویسید..." required/>
       {canInternalCreate?<label className="ticket-inline-check"><input type="checkbox" checked={commentVisibility==="internal"} onChange={e=>setCommentVisibility(e.target.checked?"internal":"public")}/> یادداشت داخلی (فقط تیم)</label>:null}
       <button className="form-submit compact-submit" disabled={busy||!comment.trim()} type="submit">ارسال پیام</button>
      </form>:null}
     </div>
     <div className="ticket-history"><h3>تاریخچه عملیات</h3>{events.slice(0,12).map(ev=><p key={ev.id}><small>{new Date(ev.created_at).toLocaleString("fa-IR")}</small> · {eventLabels[ev.event_type]??"به‌روزرسانی تیکت"}</p>)}</div>
    </>:<div className="ticket-empty-detail"><h2>یک تیکت را انتخاب کنید</h2><p>برای مشاهده جزئیات، گفتگو و تاریخچه، یکی از تیکت‌های فهرست را انتخاب کنید.</p></div>}
   </section>
  </div>
 </div>;
}
