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

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitName,
    required this.movementType,
    required this.quantity,
    required this.fromWarehouseName,
    required this.toWarehouseName,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String unitName;
  final String movementType;
  final num quantity;
  final String? fromWarehouseName;
  final String? toWarehouseName;
  final String? note;
  final DateTime createdAt;

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    final product = Map<String, dynamic>.from(json['products'] as Map);
    final from = json['from_warehouse'] as Map?;
    final to = json['to_warehouse'] as Map?;
    return InventoryMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      productName: product['name'] as String,
      unitName: product['unit_name'] as String,
      movementType: json['movement_type'] as String,
      quantity: json['quantity'] as num,
      fromWarehouseName: from?['name'] as String?,
      toWarehouseName: to?['name'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.saleNumber,
    required this.customerName,
    required this.status,
    required this.grandTotal,
    required this.createdAt,
    required this.confirmedAt,
    required this.items,
    this.paidAmount = 0,
    this.balanceDue = 0,
  });

  final String id;
  final String saleNumber;
  final String? customerName;
  final String status;
  final num grandTotal;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final List<SaleItemRecord> items;
  final num paidAmount;
  final num balanceDue;

  factory SaleRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['sale_items'] as List? ?? const []);
    return SaleRecord(
      id: json['id'] as String,
      saleNumber: json['sale_number'] as String,
      customerName: json['customer_name'] as String?,
      status: json['status'] as String,
      grandTotal: json['grand_total'] as num,
      createdAt: DateTime.parse(json['created_at'] as String),
      confirmedAt: json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String),
      items: rawItems.map((item) => SaleItemRecord.fromJson(
        Map<String, dynamic>.from(item as Map),
      )).toList(growable: false),
      paidAmount: json['paid_amount'] as num? ?? 0,
      balanceDue: json['balance_due'] as num? ?? 0,
    );
  }
}

class SaleItemRecord {
  const SaleItemRecord({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.tax,
    required this.lineTotal,
  });

  final String productName;
  final num quantity;
  final num unitPrice;
  final num discount;
  final num tax;
  final num lineTotal;

  factory SaleItemRecord.fromJson(Map<String, dynamic> json) {
    return SaleItemRecord(
      productName: json['product_name_snapshot'] as String,
      quantity: json['quantity'] as num,
      unitPrice: json['unit_price'] as num,
      discount: json['discount_amount'] as num,
      tax: json['tax_amount'] as num,
      lineTotal: json['line_total'] as num,
    );
  }
}

class CustomerReceiptRecord {
  const CustomerReceiptRecord({
    required this.id,
    required this.saleNumber,
    required this.amount,
    required this.paymentMethod,
    required this.reference,
    required this.notes,
    required this.receivedAt,
  });

  final String id;
  final String saleNumber;
  final num amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
  final DateTime receivedAt;

  factory CustomerReceiptRecord.fromJson(Map<String, dynamic> json) {
    final rawSale = json['sale'];
    final sale = rawSale is Map ? Map<String, dynamic>.from(rawSale) : null;
    return CustomerReceiptRecord(
      id: json['id'] as String,
      saleNumber: sale?['sale_number'] as String? ?? 'فاکتور',
      amount: json['amount'] as num,
      paymentMethod: json['payment_method'] as String,
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      receivedAt: DateTime.parse(json['received_at'] as String),
    );
  }
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.email,
    required this.companyName,
    required this.address,
    required this.notes,
    required this.status,
    required this.purchaseCount,
    required this.totalPurchases,
    required this.totalReceived,
    required this.balanceDue,
  });

  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? email;
  final String? companyName;
  final String? address;
  final String? notes;
  final String status;
  final int purchaseCount;
  final num totalPurchases;
  final num totalReceived;
  final num balanceDue;

  factory CustomerRecord.fromJson(Map<String, dynamic> json) {
    return CustomerRecord(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      companyName: json['company_name'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String,
      purchaseCount: (json['purchase_count'] as num?)?.toInt() ?? 0,
      totalPurchases: json['total_purchases'] as num? ?? 0,
      totalReceived: json['total_received'] as num? ?? 0,
      balanceDue: json['balance_due'] as num? ?? 0,
    );
  }
}

abstract interface class InventoryRepository {
  Future<List<InventoryProduct>> fetchProducts(String businessId);

  Future<List<CustomerRecord>> fetchCustomers(
    String businessId, {
    bool includeArchived = false,
  });

  Future<List<SaleRecord>> fetchCustomerSales({
    required String businessId,
    required String customerId,
  });

  Future<List<CustomerReceiptRecord>> fetchCustomerReceipts({
    required String businessId,
    required String customerId,
  });

  Future<String> recordCustomerReceipt({
    required String saleId,
    required num amount,
    required String paymentMethod,
    String? reference,
    String? notes,
  });

  Future<void> updateCustomer({
    required String businessId,
    required String customerId,
    required String name,
    String? phone,
    String? email,
    String? companyName,
    String? address,
    String? notes,
  });

