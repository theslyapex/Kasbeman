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
  final Map<String, Future<List<_CustomerLedgerEntry>>> _ledgerHistory = {};
  final Set<String> _expandedCustomers = {};
  bool _showArchived = false;
  late Future<List<CustomerRecord>> _future;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  void _load() {
    _future = widget.repository.fetchCustomers(
      widget.businessId,
      includeArchived: _showArchived,
    );
  }

  Future<List<_CustomerLedgerEntry>> _ledgerFor(String customerId) {
    return _ledgerHistory.putIfAbsent(customerId, () async {
      final results = await Future.wait<Object>([
        widget.repository.fetchCustomerSales(
          businessId: widget.businessId,
          customerId: customerId,
        ),
        widget.repository.fetchCustomerReceipts(
          businessId: widget.businessId,
          customerId: customerId,
        ),
      ]);
      final sales = results[0] as List<SaleRecord>;
      final receipts = results[1] as List<CustomerReceiptRecord>;
      final entries = <_CustomerLedgerEntry>[
        for (final sale in sales)
          _CustomerLedgerEntry(
            date: sale.createdAt,
            amount: sale.grandTotal,
            title: 'فاکتور ${sale.saleNumber}',
            subtitle: '${sale.items.length} قلم کالا و خدمت • مانده ${_money(sale.balanceDue)} تومان',
            isReceipt: false,
          ),
        for (final receipt in receipts)
          _CustomerLedgerEntry(
            date: receipt.receivedAt,
            amount: receipt.amount,
            title: 'دریافت از فاکتور ${receipt.saleNumber}',
            subtitle: '${_paymentMethodLabel(receipt.paymentMethod)}'
                '${receipt.reference == null ? '' : ' • ${receipt.reference}'}',
            isReceipt: true,
          ),
      ];
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    });
  }

  Future<void> _refresh() async {
    _ledgerHistory.clear();
    
    setState(_load);
    await _future;
  }

  Future<void> _editCustomer(CustomerRecord customer) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF10233D),
      builder: (_) => _CustomerForm(
        repository: widget.repository,
        businessId: widget.businessId,
        customer: customer,
      ),
    );
    if (saved == true && mounted) {
      _ledgerHistory.remove(customer.id);
      
      setState(_load);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پرونده مشتری به‌روزرسانی شد.')),
      );
    }
  }

  Future<void> _changeCustomerStatus(CustomerRecord customer) async {
    final archive = customer.status == 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archive ? 'بایگانی مشتری' : 'بازگردانی مشتری'),
        content: Text(
          archive
              ? 'پرونده «${customer.name}» بایگانی می‌شود. سوابق فاکتورها و دریافت‌ها حفظ خواهند شد.'
              : 'پرونده «${customer.name}» دوباره فعال می‌شود و در فاکتورهای جدید قابل انتخاب خواهد بود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archive ? 'بایگانی' : 'فعال‌سازی'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.setCustomerStatus(
        businessId: widget.businessId,
        customerId: customer.id,
        status: archive ? 'archived' : 'active',
      );
      if (!mounted) return;
      _ledgerHistory.remove(customer.id);
      
      setState(_load);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archive ? 'مشتری بایگانی شد.' : 'مشتری فعال شد.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.code == '42501'
            ? 'مجوز مدیریت پرونده مشتری را نداری.'
            : 'تغییر وضعیت مشتری انجام نشد.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارتباط با سرور برقرار نشد.')),
      );
    }
  }

  Future<void> _recordReceipt(CustomerRecord customer) async {
    try {
      final invoices = await widget.repository.fetchCustomerSales(
        businessId: widget.businessId,
        customerId: customer.id,
      );
      if (!mounted) return;
      final unpaid = invoices.where((sale) => sale.balanceDue > 0).toList();
      if (unpaid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برای این مشتری فاکتور تأییدشده با مانده باز وجود ندارد.')),
        );
        return;
      }
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF10233D),
        builder: (_) => _CustomerReceiptForm(
          repository: widget.repository,
          customer: customer,
          invoices: unpaid,
        ),
      );
      if (saved == true && mounted) {
        _ledgerHistory.remove(customer.id);
        
        setState(_load);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دریافت وجه ثبت شد.')),
        );
      }
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.code == '42501'
            ? 'مجوز مشاهده فاکتورهای این مشتری را نداری.'
            : 'دریافت فاکتورها ناموفق بود.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارتباط با سرور برقرار نشد.')),
      );
    }
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
          IconButton(
            onPressed: () => setState(() {
              _showArchived = !_showArchived;
              _load();
            }),
            tooltip: _showArchived ? 'نمایش مشتریان فعال' : 'نمایش مشتریان بایگانی‌شده',
            icon: Icon(_showArchived ? Icons.person_search_outlined : Icons.inventory_2_outlined),
          ),
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF173B5B), Color(0xFF10233D), Color(0xFF0B1B30)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x3300D8E8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0x2200D8E8),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.groups_2_outlined, color: Color(0xFF00D8E8), size: 27),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showArchived ? 'آرشیو مشتریان' : 'ارتباط با مشتریان',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _showArchived
                              ? 'پرونده‌های بایگانی‌شده و سوابق آن‌ها'
                              : 'پرونده‌ها، فاکتورها و دریافت‌های هر مشتری در یک نگاه',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                      final contact = [
                        if (customer.phone?.isNotEmpty == true) customer.phone!,
                        if (customer.companyName?.isNotEmpty == true) customer.companyName!,
                      ].join(' • ');
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x1F00D8E8),
                            child: Icon(Icons.person_outline, color: Color(0xFF00D8E8)),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              if (customer.status == 'archived') ...[
                                const SizedBox(width: 8),
                                const Chip(
                                  label: Text('بایگانی'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Color(0x332D9CDB),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(contact.isEmpty ? 'بدون اطلاعات تماس' : contact),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedCustomers.add(customer.id);
                              } else {
                                _expandedCustomers.remove(customer.id);
                              }
                            });
                          },
                          children: [
                            const Divider(height: 1),
                            _CustomerDetail(label: 'ایمیل', value: customer.email),
                            _CustomerDetail(label: 'نشانی', value: customer.address),
                            _CustomerDetail(label: 'یادداشت', value: customer.notes),
                            if (!_expandedCustomers.contains(customer.id))
                              const SizedBox.shrink()
                            else ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _Metric(
                                            label: 'فاکتورهای تأییدشده',
                                            value: customer.purchaseCount.toString(),
                                            icon: Icons.receipt_long_outlined,
                                            accent: const Color(0xFF00D8E8),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _Metric(
                                            label: 'مجموع خرید',
                                            value: '${_money(customer.totalPurchases)} تومان',
                                            icon: Icons.trending_up_rounded,
                                            accent: const Color(0xFF6FA8FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _Metric(
                                            label: 'دریافت‌شده',
                                            value: '${_money(customer.totalReceived)} تومان',
                                            icon: Icons.south_west_rounded,
                                            accent: const Color(0xFF5AD6A0),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _Metric(
                                            label: 'مانده حساب',
                                            value: '${_money(customer.balanceDue)} تومان',
                                            icon: Icons.account_balance_wallet_outlined,
                                            accent: const Color(0xFFFFC56E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _editCustomer(customer),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('ویرایش پرونده'),
                                    ),
                                    if (customer.status == 'active')
                                      FilledButton.tonalIcon(
                                        onPressed: () => _recordReceipt(customer),
                                        icon: const Icon(Icons.payments_outlined, size: 18),
                                        label: const Text('ثبت دریافت'),
                                      ),
                                    TextButton.icon(
                                      onPressed: () => _changeCustomerStatus(customer),
                                      icon: Icon(
                                        customer.status == 'active'
                                            ? Icons.archive_outlined
                                            : Icons.unarchive_outlined,
                                        size: 18,
                                      ),
                                      label: Text(customer.status == 'active' ? 'بایگانی' : 'فعال‌سازی'),
                                    ),
                                  ],
                                ),
                              ),
                              FutureBuilder<List<_CustomerLedgerEntry>>(
                                future: _ledgerFor(customer.id),
                                builder: (context, ledger) {
                                  if (ledger.connectionState == ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    );
                                  }
                                  if (ledger.hasError) {
                                    return const ListTile(
                                      dense: true,
                                      leading: Icon(Icons.cloud_off_outlined),
                                      title: Text('گردش حساب در دسترس نیست. دوباره تلاش کن.'),
                                    );
                                  }
                                  final entries = ledger.data ?? const <_CustomerLedgerEntry>[];
                                  if (entries.isEmpty) {
                                    return const ListTile(
                                      dense: true,
                                      leading: Icon(Icons.receipt_long_outlined),
                                      title: Text('هنوز فاکتور یا دریافتی برای این مشتری ثبت نشده است.'),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                        child: Text(
                                          'گردش حساب',
                                          style: TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      ...entries.map((entry) => ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 18,
                                          backgroundColor: (entry.isReceipt
                                                  ? const Color(0xFF5AD6A0)
                                                  : const Color(0xFF00D8E8))
                                              .withValues(alpha: 0.12),
                                          child: Icon(
                                            entry.isReceipt
                                                ? Icons.south_west_rounded
                                                : Icons.receipt_long_outlined,
                                            size: 18,
                                            color: entry.isReceipt
                                                ? const Color(0xFF5AD6A0)
                                                : const Color(0xFF00D8E8),
                                          ),
                                        ),
                                        title: Text(
                                          entry.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${entry.subtitle} • ${_date(entry.date)}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Text(
                                          '${entry.isReceipt ? '−' : '+'}${_money(entry.amount)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: entry.isReceipt
                                                ? const Color(0xFF5AD6A0)
                                                : const Color(0xFF00D8E8),
                                          ),
                                        ),
                                      )),
                                    ],
                                  );
                                },
                              ),
                            ]
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
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withValues(alpha: 0.20)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 10.5),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CustomerLedgerEntry {
  const _CustomerLedgerEntry({
    required this.date,
    required this.amount,
    required this.title,
    required this.subtitle,
    required this.isReceipt,
  });

  final DateTime date;
  final num amount;
  final String title;
  final String subtitle;
  final bool isReceipt;
}
class _CustomerForm extends StatefulWidget {
  const _CustomerForm({
    required this.repository,
    required this.businessId,
    this.customer,
  });
  final InventoryRepository repository;
  final String businessId;
  final CustomerRecord? customer;

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
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer != null) {
      _name.text = customer.name;
      _phone.text = customer.phone ?? '';
      _email.text = customer.email ?? '';
      _company.text = customer.companyName ?? '';
      _address.text = customer.address ?? '';
      _notes.text = customer.notes ?? '';
    }
  }

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
      final customer = widget.customer;
      if (customer == null) {
        await widget.repository.createCustomer(
          businessId: widget.businessId,
          name: _name.text,
          phone: _phone.text,
          email: _email.text,
          companyName: _company.text,
          address: _address.text,
          notes: _notes.text,
        );
      } else {
        await widget.repository.updateCustomer(
          businessId: widget.businessId,
          customerId: customer.id,
          name: _name.text,
          phone: _phone.text,
          email: _email.text,
          companyName: _company.text,
          address: _address.text,
          notes: _notes.text,
        );
      }
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
              Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Color(0xFF00D8E8), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    widget.customer == null ? 'پرونده مشتری جدید' : 'ویرایش پرونده مشتری',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
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
                    : Text(widget.customer == null ? 'ذخیره پرونده مشتری' : 'ذخیره تغییرات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _CustomerReceiptForm extends StatefulWidget {
  const _CustomerReceiptForm({
    required this.repository,
    required this.customer,
    required this.invoices,
  });

  final InventoryRepository repository;
  final CustomerRecord customer;
  final List<SaleRecord> invoices;

  @override
  State<_CustomerReceiptForm> createState() => _CustomerReceiptFormState();
}

