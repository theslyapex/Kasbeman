import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_repository.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_screen.dart';

class _FakeWorkspaceRepository implements WorkspaceRepository {
  _FakeWorkspaceRepository(this.memberships);

  final List<BusinessMembership> memberships;

  @override
  Future<List<BusinessMembership>> fetchMyBusinesses() async => memberships;
}

void main() {
  testWidgets('shows an empty state when the user has no active business',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          email: 'user@example.com',
          repository: _FakeWorkspaceRepository(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('هنوز فضای کاری فعالی نداری'), findsOneWidget);
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
          repository: _FakeWorkspaceRepository(const [membership]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فروشگاه نمونه'), findsOneWidget);
    expect(find.text('نقش شما: مالک'), findsOneWidget);

    await tester.tap(find.text('فروشگاه نمونه'));
    await tester.pumpAndSettle();

    expect(find.text('فضای کاری شما آماده است'), findsOneWidget);
    expect(find.text('فروشگاه نمونه'), findsOneWidget);
  });
}
