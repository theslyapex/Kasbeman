import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.email});

  final String email;

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
        title: const Text('کسبمن'),
        actions: [
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
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 48, color: Color(0xFF00D8E8)),
                  const SizedBox(height: 20),
                  Text(
                    'با موفقیت وارد شدی',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(email,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 28),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('فضای کاری کسبمن',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                            'ورود امن فعال است. مرحله بعد، دریافت فهرست کسب‌وکارهای عضو و انتخاب فضای کاری خواهد بود.',
                            style: TextStyle(height: 1.8, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('خروج از حساب'),
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
