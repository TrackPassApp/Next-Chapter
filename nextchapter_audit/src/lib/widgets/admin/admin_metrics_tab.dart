import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_user_detail_dialog.dart';

/// Overview tab — 8 real platform metrics from admin_dashboard_metrics RPC.
class AdminMetricsTab extends StatefulWidget {
  const AdminMetricsTab({super.key});

  @override
  State<AdminMetricsTab> createState() => _AdminMetricsTabState();
}

class _AdminMetricsTabState extends State<AdminMetricsTab> {
  Map<String, dynamic> _metrics = {};
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
      final m = await AdminRepository.instance.fetchMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load metrics: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorBox(_error!, _load, appColors, text);
    }

    int _i(String k) => (_metrics[k] as num?)?.toInt() ?? 0;

    final cards = [
      _MetricSpec('Total Users', _i('total_users'), Icons.people_outline, colors.primary),
      _MetricSpec('Active (7d)', _i('active_users'), Icons.circle, appColors.online),
      _MetricSpec('Verified', _i('verified_users'), Icons.verified_outlined, appColors.verified),
      _MetricSpec('Pending Reports', _i('pending_reports'), Icons.flag_outlined, appColors.warning),
      _MetricSpec('Suspended', _i('suspended_users'), Icons.person_off_outlined, appColors.danger),
      _MetricSpec('Deleted', _i('deleted_users'), Icons.delete_outline, appColors.subtleText),
      _MetricSpec('New Today', _i('new_users_today'), Icons.person_add_outlined, colors.tertiary),
      _MetricSpec('Messages Today', _i('messages_sent_today'), Icons.chat_bubble_outline, colors.secondary),
    ];

    final width = MediaQuery.sizeOf(context).width;
    final cols = width < 700 ? 2 : (width < 1100 ? 3 : 4);
    final aspect = width < 400 ? 1.05 : (width < 700 ? 1.25 : 1.6);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingSm),
        children: [
          Row(
            children: [
              Text('Platform Metrics', style: text.titleMedium),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: AppTheme.spacingMd,
              crossAxisSpacing: AppTheme.spacingMd,
              childAspectRatio: aspect,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => _MetricCard(spec: cards[i]),
          ),
          const SizedBox(height: AppTheme.spacingLg),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: appColors.success),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Text(
                    'All metrics are sourced live from Supabase via admin_dashboard_metrics(). '
                    'No mock data anywhere on this dashboard.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSpec {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  _MetricSpec(this.label, this.value, this.icon, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricSpec spec;
  const _MetricCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(spec.icon, color: spec.color, size: AppTheme.iconMd),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${spec.value}',
                style: text.headlineSmall?.copyWith(color: spec.color)),
          ),
          Text(spec.label,
              style: text.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

Widget _errorBox(String msg, VoidCallback onRetry, AppColorsExtension appColors, TextTheme text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: appColors.danger, size: 40),
          const SizedBox(height: AppTheme.spacingSm),
          Text(msg, style: text.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppTheme.spacingMd),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

// Exposed for use by the other admin tabs.
Widget adminErrorBox(BuildContext context, String msg, VoidCallback onRetry) {
  final theme = Theme.of(context);
  return _errorBox(msg, onRetry, theme.extension<AppColorsExtension>()!, theme.textTheme);
}

// Tiny helper widget for tabs that need an empty state.
class AdminEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const AdminEmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: appColors.subtleText),
            const SizedBox(height: AppTheme.spacingSm),
            Text(message, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// Open user detail dialog.
Future<void> openAdminUserDialog(BuildContext context, String profileId) {
  return showDialog(
    context: context,
    builder: (_) => AdminUserDetailDialog(profileId: profileId),
  );
}
