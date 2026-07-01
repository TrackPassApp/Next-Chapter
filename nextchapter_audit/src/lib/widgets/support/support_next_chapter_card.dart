import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../theme/theme.dart';

/// Reusable "Support Next Chapter" surface. Rendered in three sizes:
/// banner / card / sponsored. Copy stays constant across placements.
enum SupportVariant { banner, card, sponsored }

class SupportNextChapterCard extends StatelessWidget {
  final SupportVariant variant;
  final EdgeInsetsGeometry? margin;
  const SupportNextChapterCard({
    super.key,
    this.variant = SupportVariant.card,
    this.margin,
  });

  static const String copy =
      "Next Chapter will always keep messaging free. If you'd like to help "
      'support development and keep this community growing, you can support '
      'the project here.';

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
                  style: text.labelMedium
                      ?.copyWith(color: colors.onPrimaryContainer),
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
                    Text(copy,
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
              Row(children: [
                Icon(Icons.volunteer_activism_outlined,
                    color: colors.primary),
                const SizedBox(width: AppTheme.spacingSm),
                Text('Support Next Chapter',
                    style: text.titleMedium
                        ?.copyWith(color: colors.onPrimaryContainer)),
              ]),
              const SizedBox(height: AppTheme.spacingSm),
              Text(copy,
                  style: text.bodySmall
                      ?.copyWith(color: colors.onPrimaryContainer)),
              const SizedBox(height: AppTheme.spacingMd),
              FilledButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.favorite_outline,
                    size: AppTheme.iconSm),
                label: const Text('View options'),
              ),
            ],
          ),
        );
    }
  }

  void _open(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const SupportDialog(),
    );
  }
}

/// Dialog listing every configured payment provider (BMC, PayPal, Stripe).
/// Providers with an empty URL are hidden. If none are configured, users see
/// a friendly "coming soon" state.
class SupportDialog extends StatelessWidget {
  const SupportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    final providers = <_Provider>[
      if (AppConfig.bmcUrl.trim().isNotEmpty)
        _Provider(
          label: 'Buy Me a Coffee',
          emoji: '\u2615', // ☕
          url: AppConfig.bmcUrl.trim(),
          color: const Color(0xFFFFDD00),
        ),
      if (AppConfig.paypalUrl.trim().isNotEmpty)
        _Provider(
          label: 'PayPal',
          icon: Icons.account_balance_wallet_outlined,
          url: AppConfig.paypalUrl.trim(),
          color: const Color(0xFF003087),
        ),
      if (AppConfig.stripeUrl.trim().isNotEmpty)
        _Provider(
          label: 'Stripe',
          icon: Icons.payment_outlined,
          url: AppConfig.stripeUrl.trim(),
          color: const Color(0xFF635BFF),
        ),
    ];
    // Legacy DONATE_URL fallback if no provider-specific key is configured.
    if (providers.isEmpty && AppConfig.donateUrl.trim().isNotEmpty) {
      providers.add(_Provider(
        label: 'Support',
        icon: Icons.favorite_outline,
        url: AppConfig.donateUrl.trim(),
        color: colors.primary,
      ));
    }

    return AlertDialog(
      icon: Icon(Icons.volunteer_activism_outlined,
          color: colors.primary, size: 40),
      title: const Text('Support Next Chapter'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(children: [
                  Icon(Icons.chat_bubble_outline,
                      size: AppTheme.iconSm, color: colors.primary),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Text(
                      SupportNextChapterCard.copy,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              if (providers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                  child: Text(
                    'Donation options will appear here soon. Thanks for '
                    'wanting to help.',
                    style: text.bodyMedium,
                  ),
                )
              else
                for (final p in providers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                    child: _ProviderTile(p: p),
                  ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                'One-time only. No subscriptions. No premium messaging. '
                'Donation never affects who you can talk to or who sees you.',
                style: text.labelSmall
                    ?.copyWith(color: theme
                        .extension<AppColorsExtension>()!
                        .subtleText),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  // Local helper used above.
  static bool providersIsEmpty() =>
      AppConfig.bmcUrl.trim().isEmpty &&
      AppConfig.paypalUrl.trim().isEmpty &&
      AppConfig.stripeUrl.trim().isEmpty;
}

class _Provider {
  final String label;
  final String? emoji;
  final IconData? icon;
  final String url;
  final Color color;
  _Provider({
    required this.label,
    this.emoji,
    this.icon,
    required this.url,
    required this.color,
  });
}

class _ProviderTile extends StatelessWidget {
  final _Provider p;
  const _ProviderTile({required this.p});

  Future<void> _launch(BuildContext context) async {
    final uri = Uri.tryParse(p.url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open ${p.label}')));
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: p.url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.label} link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: p.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: p.color.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSm, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: p.emoji != null
                ? Text(p.emoji!, style: const TextStyle(fontSize: 22))
                : Icon(p.icon ?? Icons.link, color: p.color),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Text(p.label,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: Icon(Icons.copy_outlined,
                size: AppTheme.iconSm, color: colors.onSurfaceVariant),
            onPressed: () => _copy(context),
          ),
          FilledButton.tonal(
            onPressed: () => _launch(context),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
