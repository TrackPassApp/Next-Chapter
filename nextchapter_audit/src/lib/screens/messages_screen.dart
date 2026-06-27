import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/theme.dart';
import '../widgets/common/conversation_tile.dart';
import '../widgets/common/my_avatar_leading.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileId = context.read<ProfileProvider>().profileId;
      if (profileId == null) return;
      context.read<MessagesProvider>().bindProfile(profileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final provider = context.watch<MessagesProvider>();
    final profileId = context.watch<ProfileProvider>().profileId;

    return Scaffold(
      appBar: AppBar(
        leading: const MyAvatarLeading(),
        leadingWidth: 64,
        title: const Text('Messages'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingMd),
            child: Center(
              child: Text(
                'Free & unlimited messaging',
                style: text.labelSmall?.copyWith(color: appColors.success),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
                child: Row(
                  children: [
                    Expanded(
                      child: _TabButton(
                        label: 'Messages',
                        isSelected: provider.selectedTab == 0,
                        onTap: () => provider.setTab(0),
                        colors: colors,
                        text: text,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Badge(
                        isLabelVisible: provider.requestCount > 0,
                        label: Text('${provider.requestCount}'),
                        child: _TabButton(
                          label: 'Requests',
                          isSelected: provider.selectedTab == 1,
                          onTap: () => provider.setTab(1),
                          colors: colors,
                          text: text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: profileId == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingLg),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline, size: 48, color: appColors.subtleText),
                              const SizedBox(height: AppTheme.spacingMd),
                              Text('Finish your profile to start messaging.', style: text.bodyMedium, textAlign: TextAlign.center),
                              const SizedBox(height: AppTheme.spacingMd),
                              ElevatedButton(onPressed: () => context.go('/edit-profile'), child: const Text('Set up profile')),
                            ],
                          ),
                        ),
                      )
                    : provider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.error != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 48, color: appColors.danger),
                                    const SizedBox(height: AppTheme.spacingSm),
                                    Text(provider.error!, style: text.bodyMedium, textAlign: TextAlign.center),
                                    const SizedBox(height: AppTheme.spacingMd),
                                    ElevatedButton(onPressed: provider.loadConversations, child: const Text('Retry')),
                                  ],
                                ),
                              )
                            : provider.conversations.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.chat_bubble_outline, size: AppTheme.spacingXxl, color: appColors.subtleText),
                                        const SizedBox(height: AppTheme.spacingMd),
                                        Text(
                                          provider.selectedTab == 0 ? 'No messages yet' : 'No message requests',
                                          style: text.titleMedium,
                                        ),
                                        const SizedBox(height: AppTheme.spacingSm),
                                        Text('Start browsing profiles and say hello!', style: text.bodySmall),
                                        const SizedBox(height: AppTheme.spacingMd),
                                        OutlinedButton(
                                          onPressed: () => context.go('/browse'),
                                          style: OutlinedButton.styleFrom(minimumSize: const Size(200, 44)),
                                          child: const Text('Browse Profiles'),
                                        ),
                                      ],
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: provider.loadConversations,
                                    child: ListView.separated(
                                      itemCount: provider.conversations.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                                      itemBuilder: (context, index) {
                                        final convo = provider.conversations[index];
                                        return ConversationTile(
                                          conversation: convo,
                                          onTap: () => context.go('/messages/${convo.id}'),
                                          // Beta: no soft delete yet — disable swipe-to-delete.
                                          onDelete: () {},
                                        );
                                      },
                                    ),
                                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colors;
  final TextTheme text;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? colors.primary : Colors.transparent,
              width: AppTheme.borderSelected,
            ),
          ),
        ),
        child: Text(
          label,
          style: text.labelLarge?.copyWith(color: isSelected ? colors.primary : colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
