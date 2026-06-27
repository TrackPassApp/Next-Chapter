import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppTheme.spacingMd : AppTheme.spacingXxl,
        vertical: AppTheme.spacingXxl,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withOpacity(0.3),
            colors.surface,
            colors.secondaryContainer.withOpacity(0.2),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
          child: Column(
            children: [
              Text(
                'Find Real Connections.\nNo Paywalls. No Games.',
                style: isMobile ? text.headlineMedium : text.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  'Next Chapter is a free social platform for adults 18+ looking for friendship, dating, activity partners, and genuine human connections.',
                  style: text.bodyLarge?.copyWith(color: appColors.subtleText, height: 1.7),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXl),
              Wrap(
                spacing: AppTheme.spacingMd,
                runSpacing: AppTheme.spacingMd,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/signup'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Get Started Free'),
                    ),
                  ),
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/browse'),
                      icon: const Icon(Icons.search),
                      label: const Text('Browse Profiles'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingXl),
              Wrap(
                spacing: AppTheme.spacingXl,
                runSpacing: AppTheme.spacingMd,
                alignment: WrapAlignment.center,
                children: [
                  _StatChip(icon: Icons.message_outlined, label: 'Free Messaging', colors: colors, text: text),
                  _StatChip(icon: Icons.verified_user_outlined, label: 'Verified Profiles', colors: colors, text: text),
                  _StatChip(icon: Icons.shield_outlined, label: 'Privacy First', colors: colors, text: text),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colors;
  final TextTheme text;

  const _StatChip({required this.icon, required this.label, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppTheme.iconMd, color: colors.primary),
        const SizedBox(width: AppTheme.spacingSm),
        Text(label, style: text.labelLarge?.copyWith(color: colors.primary)),
      ],
    );
  }
}
