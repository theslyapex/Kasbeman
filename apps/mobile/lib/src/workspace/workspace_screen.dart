import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_screen.dart';
import 'branch_selection_store.dart';
import 'create_business_screen.dart';
import 'workspace_repository.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.email,
    this.repository,
    this.branchSelectionStore,
  });

  final String email;
  final WorkspaceRepository? repository;
  final BranchSelectionStore? branchSelectionStore;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late Future<List<BusinessMembership>> _membershipsFuture;

  WorkspaceRepository get _repository =>
      widget.repository ??
      SupabaseWorkspaceRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  void _loadMemberships() {
    _membershipsFuture = _repository.fetchMyBusinesses();
  }

  Future<void> _createBusiness() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateBusinessScreen(repository: _repository),
      ),
    );

    if (created == true && mounted) {
      setState(_loadMemberships);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کسب‌وکار با موفقیت ساخته شد.')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خروج انجام نشد. دوباره تلاش کن.')),
      );
    }
  }

  void _openWorkspace(BusinessMembership membership) {
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(
          email: widget.email,
          membership: membership,
          repository: _repository,
          branchSelectionStore: widget.branchSelectionStore,
          onSwitchWorkspace: () {
            navigator.pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => WorkspaceScreen(email: widget.email),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('انتخاب فضای کاری'),
        actions: [
          IconButton(
            tooltip: 'ساخت کسب‌وکار',
            onPressed: _createBusiness,
            icon: const Icon(Icons.add_business_outlined),
          ),
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: FutureBuilder<List<BusinessMembership>>(
                future: _membershipsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingState();
                  }

                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      title: 'دریافت فهرست کسب‌وکارها ناموفق بود',
                      description:
                          'اتصال را بررسی کن و دوباره تلاش کن. اطلاعات حساب و دسترسی‌ها تغییری نکرده‌اند.',
                      actionLabel: 'تلاش دوباره',
                      onAction: () => setState(_loadMemberships),
                    );
                  }

                  final memberships = snapshot.data ?? const [];
                  if (memberships.isEmpty) {
                    return _MessageState(
                      icon: Icons.storefront_outlined,
                      title: 'هنوز فضای کاری فعالی نداری',
                      description:
                          'می‌توانی همین حالا اولین کسب‌وکارت را بسازی یا بعداً با دعوت‌نامه به کسب‌وکار دیگری بپیوندی.',
                      actionLabel: 'ساخت اولین کسب‌وکار',
                      onAction: _createBusiness,
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        'به کسبمن خوش آمدی',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'برای ادامه، یکی از کسب‌وکارهای خودت را انتخاب کن.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: ListView.separated(
                          itemCount: memberships.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final membership = memberships[index];
                            return _WorkspaceTile(
                              membership: membership,
                              onTap: () => _openWorkspace(membership),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _createBusiness,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('افزودن کسب‌وکار دیگر'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.membership,
    required this.onTap,
  });

  final BusinessMembership membership;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF10233D),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF00D8E8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: Color(0xFF00D8E8),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'نقش شما: ${membership.roleLabel}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF00D8E8)),
          SizedBox(height: 16),
          Text('در حال دریافت فضاهای کاری...'),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: const Color(0xFF00D8E8)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.8),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
