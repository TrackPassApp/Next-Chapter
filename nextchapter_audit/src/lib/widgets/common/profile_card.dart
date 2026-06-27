import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/user_profile.dart';
import '../../theme/theme.dart';

class ProfileCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;

  const ProfileCard({super.key, required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (profile.photoUrls.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: profile.photoUrls.first,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: colors.surfaceContainerHighest,
                        child: Icon(Icons.person, size: AppTheme.iconLg, color: appColors.subtleText),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: colors.surfaceContainerHighest,
                        child: Icon(Icons.person, size: AppTheme.iconLg, color: appColors.subtleText),
                      ),
                    )
                  else
                    Container(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.person, size: AppTheme.iconLg, color: appColors.subtleText),
                    ),
                  Positioned(
                    top: AppTheme.spacingSm,
                    right: AppTheme.spacingSm,
                    child: _OnlineIndicator(isOnline: profile.isOnline, appColors: appColors, colors: colors),
                  ),
                  if (profile.hasAnyVerification)
                    Positioned(
                      top: AppTheme.spacingSm,
                      left: AppTheme.spacingSm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: appColors.verified,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: AppTheme.iconSm - 2, color: colors.onPrimary),
                            const SizedBox(width: 2),
                            Text('Verified', style: text.labelSmall?.copyWith(color: colors.onPrimary, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile.firstName}, ${profile.age}',
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTheme.spacingXs),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: AppTheme.iconSm - 2, color: appColors.subtleText),
                        const SizedBox(width: AppTheme.spacingXs),
                        Expanded(
                          child: Text(
                            '${profile.city}, ${profile.state}',
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: AppTheme.spacingXs,
                      runSpacing: AppTheme.spacingXs,
                      children: profile.lookingFor.take(2).map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(AppTheme.spacingXs),
                        ),
                        child: Text(tag, style: text.labelSmall?.copyWith(color: colors.primary, fontSize: 10)),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineIndicator extends StatelessWidget {
  final bool isOnline;
  final AppColorsExtension appColors;
  final ColorScheme colors;

  const _OnlineIndicator({required this.isOnline, required this.appColors, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isOnline ? appColors.online : appColors.subtleText,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
      ),
    );
  }
}
