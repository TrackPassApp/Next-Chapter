import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    final features = [
      _FeatureData(Icons.search, 'Browse & Discover', 'Search by location, interests, age, and more to find people who share your values.', colors.primary),
      _FeatureData(Icons.chat_bubble_outline, 'Message Freely', 'No paywalls on messaging — ever. Start real conversations from day one.', colors.secondary),
      _FeatureData(Icons.verified_user_outlined, 'Trust & Safety', 'Multi-level verification, easy reporting, and instant blocking keep everyone safe.', colors.tertiary),
      _FeatureData(Icons.favorite_border, 'All Connection Types', 'Whether you want friendship, dating, travel partners, or activity buddies — all welcome here.', colors.primary),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppTheme.spacingMd : AppTheme.spacingXxl,
        vertical: AppTheme.spacingXxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
          child: Column(
            children: [
              Text('Why Next Chapter?', style: text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingXl),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isMobile ? 1 : (width < 900 ? 2 : 4),
                  mainAxisSpacing: AppTheme.spacingMd,
                  crossAxisSpacing: AppTheme.spacingMd,
                  mainAxisExtent: 200,
                ),
                itemCount: features.length,
                itemBuilder: (_, i) => _FeatureCard(data: features[i], colors: colors, text: text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureData {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  const _FeatureData(this.icon, this.title, this.description, this.color);
}

class _FeatureCard extends StatelessWidget {
  final _FeatureData data;
  final ColorScheme colors;
  final TextTheme text;

  const _FeatureCard({required this.data, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingSm),
            decoration: BoxDecoration(
              color: data.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(data.icon, color: data.color, size: AppTheme.iconMd),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(data.title, style: text.titleSmall),
          const SizedBox(height: AppTheme.spacingSm),
          Flexible(
            child: Text(data.description, style: text.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
