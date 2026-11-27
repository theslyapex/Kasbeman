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

abstract interface class WorkspaceRepository {
  Future<List<BusinessMembership>> fetchMyBusinesses();
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
}
