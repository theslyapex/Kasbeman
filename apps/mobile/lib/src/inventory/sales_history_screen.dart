import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_repository.dart';
import 'inventory_repository.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
    required this.membership,
    required this.branch,
    required this.repository,
  });

  final BusinessMembership membership;
  final BusinessBranch branch;
  final InventoryRepository repository;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _search = TextEditingController();
  String _status = 'all';
  late Future<List<SaleRecord>> _future;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  void _load() {
    _future = widget.repository.fetchSales(
      businessId: widget.membership.businessId,
      branchId: widget.branch.id,
      status: _status,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فروش‌های شعبه'),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'جست‌وجوی شماره فاکتور یا مشتری',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip('همه', 'all'),
                _filterChip('پیش‌نویس', 'draft'),
                _filterChip('تأییدشده', 'confirmed'),
                _filterChip('لغوشده', 'cancelled'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<SaleRecord>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('دریافت فهرست فروش‌ها ناموفق بود. دسترسی و اتصال را بررسی کن.'),
                  );
                }
                final needle = _search.text.trim().toLowerCase();
                final sales = (snapshot.data ?? const <SaleRecord>[]).where((sale) {
                  return needle.isEmpty ||
                      sale.saleNumber.toLowerCase().contains(needle) ||
                      (sale.customerName ?? '').toLowerCase().contains(needle);
                }).toList(growable: false);
                if (sales.isEmpty) {
                  return const Center(child: Text('فروشی با این مشخصات پیدا نشد.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: sales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final sale = sales[index];
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.receipt_long_outlined),
                          ),
                          title: Text(sale.saleNumber),
                          subtitle: Text(
                            '${sale.customerName ?? 'مشتری ثبت‌نشده'} • '
                            '${_date(sale.createdAt)}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${_money(sale.grandTotal)} تومان'),
                              Text(_statusLabel(sale.status),
                                  style: TextStyle(
                                    color: _statusColor(sale.status),
                                    fontSize: 11,
                                  )),
                            ],
                          ),
                          children: [
                            const Divider(height: 1),
                            ...sale.items.map((item) => ListTile(
                              dense: true,
                              title: Text(item.productName),
                              subtitle: Text(
                                '${item.quantity} × ${_money(item.unitPrice)}'
                                ' • تخفیف ${_money(item.discount)}',
                              ),
                              trailing: Text('${_money(item.lineTotal)}'),
                            )),
                            if (sale.confirmedAt != null)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text('تأیید در: ${_date(sale.confirmedAt!)}'),
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

  Widget _filterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(label),
        selected: _status == value,
        onSelected: (selected) {
          if (!selected) return;
          setState(() {
            _status = value;
            _load();
          });
        },
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'draft' => 'پیش‌نویس',
  'confirmed' => 'تأییدشده',
  'cancelled' => 'لغوشده',
  _ => status,
};

Color _statusColor(String status) => switch (status) {
  'confirmed' => const Color(0xFF31C48D),
  'cancelled' => const Color(0xFFEF6A6A),
  _ => const Color(0xFFFFC857),
};

String _money(num value) => value.toStringAsFixed(0).replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (match) => ',',
);

String _date(DateTime value) {
  final local = value.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '${local.year}/$m/$d  ${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
