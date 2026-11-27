import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryProduct {
  const InventoryProduct({
    required this.id,
    required this.businessId,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.productType,
    required this.unitName,
    required this.salePrice,
    required this.purchasePrice,
    required this.status,
  });

  final String id;
  final String businessId;
  final String name;
  final String? sku;
  final String? barcode;
  final String productType;
  final String unitName;
  final num salePrice;
  final num purchasePrice;
  final String status;

  bool get isGoods => productType == 'goods';

  factory InventoryProduct.fromJson(Map<String, dynamic> json) {
    return InventoryProduct(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      productType: json['product_type'] as String,
      unitName: json['unit_name'] as String,
      salePrice: json['sale_price'] as num,
      purchasePrice: json['purchase_price'] as num,
      status: json['status'] as String,
    );
  }
}

class InventoryWarehouse {
  const InventoryWarehouse({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.name,
    required this.code,
    required this.isDefault,
    required this.status,
  });

  final String id;
  final String businessId;
  final String branchId;
  final String name;
  final String code;
  final bool isDefault;
  final String status;

  factory InventoryWarehouse.fromJson(Map<String, dynamic> json) {
    return InventoryWarehouse(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      isDefault: json['is_default'] as bool? ?? false,
      status: json['status'] as String,
    );
  }
}

class InventoryBalance {
  const InventoryBalance({
    required this.businessId,
    required this.branchId,
    required this.warehouseId,
    required this.productId,
    required this.productName,
    required this.unitName,
    required this.warehouseName,
    required this.quantity,
    required this.updatedAt,
  });

  final String businessId;
  final String branchId;
  final String warehouseId;
  final String productId;
  final String productName;
  final String unitName;
  final String warehouseName;
  final num quantity;
  final DateTime updatedAt;

  factory InventoryBalance.fromJson(Map<String, dynamic> json) {
    return InventoryBalance(
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String,
      warehouseId: json['warehouse_id'] as String,
      productId: json['product_id'] as String,
      productName: (json['products'] as Map)['name'] as String,
      unitName: (json['products'] as Map)['unit_name'] as String,
      warehouseName: (json['warehouses'] as Map)['name'] as String,
      quantity: json['quantity_on_hand'] as num,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

abstract interface class InventoryRepository {
  Future<List<InventoryProduct>> fetchProducts(String businessId);

  Future<String> createProduct({
    required String businessId,
    required String name,
    required String productType,
    required String unitName,
    required num salePrice,
    required num purchasePrice,
    String? sku,
    String? barcode,
  });

  Future<List<InventoryWarehouse>> fetchWarehouses({
    required String businessId,
    required String branchId,
  });

  Future<List<InventoryBalance>> fetchBalances({
    required String businessId,
    required String branchId,
  });
}

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<InventoryProduct>> fetchProducts(String businessId) async {
    final rows = await _client
        .from('products')
        .select(
          'id,business_id,name,sku,barcode,product_type,unit_name,'
          'sale_price,purchase_price,status',
        )
        .eq('business_id', businessId)
        .order('name');

    return rows
        .map((row) => InventoryProduct.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  @override
  Future<String> createProduct({
    required String businessId,
    required String name,
    required String productType,
    required String unitName,
    required num salePrice,
    required num purchasePrice,
    String? sku,
    String? barcode,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const FormatException('Authentication required.');
    }

    final row = await _client
        .from('products')
        .insert({
          'business_id': businessId,
          'created_by': userId,
          'name': name.trim(),
          'sku': _emptyToNull(sku),
          'barcode': _emptyToNull(barcode),
          'product_type': productType,
          'unit_name': unitName.trim(),
          'sale_price': salePrice,
          'purchase_price': purchasePrice,
        })
        .select('id')
        .single();

    final id = row['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Unexpected product identifier.');
    }
    return id;
  }

  @override
  Future<List<InventoryWarehouse>> fetchWarehouses({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _client
        .from('warehouses')
        .select('id,business_id,branch_id,name,code,is_default,status')
        .eq('business_id', businessId)
        .eq('branch_id', branchId)
        .eq('status', 'active')
        .order('is_default', ascending: false)
        .order('name');

    return rows
        .map((row) => InventoryWarehouse.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  @override
  Future<List<InventoryBalance>> fetchBalances({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _client
        .from('stock_balances')
        .select(
          'business_id,branch_id,warehouse_id,product_id,quantity_on_hand,updated_at,'
          'products!stock_balances_product_fkey(name,unit_name),'
          'warehouses!stock_balances_warehouse_fkey(name)',
        )
        .eq('business_id', businessId)
        .eq('branch_id', branchId)
        .order('updated_at', ascending: false);

    return rows
        .map((row) => InventoryBalance.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
