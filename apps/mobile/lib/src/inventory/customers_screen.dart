import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inventory_repository.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.businessId,
    required this.repository,
  });

  final String businessId;
  final InventoryRepository repository;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  late Future<List<CustomerRecord>> _future;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  void _load() {
    _future = widget.repository.fetchCustomers(widget.businessId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _addCustomer() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF10233D),
      builder: (_) => _CustomerForm(repository: widget.repository, businessId: widget.businessId),
    );
    if (created == true && mounted) {
      setState(_load);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پرونده مشتری ثبت شد.')),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت مشتریان'),
        actions: [
          IconButton(onPressed: _refresh, tooltip: 'بروزرسانی', icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('مشتری جدید'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'جست‌وجوی نام، تلفن یا شرکت',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close)),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerRecord>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('دریافت مشتریان ناموفق بود. اتصال و مجوز customers.read را بررسی کن.'),
                    ),
                  );
                }
                final customers = (snapshot.data ?? const <CustomerRecord>[]).where((customer) {
                  return query.isEmpty ||
                      customer.name.toLowerCase().contains(query) ||
                      (customer.phone ?? '').toLowerCase().contains(query) ||
                      (customer.companyName ?? '').toLowerCase().contains(query);
                }).toList(growable: false);
                if (customers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 52, color: Color(0xFF00D8E8)),
                          const SizedBox(height: 14),
                          Text(query.isEmpty ? 'هنوز مشتری ثبت نشده' : 'مشتری‌ای پیدا نشد',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text('پرونده مشتریان این کسب‌وکار از این بخش مدیریت می‌شود.',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x1F00D8E8),
                            child: Icon(Icons.person_outline, color: Color(0xFF00D8E8)),
                          ),
                          title: Text(customer.name),
                          subtitle: Text([
                            if (customer.phone?.isNotEmpty == true) customer.phone!,
                            if (customer.companyName?.isNotEmpty == true) customer.companyName!,
                          ].join(' • ').isEmpty ? 'بدون اطلاعات تماس' : [
                            if (customer.phone?.isNotEmpty == true) customer.phone!,
                            if (customer.companyName?.isNotEmpty == true) customer.companyName!,
                          ].join(' • ')),
                          children: [
                            const Divider(height: 1),
                            _CustomerDetail(label: 'ایمیل', value: customer.email),
                            _CustomerDetail(label: 'نشانی', value: customer.address),
                            _CustomerDetail(label: 'یادداشت', value: customer.notes),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Row(
                                children: [
                                  Expanded(child: _Metric(label: 'خریدهای تأییدشده', value: customer.purchaseCount.toString())),
                                  const SizedBox(width: 12),
                                  Expanded(child: _Metric(label: 'مجموع خرید', value: '${_money(customer.totalPurchases)} تومان')),
                                ],
                              ),
                            ),
                            FutureBuilder<List<SaleRecord>>(
                              future: widget.repository.fetchCustomerSales(
                                businessId: widget.businessId,
                                customerId: customer.id,
                              ),
                              builder: (context, history) {
                                if (history.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                if (history.hasError) {
                                  return const ListTile(
                                    dense: true,
                                    title: Text('سابقه خرید در دسترس نیست'),
                                  );
                                }
                                final purchases = history.data ?? const <SaleRecord>[];
                                if (purchases.isEmpty) {
                                  return const ListTile(
                                    dense: true,
                                    title: Text('هنوز خرید تأییدشده‌ای ثبت نشده است.'),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                      child: Text('سوابق خرید', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    ...purchases.map((sale) => ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.receipt_long_outlined),
                                      title: Text(sale.saleNumber),
                                      subtitle: Text('${sale.items.length} قلم • ${_date(sale.createdAt)}'),
                                      trailing: Text('${_money(sale.grandTotal)} تومان'),
                                    )),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return ListTile(dense: true, title: Text(label), subtitle: Text(value!));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({required this.repository, required this.businessId});
  final InventoryRepository repository;
  final String businessId;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _company.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.createCustomer(
        businessId: widget.businessId,
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        companyName: _company.text,
        address: _address.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '42501'
          ? 'برای ایجاد پرونده مشتری مجوز کافی نداری.'
          : 'ثبت مشتری انجام نشد. اطلاعات و دسترسی را بررسی کن.';
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

  String? _validateName(String? value) =>
      value == null || value.trim().length < 2 ? 'نام باید حداقل دو نویسه باشد.' : null;

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'ایمیل معتبر وارد کن.';
    }
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
              Text('پرونده مشتری جدید', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'نام مشتری *'), validator: _validateName, textInputAction: TextInputAction.next),
              const SizedBox(height: 10),
              TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'شماره تماس'), keyboardType: TextInputType.phone, textInputAction: TextInputAction.next),
              const SizedBox(height: 10),
              TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'ایمیل'), keyboardType: TextInputType.emailAddress, validator: _validateEmail, textInputAction: TextInputAction.next),
              const SizedBox(height: 10),
              TextFormField(controller: _company, decoration: const InputDecoration(labelText: 'نام شرکت (اختیاری)'), textInputAction: TextInputAction.next),
              const SizedBox(height: 10),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'نشانی'), minLines: 1, maxLines: 2),
              const SizedBox(height: 10),
              TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'یادداشت داخلی'), minLines: 2, maxLines: 3),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ذخیره پرونده مشتری'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

String _money(num value) => value.toStringAsFixed(0).replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (match) => ',',
);
