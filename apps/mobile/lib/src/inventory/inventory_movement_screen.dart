import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';
import 'inventory_repository.dart';

class InventoryMovementScreen extends StatefulWidget {
  const InventoryMovementScreen({
    super.key,
    required this.membership,
    required this.branch,
    required this.repository,
    required this.permissions,
  });

  final Set<String> permissions;
  final BusinessMembership membership;
  final BusinessBranch branch;
  final InventoryRepository repository;

  @override
  State<InventoryMovementScreen> createState() =>
      _InventoryMovementScreenState();
}

class _InventoryMovementScreenState extends State<InventoryMovementScreen> {
  late Future<({List<InventoryProduct> products, List<InventoryWarehouse> warehouses})>
      _data;

  @override
  void initState() {
    super.initState();
    _data = widget.permissions.contains('inventory.stock.manage')
        ? _load()
        : Future.value((
            products: <InventoryProduct>[],
            warehouses: <InventoryWarehouse>[],
          ));
  }

  Future<({List<InventoryProduct> products, List<InventoryWarehouse> warehouses})>
      _load() async {
    final results = await Future.wait<Object>([
      widget.repository.fetchProducts(widget.membership.businessId),
      widget.repository.fetchWarehouses(
        businessId: widget.membership.businessId,
        branchId: widget.branch.id,
      ),
    ]);
    return (
      products: results[0] as List<InventoryProduct>,
      warehouses: results[1] as List<InventoryWarehouse>,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.permissions.contains('inventory.stock.manage')) {
      return const Scaffold(
        body: Center(child: Text('برای مدیریت موجودی مجوز کافی نداری.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('گردش موجودی')),
      body: FutureBuilder<
          ({List<InventoryProduct> products, List<InventoryWarehouse> warehouses})>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'اطلاعات کالاها و انبارها دریافت نشد. اتصال و سطح دسترسی را بررسی کن.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final products = data.products.where((p) => p.isGoods && p.status == 'active').toList();
          final warehouses = data.warehouses;
          if (products.isEmpty || warehouses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  products.isEmpty
                      ? 'برای ثبت گردش، ابتدا یک کالای فعال ثبت کن.'
                      : 'برای این شعبه انبار فعالی وجود ندارد.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _MovementForm(
            key: ValueKey('${widget.branch.id}-${products.length}-${warehouses.length}'),
            repository: widget.repository,
            businessId: widget.membership.businessId,
            branch: widget.branch,
            products: products,
            warehouses: warehouses,
          );
        },
      ),
    );
  }
}

class _MovementForm extends StatefulWidget {
  const _MovementForm({
    super.key,
    required this.repository,
    required this.businessId,
    required this.branch,
    required this.products,
    required this.warehouses,
  });

  final InventoryRepository repository;
  final String businessId;
  final BusinessBranch branch;
  final List<InventoryProduct> products;
  final List<InventoryWarehouse> warehouses;

  @override
  State<_MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends State<_MovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  late String _productId;
  late String _fromWarehouseId;
  late String _toWarehouseId;
  String _type = 'in';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.products.first.id;
    _fromWarehouseId = widget.warehouses.first.id;
    _toWarehouseId = widget.warehouses.length > 1
        ? widget.warehouses[1].id
        : widget.warehouses.first.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  num? _parseQuantity(String value) =>
      num.tryParse(value.trim().replaceAll(',', ''));

  String? _validateQuantity(String? value) {
    final quantity = value == null ? null : _parseQuantity(value);
    if (quantity == null || quantity <= 0) {
      return 'مقدار باید عددی بزرگ‌تر از صفر باشد.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'transfer' && _fromWarehouseId == _toWarehouseId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انبار مبدأ و مقصد باید متفاوت باشند.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.createMovement(
        businessId: widget.businessId,
        productId: _productId,
        movementType: _type,
        quantity: _parseQuantity(_quantity.text)!,
        fromBranchId: _type == 'in' ? null : widget.branch.id,
        fromWarehouseId: _type == 'in' ? null : _fromWarehouseId,
        toBranchId: _type == 'out' ? null : widget.branch.id,
        toWarehouseId: _type == 'out' ? null : _toWarehouseId,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23514'
          ? 'موجودی کافی نیست یا مقدار با محدودیت‌های انبار سازگار نیست.'
          : error.code == '42501'
              ? 'برای ثبت این گردش، دسترسی مدیریت موجودی لازم است.'
              : 'ثبت گردش انجام نشد. اطلاعات و وضعیت انبار را بررسی کن.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارتباط با سرور برقرار نشد.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFrom = _type != 'in';
    final showTo = _type != 'out';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.warehouse_outlined, color: Color(0xFF00D8E8)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'شعبه: ${widget.branch.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع گردش'),
                items: const [
                  DropdownMenuItem(value: 'in', child: Text('ورود به انبار')),
                  DropdownMenuItem(value: 'out', child: Text('خروج از انبار')),
                  DropdownMenuItem(value: 'transfer', child: Text('انتقال بین انبارها')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _type = value ?? 'in'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'کالا'),
                items: widget.products
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.name}  •  ${p.unitName}'),
                        ))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _productId = value ?? _productId),
              ),
              if (showFrom) ...[
                const SizedBox(height: 14),
                _warehouseDropdown(
                  label: 'انبار مبدأ',
                  value: _fromWarehouseId,
                  onChanged: (value) => setState(() => _fromWarehouseId = value!),
                ),
              ],
              if (showTo) ...[
                const SizedBox(height: 14),
                _warehouseDropdown(
                  label: 'انبار مقصد',
                  value: _toWarehouseId,
                  onChanged: (value) => setState(() => _toWarehouseId = value!),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _quantity,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'مقدار',
                  hintText: 'مثلاً 12 یا 2.5',
                ),
                validator: _validateQuantity,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                enabled: !_saving,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'توضیحات (اختیاری)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'در حال ثبت...' : 'ثبت گردش موجودی'),
              ),
              const SizedBox(height: 10),
              const Text(
                'موجودی فقط پس از تأیید سرور تغییر می‌کند. خروج یا انتقال بیش از موجودی قابل ثبت نیست.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _warehouseDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: widget.warehouses
          .map((warehouse) => DropdownMenuItem(
                value: warehouse.id,
                child: Text(warehouse.name),
              ))
          .toList(),
      onChanged: _saving ? null : onChanged,
    );
  }
}
