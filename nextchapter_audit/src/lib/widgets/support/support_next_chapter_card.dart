import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../theme/theme.dart';

/// Reusable "Support Next Chapter" surface used across the app in three sizes:
///
///   • [SupportVariant.banner]   – slim single-line banner (Messages screen)
///   • [SupportVariant.card]     – medium card with copy + CTA (Community, Profile)
///   • [SupportVariant.sponsored]– compact sponsored card (Activity placeholder)
///
/// Copy is identical everywhere and never suggests donation is required.
/// Messaging is 100% free — always.
enum SupportVariant { banner, card, sponsored }

class SupportNextChapterCard extends StatelessWidget {
  final SupportVariant variant;
  final EdgeInsetsGeometry? margin;

  const SupportNextChapterCard({
    super.key,
    this.variant = SupportVariant.card,
    this.margin,
  });

  static const _copy =
      'Next Chapter will always keep messaging free. If you want to help '
      'support development and keep this community growing, you can support '
      'the project here.';

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = AppConfig.donateUrl.trim();
    if (url.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Donation link coming soon. Thanks for wanting to help.'),
      ));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = AppConfig.donateUrl.trim();
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    switch (variant) {
      case SupportVariant.banner:
        return Container(
          margin: margin ??
              const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withOpacity(0.35),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: colors.primary.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.volunteer_activism_outlined,
                  size: AppTheme.iconSm, color: colors.primary),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: Text(
                  'Messaging stays free — support Next Chapter if you can.',
                  style: text.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _open(context),
                child: const Text('Support'),
              ),
            ],
          ),
        );

      case SupportVariant.sponsored:
        return Container(
          margin: margin ?? const EdgeInsets.all(AppTheme.spacingMd),
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.outlineVariant.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite_outline,
                  color: colors.primary, size: AppTheme.iconMd),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Support Next Chapter',
                        style: text.titleSmall
                            ?.copyWith(color: colors.onSurface)),
                    const SizedBox(height: 2),
                    Text(_copy,
                        style: text.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              FilledButton.tonal(
                onPressed: () => _open(context),
                child: const Text('Support'),
              ),
            ],
          ),
        );

      case SupportVariant.card:
        return Container(
          margin: margin ?? const EdgeInsets.all(AppTheme.spacingMd),
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primaryContainer.withOpacity(0.55),
                colors.primaryContainer.withOpacity(0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.primary.withOpacity(0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.volunteer_activism_outlined,
                      color: colors.primary),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text('Support Next Chapter',
                      style: text.titleMedium
                          ?.copyWith(color: colors.onPrimaryContainer)),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(_copy,
                  style: text.bodySmall
                      ?.copyWith(color: colors.onPrimaryContainer)),
              const SizedBox(height: AppTheme.spacingMd),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.favorite_outline,
                        size: AppTheme.iconSm),
                    label: const Text('Support'),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  if (AppConfig.donateUrl.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _copyLink(context),
                      icon: const Icon(Icons.copy_outlined,
                          size: AppTheme.iconSm),
                      label: const Text('Copy link'),
                    ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
