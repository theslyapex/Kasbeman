import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workspace_repository.dart';

class CreateBranchScreen extends StatefulWidget {
  const CreateBranchScreen({
    super.key,
    required this.repository,
    required this.businessId,
  });

  final WorkspaceRepository repository;
  final String businessId;

  @override
  State<CreateBranchScreen> createState() => _CreateBranchScreenState();
}

class _CreateBranchScreenState extends State<CreateBranchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'نام شعبه حداقل ۲ نویسه باشد.';
    if (name.length > 120) return 'نام شعبه بیش از حد طولانی است.';
    return null;
  }

  String? _validateCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return null;
    if (!RegExp(r'^[A-Z0-9-]{2,20}$').hasMatch(code)) {
      return 'کد شعبه باید ۲ تا ۲۰ نویسه و شامل حروف انگلیسی بزرگ، عدد یا خط تیره باشد.';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final id = await widget.repository.createBranch(
        businessId: widget.businessId,
        name: _nameController.text.trim(),
        code: _codeController.text.trim().isEmpty
            ? null
            : _codeController.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == '23505'
            ? 'این کد قبلاً برای شعبه دیگری ثبت شده است.'
            : 'ساخت شعبه مجاز نبود یا انجام نشد. دسترسی مالک را بررسی کن.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'ارتباط با سرور برقرار نشد. دوباره تلاش کن.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('افزودن شعبه')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.store_mall_directory_outlined,
                      size: 54,
                      color: Color(0xFF00D8E8),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'شعبه جدید کسب‌وکارت را اضافه کن',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'شعبه جدید به همین کسب‌وکار متصل می‌شود و به‌صورت پیش‌فرض شعبه اصلی نخواهد بود.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.8),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_saving,
                      maxLength: 120,
                      validator: _validateName,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'نام شعبه',
                        hintText: 'مثلاً شعبه مرکزی',
                        prefixIcon: Icon(Icons.store_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _codeController,
                      enabled: !_saving,
                      maxLength: 20,
                      textDirection: TextDirection.ltr,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9-]'),
                        ),
                        UpperCaseTextFormatter(),
                      ],
                      validator: _validateCode,
                      decoration: const InputDecoration(
                        labelText: 'کد شعبه (اختیاری)',
                        hintText: 'مثلاً NORTH-01',
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          height: 1.7,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('ثبت شعبه'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
