import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_repository.dart';
import 'inventory_repository.dart';

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({
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
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  late Future<List<InventoryMovement>> _future;

  @override
  void initState() {
    super.initState();
    if (widget.permissions.contains('inventory.stock.read')) {
      _load();
    } else {
      _future = Future.error(StateError('inventory.stock.read permission required'));
    }
  }

  void _load() {
    _future = widget.repository.fetchMovements(
      businessId: widget.membership.businessId,
      branchId: widget.branch.id,
      movementType: _filter,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'in':
        return 'ورود';
      case 'out':
        return 'خروج';
      case 'transfer':
        return 'انتقال';
      default:
        return type;
    }
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final date = local.toString();
    return date.length >= 16 ? date.substring(0, 16) : date;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.permissions.contains('inventory.stock.read')) {
      return const Scaffold(
        body: Center(child: Text('برای مشاهده تاریخچه موجودی مجوز کافی نداری.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه گردش انبار'),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: () => setState(_load),
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'جست‌وجوی نام کالا یا توضیحات',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'پاک کردن جست‌وجو',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: DropdownButtonFormField<String>(
              initialValue: _filter,
              decoration: const InputDecoration(
                labelText: 'نوع عملیات',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('همه عملیات')),
                DropdownMenuItem(value: 'in', child: Text('ورود کالا')),
                DropdownMenuItem(value: 'out', child: Text('خروج کالا')),
                DropdownMenuItem(value: 'transfer', child: Text('انتقال بین انبارها')),
              ],
              onChanged: (value) {
                setState(() {
                  _filter = value ?? 'all';
                  _load();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InventoryMovement>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'تاریخچه دریافت نشد. دسترسی و اتصال را بررسی کن.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final needle = _search.text.trim().toLowerCase();
                final movements = (snapshot.data ?? const <InventoryMovement>[])
                    .where((item) =>
                        needle.isEmpty ||
                        item.productName.toLowerCase().contains(needle) ||
                        (item.note ?? '').toLowerCase().contains(needle) ||
                        (item.fromWarehouseName ?? '').toLowerCase().contains(needle) ||
                        (item.toWarehouseName ?? '').toLowerCase().contains(needle))
                    .toList(growable: false);
                if (movements.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        needle.isEmpty
                            ? 'هنوز گردش موجودی برای این شعبه ثبت نشده است.'
                            : 'موردی با این عبارت پیدا نشد.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = movements[index];
                    final route = item.movementType == 'in'
                        ? 'ورود به ${item.toWarehouseName ?? 'انبار مقصد'}'
                        : item.movementType == 'out'
                            ? 'خروج از ${item.fromWarehouseName ?? 'انبار مبدأ'}'
                            : '${item.fromWarehouseName ?? 'مبدأ'} ← ${item.toWarehouseName ?? 'مقصد'}';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Chip(label: Text(_typeLabel(item.movementType))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(route),
                            const SizedBox(height: 4),
                            Text(
                              'مقدار: ${item.quantity} ${item.unitName}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (item.note != null && item.note!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('توضیحات: ${item.note}'),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                _dateLabel(item.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
