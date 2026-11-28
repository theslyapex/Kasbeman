import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget did not appear before timeout: $finder');
}

@Tags(['local-supabase-e2e'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Flutter signup and workspace creation use the local Supabase Auth and Data API',
    (tester) async {
      expect(_supabaseUrl, isNotEmpty, reason: 'Pass SUPABASE_URL with --dart-define.');
      expect(_supabaseKey, isNotEmpty, reason: 'Pass SUPABASE_PUBLISHABLE_KEY with --dart-define.');

      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseKey,
      );

      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final email = 'kasbeman-mobile-e2e-$runId@example.com';
      final password = 'Mobile-E2E-$runId-Aa9!';
      const businessName = 'کسب‌وکار آزمایش موبایل';
      final businessSlug = 'kasbeman-mobile-e2e-$runId';

      await tester.pumpWidget(const KasbemanApp(configured: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ثبت‌نام'));
      await tester.pumpAndSettle();

      final authFields = find.byType(TextFormField);
      expect(authFields, findsNWidgets(3));
      await tester.enterText(authFields.at(0), email);
      await tester.enterText(authFields.at(1), password);
      await tester.enterText(authFields.at(2), password);
      final signupButton = find.text('ایجاد حساب کسبمن');
      await tester.ensureVisible(signupButton);
      await tester.tap(signupButton);
      await _pumpUntilVisible(tester, find.text('ساخت اولین کسب‌وکار'));

      final createFirstBusiness = find.text('ساخت اولین کسب‌وکار');
      await tester.ensureVisible(createFirstBusiness);
      await tester.tap(createFirstBusiness);
      await tester.pumpAndSettle();

      final businessFields = find.byType(TextFormField);
      expect(businessFields, findsNWidgets(2));
      await tester.enterText(businessFields.at(0), businessName);
      await tester.enterText(businessFields.at(1), businessSlug);
      final createButton = find.text('ساخت کسب‌وکار');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await _pumpUntilVisible(tester, find.text(businessName));

      expect(find.text('نقش شما: مالک'), findsOneWidget);

      final signOutButton = find.byTooltip('خروج از حساب');
      await tester.tap(signOutButton);
      await _pumpUntilVisible(tester, find.text('خوش برگشتی'));

      final loginFields = find.byType(TextFormField);
      expect(loginFields, findsNWidgets(2));
      await tester.enterText(loginFields.at(0), email);
      await tester.enterText(loginFields.at(1), password);
      final loginButton = find.text('ورود به کسبمن');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await _pumpUntilVisible(tester, find.text('انتخاب فضای کاری'));
      await _pumpUntilVisible(tester, find.text(businessName));

      await Supabase.instance.client.auth.signOut();
    },
  );
}
