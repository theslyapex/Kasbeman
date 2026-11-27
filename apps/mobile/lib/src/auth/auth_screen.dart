import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSignup = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _notice;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      if (_isSignup) {
        final response = await auth.signUp(
          email: email,
          password: password,
        );
        if (response.session == null && mounted) {
          setState(() {
            _notice =
                'حساب ساخته شد. ایمیل تأیید ارسال‌شده را باز کن؛ سپس وارد کسبمن شو.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException {
      if (mounted) {
        setState(() {
          _error = _isSignup
              ? 'ثبت‌نام انجام نشد. ایمیل را بررسی کن یا ممکن است قبلاً ثبت شده باشد.'
              : 'ورود انجام نشد. ایمیل و رمز عبور را بررسی کن.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ارتباط با سرور برقرار نشد. دوباره تلاش کن.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'یک ایمیل معتبر وارد کن.';
    }
    if (email.length > 254) return 'ایمیل بیش از حد طولانی است.';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'رمز عبور را وارد کن.';
    if (_isSignup && password.length < 10) {
      return 'رمز عبور باید حداقل ۱۰ کاراکتر باشد.';
    }
    if (password.length > 128) return 'رمز عبور بیش از حد طولانی است.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('کسبمن'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 18),
            child: Icon(Icons.business_center_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 48, color: Color(0xFF00D8E8)),
                    const SizedBox(height: 22),
                    Text(
                      _isSignup ? 'حساب کسبمن بساز' : 'خوش برگشتی',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignup
                          ? 'با یک حساب، کسب‌وکارهایت را یکپارچه مدیریت کن.'
                          : 'برای ورود به فضای کاری خود اطلاعات حسابت را وارد کن.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70, height: 1.8),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('ورود')),
                        ButtonSegment(value: true, label: Text('ثبت‌نام')),
                      ],
                      selected: {_isSignup},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) {
                              setState(() {
                                _isSignup = selection.first;
                                _error = null;
                                _notice = null;
                              });
                            },
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _emailController,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'ایمیل',
                        hintText: 'name@example.com',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      validator: _validatePassword,
                      obscureText: _obscurePassword,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      autofillHints: [
                        _isSignup
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'نمایش رمز عبور'
                              : 'پنهان کردن رمز عبور',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (_isSignup) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: true,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        validator: (value) => value != _passwordController.text
                            ? 'تکرار رمز عبور یکسان نیست.'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'تکرار رمز عبور',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _Message(text: _error!, isError: true),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      _Message(text: _notice!, isError: false),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isSignup ? 'ایجاد حساب کسبمن' : 'ورود به کسبمن'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'کسب‌وکارت، یک قدم جلوتر.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white54),
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

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : const Color(0xFF00D8A5);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.7)),
    );
  }
}
