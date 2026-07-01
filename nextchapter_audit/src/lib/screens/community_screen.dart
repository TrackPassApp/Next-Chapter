import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/community_provider.dart';
import '../repositories/community_repository.dart';
import '../theme/theme.dart';
import '../widgets/common/ad_banner.dart';
import '../widgets/common/my_avatar_leading.dart';
import '../widgets/support/support_next_chapter_card.dart';

/// Room list (Beta community feature). No ads inside chat streams.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommunityProvider>().loadRooms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final provider = context.watch<CommunityProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: const MyAvatarLeading(),
        leadingWidth: 64,
        title: const Text('Community'),
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadRooms(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingLg),
          children: [
            const AdBanner(),
            const SupportNextChapterCard(variant: SupportVariant.card),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd, AppTheme.spacingSm,
                AppTheme.spacingMd, AppTheme.spacingSm,
              ),
              child: Text(
                'Public chat rooms — say hi, share, and connect.',
                style: text.bodyMedium?.copyWith(color: appColors.subtleText),
              ),
            ),
            if (provider.loadingRooms)
              const Padding(
                padding: EdgeInsets.all(AppTheme.spacingLg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.error != null)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.error_outline, color: appColors.danger),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: AppTheme.spacingSm),
                    ElevatedButton(
                      onPressed: provider.loadRooms,
                      child: const Text('Retry'),
                    ),
                  ]),
                ),
              )
            else if (provider.rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Text(
                  'No rooms yet. Check back soon.',
                  style: text.bodyMedium?.copyWith(color: appColors.subtleText),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final room in provider.rooms)
                _RoomTile(
                  room: room,
                  onTap: () => context.push('/community/${room.slug}'),
                  colors: colors,
                  text: text,
                  appColors: appColors,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _RoomTile({
    required this.room,
    required this.onTap,
    required this.colors,
    required this.text,
    required this.appColors,
  });

  IconData get _icon {
    switch (room.category) {
      case 'region':
        return Icons.location_on_outlined;
      case 'interest':
        return Icons.tag_outlined;
      case 'advice':
        return Icons.lightbulb_outline;
      case 'connect':
        return Icons.groups_outlined;
      default:
        return Icons.forum_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: 4),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.outlineVariant.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(_icon, color: colors.primary),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name, style: text.titleSmall),
                      if (room.description != null && room.description!.isNotEmpty)
                        Text(room.description!,
                            style: text.bodySmall
                                ?.copyWith(color: appColors.subtleText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: appColors.subtleText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
