// The screen favors explicit string composition in compact Persian labels.
// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../workspace/workspace_repository.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key, required this.membership, required this.branchId, required this.permissions});
  final BusinessMembership membership;
  final String branchId;
  final Set<String> permissions;
  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true, _busy = false;
  String? _error, _selectedId;
  String _filter = 'all';
  List<Map<String,dynamic>> _tickets = [], _members = [], _comments = [], _events = [];
  String get _businessId => widget.membership.businessId;
  bool can(String key) => widget.permissions.contains(key);
  Map<String,dynamic>? get selected {
    for (final t in _tickets) { if (t['id'] == _selectedId) return t; }
    return null;
  }
  static const statuses = {'open':'باز','in_progress':'در حال انجام','waiting':'در انتظار','resolved':'حل‌شده','closed':'بسته'};
  static const priorities = {'low':'کم','normal':'عادی','high':'زیاد','urgent':'فوری'};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!can('tickets.read')) {
      setState(() { _loading=false; _error='مجوز مشاهده تیکت‌ها برای این شعبه فعال نیست.'; });
      return;
    }
    setState(() { _loading=true; _error=null; });
    try {
      final rows=await _db.from('tickets').select('id,business_id,branch_id,ticket_number,title,description,status,priority,requester_user_id,assignee_user_id,archived_at,updated_at')
        .eq('business_id',_businessId).eq('branch_id',widget.branchId).isFilter('archived_at',null).order('updated_at',ascending:false).limit(150);
      final members=can('tickets.assign') ? await _db.from('business_members').select('user_id,role_key,status')
        .eq('business_id',_businessId).eq('status','active') : <Map<String,dynamic>>[];
      if (!mounted) return;
      final data=List<Map<String,dynamic>>.from(rows);
      setState(() {
        _tickets=data; _members=List<Map<String,dynamic>>.from(members);
        if (_selectedId==null || !data.any((t)=>t['id']==_selectedId)) _selectedId=data.isEmpty?null:data.first['id'] as String;
        _loading=false;
      });
      if (_selectedId!=null) await _loadDetail(_selectedId!);
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading=false; _error='دریافت تیکت‌ها انجام نشد. اتصال و دسترسی را بررسی کنید.'; });
    }
  }

  Future<void> _loadDetail(String id) async {
    try {
      final comments = can('tickets.comments.read')
        ? await _db.from('ticket_comments').select('id,ticket_id,author_user_id,body,visibility,created_at')
            .eq('business_id',_businessId).eq('ticket_id',id).order('created_at')
        : <Map<String,dynamic>>[];
      final events = await _db.from('ticket_events').select('id,ticket_id,actor_user_id,event_type,payload,created_at')
        .eq('business_id',_businessId).eq('ticket_id',id).order('created_at',ascending:false).limit(25);
      if (!mounted || _selectedId!=id) return;
      setState(() { _comments=List<Map<String,dynamic>>.from(comments); _events=List<Map<String,dynamic>>.from(events); });
    } catch (_) {
      if (!mounted) return;
      setState(() { _comments=[]; _events=[]; });
    }
  }

  Future<void> _run(Future<void> Function() task, String message) async {
    setState(()=>_busy=true);
    try { await task(); if (!mounted) return; _toast(message); await _load(); }
    on PostgrestException catch (e) {
      if (mounted) _toast(e.code=='42501'?'این عملیات با مجوزهای فعلی مجاز نیست.':'عملیات انجام نشد؛ اطلاعات را بررسی کنید.');
    } catch (_) { if (mounted) _toast('عملیات انجام نشد. دوباره تلاش کنید.'); }
    finally { if (mounted) setState(()=>_busy=false); }
  }
  void _toast(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));

  String _number() {
    final n=DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'TK-'+n;
  }

  Future<void> _create() async {
    final title=TextEditingController(), desc=TextEditingController();
    var priority='normal';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:const Text('ثبت تیکت جدید'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,maxLength:200,decoration:const InputDecoration(labelText:'عنوان درخواست')),
        const SizedBox(height:10),
        TextField(controller:desc,minLines:3,maxLines:6,maxLength:10000,decoration:const InputDecoration(labelText:'شرح درخواست')),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue:priority,decoration:const InputDecoration(labelText:'اولویت'),
          items:priorities.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
          onChanged:(v)=>setDialog(()=>priority=v??'normal')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ثبت'))],
    )));
    if (ok==true) {
      if (title.text.trim().length<3 || desc.text.trim().isEmpty) { _toast('عنوان و شرح تیکت را کامل کنید.'); }
      else await _run(() async {
        final uid=_db.auth.currentUser?.id;
        if(uid==null) throw StateError('Authentication required');
        await _db.from('tickets').insert({'business_id':_businessId,'branch_id':widget.branchId,'ticket_number':_number(),
          'title':title.text.trim(),'description':desc.text.trim(),'priority':priority,'requester_user_id':uid,'created_by':uid});
      },'تیکت ثبت شد.');
    }
    title.dispose(); desc.dispose();
  }

  Future<void> _patch(Map<String,dynamic> ticket, Map<String,dynamic> patch, String success) async {
    await _run(() async {
      final rows=await _db.from('tickets').update(patch).eq('business_id',_businessId).eq('id',ticket['id']).isFilter('archived_at',null).select('id');
      if(rows.isEmpty) throw StateError('Ticket not found or forbidden.');
    },success);
  }

  Future<void> _comment() async {
    final t=selected; if(t==null) return;
    final body=TextEditingController(); var internal=false;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:const Text('ارسال پیام'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:body,minLines:3,maxLines:6,maxLength:10000,decoration:const InputDecoration(labelText:'متن پیام')),
        if(can('tickets.comments.internal.create')) CheckboxListTile(value:internal,contentPadding:EdgeInsets.zero,
          onChanged:(v)=>setDialog(()=>internal=v??false),title:const Text('یادداشت داخلی'),controlAffinity:ListTileControlAffinity.leading),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ارسال'))],
    )));
    if(ok==true && body.text.trim().isNotEmpty) await _run(() async {
      final uid=_db.auth.currentUser?.id; if(uid==null) throw const AuthException('Authentication required');
      await _db.from('ticket_comments').insert({'business_id':_businessId,'ticket_id':t['id'],'author_user_id':uid,'body':body.text.trim(),'visibility':internal?'internal':'public'});
    },'پیام ثبت شد.');
    body.dispose();
  }

  Future<void> _edit(Map<String,dynamic> t) async {
    final title = TextEditingController(text: t['title'] as String);
    final description = TextEditingController(text: t['description'] as String);
    var priority = t['priority'] as String;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('ویرایش تیکت'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 200, decoration: const InputDecoration(labelText: 'عنوان')),
          const SizedBox(height: 10),
          TextField(controller: description, minLines: 3, maxLines: 6, maxLength: 10000,
            decoration: const InputDecoration(labelText: 'شرح')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: priority, decoration: const InputDecoration(labelText: 'اولویت'),
            items: priorities.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setDialog(() => priority = v ?? 'normal')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    ));
    if (ok == true) {
      if (title.text.trim().length < 3 || description.text.trim().isEmpty) {
        _toast('عنوان و شرح تیکت را کامل کنید.');
      } else {
        await _patch(t, {'title': title.text.trim(), 'description': description.text.trim(), 'priority': priority}, 'تغییرات ذخیره شد.');
      }
    }
    title.dispose();
    description.dispose();
  }

  Future<void> _archive(Map<String,dynamic> t) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('بایگانی تیکت؟'),
      content:const Text('تیکت بایگانی شود؟'),actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('بایگانی'))]));
    if(ok==true) await _patch(t,{'archived_at':DateTime.now().toUtc().toIso8601String()},'تیکت بایگانی شد.');
  }

  @override
  Widget build(BuildContext context) {
    final chosen=selected;
    final filtered=_tickets.where((t)=>_filter=='all'||t['status']==_filter).toList();
    return Scaffold(
      appBar:AppBar(title:const Text('مرکز تیکت‌ها'),actions:[IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh))]),
      floatingActionButton:can('tickets.create')?FloatingActionButton.extended(onPressed:_busy?null:_create,icon:const Icon(Icons.add),label:const Text('تیکت جدید')):null,
      body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),
        child:Column(mainAxisSize:MainAxisSize.min,children:[Text(_error!,textAlign:TextAlign.center),TextButton(onPressed:_load,child:const Text('تلاش دوباره'))])))
      :RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(14,12,14,100),children:[
        Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.membership.businessName,style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:4),Text('تیکت‌های شعبه انتخاب‌شده: '+_tickets.length.toString(),style:const TextStyle(color:Colors.white60)),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(initialValue:_filter,decoration:const InputDecoration(labelText:'فیلتر وضعیت'),
            items:[const DropdownMenuItem(value:'all',child:Text('همه وضعیت‌ها')),...statuses.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value)))],
            onChanged:(v)=>setState(()=>_filter=v??'all')),
        ]))),
        if(filtered.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(24),child:Text('تیکتی برای نمایش وجود ندارد.',textAlign:TextAlign.center))),
        ...filtered.map((t)=>Card(clipBehavior:Clip.antiAlias,child:InkWell(onTap:()async{
          setState(()=>_selectedId=t['id'] as String); await _loadDetail(t['id'] as String);
        },child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(t['ticket_number'] as String,style:const TextStyle(color:Color(0xFF00D8E8),fontWeight:FontWeight.bold))),
            Text(statuses[t['status']]??t['status'] as String,style:const TextStyle(color:Colors.white60,fontSize:11))]),
          const SizedBox(height:8),Text(t['title'] as String,style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:6),Text(t['description'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white60,height:1.6)),
          const SizedBox(height:8),Text('اولویت: '+(priorities[t['priority']]??t['priority'] as String),style:const TextStyle(color:Colors.white54,fontSize:11)),
        ]))))),
        if(chosen!=null) _details(chosen),
      ])),
    );
  }

  Widget _details(Map<String,dynamic> t) {
    final status=t['status'] as String;
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('جزئیات '+(t['ticket_number'] as String),style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:12),Text(t['description'] as String,style:const TextStyle(height:1.8)),
      if(can('tickets.status.manage')) ...[
        const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:status,decoration:const InputDecoration(labelText:'وضعیت'),
          items:statuses.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
          onChanged:_busy?null:(v)=>v==null||v==status?null:_patch(t,{'status':v},'وضعیت تغییر کرد.')),
      ],
      if(can('tickets.assign')) ...[
        const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:(t['assignee_user_id'] as String?)??'',decoration:const InputDecoration(labelText:'مسئول'),
          items:[const DropdownMenuItem(value:'',child:Text('بدون مسئول')),..._members.map((m)=>DropdownMenuItem(value:m['user_id'] as String,
            child:Text((m['role_key'] as String)+' · '+(m['user_id'] as String).substring(0,8))))],
          onChanged:_busy?null:(v)=>_patch(t,{'assignee_user_id':(v==null||v.isEmpty)?null:v},'مسئول تغییر کرد.')),
      ],
      if(can('tickets.delete')&&(status=='resolved'||status=='closed')) ...[
        const SizedBox(height:10),OutlinedButton.icon(onPressed:_busy?null:()=>_archive(t),icon:const Icon(Icons.archive_outlined),label:const Text('بایگانی تیکت')),
      ],
      if (can('tickets.update')) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _busy ? null : () => _edit(t),
          icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش محتوا')),
      ],
      const Divider(height:28),
      Row(children:[Expanded(child:Text('گفتگو',style:Theme.of(context).textTheme.titleSmall)),
        if(can('tickets.comments.create')) TextButton.icon(onPressed:_busy?null:_comment,icon:const Icon(Icons.add_comment_outlined),label:const Text('پیام جدید'))]),
      ..._comments.where((c)=>c['visibility']=='public'||can('tickets.comments.internal.read')).map((c)=>Container(
        width:double.infinity,margin:const EdgeInsets.only(top:8),padding:const EdgeInsets.all(12),
        decoration:BoxDecoration(color:c['visibility']=='internal'?const Color(0x2234C9D7):const Color(0x221477FF),borderRadius:BorderRadius.circular(12)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(c['visibility']=='internal'?'یادداشت داخلی':'پیام',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:11)),
          const SizedBox(height:6),Text(c['body'] as String,style:const TextStyle(height:1.7)),
        ]))),
      if(_comments.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text('هنوز پیامی ثبت نشده است.',style:TextStyle(color:Colors.white54))),
      const Divider(height:28),Text('تاریخچه',style:Theme.of(context).textTheme.titleSmall),
      ..._events.take(10).map((e)=>Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
        const Icon(Icons.history,size:15,color:Colors.white54),const SizedBox(width:8),
        Expanded(child:Text(e['event_type'] as String,style:const TextStyle(color:Colors.white70,fontSize:12))),
        Text(_date(e['created_at'] as String),style:const TextStyle(color:Colors.white38,fontSize:10)),
      ]))),
    ])));
  }
  String _date(String s) {
    final d=DateTime.tryParse(s)?.toLocal(); if(d==null)return '';
    return d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
  }
}