  Future<void> setCustomerStatus({
    required String businessId,
    required String customerId,
    required String status,
  });

  Future<String> createCustomer({
    required String businessId,
    required String name,
    String? phone,
    String? email,
    String? companyName,
    String? address,
    String? notes,
  });

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

  Future<List<SaleRecord>> fetchSales({
    required String businessId,
    required String branchId,
    String? status,
  });

  Future<String> createSaleDraft({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String saleNumber,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerId,
    String? notes,
  });

  Future<void> confirmSale(String saleId);

  Future<List<InventoryMovement>> fetchMovements({
    required String businessId,
    required String branchId,
    String? movementType,
  });

  Future<String> createMovement({
    required String businessId,
    required String productId,
    required String movementType,
    required num quantity,
    String? fromBranchId,
    String? fromWarehouseId,
    String? toBranchId,
    String? toWarehouseId,
    String? note,
  });
}

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CustomerRecord>> fetchCustomers(
    String businessId, {
    bool includeArchived = false,
  }) async {
    var customersQuery = _client.from('customers')
        .select('id,business_id,name,phone,email,company_name,address,notes,status')
        .eq('business_id', businessId);
    if (!includeArchived) customersQuery = customersQuery.eq('status', 'active');
    final result = await Future.wait<Object>([
      customersQuery.order('name').limit(500),
      _client.from('customer_purchase_summary')
          .select('customer_id,purchase_count,total_purchases,total_received,balance_due')
          .eq('business_id', businessId),
    ]);
    final summary = <String, Map<String, dynamic>>{
      for (final row in result[1] as List)
        row['customer_id'] as String: Map<String, dynamic>.from(row),
    };
    return (result[0] as List).map((row) {
      final customer = Map<String, dynamic>.from(row);
      final totals = summary[customer['id']] ?? const <String, dynamic>{};
      customer['purchase_count'] = totals['purchase_count'] ?? 0;
      customer['total_purchases'] = totals['total_purchases'] ?? 0;
      customer['total_received'] = totals['total_received'] ?? 0;
      customer['balance_due'] = totals['balance_due'] ?? 0;
      return CustomerRecord.fromJson(customer);
    }).toList(growable: false);
  }

  @override
  @override
  Future<List<SaleRecord>> fetchCustomerSales({
    required String businessId,
    required String customerId,
  }) async {
    const pageSize = 500;
    final rows = <dynamic>[];
    for (var offset = 0;; offset += pageSize) {
      final page = await _client.from('sales')
          .select(
            'id,sale_number,customer_name,status,grand_total,created_at,confirmed_at,'
            'sale_items!sale_items_sale_fkey(id,product_name_snapshot,quantity,'
            'unit_price,discount_amount,tax_amount,line_total)',
          )
          .eq('business_id', businessId)
          .eq('customer_id', customerId)
          .eq('status', 'confirmed')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }

    final saleIds = rows.map((row) => row['id'] as String).toList(growable: false);
    final balances = <String, Map<String, dynamic>>{};
    for (var offset = 0; offset < saleIds.length; offset += 500) {
      final ids = saleIds.skip(offset).take(500).toList(growable: false);
      final page = await _client.from('customer_invoice_balance_summary')
          .select('sale_id,total_received,balance_due')
          .eq('business_id', businessId)
          .eq('customer_id', customerId)
          .inFilter('sale_id', ids);
      for (final row in page) {
        balances[row['sale_id'] as String] = Map<String, dynamic>.from(row);
      }
    }

    return rows.map((row) {
      final sale = Map<String, dynamic>.from(row);
      final balance = balances[sale['id']] ?? const <String, dynamic>{};
      sale['paid_amount'] = balance['total_received'] ?? 0;
      sale['balance_due'] = balance['balance_due'] ?? sale['grand_total'];
      return SaleRecord.fromJson(sale);
    }).toList(growable: false);
  }

  @override
  Future<List<CustomerReceiptRecord>> fetchCustomerReceipts({
    required String businessId,
    required String customerId,
  }) async {
    const pageSize = 500;
    final rows = <dynamic>[];
    for (var offset = 0;; offset += pageSize) {
      final page = await _client.from('customer_receipts')
          .select(
            'id,amount,payment_method,reference,notes,received_at,'
            'sale:sales!customer_receipts_sale_customer_fkey(sale_number)',
          )
          .eq('business_id', businessId)
          .eq('customer_id', customerId)
          .order('received_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows.map((row) => CustomerReceiptRecord.fromJson(
      Map<String, dynamic>.from(row),
    )).toList(growable: false);
  }

  @override
  Future<String> recordCustomerReceipt({
    required String saleId,
    required num amount,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final result = await _client.rpc('record_customer_receipt', params: {
      'p_sale_id': saleId,
      'p_amount': amount,
      'p_payment_method': paymentMethod,
      'p_reference': _emptyToNull(reference),
      'p_notes': _emptyToNull(notes),
    });
    if (result is! String || result.isEmpty) {
      throw const FormatException('Unexpected receipt identifier.');
    }
    return result;
  }

  @override
  Future<void> updateCustomer({
    required String businessId,
    required String customerId,
    required String name,
    String? phone,
    String? email,
    String? companyName,
    String? address,
    String? notes,
  }) async {
    await _client.from('customers').update({
      'name': name.trim(),
      'phone': _emptyToNull(phone),
      'email': _emptyToNull(email),
      'company_name': _emptyToNull(companyName),
      'address': _emptyToNull(address),
      'notes': _emptyToNull(notes),
    }).eq('business_id', businessId).eq('id', customerId).select('id').single();
  }

  @override
  Future<void> setCustomerStatus({
    required String businessId,
    required String customerId,
    required String status,
  }) async {
    if (status != 'active' && status != 'archived') {
      throw ArgumentError.value(status, 'status');
    }
    await _client.from('customers').update({'status': status})
        .eq('business_id', businessId)
        .eq('id', customerId)
        .select('id').single();
  }

  @override
  Future<String> createCustomer({
    required String businessId,
    required String name,
    String? phone,
    String? email,
    String? companyName,
    String? address,
    String? notes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const FormatException('Authentication required.');
    }
    final row = await _client.from('customers').insert({
      'business_id': businessId,
      'created_by': userId,
      'name': name.trim(),
      'phone': _emptyToNull(phone),
      'email': _emptyToNull(email),
      'company_name': _emptyToNull(companyName),
      'address': _emptyToNull(address),
      'notes': _emptyToNull(notes),
    }).select('id').single();
    final id = row['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Unexpected customer identifier.');
    }
    return id;
  }

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

  @override
  Future<List<SaleRecord>> fetchSales({
    required String businessId,
    required String branchId,
    String? status,
  }) async {
    var query = _client
        .from('sales')
        .select(
          'id,sale_number,customer_name,status,grand_total,created_at,confirmed_at,'
          'sale_items!sale_items_sale_fkey(id,product_name_snapshot,quantity,'
          'unit_price,discount_amount,tax_amount,line_total)',
        )
        .eq('business_id', businessId)
        .eq('branch_id', branchId);
    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }
    final rows = await query.order('created_at', ascending: false).limit(200);
    return rows.map((row) => SaleRecord.fromJson(
      Map<String, dynamic>.from(row),
    )).toList(growable: false);
  }

  @override
  Future<String> createSaleDraft({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String saleNumber,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerId,
    String? notes,
  }) async {
    final result = await _client.rpc('create_sale_draft', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_warehouse_id': warehouseId,
      'p_sale_number': saleNumber,
      'p_customer_name': _emptyToNull(customerName),
      'p_customer_id': customerId,
      'p_notes': _emptyToNull(notes),
      'p_items': items,
    });
    if (result is! String || result.isEmpty) {
      throw const FormatException('Unexpected sale identifier.');
    }
    return result;
  }

  @override
  Future<void> confirmSale(String saleId) async {
    await _client.rpc('confirm_sale', params: {'p_sale_id': saleId});
  }

  @override
  Future<List<InventoryMovement>> fetchMovements({
    required String businessId,
    required String branchId,
    String? movementType,
  }) async {
    var query = _client
        .from('stock_movements')
        .select(
          'id,product_id,movement_type,quantity,note,created_at,'
          'products!stock_movements_product_fkey(name,unit_name),'
          'from_warehouse:warehouses!stock_movements_from_warehouse_fkey(name),'
          'to_warehouse:warehouses!stock_movements_to_warehouse_fkey(name)',
        )
        .eq('business_id', businessId)
        .or('from_branch_id.eq.$branchId,to_branch_id.eq.$branchId');

    if (movementType != null && movementType != 'all') {
      query = query.eq('movement_type', movementType);
    }

    final rows = await query.order('created_at', ascending: false).limit(200);
    return rows
        .map((row) => InventoryMovement.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  @override
  Future<String> createMovement({
    required String businessId,
    required String productId,
    required String movementType,
    required num quantity,
    String? fromBranchId,
    String? fromWarehouseId,
    String? toBranchId,
    String? toWarehouseId,
    String? note,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const FormatException('Authentication required.');
    }
    if (quantity <= 0) {
      throw const FormatException('Quantity must be positive.');
    }

    final row = await _client
        .from('stock_movements')
        .insert({
          'business_id': businessId,
          'product_id': productId,
          'movement_type': movementType,
          'quantity': quantity,
          'from_branch_id': fromBranchId,
          'from_warehouse_id': fromWarehouseId,
          'to_branch_id': toBranchId,
          'to_warehouse_id': toWarehouseId,
          'note': _emptyToNull(note),
          'created_by': userId,
        })
        .select('id')
        .single();

    final id = row['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Unexpected movement identifier.');
    }
    return id;
  }

  String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
