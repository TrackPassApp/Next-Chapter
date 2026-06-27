import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_metrics_tab.dart' show adminErrorBox, AdminEmptyState, openAdminUserDialog;

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  bool? _suspendedFilter;   // null = any
  bool? _deletedFilter;     // null = any

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminRepository.instance.listUsers(
        query: _searchCtrl.text.trim(),
        suspended: _suspendedFilter,
        deleted: _deletedFilter,
      );
      if (!mounted) return;
      setState(() {
        _users = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load users: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, city, or state…',
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSm),
            _FilterDropdown<bool?>(
              hint: 'Suspended',
              value: _suspendedFilter,
              items: const [
                DropdownMenuItem(value: null, child: Text('Any')),
                DropdownMenuItem(value: true, child: Text('Suspended')),
                DropdownMenuItem(value: false, child: Text('Active')),
              ],
              onChanged: (v) {
                setState(() => _suspendedFilter = v);
                _load();
              },
            ),
            const SizedBox(width: AppTheme.spacingSm),
            _FilterDropdown<bool?>(
              hint: 'Deleted',
              value: _deletedFilter,
              items: const [
                DropdownMenuItem(value: null, child: Text('Any')),
                DropdownMenuItem(value: true, child: Text('Deleted')),
                DropdownMenuItem(value: false, child: Text('Live')),
              ],
              onChanged: (v) {
                setState(() => _deletedFilter = v);
                _load();
              },
            ),
            const SizedBox(width: AppTheme.spacingSm),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ],
        ),
        const SizedBox(height: AppTheme.spacingMd),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? adminErrorBox(context, _error!, _load)
                  : _users.isEmpty
                      ? const AdminEmptyState(message: 'No users match these filters', icon: Icons.people_outline)
                      : Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = _users[i];
                              final name = (u['first_name'] as String?) ?? '—';
                              final city = (u['city'] as String?) ?? '';
                              final state = (u['state'] as String?) ?? '';
                              final isSuspended = u['is_suspended'] == true;
                              final isDeleted = u['is_deleted'] == true;
                              final score = (u['completeness_score'] as num?)?.toInt() ?? 0;
                              return ListTile(
                                onTap: () => openAdminUserDialog(context, u['id'] as String).then((_) => _load()),
                                leading: CircleAvatar(
                                  backgroundColor: colors.primaryContainer,
                                  child: Text(name.isNotEmpty ? name[0] : '?', style: text.titleSmall?.copyWith(color: colors.primary)),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(name, style: text.titleSmall)),
                                    if (isSuspended)
                                      _Pill(label: 'SUSPENDED', color: appColors.danger),
                                    if (isDeleted) ...[
                                      const SizedBox(width: 4),
                                      _Pill(label: 'DELETED', color: appColors.subtleText),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '${city.isEmpty ? "" : "$city, "}$state • completeness $score',
                                  style: text.bodySmall,
                                ),
                                trailing: Icon(Icons.chevron_right, color: appColors.subtleText),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({required this.hint, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: 0),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: text.labelSmall?.copyWith(color: color, fontSize: 10)),
    );
  }
}
