import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About Next Chapter'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            children: [
              Row(
                children: [
                  Icon(Icons.favorite, color: colors.primary),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text('Next Chapter',
                      style: text.headlineSmall),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                'Dating, friendship, activity partners, and community — 100% '
                'free messaging, privacy first.',
                style: text.bodyMedium?.copyWith(color: appColors.subtleText),
              ),
              const SizedBox(height: AppTheme.spacingLg),
              _Tile(
                icon: Icons.auto_stories_outlined,
                title: 'Letter from the Founder',
                subtitle: 'Why Next Chapter exists.',
                onTap: () => context.push('/about/letter'),
              ),
              _Tile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'How we handle your data.',
                onTap: () => context.push('/privacy'),
              ),
              _Tile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                subtitle: 'The community agreement.',
                onTap: () => context.push('/terms'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
