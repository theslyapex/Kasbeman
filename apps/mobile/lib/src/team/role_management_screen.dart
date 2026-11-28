import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({super.key, required this.businessId});
  final String businessId;

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _catalogue = [];
  Set<String> _manageablePermissions = {};

  bool get _canManageRoles =>
      _manageablePermissions.contains('team.roles.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roles = await _client.from('roles')
          .select('id,role_key,name,description,is_system,status')
          .eq('business_id', widget.businessId)
          .order('is_system', ascending: false)
          .order('name');
      final permissionCatalogue = await _client.from('permissions')
          .select('permission_key,module_key,label_fa,description_fa,is_sensitive')
          .order('module_key')
          .order('action_key');

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw const FormatException('Authentication required');

      final assignments = await _client.from('member_role_assignments')
          .select('role_id')
          .eq('business_id', widget.businessId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .isFilter('branch_id', null);
      final assignedRoleIds = assignments
          .map((row) => row['role_id'] as String)
          .toList(growable: false);
      final ownPermissionRows = assignedRoleIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client.from('role_permissions')
              .select('permission_key')
              .eq('business_id', widget.businessId)
              .inFilter('role_id', assignedRoleIds);
      final allRoleIds = roles.map((row) => row['id'] as String).toList();
      final allPermissionRows = allRoleIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client.from('role_permissions')
              .select('role_id,permission_key')
              .eq('business_id', widget.businessId)
              .inFilter('role_id', allRoleIds);

      final permissionsByRole = <String, List<String>>{};
      for (final row in allPermissionRows) {
        final roleId = row['role_id'] as String;
        permissionsByRole.putIfAbsent(roleId, () => <String>[])
            .add(row['permission_key'] as String);
      }

      if (!mounted) return;
      setState(() {
        _roles = roles.map((row) {
          final item = Map<String, dynamic>.from(row);
          item['permission_keys'] =
              permissionsByRole[item['id'] as String] ?? <String>[];
          return item;
        }).toList();
        _catalogue = List<Map<String, dynamic>>.from(permissionCatalogue);
        _manageablePermissions = ownPermissionRows
            .map((row) => row['permission_key'] as String)
            .toSet();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'دریافت نقش‌ها و مجوزها انجام نشد. دسترسی و اتصال را بررسی کن.';
      });
    }
  }

  Future<void> _editRole({Map<String, dynamic>? role}) async {
    final nameController = TextEditingController(
      text: role?['name'] as String? ?? '',
    );
    final descriptionController = TextEditingController(
      text: role?['description'] as String? ?? '',
    );
    final selected = <String>{
      ...((role?['permission_keys'] as List?)?.cast<String>() ?? const <String>[]),
    };
    var validationError = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(role == null ? 'ساخت نقش سفارشی' : 'ویرایش نقش'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'نام نقش'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                  ),
                  const SizedBox(height: 14),
                  const Text('مجوزها', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'فقط مجوزهایی را می‌توانی اضافه کنی که خودت در این کسب‌وکار داری. مجوزهای حساس جداگانه مشخص شده‌اند.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  ..._catalogue.map((permission) {
                    final key = permission['permission_key'] as String;
                    final checked = selected.contains(key);
                    final canGrant = _manageablePermissions.contains(key);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      title: Text(permission['label_fa'] as String),
                      subtitle: Text(
                        permission['is_sensitive'] == true
                            ? 'حساس · ${permission['description_fa'] ?? key}'
                            : (permission['description_fa'] as String? ?? key),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onChanged: !canGrant && !checked
                          ? null
                          : (value) => setDialogState(() {
                                if (value == true) {
                                  selected.add(key);
                                } else {
                                  selected.remove(key);
                                }
                              }),
                    );
                  }),
                  if (validationError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(validationError, style: const TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().length < 2) {
                  setDialogState(() => validationError = 'نام نقش باید حداقل دو نویسه باشد.');
                  return;
                }
                if (selected.any((key) => !_manageablePermissions.contains(key))) {
                  setDialogState(() => validationError = 'ابتدا مجوزهایی را که خودت نداری از نقش حذف کن.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('ذخیره نقش'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      nameController.dispose();
      descriptionController.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      final payload = {
        'name': nameController.text.trim(),
        'description': descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
      };
      String roleId;
      if (role == null) {
        final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
        final created = await _client.from('roles').insert({
          'business_id': widget.businessId,
          'role_key': key,
          ...payload,
          'is_system': false,
          'created_by': _client.auth.currentUser!.id,
        }).select('id').single();
        roleId = created['id'] as String;
      } else {
        roleId = role['id'] as String;
        await _client.from('roles').update(payload)
            .eq('business_id', widget.businessId)
            .eq('id', roleId);
      }

      final currentKeys = role == null
          ? <String>{}
          : (role['permission_keys'] as List).cast<String>().toSet();
      final additions = selected.difference(currentKeys);
      final removals = currentKeys.difference(selected);
      if (additions.isNotEmpty) {
        try {
          await _client.from('role_permissions').insert(additions.map((key) => {
            'business_id': widget.businessId,
            'role_id': roleId,
            'permission_key': key,
          }).toList());
        } catch (_) {
          if (role == null) {
            await _client.from('roles').delete()
                .eq('business_id', widget.businessId).eq('id', roleId);
          }
          rethrow;
        }
      }
      if (removals.isNotEmpty) {
        try {
          await _client.from('role_permissions').delete()
              .eq('business_id', widget.businessId)
              .eq('role_id', roleId)
              .inFilter('permission_key', removals.toList());
        } catch (_) {
          if (additions.isNotEmpty) {
            await _client.from('role_permissions').delete()
                .eq('business_id', widget.businessId)
                .eq('role_id', roleId)
                .inFilter('permission_key', additions.toList());
          }
          rethrow;
        }
      }
      await _load();
      if (mounted) _showMessage('نقش و مجوزهای آن ذخیره شد.');
    } on PostgrestException {
      if (mounted) _showMessage('ذخیره نقش انجام نشد؛ مجوزهای انتخاب‌شده را بررسی کن.');
    } catch (_) {
      if (mounted) _showMessage('ذخیره نقش انجام نشد.');
    } finally {
      nameController.dispose();
      descriptionController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveRole(Map<String, dynamic> role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بایگانی نقش'),
        content: Text('نقش «${role['name']}» بایگانی شود؟ دسترسی‌های این نقش غیرفعال می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('بایگانی')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _client.from('roles').update({'status': 'archived'})
          .eq('business_id', widget.businessId)
          .eq('id', role['id'] as String)
          .eq('is_system', false)
          .eq('status', 'active');
      await _load();
      if (mounted) _showMessage('نقش بایگانی شد.');
    } on PostgrestException {
      if (mounted) _showMessage('بایگانی نقش انجام نشد؛ مجوز مدیریت نقش‌ها را بررسی کن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نقش‌ها و مجوزها')),
      floatingActionButton: _canManageRoles
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _editRole(),
              icon: const Icon(Icons.add),
              label: const Text('نقش جدید'),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
                    ]),
                  ))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      const Text(
                        'نقش‌های سیستمی محافظت شده‌اند. نقش سفارشی فقط می‌تواند مجوزهایی را دریافت کند که مدیر ایجادکننده در اختیار دارد.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      if (!_canManageRoles)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text('برای ساخت یا ویرایش نقش، مجوز «مدیریت نقش‌ها» لازم است.'),
                        )),
                      ..._roles.map((role) {
                        final system = role['is_system'] == true;
                        final active = role['status'] == 'active';
                        final keys = (role['permission_keys'] as List).cast<String>();
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(
                                    '${role['name']}${system ? ' · سیستمی' : ''}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  )),
                                  if (system)
                                    const Text('محافظت‌شده', style: TextStyle(color: Colors.white54, fontSize: 11))
                                  else if (!active)
                                    const Text('بایگانی‌شده', style: TextStyle(color: Colors.white54, fontSize: 11))
                                  else if (_canManageRoles)
                                    PopupMenuButton<String>(
                                      enabled: !_busy,
                                      onSelected: (value) {
                                        if (value == 'edit') _editRole(role: role);
                                        if (value == 'archive') _archiveRole(role);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                        PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                                      ],
                                    ),
                                ]),
                                if ((role['description'] as String?)?.isNotEmpty == true)
                                  Text(role['description'] as String, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 6),
                                Text('${keys.length} مجوز', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                if (keys.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: keys.map((key) {
                                      final permission = _catalogue.where((item) => item['permission_key'] == key);
                                      final label = permission.isEmpty ? key : permission.first['label_fa'] as String;
                                      return Chip(label: Text(label, style: const TextStyle(fontSize: 10)));
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
      ),
    );
  }
}
