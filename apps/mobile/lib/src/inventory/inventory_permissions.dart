class InventoryPermissions {
  InventoryPermissions(Set<String> permissions)
      : _permissions = Set<String>.unmodifiable(permissions);

  final Set<String> _permissions;

  Set<String> get values => _permissions;
  bool get canReadItems => _permissions.contains('inventory.items.read');
  bool get canManageItems => _permissions.contains('inventory.items.manage');
  bool get canReadStock => _permissions.contains('inventory.stock.read');
  bool get canManageStock => _permissions.contains('inventory.stock.manage');
  bool get canReadCustomers => _permissions.contains('crm.customers.read');
  bool get canCreateCustomers => _permissions.contains('crm.customers.create');
  bool get canReadSales => _permissions.contains('sales.invoices.read');
  bool get canManageSales => _permissions.contains('sales.invoices.manage');
}
