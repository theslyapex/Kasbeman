import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';
import 'inventory_repository.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({
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
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late Future<({
    List<InventoryProduct> products,
    List<InventoryWarehouse> warehouses,
    List<CustomerRecord> customers,
  })> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.permissions.containsAll(const [
          'sales.invoices.manage',
          'inventory.items.read',
          'inventory.stock.read',
        ])
        ? _load()
        : Future.value((
            products: <InventoryProduct>[],
            warehouses: <InventoryWarehouse>[],
            customers: <CustomerRecord>[],
          ));
  }

  Future<({
    List<InventoryProduct> products,
    List<InventoryWarehouse> warehouses,
    List<CustomerRecord> customers,
  })> _load() async {
    final result = await Future.wait<Object>([
      widget.repository.fetchProducts(widget.membership.businessId),
      widget.repository.fetchWarehouses(
        businessId: widget.membership.businessId,
        branchId: widget.branch.id,
      ),
      widget.permissions.contains('crm.customers.read')
          ? widget.repository.fetchCustomers(widget.membership.businessId)
          : Future.value(const <CustomerRecord>[]),
    ]);
    return (
      products: result[0] as List<InventoryProduct>,
      warehouses: result[1] as List<InventoryWarehouse>,
      customers: result[2] as List<CustomerRecord>,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.permissions.containsAll(const [
          'sales.invoices.manage',
          'inventory.items.read',
          'inventory.stock.read',
        ])) {
      return const Scaffold(
        body: Center(child: Text('برای ثبت فروش مجوز کافی نداری.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت فروش')),
      body: FutureBuilder<({
        List<InventoryProduct> products,
        List<InventoryWarehouse> warehouses,
        List<CustomerRecord> customers,
      })>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('دریافت کالاها و انبارها ناموفق بود.'));
          }
          final products = snapshot.data!.products.where((p) => p.status == 'active').toList();
          final warehouses = snapshot.data!.warehouses;
          if (products.isEmpty || warehouses.isEmpty) {
            return Center(
              child: Text(products.isEmpty
                  ? 'ابتدا کالا یا خدمت فعال ثبت کن.'
                  : 'برای این شعبه انبار فعال وجود ندارد.'),
            );
          }
          return _SaleForm(
            key: ValueKey(widget.branch.id),
            membership: widget.membership,
            branch: widget.branch,
            repository: widget.repository,
            products: products,
            warehouses: warehouses,
            customers: snapshot.data!.customers,
          );
        },
      ),
    );
  }
}

class _SaleLine {
  const _SaleLine({
    required this.product,
    required this.quantity,
    required this.discount,
    required this.tax,
  });

  final InventoryProduct product;
  final num quantity;
  final num discount;
  final num tax;

  num get total => (quantity * product.salePrice) - discount + tax;
}

class _SaleForm extends StatefulWidget {
  const _SaleForm({
    super.key,
    required this.membership,
    required this.branch,
    required this.repository,
    required this.products,
    required this.warehouses,
    required this.customers,
  });

  final BusinessMembership membership;
  final BusinessBranch branch;
  final InventoryRepository repository;
  final List<InventoryProduct> products;
  final List<InventoryWarehouse> warehouses;
  final List<CustomerRecord> customers;

