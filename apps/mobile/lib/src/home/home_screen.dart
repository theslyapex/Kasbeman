import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.email,
    required this.membership,
    required this.onSwitchWorkspace,
  });

  final String email;
  final BusinessMembership membership;
  final VoidCallback onSwitchWorkspace;

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خروج انجام نشد. دوباره تلاش کن.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(membership.businessName),
        actions: [
          IconButton(
            tooltip: 'تغییر فضای کاری',
            onPressed: onSwitchWorkspace,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 52,
                    color: Color(0xFF00D8E8),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'فضای کاری شما آماده است',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    membership.businessName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'نقش شما: ${membership.roleLabel}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'حساب کاربری',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            email,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 8),
                          const Text(
                            'اتصال به عضویت کسب‌وکار از دیتابیس برقرار است. ماژول‌های عملیاتی در مراحل بعدی به این فضای کاری متصل می‌شوند.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onSwitchWorkspace,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('تغییر فضای کاری'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
