import 'package:flutter/material.dart';
import '../services/mock_data_service.dart';
import '../theme/theme.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppTheme.spacingMd),
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: AppTheme.spacingXs),
            decoration: BoxDecoration(
              color: appColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Text('ADMIN', style: text.labelSmall?.copyWith(color: appColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Platform Metrics', style: text.titleMedium),
                const SizedBox(height: AppTheme.spacingMd),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isMobile ? 2 : 4,
                  mainAxisSpacing: AppTheme.spacingMd,
                  crossAxisSpacing: AppTheme.spacingMd,
                  childAspectRatio: 1.5,
                  children: [
                    _MetricCard(label: 'Total Users', value: '${MockDataService.profiles.length}', icon: Icons.people_outline, color: colors.primary, colors: colors, text: text),
                    _MetricCard(label: 'Active Today', value: '${MockDataService.profiles.where((p) => p.isOnline).length}', icon: Icons.circle, color: appColors.online, colors: colors, text: text),
                    _MetricCard(label: 'Reports', value: '${MockDataService.reports.length}', icon: Icons.flag_outlined, color: appColors.warning, colors: colors, text: text),
                    _MetricCard(label: 'Verified', value: '${MockDataService.profiles.where((p) => p.hasAnyVerification).length}', icon: Icons.verified_outlined, color: appColors.verified, colors: colors, text: text),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingLg),
                Text('Recent Reports', style: text.titleMedium),
                const SizedBox(height: AppTheme.spacingMd),
                ...MockDataService.reports.map((report) => Container(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingSm),
                        decoration: BoxDecoration(
                          color: appColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Icon(Icons.flag, color: appColors.warning, size: AppTheme.iconMd),
                      ),
                      const SizedBox(width: AppTheme.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(report.reportedUserName, style: text.titleSmall),
                            Text('Reason: ${report.reason}', style: text.bodySmall),
                            if (report.details != null) Text(report.details!, style: text.bodySmall?.copyWith(color: appColors.subtleText), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: AppTheme.spacingXs),
                            decoration: BoxDecoration(
                              color: appColors.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                            child: Text('Pending', style: text.labelSmall?.copyWith(color: appColors.warning)),
                          ),
                          const SizedBox(height: AppTheme.spacingSm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.check_circle_outline, color: appColors.success, size: AppTheme.iconMd),
                                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report resolved'))),
                                tooltip: 'Resolve',
                              ),
                              IconButton(
                                icon: Icon(Icons.person_off_outlined, color: appColors.danger, size: AppTheme.iconMd),
                                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User suspended'))),
                                tooltip: 'Suspend User',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: AppTheme.spacingLg),
                Text('Users', style: text.titleMedium),
                const SizedBox(height: AppTheme.spacingMd),
                ...MockDataService.profiles.map((profile) => Container(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: Text(profile.firstName[0], style: text.titleSmall?.copyWith(color: colors.primary)),
                    ),
                    title: Text('${profile.firstName}, ${profile.age}', style: text.titleSmall),
                    subtitle: Text('${profile.city}, ${profile.state} • ${profile.verificationCount}/4 verified', style: text.bodySmall),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$v: ${profile.firstName}')));
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'Suspend', child: Text('Suspend')),
                        const PopupMenuItem(value: 'Delete', child: Text('Delete')),
                        const PopupMenuItem(value: 'View Reports', child: Text('View Reports')),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: AppTheme.spacingLg),
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_outlined, color: appColors.subtleText),
                      const SizedBox(width: AppTheme.spacingMd),
                      Expanded(child: Text('Ad management coming soon', style: text.bodySmall?.copyWith(color: appColors.subtleText))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ColorScheme colors;
  final TextTheme text;

  const _MetricCard({required this.label, required this.value, required this.icon, required this.color, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: AppTheme.iconMd),
          const Spacer(),
          Text(value, style: text.headlineSmall?.copyWith(color: color)),
          Text(label, style: text.labelSmall),
        ],
      ),
    );
  }
}
