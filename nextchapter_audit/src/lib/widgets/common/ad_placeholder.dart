import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../theme/theme.dart';

/// Single non-intrusive ad slot placeholder used inside the Browse grid.
///
/// Design goals (see B11 spec):
///   • Sits in the flow of the profile grid like a normal card — never a popup,
///     never a full-screen takeover, never inside chat threads.
///   • Reads [AppConfig.adsEnabled] so an entire release can ship with ads
///     hidden by passing `--dart-define=ADS_ENABLED=false`.
///   • Renders a labelled "Ad" placeholder with clean typography so the space
///     is obviously reserved without pretending to be a real ad.
///   • Easy to swap: replace the [_placeholderBody] widget with a real ad
///     provider's SDK widget (e.g. AdMob, Carbon) — no other file needs to
///     know about it.
class AdPlaceholder extends StatelessWidget {
  final double height;

  const AdPlaceholder({super.key, this.height = 60});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: colors.outlineVariant.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: _placeholderBody(text, colors, appColors),
    );
  }

  Widget _placeholderBody(
    TextTheme text,
    ColorScheme colors,
    AppColorsExtension appColors,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: colors.outlineVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'AD',
              style: text.labelSmall?.copyWith(
                color: appColors.subtleText,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Icon(
            Icons.campaign_outlined,
            size: AppTheme.iconMd,
            color: appColors.subtleText,
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'Sponsored slot',
            style: text.labelMedium?.copyWith(color: appColors.subtleText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Messaging stays free.',
            style: text.labelSmall?.copyWith(color: appColors.subtleText),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
