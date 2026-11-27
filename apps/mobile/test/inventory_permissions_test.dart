import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/src/inventory/inventory_permissions.dart';

void main() {
  test('read-only member cannot access write operations', () {
    final permissions = InventoryPermissions({
      'inventory.items.read',
      'inventory.stock.read',
      'crm.customers.read',
      'sales.invoices.read',
    });
    expect(permissions.canReadItems, isTrue);
    expect(permissions.canReadStock, isTrue);
    expect(permissions.canReadCustomers, isTrue);
    expect(permissions.canReadSales, isTrue);
    expect(permissions.canManageItems, isFalse);
    expect(permissions.canManageStock, isFalse);
    expect(permissions.canManageSales, isFalse);
    expect(permissions.canCreateCustomers, isFalse);
  });

  test('write permissions are independent per operation', () {
    final permissions = InventoryPermissions({
      'inventory.items.manage',
      'inventory.stock.manage',
      'sales.invoices.manage',
      'crm.customers.create',
    });
    expect(permissions.canManageItems, isTrue);
    expect(permissions.canManageStock, isTrue);
    expect(permissions.canManageSales, isTrue);
    expect(permissions.canCreateCustomers, isTrue);
    expect(permissions.canReadItems, isFalse);
    expect(permissions.canReadStock, isFalse);
    expect(permissions.canReadSales, isFalse);
  });

  test('permission set is copied and immutable', () {
    final source = <String>{'inventory.items.read'};
    final permissions = InventoryPermissions(source);
    source.clear();
    expect(permissions.canReadItems, isTrue);
    expect(() => permissions.values.add('inventory.items.manage'),
        throwsUnsupportedError);
  });
}
