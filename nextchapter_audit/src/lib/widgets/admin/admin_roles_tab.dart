import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_metrics_tab.dart' show adminErrorBox, AdminEmptyState;

/// Role Management tab — visible to any tier, mutation buttons only enabled
/// when the caller is a super_admin (matches the server-side guard).
class AdminRolesTab extends StatefulWidget {
  const AdminRolesTab({super.key});

  @override
  State<AdminRolesTab> createState() => _AdminRolesTabState();
}

class _AdminRolesTabState extends State<AdminRolesTab> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  static const _tiers = ['moderator', 'admin', 'super_admin'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminRepository.instance.listAdmins();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load admin roles: $e';
      });
    }
  }

  Future<void> _grant() async {
    final userId = TextEditingController();
    final reason = TextEditingController();
    String tier = 'moderator';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (dialogCtx, setD) {
        return AlertDialog(
          title: const Text('Grant role'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userId,
                  decoration: const InputDecoration(
                    labelText: 'auth.users.id (UUID)',
                    hintText: '00000000-0000-0000-0000-000000000000',
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                DropdownButtonFormField<String>(
                  initialValue: tier,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: _tiers
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setD(() => tier = v ?? 'moderator'),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Grant')),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      await AdminRepository.instance.grantRole(
        userId.text.trim(),
        tier,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Granted $tier — user must sign back in to see the new role')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _revoke(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Revoke role'),
        content: Text('Revoke ${row['role']} from ${row['email'] ?? row['user_id']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminRepository.instance.revokeRole(row['user_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role revoked')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final auth = context.watch<AuthProvider>();
    final isSuper = auth.isSuperAdmin;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return adminErrorBox(context, _error!, _load);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: appColors.danger),
              const SizedBox(width: AppTheme.spacingSm),
              Text('Admin Roles', style: text.titleMedium),
              const SizedBox(width: AppTheme.spacingSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isSuper ? appColors.success : appColors.subtleText).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  isSuper ? 'super_admin — can grant/revoke' : 'read-only for your role',
                  style: text.labelSmall?.copyWith(
                    color: isSuper ? appColors.success : appColors.subtleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isSuper ? _grant : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Grant role'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingSm),
        Expanded(
          child: _rows.isEmpty
              ? const AdminEmptyState(
                  message: 'No admin/moderator roles granted yet.',
                  icon: Icons.admin_panel_settings_outlined,
                )
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final row = _rows[i];
                    final role = (row['role'] as String?) ?? '';
                    final email = (row['email'] as String?) ?? '(no email)';
                    final grantedAt = row['granted_at']?.toString() ?? '';
                    return Container(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(color: colors.outlineVariant.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          _roleBadge(role, colors, text),
                          const SizedBox(width: AppTheme.spacingMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email, style: text.bodyMedium),
                                Text('id: ${row['user_id']}',
                                    style: text.bodySmall?.copyWith(color: appColors.subtleText)),
                                if (grantedAt.isNotEmpty)
                                  Text('granted: $grantedAt',
                                      style: text.bodySmall?.copyWith(color: appColors.subtleText)),
                              ],
                            ),
                          ),
                          if (isSuper)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              label: const Text('Revoke'),
                              onPressed: () => _revoke(row),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _roleBadge(String role, ColorScheme colors, TextTheme text) {
    final Color bg = switch (role) {
      'super_admin' => Colors.deepPurple,
      'admin'       => colors.primary,
      'moderator'   => colors.tertiary,
      _             => colors.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: bg.withOpacity(0.4)),
      ),
      child: Text(role,
          style: text.labelMedium?.copyWith(color: bg, fontWeight: FontWeight.w700)),
    );
  }
}