class _CustomerReceiptFormState extends State<_CustomerReceiptForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late String _saleId;
  String _method = 'cash';
  bool _saving = false;

  SaleRecord get _selectedInvoice =>
      widget.invoices.firstWhere((sale) => sale.id == _saleId);

  @override
  void initState() {
    super.initState();
    _saleId = widget.invoices.first.id;
    _amount.text = _selectedInvoice.balanceDue.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  num? _parseAmount() {
    var raw = _amount.text.replaceAll(',', '').replaceAll('٬', '').trim();
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      raw = raw.replaceAll(persianDigits[i], '$i');
      raw = raw.replaceAll(arabicDigits[i], '$i');
    }
    return num.tryParse(raw);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _parseAmount();
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.recordCustomerReceipt(
        saleId: _saleId,
        amount: amount,
        paymentMethod: _method,
        reference: _reference.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '42501'
          ? 'مجوز ثبت دریافت وجه را نداری.'
          : 'ثبت دریافت انجام نشد؛ مانده فاکتور را دوباره بررسی کن.';
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
              Row(
                children: [
                  const Icon(Icons.payments_outlined, color: Color(0xFF00D8E8), size: 25),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('ثبت دریافت از ${widget.customer.name}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'هر دریافت به یک فاکتور مشخص متصل می‌شود. ثبت نهایی در سرور با کنترل مانده انجام می‌شود.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _saleId,
                decoration: const InputDecoration(labelText: 'فاکتور'),
                items: widget.invoices.map((sale) => DropdownMenuItem(
                  value: sale.id,
                  child: Text('${sale.saleNumber} • مانده ${_money(sale.balanceDue)} تومان'),
                )).toList(growable: false),
                onChanged: _saving ? null : (value) {
                  if (value == null) return;
                  setState(() {
                    _saleId = value;
                    _amount.text = _selectedInvoice.balanceDue.toStringAsFixed(0);
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'مبلغ دریافتی (تومان) *'),
                validator: (_) {
                  final amount = _parseAmount();
                  if (amount == null || amount <= 0) return 'مبلغ معتبر و بیشتر از صفر وارد کن.';
                  if (amount > _selectedInvoice.balanceDue) return 'مبلغ از مانده فاکتور بیشتر است.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'روش دریافت'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('نقدی')),
                  DropdownMenuItem(value: 'card', child: Text('کارت‌خوان')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('انتقال بانکی')),
                  DropdownMenuItem(value: 'cheque', child: Text('چک')),
                  DropdownMenuItem(value: 'other', child: Text('سایر')),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'شماره پیگیری / مرجع (اختیاری)'),
                maxLength: 120,
              ),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)'),
                minLines: 1,
                maxLines: 3,
                maxLength: 1000,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'در حال ثبت...' : 'ثبت دریافت وجه'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _paymentMethodLabel(String method) => switch (method) {
  'cash' => 'نقدی',
  'card' => 'کارت‌خوان',
  'bank_transfer' => 'انتقال بانکی',
  'cheque' => 'چک',
  _ => 'سایر',
};

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

String _money(num value) => value.toStringAsFixed(0).replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (match) => ',',
);
