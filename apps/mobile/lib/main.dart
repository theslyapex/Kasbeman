import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KasbemanApp());
}

class KasbemanApp extends StatelessWidget {
  const KasbemanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF071426);
    const surface = Color(0xFF10233D);
    const cyan = Color(0xFF00D8E8);
    const blue = Color(0xFF147BFF);

    return MaterialApp(
      title: 'کسبمن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: Brightness.dark,
          surface: surface,
        ),
        scaffoldBackgroundColor: navy,
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: _WelcomeScreen(),
      ),
    );
  }
}

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کسبمن'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: Icon(Icons.business_center_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 52,
                    color: Color(0xFF00D8E8),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'کسب‌وکارت، یک قدم جلوتر',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'مدیریت یکپارچه کسب‌وکار، در وب و موبایل؛ با یک حساب و یک فضای کاری مشترک.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                          height: 1.8,
                        ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('شروع به کار'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'نسخه پایه اپلیکیشن در حال آماده‌سازی است.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
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
