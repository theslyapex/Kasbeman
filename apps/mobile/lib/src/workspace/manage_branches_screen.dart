import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_branch_screen.dart';
import 'workspace_repository.dart';

class ManageBranchesScreen extends StatefulWidget {
  const ManageBranchesScreen({
    super.key,
    required this.businessId,
    required this.repository,
  });

  final String businessId;
  final WorkspaceRepository repository;

  @override
  State<ManageBranchesScreen> createState() => _ManageBranchesScreenState();
}

class _ManageBranchesScreenState extends State<ManageBranchesScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;
  List<Map<String, dynamic>> _branches = [];

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
      final rows = await _client
          .from('branches')
          .select('id,business_id,name,code,is_primary,status')
          .eq('business_id', widget.businessId)
          .order('is_primary', ascending: false)
          .order('name');
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'دریافت فهرست شعب انجام نشد. مجوز و اتصال را بررسی کن.';
      });
    }
  }

  Future<void> _addBranch() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => CreateBranchScreen(
          repository: widget.repository,
          businessId: widget.businessId,
        ),
      ),
    );
    if (id == null || !mounted) return;
    _changed = true;
    await _load();
  }

  Future<void> _editBranch(Map<String, dynamic> branch) async {
    final nameController = TextEditingController(text: branch['name'] as String);
    final codeController = TextEditingController(text: (branch['code'] as String?) ?? '');
    var status = branch['status'] as String;
    final isPrimary = branch['is_primary'] == true;
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ویرایش شعبه'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'نام شعبه'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.length < 2) return 'نام حداقل ۲ نویسه باشد.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeController,
                    maxLength: 20,
                    textDirection: TextDirection.ltr,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'کد شعبه (اختیاری)'),
                    validator: (value) {
                      final code = value?.trim() ?? '';
                      if (code.isNotEmpty &&
                          !RegExp(r'^[A-Za-z0-9-]{2,20}$').hasMatch(code)) {
                        return 'کد باید ۲ تا ۲۰ نویسه معتبر باشد.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'وضعیت'),
                    items: [
                      const DropdownMenuItem(value: 'active', child: Text('فعال')),
                      if (!isPrimary)
                        const DropdownMenuItem(value: 'inactive', child: Text('غیرفعال')),
                      if (!isPrimary)
                        const DropdownMenuItem(value: 'archived', child: Text('بایگانی‌شده')),
                    ],
                    onChanged: isPrimary
                        ? null
                        : (value) => setDialogState(() => status = value ?? 'active'),
                  ),
                  if (isPrimary)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'شعبه اصلی همیشه فعال می‌ماند.',
                        style: TextStyle(color: Colors.white60),
                      ),
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
              onPressed: _saving
                  ? null
                  : () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && mounted) {
      await _saveBranch(
        branchId: branch['id'] as String,
        name: nameController.text.trim(),
        code: codeController.text.trim().isEmpty
            ? null
            : codeController.text.trim().toUpperCase(),
        status: status,
      );
    }
    nameController.dispose();
    codeController.dispose();
  }

  Future<void> _saveBranch({
    required String branchId,
    required String name,
    required String? code,
    required String status,
  }) async {
    setState(() => _saving = true);
    try {
      final rows = await _client
          .from('branches')
          .update({
            'name': name,
            'code': code,
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('business_id', widget.businessId)
          .eq('id', branchId)
          .select('id');
      if (rows.isEmpty) {
        throw const PostgrestException(
          message: 'Branch update was not authorized.',
          code: '42501',
        );
      }
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تغییرات شعبه ذخیره شد.')),
      );
      await _load();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23505'
          ? 'این کد قبلاً برای شعبه دیگری ثبت شده است.'
          : 'ویرایش شعبه مجاز نبود یا انجام نشد.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ذخیره تغییرات انجام نشد. دوباره تلاش کن.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() => Navigator.of(context).pop(_changed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت شعب'),
        leading: IconButton(onPressed: _close, icon: const Icon(Icons.arrow_back)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addBranch,
        icon: const Icon(Icons.add_business),
        label: const Text('افزودن شعبه'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
                      ],
                    ),
                  )
                : _branches.isEmpty
                    ? const Center(child: Text('شعبه‌ای ثبت نشده است.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _branches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final branch = _branches[index];
                          final isPrimary = branch['is_primary'] == true;
                          final status = branch['status'] as String;
                          final statusLabel = status == 'active'
                              ? 'فعال'
                              : status == 'inactive'
                                  ? 'غیرفعال'
                                  : 'بایگانی‌شده';
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isPrimary ? Icons.store_mall_directory : Icons.store_outlined,
                              ),
                              title: Text(branch['name'] as String),
                              subtitle: Text(
                                '\${isPrimary ? 'شعبه اصلی · ' : ''}$statusLabel'
                                '\${branch['code'] == null ? '' : ' · \${branch['code']}'}',
                              ),
                              trailing: IconButton(
                                tooltip: 'ویرایش شعبه',
                                onPressed: _saving ? null : () => _editBranch(branch),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
