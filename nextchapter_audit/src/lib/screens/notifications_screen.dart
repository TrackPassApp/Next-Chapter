import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/notifications_provider.dart';
import '../theme/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().refresh();
    });
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'private_message': return Icons.chat_bubble_outline;
      case 'room_reply': return Icons.forum_outlined;
      case 'mention': return Icons.alternate_email;
      case 'verification': return Icons.verified_user_outlined;
      case 'moderator_warning': return Icons.report_gmailerrorred_outlined;
      case 'admin_announcement': return Icons.campaign_outlined;
      case 'match_new': return Icons.favorite_border;
      default: return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/browse'),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/notifications/settings'),
            icon: const Icon(Icons.tune),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'read') provider.markAllRead();
              if (v == 'clear') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete all notifications?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete all')),
                    ],
                  ),
                );
                if (ok == true) await provider.deleteAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Mark all read')),
              PopupMenuItem(value: 'clear', child: Text('Delete all')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: provider.items.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingXl),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none,
                            size: 56, color: appColors.subtleText),
                        const SizedBox(height: AppTheme.spacingMd),
                        Text('You are all caught up.',
                            style: text.bodyMedium
                                ?.copyWith(color: appColors.subtleText)),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: provider.items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colors.outlineVariant.withOpacity(0.3),
                ),
                itemBuilder: (_, i) {
                  final n = provider.items[i];
                  return Dismissible(
                    key: ValueKey(n.id),
                    background: Container(
                      color: appColors.danger.withOpacity(0.9),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => provider.deleteOne(n.id),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: n.isUnread
                            ? colors.primaryContainer
                            : colors.surface,
                        child: Icon(_iconFor(n.kind), color: colors.primary),
                      ),
                      title: Text(n.title,
                          style: text.titleSmall?.copyWith(
                            fontWeight:
                                n.isUnread ? FontWeight.w700 : FontWeight.w400,
                          )),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (n.body != null && n.body!.isNotEmpty)
                            Text(n.body!,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(
                            DateFormat.MMMd()
                                .add_jm()
                                .format(n.createdAt.toLocal()),
                            style: text.labelSmall
                                ?.copyWith(color: appColors.subtleText),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: Icon(Icons.close,
                            size: 18, color: appColors.subtleText),
                        onPressed: () => provider.deleteOne(n.id),
                      ),
                      onTap: () async {
                        await provider.markOneRead(n.id);
                        if (!context.mounted) return;
                        if (n.link != null && n.link!.isNotEmpty) {
                          context.push(n.link!);
                        } else {
                          // No target — show the full body so nothing feels broken.
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(n.title),
                              content: SingleChildScrollView(
                                child: Text(n.body ?? ''),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
