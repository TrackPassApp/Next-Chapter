import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_metrics_tab.dart' show adminErrorBox, AdminEmptyState;

class AdminLogTab extends StatefulWidget {
  const AdminLogTab({super.key});

  @override
  State<AdminLogTab> createState() => _AdminLogTabState();
}

class _AdminLogTabState extends State<AdminLogTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

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
      final rows = await AdminRepository.instance.listModerationLog();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load log: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return adminErrorBox(context, _error!, _load);

    return Column(
      children: [
        Row(
          children: [
            Text('Last 200 admin actions', style: text.bodySmall?.copyWith(color: appColors.subtleText)),
            const Spacer(),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ],
        ),
        const SizedBox(height: AppTheme.spacingSm),
        Expanded(
          child: _rows.isEmpty
              ? const AdminEmptyState(message: 'No admin actions logged yet.', icon: Icons.history)
              : Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final actor = r['actor_id'] as String? ?? '—';
                      final target = r['target_user_id'] as String? ?? '—';
                      final action = r['action'] as String? ?? '';
                      final reason = r['reason'] as String? ?? '';
                      final kind = r['target_kind'] as String? ?? '';
                      final createdAt = r['created_at'] as String? ?? '';
                      return ListTile(
                        leading: Icon(_iconForAction(action), color: _colorForAction(action, appColors)),
                        title: Text('$action  •  $kind', style: text.titleSmall),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText('Actor: $actor', style: text.labelSmall?.copyWith(color: appColors.subtleText)),
                            SelectableText('Target user: $target', style: text.labelSmall?.copyWith(color: appColors.subtleText)),
                            if (reason.isNotEmpty) Text('Notes: $reason', style: text.bodySmall),
                          ],
                        ),
                        trailing: Text(
                          createdAt.length >= 19 ? createdAt.substring(0, 19).replaceAll('T', ' ') : createdAt,
                          style: text.labelSmall?.copyWith(color: appColors.subtleText),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  IconData _iconForAction(String action) {
    if (action.startsWith('suspend')) return Icons.person_off_outlined;
    if (action.startsWith('unsuspend')) return Icons.person_outline;
    if (action.startsWith('soft_delete')) return Icons.delete_outline;
    if (action.startsWith('restore')) return Icons.restore;
    if (action.startsWith('verify_')) return Icons.verified_outlined;
    if (action.startsWith('unverify_')) return Icons.cancel_outlined;
    if (action == 'resolve') return Icons.check_circle_outline;
    if (action == 'dismiss') return Icons.close;
    return Icons.history;
  }

  Color _colorForAction(String action, AppColorsExtension c) {
    if (action.startsWith('suspend') || action.startsWith('soft_delete') || action.startsWith('unverify_')) return c.danger;
    if (action.startsWith('verify_') || action == 'resolve' || action.startsWith('restore') || action.startsWith('unsuspend')) return c.success;
    return c.subtleText;
  }
}
