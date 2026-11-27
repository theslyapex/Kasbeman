import 'package:shared_preferences/shared_preferences.dart';

abstract interface class BranchSelectionStore {
  Future<String?> read({
    required String userId,
    required String businessId,
  });

  Future<void> write({
    required String userId,
    required String businessId,
    required String branchId,
  });
}

class SharedPreferencesBranchSelectionStore
    implements BranchSelectionStore {
  const SharedPreferencesBranchSelectionStore();

  String _key(String userId, String businessId) =>
      'kasbeman.active_branch.v1.$userId.$businessId';

  @override
  Future<String?> read({
    required String userId,
    required String businessId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key(userId, businessId));
  }

  @override
  Future<void> write({
    required String userId,
    required String businessId,
    required String branchId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(userId, businessId), branchId);
  }
}
