import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../inventory/inventory_screen.dart';
import '../workspace/branch_selection_store.dart';
import '../workspace/create_branch_screen.dart';
import '../workspace/workspace_repository.dart';

const _inventoryModuleEnabled = bool.fromEnvironment(
  'KASBEMAN_INVENTORY_ENABLED',
  defaultValue: false,
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.email,
    required this.membership,
    required this.repository,
    required this.onSwitchWorkspace,
    this.branchSelectionStore,
    required this.userId,
  });

  final String email;
  final BusinessMembership membership;
  final WorkspaceRepository repository;
  final VoidCallback onSwitchWorkspace;
  final BranchSelectionStore? branchSelectionStore;
  final String userId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _BranchLoadResult {
  const _BranchLoadResult({
    required this.branches,
    required this.preferredBranchId,
    required this.permissions,
  });

  final List<BusinessBranch> branches;
  final String? preferredBranchId;
  final Set<String> permissions;
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_BranchLoadResult> _branchesFuture;
  late final BranchSelectionStore _selectionStore;
  String? _selectedBranchId;

  String get _userId => widget.userId;

  @override
  void initState() {
    super.initState();
    _selectionStore = widget.branchSelectionStore ??
        const SharedPreferencesBranchSelectionStore();
    _branchesFuture = _loadBranches();
  }

  Future<_BranchLoadResult> _loadBranches() async {
    final branches = await widget.repository.fetchBranches(
      widget.membership.businessId,
    );
    final savedId = await _selectionStore.read(
      userId: _userId,
      businessId: widget.membership.businessId,
    );

    final savedBranchExists =
        savedId != null && branches.any((branch) => branch.id == savedId);
    final fallback = branches.where((branch) => branch.isPrimary);
    final preferred = savedBranchExists
        ? savedId
        : fallback.isNotEmpty
            ? fallback.first.id
            : branches.isNotEmpty
                ? branches.first.id
                : null;

    final activeBranchId = _selectedBranchId ?? preferred;
    final permissions = await widget.repository.fetchPermissions(
      businessId: widget.membership.businessId,
      userId: _userId,
      branchId: activeBranchId,
    );

    return _BranchLoadResult(
      branches: branches,
      preferredBranchId: activeBranchId,
      permissions: permissions,
    );
  }

  BusinessBranch? _findBranch(
    List<BusinessBranch> branches,
    String? branchId,
  ) {
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    return null;
  }

  Future<void> _selectBranch(String branchId) async {
    setState(() => _selectedBranchId = branchId);
    try {
      await _selectionStore.write(
        userId: _userId,
        businessId: widget.membership.businessId,
        branchId: branchId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('شعبه انتخاب شد، اما ذخیره آن روی دستگاه انجام نشد.'),
        ),
      );
    }
  }

  Future<void> _createBranch() async {
    final createdId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => CreateBranchScreen(
          repository: widget.repository,
          businessId: widget.membership.businessId,
        ),
      ),
    );

    if (createdId == null || !mounted) return;

    setState(() {
      _selectedBranchId = createdId;
      _branchesFuture = _loadBranches();
    });

    try {
      await _selectionStore.write(
        userId: _userId,
        businessId: widget.membership.businessId,
        branchId: createdId,
      );
    } catch (_) {
      // The branch remains selected for this session.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('شعبه با موفقیت ایجاد شد.')),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خروج انجام نشد. دوباره تلاش کن.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.membership.businessName),
        actions: [
          IconButton(
            tooltip: 'تغییر فضای کاری',
            onPressed: widget.onSwitchWorkspace,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 52,
                    color: Color(0xFF00D8E8),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'فضای کاری شما آماده است',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.membership.businessName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'نقش شما: ${widget.membership.roleLabel}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'شعبه فعال',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          FutureBuilder<_BranchLoadResult>(
                            future: _branchesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const LinearProgressIndicator();
                              }
                              if (snapshot.hasError) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'دریافت شعبه‌ها ناموفق بود.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => setState(
                                        () => _branchesFuture = _loadBranches(),
                                      ),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('تلاش دوباره'),
                                    ),
                                  ],
                                );
                              }

                              final result = snapshot.data!;
                              final branches = result.branches;
                              if (branches.isEmpty) {
                                return const Text(
                                  'شعبه فعال برای این کسب‌وکار پیدا نشد.',
                                  style: TextStyle(color: Colors.white70),
                                );
                              }

                              final selected = _findBranch(
                                    branches,
                                    _selectedBranchId ??
                                        result.preferredBranchId,
                                  ) ??
                                  branches.first;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<String>(
                                    key: ValueKey<String>(selected.id),
                                    initialValue: selected.id,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      prefixIcon:
                                          Icon(Icons.store_mall_directory),
                                    ),
                                    items: branches
                                        .map(
                                          (branch) =>
                                              DropdownMenuItem<String>(
                                            value: branch.id,
                                            child: Text(
                                              branch.isPrimary
                                                  ? '${branch.name} (اصلی)'
                                                  : branch.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (id) {
                                      if (id != null) _selectBranch(id);
                                    },
                                  ),
                                  if (selected.code != null &&
                                      selected.code!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'کد شعبه: ${selected.code}',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                  if (result.permissions.contains('branches.manage')) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _createBranch,
                                      icon: const Icon(Icons.add_business),
                                      label: const Text('افزودن شعبه'),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  const Divider(color: Colors.white12),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: _inventoryModuleEnabled &&
                                            result.permissions.contains('inventory.items.read') &&
                                            result.permissions.contains('inventory.stock.read')
                                        ? () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => InventoryScreen(
                                                  membership: widget.membership,
                                                  branch: selected,
                                                ),
                                              ),
                                            )
                                        : null,
                                    icon: const Icon(Icons.inventory_2_outlined),
                                    label: const Text('مدیریت کالا و انبار'),
                                  ),
                                  if (!_inventoryModuleEnabled ||
                                      !result.permissions.contains('inventory.items.read') ||
                                      !result.permissions.contains('inventory.stock.read'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        !_inventoryModuleEnabled
                                            ? 'این ماژول پس از آماده‌سازی دیتابیس و فعال‌سازی نسخه عملیاتی در دسترس قرار می‌گیرد.'
                                            : 'برای مشاهده این بخش، مجوزهای لازم در فضای کاری شما فعال نیست.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'حساب کاربری',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.email,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 8),
                          const Text(
                            'شعبه انتخاب‌شده به‌صورت جداگانه برای هر کسب‌وکار ذخیره می‌شود. عملیات ماژول‌ها باید شناسه همین شعبه را در درخواست‌های خود ارسال کنند.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: widget.onSwitchWorkspace,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('تغییر فضای کاری'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
