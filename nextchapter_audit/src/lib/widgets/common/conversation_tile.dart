import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/conversation.dart';
import '../../theme/theme.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool enableSwipeDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onDelete,
    this.enableSwipeDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final tile = ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        ),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: AppTheme.avatarSm / 2 + 4,
              backgroundColor: colors.surfaceContainerHighest,
              backgroundImage: conversation.otherUserPhoto.isNotEmpty
                  ? CachedNetworkImageProvider(conversation.otherUserPhoto)
                  : null,
              child: conversation.otherUserPhoto.isEmpty
                  ? Icon(Icons.person, color: appColors.subtleText)
                  : null,
            ),
            if (conversation.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: appColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          conversation.otherUserName,
          style: text.titleSmall?.copyWith(
            fontWeight: conversation.unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          conversation.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            fontWeight: conversation.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
            color: conversation.unreadCount > 0 ? colors.onSurface : appColors.subtleText,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatTime(conversation.lastMessageTime), style: text.labelSmall),
            if (conversation.unreadCount > 0) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: text.labelSmall?.copyWith(color: colors.onPrimary, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      );

    if (!enableSwipeDelete) return tile;

    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppTheme.spacingMd),
        color: appColors.danger,
        child: Icon(Icons.delete_outline, color: colors.onError),
      ),
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
