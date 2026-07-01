import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';

/// Canonical copy of the founder's letter. Rendered as either a full screen
/// (from Settings) or as a modal dialog on first onboarding completion.
class FounderLetterView extends StatelessWidget {
  final VoidCallback? onDismiss;
  const FounderLetterView({super.key, this.onDismiss});

  static const _paragraphs = <String>[
    'Thank you for giving Next Chapter a chance.',
    'I created this community because I believe too many apps profit from '
        'keeping people lonely instead of helping them build meaningful '
        'relationships.',
    'My promise to you is simple:',
  ];

  static const _promises = <String>[
    'Messaging will always be free.',
    'I will never sell, rent, or give away your personal information.',
    "You'll never be forced to pay just to talk with another person.",
    'Your privacy and safety will always come before profits.',
  ];

  static const _closing = <String>[
    "Whether you're looking for love, friendship, activity partners, or "
        'simply someone to talk to, I hope Next Chapter becomes a place '
        'where genuine relationships begin.',
    'Welcome to your Next Chapter.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg, vertical: AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.favorite, color: colors.primary, size: 28),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Text('Welcome to Next Chapter',
                    style: text.headlineSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingLg),
          for (final p in _paragraphs) ...[
            Text(p, style: text.bodyLarge?.copyWith(height: 1.55)),
            const SizedBox(height: AppTheme.spacingMd),
          ],
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.primary.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in _promises)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: colors.primary, size: AppTheme.iconSm),
                        const SizedBox(width: AppTheme.spacingSm),
                        Expanded(
                          child: Text(p,
                              style: text.bodyMedium?.copyWith(
                                color: colors.onPrimaryContainer,
                                height: 1.4,
                              )),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),
          for (final p in _closing) ...[
            Text(p, style: text.bodyLarge?.copyWith(height: 1.55)),
            const SizedBox(height: AppTheme.spacingMd),
          ],
          const SizedBox(height: AppTheme.spacingMd),
          Container(
            padding: const EdgeInsets.only(top: AppTheme.spacingMd),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.outlineVariant.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('— Derek Louks',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    Text('Founder',
                        style: text.bodySmall
                            ?.copyWith(color: appColors.subtleText)),
                  ],
                ),
                const Spacer(),
                if (onDismiss != null)
                  FilledButton(
                    onPressed: onDismiss,
                    child: const Text('Enter Next Chapter'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-page route rendered from Settings → About Next Chapter → Letter.
class FounderLetterScreen extends StatelessWidget {
  const FounderLetterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Letter from the Founder'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const FounderLetterView(),
        ),
      ),
    );
  }
}
