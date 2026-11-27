import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_repository.dart';
import 'inventory_repository.dart';
import 'inventory_movement_screen.dart';
import 'inventory_history_screen.dart';
import 'sales_screen.dart';
import 'sales_history_screen.dart';
import 'customers_screen.dart';
import 'inventory_permissions.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.membership,
    required this.branch,
    required this.permissions,
    this.repository,
  });

  final BusinessMembership membership;
  final BusinessBranch branch;
  final Set<String> permissions;
  final InventoryRepository? repository;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final InventoryRepository _repository;
  late final InventoryPermissions _permissions;
  late Future<List<InventoryProduct>> _productsFuture;
  late Future<List<InventoryBalance>> _balancesFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _repository = widget.repository ??
        SupabaseInventoryRepository(Supabase.instance.client);
    _permissions = InventoryPermissions(widget.permissions);
    _reload();
  }

  void _reload() {
    _productsFuture =
        _repository.fetchProducts(widget.membership.businessId);
    _balancesFuture = _repository.fetchBalances(
      businessId: widget.membership.businessId,
      branchId: widget.branch.id,
    );
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InventoryHistoryScreen(
          membership: widget.membership,
          branch: widget.branch,
          repository: _repository,
        ),
      ),
    );
  }

  Future<void> _openMovements() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InventoryMovementScreen(
          membership: widget.membership,
          branch: widget.branch,
          repository: _repository,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('گردش موجودی ثبت شد.')),
      );
    }
  }

  Future<void> _openCustomers() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CustomersScreen(
          businessId: widget.membership.businessId,
          repository: _repository,
          permissions: widget.permissions,
        ),
      ),
    );
  }

  Future<void> _openSalesHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SalesHistoryScreen(
          membership: widget.membership,
          branch: widget.branch,
          repository: _repository,
        ),
      ),
    );
  }

  Future<void> _openSales() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SalesScreen(
          membership: widget.membership,
          branch: widget.branch,
          repository: _repository,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فروش با موفقیت تأیید شد.')),
      );
    }
  }

  Future<void> _addProduct() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF10233D),
      builder: (_) => _ProductForm(
        repository: _repository,
        businessId: widget.membership.businessId,
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کالا با موفقیت ثبت شد.')),
      );
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کالا و انبار'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'کالاها'),
            Tab(icon: Icon(Icons.warehouse_outlined), text: 'موجودی شعبه'),
          ],
        ),
        actions: [
          if (_permissions.canReadCustomers)
            IconButton(
              tooltip: 'مدیریت مشتریان',
              onPressed: _openCustomers,
              icon: const Icon(Icons.people_alt_outlined),
            ),
          if (_permissions.canReadSales)
            IconButton(
              tooltip: 'فهرست فروش‌ها',
              onPressed: _openSalesHistory,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
          if (_permissions.canManageSales)
            IconButton(
              tooltip: 'ثبت فروش',
              onPressed: _openSales,
              icon: const Icon(Icons.point_of_sale_outlined),
            ),
          if (_permissions.canReadStock)
            IconButton(
              tooltip: 'تاریخچه گردش',
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
            ),
          if (_permissions.canManageStock)
            IconButton(
              tooltip: 'ثبت گردش موجودی',
              onPressed: _openMovements,
              icon: const Icon(Icons.swap_horiz),
            ),
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => _tabs.index == 0 && _permissions.canManageItems
            ? FloatingActionButton.extended(
                onPressed: _addProduct,
                icon: const Icon(Icons.add),
                label: const Text('ثبت کالا'),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ProductsTab(future: _productsFuture),
          _BalancesTab(
            future: _balancesFuture,
            branchName: widget.branch.name,
          ),
        ],
      ),
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.future});

  final Future<List<InventoryProduct>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryProduct>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _InventoryMessage(
            title: 'دریافت کالاها ناموفق بود',
            description: 'اتصال یا سطح دسترسی را بررسی و دوباره تلاش کن.',
            icon: Icons.cloud_off_outlined,
          );
        }
        final products = snapshot.data ?? const [];
        if (products.isEmpty) {
          return const _InventoryMessage(
            title: 'هنوز کالایی ثبت نشده',
            description: 'با دکمه «ثبت کالا» اولین قلم کالا یا خدمت را اضافه کن.',
            icon: Icons.inventory_2_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final product = products[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF00D8E8).withValues(alpha: .12),
                  child: Icon(
                    product.isGoods
                        ? Icons.inventory_2_outlined
                        : Icons.design_services_outlined,
                    color: const Color(0xFF00D8E8),
                  ),
                ),
                title: Text(product.name),
                subtitle: Text([
                  if (product.sku != null) 'شناسه: ${product.sku}',
                  product.isGoods ? 'کالا' : 'خدمت',
                  'واحد: ${product.unitName}',
                ].join(' • ')),
                trailing: Text(
                  '${_money(product.salePrice)} تومان',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _BalancesTab extends StatelessWidget {
  const _BalancesTab({
    required this.future,
    required this.branchName,
  });

  final Future<List<InventoryBalance>> future;
  final String branchName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryBalance>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _InventoryMessage(
            title: 'دریافت موجودی ناموفق بود',
            description: 'اتصال یا سطح دسترسی را بررسی و دوباره تلاش کن.',
            icon: Icons.cloud_off_outlined,
          );
        }
        final balances = snapshot.data ?? const [];
        if (balances.isEmpty) {
          return _InventoryMessage(
            title: 'موجودی ثبت‌شده‌ای وجود ندارد',
            description: 'موجودی کالاها در شعبه «$branchName» پس از ثبت ورود کالا نمایش داده می‌شود.',
            icon: Icons.warehouse_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: balances.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final balance = balances[index];
            return Card(
              child: ListTile(
                leading: const Icon(
                  Icons.stacked_bar_chart,
                  color: Color(0xFF00D8E8),
                ),
                title: Text(balance.productName),
                subtitle: Text('انبار: ${balance.warehouseName} • واحد: ${balance.unitName}'),
                trailing: Text(
                  '${_quantity(balance.quantity)} ${balance.unitName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({
    required this.repository,
    required this.businessId,
  });

  final InventoryRepository repository;
  final String businessId;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _unit = TextEditingController(text: 'عدد');
  final _salePrice = TextEditingController(text: '0');
  final _purchasePrice = TextEditingController(text: '0');
  String _type = 'goods';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _unit.dispose();
    _salePrice.dispose();
    _purchasePrice.dispose();
    super.dispose();
  }

  num? _parsePrice(String value) {
    final normalized = value.replaceAll(',', '').trim();
    return num.tryParse(normalized);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final salePrice = _parsePrice(_salePrice.text)!;
    final purchasePrice = _parsePrice(_purchasePrice.text)!;
    setState(() => _saving = true);
    try {
      await widget.repository.createProduct(
        businessId: widget.businessId,
        name: _name.text,
        sku: _sku.text,
        barcode: _barcode.text,
        productType: _type,
        unitName: _unit.text,
        salePrice: salePrice,
        purchasePrice: purchasePrice,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23505'
          ? 'شناسه کالا یا بارکد تکراری است.'
          : 'ثبت کالا انجام نشد. دسترسی‌ها و اطلاعات را بررسی کن.';
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

  String? _required(String? value) {
    if (value == null || value.trim().length < 2) {
      return 'حداقل دو نویسه وارد کن.';
    }
    return null;
  }

  String? _priceValidator(String? value) {
    final parsed = value == null ? null : _parsePrice(value);
    if (parsed == null || parsed < 0) return 'مبلغ معتبر و غیرمنفی وارد کن.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ثبت قلم جدید', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'نام کالا یا خدمت'),
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع قلم'),
                items: const [
                  DropdownMenuItem(value: 'goods', child: Text('کالا (دارای موجودی)')),
                  DropdownMenuItem(value: 'service', child: Text('خدمت (بدون موجودی)')),
                ],
                onChanged: _saving ? null : (value) => setState(() => _type = value ?? 'goods'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sku,
                decoration: const InputDecoration(labelText: 'شناسه کالا (اختیاری)'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'بارکد (اختیاری)'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'واحد اندازه‌گیری'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _salePrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'قیمت فروش (تومان)'),
                validator: _priceValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purchasePrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'قیمت خرید (تومان)'),
                validator: _priceValidator,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ثبت کالا'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryMessage extends StatelessWidget {
  const _InventoryMessage({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: const Color(0xFF00D8E8)),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.8)),
          ],
        ),
      ),
    );
  }
}

String _money(num value) =>
    value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );

String _quantity(num value) => value.toString();
