import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';
import 'role_management_screen.dart';

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
  List<Map<String, dynamic>> _customRoles = [];
  List<Map<String, dynamic>> _roleAssignments = [];
  List<Map<String, dynamic>> _branches = [];

  String get _businessId => widget.membership.businessId;
  bool get _canInvite => widget.permissions.contains('team.members.invite');
  bool get _canTransfer => widget.permissions.contains('business.ownership.transfer');
  bool get _canManageMembers => widget.permissions.contains('team.members.manage');
  bool get _canAssignRoles => widget.permissions.contains('team.roles.assign');

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
      final customRoles = _canAssignRoles
          ? await _client.from('roles')
              .select('id,name,description,status')
              .eq('business_id', _businessId)
              .eq('is_system', false)
              .eq('status', 'active')
              .order('name')
          : <Map<String, dynamic>>[];
      final permissionLabels = _canAssignRoles
          ? await _client.from('permissions')
              .select('permission_key,label_fa')
          : <Map<String, dynamic>>[];
      final rolePermissionRows = _canAssignRoles && customRoles.isNotEmpty
          ? await _client.from('role_permissions')
              .select('role_id,permission_key')
              .eq('business_id', _businessId)
              .inFilter('role_id', customRoles.map((role) => role['id'] as String).toList())
          : <Map<String, dynamic>>[];
      final labelsByKey = <String, String>{
        for (final row in permissionLabels)
          row['permission_key'] as String: row['label_fa'] as String,
      };
      final keysByRole = <String, List<String>>{};
      for (final row in rolePermissionRows) {
        keysByRole.putIfAbsent(row['role_id'] as String, () => <String>[])
            .add(row['permission_key'] as String);
      }
      final enrichedRoles = customRoles.map((role) {
        final item = Map<String, dynamic>.from(role);
        final keys = keysByRole[item['id'] as String] ?? <String>[];
        item['permission_keys'] = keys;
        item['permission_labels'] = keys.map((key) => labelsByKey[key] ?? key).toList();
        return item;
      }).toList();
      final branches = (_canAssignRoles || _canManageMembers ||
              widget.permissions.contains('team.members.read'))
          ? await _client.from('branches')
              .select('id,name,is_primary')
              .eq('business_id', _businessId)
              .eq('status', 'active')
              .order('is_primary', ascending: false)
              .order('name')
          : <Map<String, dynamic>>[];
      final roleAssignments = (_canAssignRoles || _canManageMembers ||
              widget.permissions.contains('team.members.read'))
          ? await _client.from('member_role_assignments')
              .select('id,user_id,role_id,branch_id,status')
              .eq('business_id', _businessId)
              .eq('status', 'active')
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _members = List<Map<String, dynamic>>.from(members);
        _invitations = List<Map<String, dynamic>>.from(invitations);
        _customRoles = List<Map<String, dynamic>>.from(enrichedRoles);
        _roleAssignments = List<Map<String, dynamic>>.from(roleAssignments);
        _branches = List<Map<String, dynamic>>.from(branches);
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

  Future<void> _assignCustomRole(Map<String, dynamic> member) async {
    if (!_canAssignRoles || member['status'] != 'active' ||
        member['role_key'] == 'owner' || _customRoles.isEmpty) {
      return;
    }
    String? selectedRoleId;
    String selectedBranchId = '__business__';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تخصیص نقش سفارشی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedRoleId,
                decoration: const InputDecoration(labelText: 'نقش'),
                items: _customRoles.map((role) => DropdownMenuItem(
                  value: role['id'] as String,
                  child: Text(role['name'] as String),
                )).toList(),
                onChanged: (value) => setDialogState(() => selectedRoleId = value),
              ),
              const SizedBox(height: 12),
              if (selectedRoleId != null) ...[
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final selectedRole = _customRoles.firstWhere(
                    (role) => role['id'] == selectedRoleId,
                  );
                  final labels = (selectedRole['permission_labels'] as List?)?.cast<String>() ?? const <String>[];
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('مجوزهای این نقش', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(labels.isEmpty ? 'بدون مجوز ثبت‌شده' : labels.join('، ')),
                        const SizedBox(height: 4),
                        const Text('این مجوزها فقط در محدوده انتخاب‌شده اعمال می‌شوند.',
                          style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  );
                }),
              ],
              DropdownButtonFormField<String>(
                initialValue: selectedBranchId,
                decoration: const InputDecoration(labelText: 'محدوده دسترسی'),
                items: [
                  const DropdownMenuItem(
                    value: '__business__',
                    child: Text('کل کسب‌وکار'),
                  ),
                  ..._branches.map((branch) => DropdownMenuItem(
                    value: branch['id'] as String,
                    child: Text((branch['name'] as String) +
                        (branch['is_primary'] == true ? ' · اصلی' : '')),
                  )),
                ],
                onChanged: (value) => setDialogState(
                  () => selectedBranchId = value ?? '__business__',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(
              onPressed: selectedRoleId == null ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('تخصیص نقش'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || selectedRoleId == null) return;
    setState(() => _busy = true);
    try {
      await _client.from('member_role_assignments').insert({
        'business_id': _businessId,
        'user_id': member['user_id'],
        'role_id': selectedRoleId,
        'branch_id': selectedBranchId == '__business__' ? null : selectedBranchId,
        'status': 'active',
        'assigned_by': _client.auth.currentUser!.id,
      });
      await _load();
      if (mounted) _showMessage('نقش سفارشی به عضو تخصیص داده شد.');
    } on PostgrestException catch (error) {
      if (mounted) {
        _showMessage(error.code == '23505'
            ? 'این نقش قبلاً به عضو تخصیص داده شده است.'
            : 'تخصیص نقش انجام نشد؛ مجوز و سطح دسترسی نقش بررسی شوند.');
      }
    } catch (_) {
      if (mounted) _showMessage('تخصیص نقش انجام نشد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeRoleAssignment(
      String assignmentId, String roleName, String scopeLabel) async {
    if (!_canManageMembers) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('لغو تخصیص نقش'),
        content: Text('نقش «$roleName» در محدوده «$scopeLabel» از این عضو گرفته شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('لغو نقش')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _client.from('member_role_assignments')
          .update({'status': 'revoked', 'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('business_id', _businessId)
          .eq('id', assignmentId)
          .eq('status', 'active');
      await _load();
      if (mounted) _showMessage('تخصیص نقش لغو شد.');
    } on PostgrestException {
      if (mounted) _showMessage('لغو نقش انجام نشد؛ مجوز مدیریت اعضا لازم است.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _suspendMember(Map<String, dynamic> member) async {
    final targetUserId = member['user_id'] as String;
    if (targetUserId == _client.auth.currentUser?.id || member['role_key'] == 'owner') {
      _showMessage('تعلیق حساب خودتان یا مالک کسب‌وکار مجاز نیست.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعلیق عضویت'),
        content: const Text('دسترسی این عضو به کسب‌وکار تعلیق می‌شود و نقش‌های فعال او نیز لغو خواهند شد. برای بازگشت، باید دعوت‌نامه جدیدی به همان ایمیل ارسال و توسط همان حساب پذیرفته شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تعلیق عضو')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final rows = await _client.from('business_members')
          .update({'status': 'suspended'})
          .eq('business_id', _businessId)
          .eq('user_id', targetUserId)
          .eq('status', 'active')
          .select('user_id');
      if (rows.isEmpty) throw const FormatException();
      await _load();
      if (mounted) _showMessage('عضویت تعلیق شد و دسترسی‌های فعال لغو شدند.');
    } on PostgrestException {
      if (mounted) _showMessage('تعلیق انجام نشد؛ ممکن است مجوز کافی نداشته باشی یا عضو مالک باشد.');
    } catch (_) {
      if (mounted) _showMessage('تعلیق عضو انجام نشد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      appBar: AppBar(
        title: const Text('مدیریت اعضا'),
        actions: [
          if (widget.permissions.contains('team.roles.manage'))
            IconButton(
              tooltip: 'نقش‌ها و مجوزها',
              onPressed: _busy ? null : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RoleManagementScreen(businessId: _businessId),
                ),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
        ],
      ),
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
              ..._members.map((member) {
                final userId = member['user_id'] as String;
                final assignments = _roleAssignments.where((item) => item['user_id'] == userId).toList();
                return Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(_roleLabel(member['role_key'] as String?)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userId, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (assignments.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: assignments.map((assignment) {
                            final role = _customRoles.where((item) => item['id'] == assignment['role_id']);
                            final roleName = role.isEmpty ? 'نقش سفارشی' : role.first['name'] as String;
                            final branchId = assignment['branch_id'] as String?;
                            final branch = _branches.where((item) => item['id'] == branchId);
                            final scopeLabel = branchId == null
                                ? 'کل کسب‌وکار'
                                : branch.isEmpty ? 'شعبه' : branch.first['name'] as String;
                            return ActionChip(
                              label: Text('$roleName · $scopeLabel', style: const TextStyle(fontSize: 10)),
                              onPressed: _canManageMembers
                                  ? () => _revokeRoleAssignment(
                                      assignment['id'] as String, roleName, scopeLabel)
                                  : null,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: (value) {
                      if (value == 'assign') _assignCustomRole(member);
                      if (value == 'suspend') _suspendMember(member);
                    },
                    itemBuilder: (_) => [
                      if (_canAssignRoles && member['status'] == 'active' &&
                          member['role_key'] != 'owner' && _customRoles.isNotEmpty)
                        const PopupMenuItem(value: 'assign', child: Text('تخصیص نقش سفارشی')),
                      if (_canManageMembers && member['status'] == 'active' &&
                          member['role_key'] != 'owner' && userId != _client.auth.currentUser?.id)
                        const PopupMenuItem(value: 'suspend', child: Text('تعلیق عضو')),
                    ],
                  ),
                ));
              }),
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
              const Text('برای بازگرداندن دسترسی عضو تعلیق‌شده، دعوت‌نامه جدیدی به همان ایمیل بفرستید تا همان حساب آن را بپذیرد. حذف دائمی عضویت از این صفحه ارائه نمی‌شود.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
      ))),
    );
  }
}
