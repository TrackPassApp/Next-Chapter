import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/community_provider.dart';
import '../repositories/community_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/common/ad_banner.dart';
import '../widgets/common/my_avatar_leading.dart';
import '../widgets/common/notifications_bell.dart';
import '../widgets/support/support_next_chapter_card.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String? _quote;
  Map<String, int> _memberCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CommunityProvider>().loadRooms();
      _loadQuote();
      _loadMemberCounts();
    });
  }

  Future<void> _loadQuote() async {
    final db = SupabaseService.client;
    if (db == null) return;
    try {
      final rows = await db
          .from('daily_quotes')
          .select('quote')
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return;
      final dayOfYear = int.parse(DateTime.now()
          .difference(DateTime(DateTime.now().year))
          .inDays
          .toString());
      final idx = dayOfYear % list.length;
      if (mounted) setState(() => _quote = list[idx]['quote'] as String?);
    } catch (_) {}
  }

  Future<void> _loadMemberCounts() async {
    final db = SupabaseService.client;
    if (db == null) return;
    final rooms = context.read<CommunityProvider>().rooms;
    final counts = <String, int>{};
    for (final room in rooms) {
      try {
        final n = await db.rpc(
          'room_member_count',
          params: {'target_room_id': room.id},
        );
        counts[room.id] = (n as int?) ?? 0;
      } catch (_) {
        counts[room.id] = 0;
      }
    }
    if (mounted) setState(() => _memberCounts = counts);
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
        actions: const [NotificationsBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.loadRooms();
          _loadMemberCounts();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingLg),
          children: [
            if (_quote != null && _quote!.isNotEmpty)
              _QuoteCard(quote: _quote!),
            const AdBanner(),
            const SupportNextChapterCard(variant: SupportVariant.card),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd, AppTheme.spacingSm,
                AppTheme.spacingMd, AppTheme.spacingSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Public chat rooms — say hi, share, and connect.',
                      style: text.bodyMedium
                          ?.copyWith(color: appColors.subtleText),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/stories'),
                    icon: const Icon(Icons.stars_outlined, size: 18),
                    label: const Text('Stories'),
                  ),
                ],
              ),
            ),
            if (provider.loadingRooms)
              const Padding(
                padding: EdgeInsets.all(AppTheme.spacingLg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Text(
                  provider.error ?? 'No rooms yet. Check back soon.',
                  style: text.bodyMedium?.copyWith(color: appColors.subtleText),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final room in provider.rooms)
                _RoomTile(
                  room: room,
                  memberCount: _memberCounts[room.id] ?? 0,
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

class _QuoteCard extends StatelessWidget {
  final String quote;
  const _QuoteCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacingMd, AppTheme.spacingMd,
        AppTheme.spacingMd, AppTheme.spacingSm,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wb_sunny_outlined, color: colors.primary),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily inspiration',
                    style: text.labelSmall?.copyWith(color: colors.primary)),
                const SizedBox(height: 2),
                Text(quote,
                    style: text.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  final int memberCount;
  final VoidCallback onTap;
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _RoomTile({
    required this.room,
    required this.memberCount,
    required this.onTap,
    required this.colors,
    required this.text,
    required this.appColors,
  });

  IconData get _icon {
    switch (room.category) {
      case 'region':   return Icons.location_on_outlined;
      case 'interest': return Icons.tag_outlined;
      case 'advice':   return Icons.lightbulb_outline;
      case 'connect':  return Icons.groups_outlined;
      default:         return Icons.forum_outlined;
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
                      Row(children: [
                        Expanded(child: Text(room.name, style: text.titleSmall)),
                        if (memberCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '$memberCount active',
                              style: text.labelSmall
                                  ?.copyWith(color: appColors.subtleText),
                            ),
                          ),
                      ]),
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
