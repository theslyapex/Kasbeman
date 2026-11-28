import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessMembership {
  const BusinessMembership({
    required this.businessId,
    required this.businessName,
    required this.slug,
    required this.roleKey,
  });

  final String businessId;
  final String businessName;
  final String slug;
  final String roleKey;

  String get roleLabel => switch (roleKey) {
        'owner' => 'مالک',
        'admin' => 'مدیر',
        'member' => 'عضو',
        _ => 'عضو',
      };

  factory BusinessMembership.fromJson(Map<String, dynamic> json) {
    final business = Map<String, dynamic>.from(
      json['businesses'] as Map,
    );

    return BusinessMembership(
      businessId: json['business_id'] as String,
      businessName: business['name'] as String,
      slug: business['slug'] as String,
      roleKey: json['role_key'] as String,
    );
  }
}

class BusinessBranch {
  const BusinessBranch({
    required this.id,
    required this.businessId,
    required this.name,
    required this.code,
    required this.isPrimary,
  });

  final String id;
  final String businessId;
  final String name;
  final String? code;
  final bool isPrimary;

  factory BusinessBranch.fromJson(Map<String, dynamic> json) {
    return BusinessBranch(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      code: json['code'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

class BusinessCreationRateLimitException implements Exception {
  const BusinessCreationRateLimitException();
}

abstract interface class WorkspaceRepository {
  Future<List<BusinessMembership>> fetchMyBusinesses();

  Future<String> createBusiness({
    required String name,
    required String slug,
  });

  Future<List<BusinessBranch>> fetchBranches(String businessId);

  Future<Set<String>> fetchPermissions({
    required String businessId,
    required String userId,
    required String? branchId,
  });

  Future<String> createBranch({
    required String businessId,
    required String name,
    String? code,
  });
}

class SupabaseWorkspaceRepository implements WorkspaceRepository {
  SupabaseWorkspaceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<BusinessMembership>> fetchMyBusinesses() async {
    final rows = await _client
        .from('business_members')
        .select('''
          business_id,
          role_key,
          joined_at,
          businesses!inner (
            id,
            name,
            slug,
            status
          )
        ''')
        .eq('status', 'active')
        .eq('businesses.status', 'active')
        .order('joined_at', ascending: false)
        .limit(100);

    return rows
        .map(
          (row) => BusinessMembership.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> createBusiness({
    required String name,
    required String slug,
  }) async {
    final result = await _client.rpc(
      'create_business',
      params: {
        'p_name': name.trim(),
        'p_slug': slug.trim().toLowerCase(),
      },
    );

    if (result == null) {
      throw const BusinessCreationRateLimitException();
    }
    if (result is! String || result.isEmpty) {
      throw const FormatException('Unexpected business identifier.');
    }

    return result;
  }

  @override
  Future<List<BusinessBranch>> fetchBranches(String businessId) async {
    final rows = await _client
        .from('branches')
        .select('id,business_id,name,code,is_primary')
        .eq('business_id', businessId)
        .eq('status', 'active')
        .order('is_primary', ascending: false)
        .order('created_at');

    return rows
        .map(
          (row) => BusinessBranch.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Set<String>> fetchPermissions({
    required String businessId,
    required String userId,
    required String? branchId,
  }) async {
    final assignments = await _client
        .from('member_role_assignments')
        .select('role_id,branch_id')
        .eq('business_id', businessId)
        .eq('user_id', userId)
        .eq('status', 'active');

    final roleIds = assignments
        .where((row) =>
            row['branch_id'] == null || row['branch_id'] == branchId)
        .map((row) => row['role_id'] as String)
        .toSet()
        .toList(growable: false);

    if (roleIds.isEmpty) return const <String>{};

    final rows = await _client
        .from('role_permissions')
        .select('permission_key')
        .eq('business_id', businessId)
        .inFilter('role_id', roleIds);

    return rows
        .map((row) => row['permission_key'] as String)
        .toSet();
  }

  @override
  Future<String> createBranch({
    required String businessId,
    required String name,
    String? code,
  }) async {
    final normalizedCode = code?.trim().toUpperCase();
    final row = await _client
        .from('branches')
        .insert({
          'business_id': businessId,
          'name': name.trim(),
          'code': normalizedCode == null || normalizedCode.isEmpty
              ? null
              : normalizedCode,
        })
        .select('id')
        .single();

    final id = row['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Unexpected branch identifier.');
    }
    return id;
  }
}
