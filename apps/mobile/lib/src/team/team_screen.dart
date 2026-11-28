import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.membership, required this.permissions});
  final BusinessMembership membership;
  final Set<String> permissions;
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _invitations = [];

  String get _businessId => widget.membership.businessId;
  bool get _canInvite => widget.permissions.contains('team.members.invite');
  bool get _canTransfer => widget.permissions.contains('business.ownership.transfer');

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final members = await _client.from('business_members')
          .select('user_id,role_key,status,joined_at')
          .eq('business_id', _businessId).order('joined_at');
      final invitations = await _client.from('business_invitations')
          .select('id,email,role_key,status,expires_at')
          .eq('business_id', _businessId)
          .order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      setState(() {
        _members = List<Map<String, dynamic>>.from(members);
        _invitations = List<Map<String, dynamic>>.from(invitations);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت اعضا و دعوت‌نامه‌ها انجام نشد. مجوزها و اتصال را بررسی کن.'; });
    }
  }

  Future<void> _createInvitation() async {
    final emailController = TextEditingController();
    var roleKey = 'member';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('دعوت عضو جدید'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'ایمیل')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: roleKey,
              decoration: const InputDecoration(labelText: 'نقش'),
              items: const [
                DropdownMenuItem(value: 'member', child: Text('عضو')),
                DropdownMenuItem(value: 'admin', child: Text('مدیر')),
              ],
              onChanged: (value) => setDialogState(() => roleKey = value ?? 'member'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ساخت دعوت')),
          ],
        ),
      ),
    );
    if (accepted != true) { emailController.dispose(); return; }
    setState(() => _busy = true);
    try {
      final response = await _client.rpc('create_business_invitation', params: {
        'p_business_id': _businessId,
        'p_email': emailController.text.trim().toLowerCase(),
        'p_role_key': roleKey,
        'p_expires_at': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
      });
      final row = response is List ? response.first : response;
      final token = row['invitation_token'] as String?;
      if (token == null || token.isEmpty) throw const FormatException();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('دعوت ساخته شد'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('توکن را فقط برای ایمیل دعوت‌شده ارسال کن. این مقدار فقط همین‌بار نمایش داده می‌شود.'),
            const SizedBox(height: 12),
            SelectableText(token, textDirection: TextDirection.ltr),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy), label: const Text('کپی توکن'),
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) _showMessage('ساخت دعوت انجام نشد. ایمیل یا مجوز دعوت را بررسی کن.');
    } finally {
      emailController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeInvitation(String invitationId) async {
    setState(() => _busy = true);
    try {
      final result = await _client.rpc('revoke_business_invitation', params: {
        'p_business_id': _businessId, 'p_invitation_id': invitationId,
      });
      if (result != true) throw const FormatException();
      await _load();
      if (mounted) _showMessage('دعوت‌نامه لغو شد.');
    } catch (_) {
      if (mounted) _showMessage('لغو دعوت‌نامه انجام نشد.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _transferOwnership() async {
    final candidates = _members.where((member) =>
      member['status'] == 'active' && member['role_key'] != 'owner').toList();
    if (candidates.isEmpty) { _showMessage('عضو فعال دیگری برای انتقال مالکیت وجود ندارد.'); return; }
    String? selectedId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('انتقال مالکیت'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('پس از انتقال، نقش شما به مدیر تغییر می‌کند.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(labelText: 'مالک جدید'),
              items: candidates.map((member) {
                final id = member['user_id'] as String;
                return DropdownMenuItem(value: id, child: Text(id.substring(0, 8), textDirection: TextDirection.ltr));
              }).toList(),
              onChanged: (value) => setDialogState(() => selectedId = value),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: selectedId == null ? null : () => Navigator.pop(dialogContext, true), child: const Text('تأیید انتقال')),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedId == null) return;
    setState(() => _busy = true);
    try {
      await _client.rpc('transfer_business_ownership', params: {
        'p_business_id': _businessId, 'p_new_owner_user_id': selectedId,
      });
      if (mounted) _showMessage('مالکیت منتقل شد. برای به‌روزرسانی نقش، فضای کاری را دوباره باز کن.');
      await _load();
    } catch (_) {
      if (mounted) _showMessage('انتقال مالکیت انجام نشد. مجوز و وضعیت عضو را بررسی کن.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _roleLabel(String? key) => switch (key) {
    'owner' => 'مالک', 'admin' => 'مدیر', _ => 'عضو',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت اعضا')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
              ]),
            ))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text(widget.membership.businessName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              if (_canInvite) FilledButton.icon(
                onPressed: _busy ? null : _createInvitation,
                icon: const Icon(Icons.person_add_alt_1), label: const Text('دعوت عضو جدید')),
              const SizedBox(height: 18),
              Text('اعضای کسب‌وکار (${_members.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._members.map((member) => Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(_roleLabel(member['role_key'] as String?)),
                subtitle: Text(member['user_id'] as String, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(member['status'] == 'active' ? 'فعال' : member['status'] as String),
              ))),
              const SizedBox(height: 18),
              Text('دعوت‌نامه‌ها', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_invitations.isEmpty) const Text('دعوت‌نامه‌ای ثبت نشده است.', style: TextStyle(color: Colors.white70))
              else ..._invitations.map((invite) => Card(child: ListTile(
                title: Text(invite['email'] as String, textDirection: TextDirection.ltr),
                subtitle: Text('${_roleLabel(invite['role_key'] as String?)} · ${invite['status']}'),
                trailing: invite['status'] == 'pending' && _canInvite
                  ? IconButton(tooltip: 'لغو دعوت', onPressed: _busy ? null : () => _revokeInvitation(invite['id'] as String), icon: const Icon(Icons.cancel_outlined))
                  : null,
              ))),
              if (_canTransfer) ...[
                const SizedBox(height: 22), const Divider(color: Colors.white24), const SizedBox(height: 12),
                Text('انتقال مالکیت', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('مالک جدید باید عضو فعال همین کسب‌وکار باشد. نقش شما پس از انتقال به مدیر تغییر می‌کند.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                OutlinedButton.icon(onPressed: _busy ? null : _transferOwnership, icon: const Icon(Icons.swap_horiz), label: const Text('انتقال مالکیت کسب‌وکار')),
              ],
              const SizedBox(height: 20),
              const Text('تعلیق عضویت تا افزودن مسیر مجاز اختصاصی در دیتابیس غیرفعال است.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
      ))),
    );
  }
}
