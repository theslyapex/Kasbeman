import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_repository.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_screen.dart';

class _FakeWorkspaceRepository implements WorkspaceRepository {
  _FakeWorkspaceRepository(this.memberships);

  final List<BusinessMembership> memberships;
  int createCalls = 0;

  @override
  Future<List<BusinessMembership>> fetchMyBusinesses() async =>
      List.unmodifiable(memberships);

  @override
  Future<String> createBusiness({
    required String name,
    required String slug,
  }) async {
    createCalls++;
    memberships.add(
      BusinessMembership(
        businessId: 'business-created',
        businessName: name,
        slug: slug,
        roleKey: 'owner',
      ),
    );
    return 'business-created';
  }
}

void main() {
  testWidgets('shows an empty state when the user has no active business',
      (tester) async {
    final repository = _FakeWorkspaceRepository([]);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          email: 'user@example.com',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('هنوز فضای کاری فعالی نداری'), findsOneWidget);
    expect(find.text('ساخت اولین کسب‌وکار'), findsOneWidget);
  });

  testWidgets('creates a business and refreshes the workspace list',
      (tester) async {
    final repository = _FakeWorkspaceRepository([]);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          email: 'user@example.com',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ساخت اولین کسب‌وکار'));
    await tester.pumpAndSettle();

    expect(find.text('ساخت کسب‌وکار'), findsNWidgets(2));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'نام کسب‌وکار'),
      'فروشگاه آفتاب',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'شناسه انگلیسی کسب‌وکار'),
      'aftab-store',
    );
    await tester.tap(find.text('ساخت کسب‌وکار').last);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('فروشگاه آفتاب'), findsOneWidget);
  });

  testWidgets('lists memberships and opens the selected workspace',
      (tester) async {
    const membership = BusinessMembership(
      businessId: 'business-1',
      businessName: 'فروشگاه نمونه',
      slug: 'sample-store',
      roleKey: 'owner',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          email: 'user@example.com',
          repository: _FakeWorkspaceRepository([membership]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فروشگاه نمونه'), findsOneWidget);
    expect(find.text('نقش شما: مالک'), findsOneWidget);

    await tester.tap(find.text('فروشگاه نمونه'));
    await tester.pumpAndSettle();

    expect(find.text('فضای کاری شما آماده است'), findsOneWidget);
    expect(find.text('فروشگاه نمونه'), findsNWidgets(2));
  });
}
