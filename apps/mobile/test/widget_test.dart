import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/main.dart';

void main() {
  testWidgets('shows configuration guidance when Supabase is not configured',
      (tester) async {
    await tester.pumpWidget(const KasbemanApp());

    expect(find.text('کسبمن'), findsOneWidget);
    expect(find.text('اتصال به سرور تنظیم نشده است'), findsOneWidget);
  });
}
