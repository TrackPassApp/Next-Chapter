import 'package:flutter/material.dart';
import '../../models/conversation.dart';
import '../../theme/theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const MessageBubble({super.key, required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isMe) const Spacer(flex: 2),
          Flexible(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 2),
              decoration: BoxDecoration(
                color: isMe ? colors.primary : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppTheme.radiusMedium),
                  topRight: const Radius.circular(AppTheme.radiusMedium),
                  bottomLeft: Radius.circular(isMe ? AppTheme.radiusMedium : AppTheme.spacingXs),
                  bottomRight: Radius.circular(isMe ? AppTheme.spacingXs : AppTheme.radiusMedium),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    message.text,
                    style: text.bodyMedium?.copyWith(color: isMe ? colors.onPrimary : colors.onSurface),
                  ),
                  const SizedBox(height: AppTheme.spacingXs),
                  Text(
                    _formatTime(message.timestamp),
                    style: text.labelSmall?.copyWith(
                      color: isMe ? colors.onPrimary.withOpacity(0.7) : colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isMe) const Spacer(flex: 2),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour > 12 ? time.hour - 12 : time.hour;
    final m = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
