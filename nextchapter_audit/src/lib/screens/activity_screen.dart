import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Placeholder branch for the future Activity tab. Kept intentionally simple
/// so navigation feels alive without promising features we haven't built yet.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_outline, size: 56, color: colors.primary.withOpacity(0.6)),
              const SizedBox(height: AppTheme.spacingMd),
              Text('Activity is coming soon', style: text.titleMedium),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                'Likes, new matches, and profile views will live here. For Beta we kept things simple and focused on browsing and messaging.',
                style: text.bodySmall?.copyWith(color: appColors.subtleText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
