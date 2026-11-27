import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/main.dart';

void main() {
  testWidgets('shows the Kasbeman welcome screen', (tester) async {
    await tester.pumpWidget(const KasbemanApp());

    expect(find.text('کسبمن'), findsOneWidget);
    expect(find.text('کسب‌وکارت، یک قدم جلوتر'), findsOneWidget);
  });
}
