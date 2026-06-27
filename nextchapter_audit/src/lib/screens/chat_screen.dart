import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/theme.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/chat_input.dart';
import '../widgets/common/verification_badges.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final messages = context.read<MessagesProvider>();
      final myProfileId = context.read<ProfileProvider>().profileId;
      if (myProfileId != null && messages.myProfileId == null) {
        await messages.bindProfile(myProfileId);
      }
      await messages.openConversation(widget.conversationId);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    // Detach realtime + clear state for this conversation. We do this here
    // rather than in deactivate so the listener survives quick rebuilds.
    final messages = context.read<MessagesProvider>();
    messages.closeActiveConversation();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final messages = context.watch<MessagesProvider>();
    final myProfileId = messages.myProfileId;

    // Resolve the other participant from the conversation list (already cached).
    Conversation? activeConv;
    try {
      activeConv = messages.conversations.firstWhere((c) => c.id == widget.conversationId);
    } catch (_) {
      activeConv = null;
    }

    // Auto-scroll on new message ticks.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                activeConv?.otherUserName ?? 'Conversation',
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
            ),
            if (activeConv != null) ...[
              const SizedBox(width: 6),
              VerificationBadges(
                email: activeConv.otherEmailVerified,
                phone: activeConv.otherPhoneVerified,
                selfie: activeConv.otherSelfieVerified,
                id: activeConv.otherIdVerified,
              ),
            ],
          ],
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
                color: colors.primaryContainer.withOpacity(0.3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: AppTheme.iconSm, color: colors.primary),
                    const SizedBox(width: AppTheme.spacingSm),
                    Text('Messages are free and unlimited', style: text.labelSmall?.copyWith(color: colors.primary)),
                  ],
                ),
              ),
              Expanded(
                child: messages.loadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : messages.currentMessages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppTheme.spacingLg),
                              child: Text(
                                'Say hi — your conversation starts here.',
                                style: text.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppTheme.spacingMd),
                            itemCount: messages.currentMessages.length,
                            itemBuilder: (_, i) {
                              final msg = messages.currentMessages[i];
                              final isMe = msg.senderId == myProfileId;
                              return MessageBubble(message: msg, isMe: isMe);
                            },
                          ),
              ),
              ChatInput(
                onSend: (txt) async {
                  final ok = await messages.sendMessage(txt);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not send — check your connection.')),
                    );
                  }
                  _scrollToBottom();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