  @override
  State<_SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<_SaleForm> {
  final _customer = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;
  final _quantity = TextEditingController(text: '1');
  final _discount = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final List<_SaleLine> _lines = [];
  late String _productId;
  late String _warehouseId;
  String? _draftId;
  bool _saving = false;

  num? _number(String value) => num.tryParse(value.trim().replaceAll(',', ''));

  @override
  void initState() {
    super.initState();
    _productId = widget.products.first.id;
    _warehouseId = widget.warehouses.first.id;
  }

  @override
  void dispose() {
    _customer.dispose();
    _notes.dispose();
    _quantity.dispose();
    _discount.dispose();
    _tax.dispose();
    super.dispose();
  }

  num get _subtotal => _lines.fold<num>(0, (sum, line) => sum + line.quantity * line.product.salePrice);
  num get _discountTotal => _lines.fold<num>(0, (sum, line) => sum + line.discount);
  num get _taxTotal => _lines.fold<num>(0, (sum, line) => sum + line.tax);
  num get _grandTotal => _lines.fold<num>(0, (sum, line) => sum + line.total);

  void _addLine() {
    final quantity = _number(_quantity.text);
    final discount = _number(_discount.text);
    final tax = _number(_tax.text);
    final product = widget.products.firstWhere((p) => p.id == _productId);
    if (quantity == null || quantity <= 0 || discount == null || tax == null ||
        discount < 0 || tax < 0 || discount > quantity * product.salePrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعداد، تخفیف یا مالیات معتبر نیست.')),
      );
      return;
    }
    setState(() {
      _lines.add(_SaleLine(
        product: product,
        quantity: quantity,
        discount: discount,
        tax: tax,
      ));
      _quantity.text = '1';
      _discount.text = '0';
      _tax.text = '0';
    });
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حداقل یک قلم به فروش اضافه کن.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      _draftId ??= await widget.repository.createSaleDraft(
        businessId: widget.membership.businessId,
        branchId: widget.branch.id,
        warehouseId: _warehouseId,
        saleNumber: 'KM-${DateTime.now().millisecondsSinceEpoch}',
        customerName: _customer.text,
        customerId: _customerId,
        notes: _notes.text,
        items: _lines.map((line) => {
          'product_id': line.product.id,
          'quantity': line.quantity,
          'discount_amount': line.discount,
          'tax_amount': line.tax,
        }).toList(growable: false),
      );
      await widget.repository.confirmSale(_draftId!);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23514'
          ? 'موجودی کافی نیست یا مبالغ فروش با اقلام تطبیق ندارد.'
          : error.code == '42501'
              ? 'برای ثبت فروش یا مدیریت موجودی مجوز کافی وجود ندارد.'
              : 'ثبت فروش انجام نشد. وضعیت کالا، انبار و اطلاعات را بررسی کن.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('شعبه: ${widget.branch.name}'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _customerId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'انتخاب مشتری ثبت‌شده'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('مشتری گذری / بدون پرونده'),
            ),
            ...widget.customers.map((customer) => DropdownMenuItem<String?>(
              value: customer.id,
              child: Text(
                customer.phone == null || customer.phone!.isEmpty
                    ? customer.name
                    : '${customer.name} • ${customer.phone}',
                overflow: TextOverflow.ellipsis,
              ),
            )),
          ],
          onChanged: _saving || _draftId != null
              ? null
              : (value) => setState(() {
                    _customerId = value;
                    if (value != null) {
                      _customer.text = widget.customers
                          .firstWhere((item) => item.id == value).name;
                    } else {
                      _customer.clear();
                    }
                  }),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _customer,
          enabled: !_saving && _draftId == null && _customerId == null,
          decoration: const InputDecoration(
            labelText: 'نام مشتری گذری (اختیاری)',
            helperText: 'برای سوابق خرید، مشتری را از فهرست بالا انتخاب کن.',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _warehouseId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'انبار خروج کالا'),
          items: widget.warehouses.map((w) => DropdownMenuItem(
            value: w.id, child: Text(w.name),
          )).toList(),
          onChanged: _saving || _draftId != null ? null : (v) => setState(() => _warehouseId = v ?? _warehouseId),
        ),
        const SizedBox(height: 18),
        Text('افزودن قلم', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _productId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'کالا یا خدمت'),
          items: widget.products.map((p) => DropdownMenuItem(
            value: p.id,
            child: Text('${p.name} • ${p.salePrice} تومان'),
          )).toList(),
          onChanged: _saving || _draftId != null ? null : (v) => setState(() => _productId = v ?? _productId),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: TextField(controller: _quantity, enabled: !_saving && _draftId == null, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تعداد'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _discount, enabled: !_saving && _draftId == null, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تخفیف (تومان)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _tax, enabled: !_saving && _draftId == null, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مالیات (تومان)'))),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _saving || _draftId != null ? null : _addLine,
          icon: const Icon(Icons.add),
          label: const Text('افزودن به فاکتور'),
        ),
        const SizedBox(height: 12),
        ..._lines.asMap().entries.map((entry) {
          final line = entry.value;
          return Card(
            child: ListTile(
              title: Text(line.product.name),
              subtitle: Text('${line.quantity} ${line.product.unitName} × ${line.product.salePrice}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${line.total.toStringAsFixed(0)} تومان'),
                  if (_draftId == null)
                    IconButton(
                      tooltip: 'حذف',
                      onPressed: _saving ? null : () => setState(() => _lines.removeAt(entry.key)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          enabled: !_saving && _draftId == null,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TotalRow(label: 'جمع جزء', value: _subtotal),
                _TotalRow(label: 'تخفیف', value: _discountTotal),
                _TotalRow(label: 'مالیات', value: _taxTotal),
                const Divider(),
                _TotalRow(label: 'مبلغ نهایی', value: _grandTotal, bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(_draftId == null ? 'ثبت و تأیید فروش' : 'تلاش دوباره برای تأیید فروش'),
        ),
        if (_draftId != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'پیش‌نویس فروش ذخیره شده است؛ تأیید ناموفق بود. با تلاش دوباره فقط مرحله تأیید تکرار می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});
  final String label;
  final num value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 17 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${value.toStringAsFixed(0)} تومان', style: style),
        ],
      ),
    );
  }
}
