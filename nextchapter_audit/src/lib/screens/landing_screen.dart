import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';
import '../widgets/landing/hero_section.dart';
import '../widgets/landing/features_section.dart';
import '../widgets/landing/trust_section.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: colors.surface,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: isMobile ? 108 : kToolbarHeight,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: isMobile
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppTheme.spacingSm),
                        // 1) Buttons ABOVE the brand on mobile.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => context.go('/login'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(72, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('Log In'),
                            ),
                            const SizedBox(width: AppTheme.spacingSm),
                            ElevatedButton(
                              onPressed: () => context.go('/signup'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(72, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('Sign Up'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacingSm),
                        // 2) Brand row BELOW the buttons. Words visible.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppTheme.spacingSm),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusSmall),
                              ),
                              child: Icon(Icons.favorite,
                                  size: AppTheme.iconMd, color: colors.primary),
                            ),
                            const SizedBox(width: AppTheme.spacingSm),
                            Flexible(
                              child: Text('Next Chapter',
                                  style: text.titleLarge
                                      ?.copyWith(color: colors.primary),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: AppTheme.spacingMd),
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingSm),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Icon(Icons.favorite,
                            size: AppTheme.iconMd, color: colors.primary),
                      ),
                      const SizedBox(width: AppTheme.spacingSm),
                      Text('Next Chapter',
                          style: text.titleLarge
                              ?.copyWith(color: colors.primary)),
                    ],
                  ),
            actions: isMobile
                ? const []
                : [
                    TextButton(onPressed: () => context.go('/privacy'), child: const Text('Privacy')),
                    TextButton(onPressed: () => context.go('/terms'), child: const Text('Terms')),
                    const SizedBox(width: AppTheme.spacingSm),
                    OutlinedButton(
                      onPressed: () => context.go('/login'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(80, 40)),
                      child: const Text('Log In'),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    ElevatedButton(
                      onPressed: () => context.go('/signup'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
                      child: const Text('Sign Up'),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                  ],
          ),
          const SliverToBoxAdapter(child: HeroSection()),
          const SliverToBoxAdapter(child: FeaturesSection()),
          const SliverToBoxAdapter(child: TrustSection()),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingXl),
              color: colors.surfaceContainerLow,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
                  child: Column(
                    children: [
                      Text('Ready for Your Next Chapter?', style: text.headlineMedium, textAlign: TextAlign.center),
                      const SizedBox(height: AppTheme.spacingMd),
                      Text(
                        'Join thousands of adults finding genuine connections — completely free.',
                        style: text.bodyLarge?.copyWith(color: theme.extension<AppColorsExtension>()!.subtleText),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.spacingLg),
                      SizedBox(
                        width: isMobile ? double.infinity : 300,
                        child: ElevatedButton(
                          onPressed: () => context.go('/signup'),
                          child: const Text('Create Free Account'),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXl),
                      Text(
                        'Next Chapter will never sell, rent, or share your personal information.',
                        style: text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(onPressed: () => context.go('/privacy'), child: const Text('Privacy Policy')),
                          TextButton(onPressed: () => context.go('/terms'), child: const Text('Terms of Service')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
