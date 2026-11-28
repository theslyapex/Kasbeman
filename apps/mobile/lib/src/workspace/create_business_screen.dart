import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workspace_repository.dart';

class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({
    super.key,
    required this.repository,
  });

  final WorkspaceRepository repository;

  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'نام کسب‌وکار حداقل ۲ نویسه باشد.';
    if (name.length > 160) return 'نام کسب‌وکار بیش از حد طولانی است.';
    return null;
  }

  String? _validateSlug(String? value) {
    final slug = value?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$').hasMatch(slug)) {
      return 'شناسه باید ۳ تا ۶۳ نویسه و فقط شامل حروف انگلیسی کوچک، عدد و خط تیره باشد.';
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
      await widget.repository.createBusiness(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BusinessCreationRateLimitException {
      if (!mounted) return;
      setState(() {
        _error = 'در مدت کوتاهی چند کسب‌وکار ساخته‌اید. لطفاً حدود ۱۰ دقیقه دیگر دوباره تلاش کنید.';
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == '23505'
            ? 'این شناسه قبلاً استفاده شده است. شناسه دیگری انتخاب کن.'
            : 'ساخت کسب‌وکار انجام نشد. اطلاعات را بررسی و دوباره تلاش کن.';
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
      appBar: AppBar(title: const Text('ساخت کسب‌وکار')),
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
                      Icons.add_business_outlined,
                      size: 54,
                      color: Color(0xFF00D8E8),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'کسب‌وکار جدیدت را بساز',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'پس از ساخت، حساب تو به‌عنوان مالک ثبت می‌شود و شعبه اصلی نیز به‌صورت خودکار ایجاد خواهد شد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.8),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_saving,
                      maxLength: 160,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.next,
                      validator: _validateName,
                      decoration: const InputDecoration(
                        labelText: 'نام کسب‌وکار',
                        hintText: 'مثلاً فروشگاه آفتاب',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _slugController,
                      enabled: !_saving,
                      maxLength: 63,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      autocorrect: false,
                      validator: _validateSlug,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-z0-9-]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'شناسه انگلیسی کسب‌وکار',
                        hintText: 'aftab-store',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'این شناسه باید یکتا باشد و بعداً برای آدرس و اتصال‌های کسب‌وکار استفاده می‌شود.',
                      style: TextStyle(color: Colors.white60, height: 1.7),
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
                          : const Text('ساخت کسب‌وکار'),
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
