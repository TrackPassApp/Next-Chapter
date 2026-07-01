import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../theme/theme.dart';

/// Small, horizontal ad-banner placeholder used at the top of the Messages
/// list and the top of the Community rooms list. Never inside a chat stream.
///
/// Compact, muted, obviously labelled as "AD". Reads [AppConfig.adsEnabled] so
/// a build can ship with ads hidden by passing `--dart-define=ADS_ENABLED=false`.
///
/// Swap in a real ad provider (AdSense, Ad Manager, direct sponsor) by
/// replacing [_body]. All other files just render `AdBanner()`.
class AdBanner extends StatelessWidget {
  final EdgeInsetsGeometry? margin;
  final double height;

  const AdBanner({
    super.key,
    this.margin,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Container(
      height: height,
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          ),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.35)),
      ),
      child: _body(text, appColors),
    );
  }

  Widget _body(TextTheme text, AppColorsExtension appColors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSm, vertical: 2),
          decoration: BoxDecoration(
            color: appColors.subtleText.withOpacity(0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('AD',
              style: text.labelSmall?.copyWith(
                color: appColors.subtleText,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              )),
        ),
        const SizedBox(width: AppTheme.spacingSm),
        Expanded(
          child: Text(
            'Sponsored slot. Messaging stays free.',
            style: text.bodySmall?.copyWith(color: appColors.subtleText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.campaign_outlined,
            size: AppTheme.iconSm, color: appColors.subtleText),
      ],
    );
  }
}
