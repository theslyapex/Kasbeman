import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/create_branch_screen.dart';
import '../workspace/workspace_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.email,
    required this.membership,
    required this.repository,
    required this.onSwitchWorkspace,
  });

  final String email;
  final BusinessMembership membership;
  final WorkspaceRepository repository;
  final VoidCallback onSwitchWorkspace;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<BusinessBranch>> _branchesFuture;
  BusinessBranch? _selectedBranch;

  bool get _canManageBranches => widget.membership.roleKey == 'owner';

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  void _loadBranches() {
    _branchesFuture = widget.repository.fetchBranches(
      widget.membership.businessId,
    );
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
      _selectedBranch = null;
      _loadBranches();
    });

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
                          FutureBuilder<List<BusinessBranch>>(
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
                                      onPressed: () =>
                                          setState(_loadBranches),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('تلاش دوباره'),
                                    ),
                                  ],
                                );
                              }

                              final branches = snapshot.data ?? const [];
                              if (branches.isEmpty) {
                                return const Text(
                                  'شعبه فعال برای این کسب‌وکار پیدا نشد.',
                                  style: TextStyle(color: Colors.white70),
                                );
                              }

                              final selected = branches.any(
                                (branch) => branch.id == _selectedBranch?.id,
                              )
                                  ? _selectedBranch!
                                  : branches.first;

                              if (_selectedBranch?.id != selected.id) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) {
                                    if (mounted) {
                                      setState(
                                        () => _selectedBranch = selected,
                                      );
                                    }
                                  },
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<String>(
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
                                      for (final branch in branches) {
                                        if (branch.id == id) {
                                          setState(
                                            () => _selectedBranch = branch,
                                          );
                                          break;
                                        }
                                      }
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
                                  if (_canManageBranches) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _createBranch,
                                      icon: const Icon(Icons.add_business),
                                      label: const Text('افزودن شعبه'),
                                    ),
                                  ],
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
                            'اطلاعات شعبه انتخاب‌شده در ادامه به ماژول‌های عملیاتی مانند فروش، انبار و گزارش‌ها متصل می‌شود.',
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
