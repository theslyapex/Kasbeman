import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/src/workspace/branch_selection_store.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_repository.dart';
import 'package:kasbeman_mobile/src/workspace/workspace_screen.dart';

class _FakeBranchSelectionStore implements BranchSelectionStore {
  final Map<String, String> values = {};

  String _key(String userId, String businessId) => '$userId:$businessId';

  @override
  Future<String?> read({
    required String userId,
    required String businessId,
  }) async =>
      values[_key(userId, businessId)];

  @override
  Future<void> write({
    required String userId,
    required String businessId,
    required String branchId,
  }) async {
    values[_key(userId, businessId)] = branchId;
  }
}

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

  @override
  Future<List<BusinessBranch>> fetchBranches(String businessId) async => [
        BusinessBranch(
          id: 'branch-main',
          businessId: businessId,
          name: 'شعبه اصلی',
          code: 'MAIN',
          isPrimary: true,
        ),
        BusinessBranch(
          id: 'branch-north',
          businessId: businessId,
          name: 'شعبه شمال',
          code: 'NORTH',
          isPrimary: false,
        ),
      ];

  @override
  Future<String> createBranch({
    required String businessId,
    required String name,
    String? code,
  }) async =>
      'branch-created';
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
          branchSelectionStore: _FakeBranchSelectionStore(),
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
          branchSelectionStore: _FakeBranchSelectionStore(),
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
    final submitButton = find.widgetWithText(FilledButton, 'ساخت کسب‌وکار');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
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

    final selectionStore = _FakeBranchSelectionStore();
    await selectionStore.write(
      userId: 'local-user',
      businessId: 'business-1',
      branchId: 'branch-north',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          email: 'user@example.com',
          repository: _FakeWorkspaceRepository([membership]),
          branchSelectionStore: selectionStore,
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
    expect(find.text('شعبه شمال'), findsOneWidget);
  });
}
