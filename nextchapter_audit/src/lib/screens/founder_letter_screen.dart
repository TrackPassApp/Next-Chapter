import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';

/// Three-section founder statement rendered as a `TabBar`:
///   1. Letter from the Founder
///   2. My Promise
///   3. What We Believe
///
/// Kept intentionally simple. No overlays, no diagnostics, no build stamps.
class FounderLetterView extends StatelessWidget {
  final VoidCallback? onDismiss;
  const FounderLetterView({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Letter'),
              Tab(text: 'My Promise'),
              Tab(text: 'What We Believe'),
            ],
          ),
          SizedBox(
            height: 520,
            child: TabBarView(
              children: [
                _LetterTab(onDismiss: onDismiss),
                const _PromiseTab(),
                const _BeliefsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LetterTab extends StatelessWidget {
  final VoidCallback? onDismiss;
  const _LetterTab({this.onDismiss});

  static const _paragraphs = <String>[
    'Thank you for giving Next Chapter a chance.',
    'I created this community because I believe too many apps profit from '
        'keeping people lonely instead of helping them build meaningful '
        'relationships.',
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
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
                  style: text.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: AppTheme.spacingLg),
          for (final p in _paragraphs) ...[
            Text(p, style: text.bodyLarge?.copyWith(height: 1.55)),
            const SizedBox(height: AppTheme.spacingMd),
          ],
          const SizedBox(height: AppTheme.spacingSm),
          Container(
            padding: const EdgeInsets.only(top: AppTheme.spacingMd),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.outlineVariant.withOpacity(0.3)),
              ),
            ),
            child: Row(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('— Derek Louks',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
            ]),
          ),
        ],
      ),
    );
  }
}

class _PromiseTab extends StatelessWidget {
  const _PromiseTab();

  static const _promises = <String>[
    'Messaging will always be free.',
    'I will never sell, rent, or give away your personal information.',
    "You'll never be forced to pay just to talk with another person.",
    'Your privacy and safety will always come before profits.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Promise',
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            'These are the promises Next Chapter is built on. They are the '
            'reason this project exists and the reason I keep working on it.',
            style: text.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppTheme.spacingMd),
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
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
                                  height: 1.45)),
                        ),
                      ],
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

class _BeliefsTab extends StatelessWidget {
  const _BeliefsTab();

  static const _beliefs = <(String, String)>[
    (
      'Everyone deserves connection.',
      'Dating apps, friendship, community — real relationships shouldn\'t be '
          'gated behind a paywall or a matchmaking fee.'
    ),
    (
      'You are more than an algorithm.',
      'We show you people. We don\'t score them, rank them, or hide them '
          'behind engagement metrics.'
    ),
    (
      'Safety is a feature, not a checkbox.',
      'Verification, moderation, block, report, and a real audit trail are '
          'part of the free product — not premium add-ons.'
    ),
    (
      'Loneliness deserves better than a subscription.',
      'The industry has been telling lonely people to keep paying. We think '
          'that\'s the wrong answer.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What We Believe',
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTheme.spacingMd),
          for (final b in _beliefs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.favorite,
                        size: AppTheme.iconSm, color: colors.primary),
                  ),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.$1,
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(b.$2,
                            style: text.bodySmall?.copyWith(height: 1.5)),
                      ],
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
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/about'),
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
