import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class AdPlaceholder extends StatelessWidget {
  final double height;

  const AdPlaceholder({super.key, this.height = 60});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: AppTheme.iconSm, color: appColors.subtleText),
            const SizedBox(width: AppTheme.spacingSm),
            Text('Ad Space', style: text.labelSmall?.copyWith(color: appColors.subtleText)),
          ],
        ),
      ),
    );
  }
}
