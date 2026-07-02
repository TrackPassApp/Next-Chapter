import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/notifications_provider.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/support/support_next_chapter_card.dart';

/// Activity feed for Beta — combines the user's recent notifications with
/// public discovery items so the screen is never empty.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>> _newMembers = [];
  List<Map<String, dynamic>> _stories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<NotificationsProvider>().refresh();
      await _loadDiscovery();
    });
  }

  Future<void> _loadDiscovery() async {
    final db = SupabaseService.client;
    if (db == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final members = await db
          .from('profiles')
          .select('id, first_name, city, state, created_at')
          .eq('is_complete', true)
          .eq('is_deleted', false)
          .eq('is_suspended', false)
          .order('created_at', ascending: false)
          .limit(8);
      _newMembers = List<Map<String, dynamic>>.from(members as List);

      final stories = await db
          .from('success_stories')
          .select('id, title, body, created_at,'
              ' author:profiles!success_stories_author_id_fkey(first_name)')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(3);
      _stories = List<Map<String, dynamic>>.from(stories as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final notifs = context.watch<NotificationsProvider>().items.take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<NotificationsProvider>().refresh();
          await _loadDiscovery();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
          children: [
            _SectionHeader(
              icon: Icons.notifications_outlined,
              title: 'Recent notifications',
              actionLabel: 'See all',
              onAction: () => context.push('/notifications'),
            ),
            if (notifs.isEmpty)
              _EmptyRow('No notifications yet.', appColors)
            else
              for (final n in notifs)
                ListTile(
                  leading:
                      Icon(Icons.notifications, color: colors.primary),
                  title: Text(n.title, style: text.titleSmall),
                  subtitle: Text(
                    n.body ?? DateFormat.MMMd().add_jm().format(n.createdAt.toLocal()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    if (n.link != null && n.link!.isNotEmpty) {
                      context.push(n.link!);
                    } else {
                      context.push('/notifications');
                    }
                  },
                ),
            const Divider(),
            _SectionHeader(
              icon: Icons.person_add_outlined,
              title: 'New members',
              actionLabel: 'Browse',
              onAction: () => context.go('/browse'),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_newMembers.isEmpty)
              _EmptyRow('No new members yet.', appColors)
            else
              SizedBox(
                height: 108,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
                  scrollDirection: Axis.horizontal,
                  itemCount: _newMembers.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppTheme.spacingSm),
                  itemBuilder: (_, i) {
                    final m = _newMembers[i];
                    return InkWell(
                      onTap: () => context.go('/browse/profile/${m['id']}'),
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.all(AppTheme.spacingSm),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                          border: Border.all(
                              color: colors.outlineVariant.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: colors.primaryContainer,
                              child: Text(
                                (m['first_name'] as String? ?? '?')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(color: colors.primary),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(m['first_name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall),
                            Text(
                              [m['city'], m['state']]
                                  .where((s) => (s as String?)?.isNotEmpty == true)
                                  .join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall
                                  ?.copyWith(color: appColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const Divider(),
            _SectionHeader(
              icon: Icons.stars_outlined,
              title: 'Success Stories',
              actionLabel: 'All stories',
              onAction: () => context.push('/stories'),
            ),
            if (_stories.isEmpty)
              _EmptyRow('No stories yet — share yours.', appColors)
            else
              for (final s in _stories)
                Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd, vertical: 4),
                  child: ListTile(
                    leading: Icon(Icons.favorite, color: colors.primary),
                    title: Text(s['title'] ?? ''),
                    subtitle: Text(s['body'] ?? '',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => context.push('/stories'),
                  ),
                ),
            const Padding(
              padding: EdgeInsets.only(top: AppTheme.spacingMd),
              child: SupportNextChapterCard(variant: SupportVariant.sponsored),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      child: Row(children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppTheme.spacingSm),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ]),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  final AppColorsExtension appColors;
  const _EmptyRow(this.text, this.appColors);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: appColors.subtleText)),
    );
  }
}
