import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class TrustSection extends StatelessWidget {
  const TrustSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppTheme.spacingMd : AppTheme.spacingXxl,
        vertical: AppTheme.spacingXl,
      ),
      color: colors.surfaceContainerLow,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Icon(Icons.lock_outline, size: AppTheme.iconLg, color: colors.primary),
              const SizedBox(height: AppTheme.spacingMd),
              Text('Your Privacy Matters', style: text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingMd),
              Text(
                'We will never sell, rent, give away, or share your personal information with advertisers, data brokers, or third-party marketers. Period.',
                style: text.bodyLarge?.copyWith(color: appColors.subtleText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingLg),
              Wrap(
                spacing: AppTheme.spacingMd,
                runSpacing: AppTheme.spacingSm,
                alignment: WrapAlignment.center,
                children: [
                  _TrustBadge(icon: Icons.no_accounts_outlined, label: 'No Data Selling', colors: colors, text: text),
                  _TrustBadge(icon: Icons.delete_forever_outlined, label: 'True Account Deletion', colors: colors, text: text),
                  _TrustBadge(icon: Icons.shield_outlined, label: 'Secure by Design', colors: colors, text: text),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colors;
  final TextTheme text;

  const _TrustBadge({required this.icon, required this.label, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.iconSm, color: colors.primary),
          const SizedBox(width: AppTheme.spacingSm),
          Text(label, style: text.labelMedium?.copyWith(color: colors.primary)),
        ],
      ),
    );
  }
}
