import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/theme.dart';

/// Bell icon for the AppBar. Shows unread count + opens a slide-over sheet
/// with the notifications list. Falls back to a full route on mobile.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: provider.unreadCount > 0,
        label: Text('${provider.unreadCount}'),
        backgroundColor: appColors.danger,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
