import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/messages_provider.dart';
import '../theme/theme.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/chat_input.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagesProvider>().loadMessages(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final provider = context.watch<MessagesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Conversation', style: text.titleMedium),
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
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        itemCount: provider.currentMessages.length,
                        itemBuilder: (_, i) {
                          final msg = provider.currentMessages[i];
                          final isMe = msg.senderId == 'me';
                          return MessageBubble(message: msg, isMe: isMe);
                        },
                      ),
              ),
              ChatInput(
                onSend: (text) {
                  provider.sendMessage(text);
                  Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
