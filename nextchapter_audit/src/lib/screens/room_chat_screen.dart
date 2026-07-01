import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/community_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/community_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

/// Individual room chat view. No ads inside the message stream.
class RoomChatScreen extends StatefulWidget {
  final String slug;
  const RoomChatScreen({super.key, required this.slug});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  ChatRoom? _room;
  List<Map<String, dynamic>> _pinned = [];

  Future<void> _loadPinned(String roomId) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      final rows = await client
          .from('room_pinned_messages')
          .select(
            'message_id, pinned_at,'
            ' msg:room_messages!room_pinned_messages_message_id_fkey('
            '   id, body, deleted_at,'
            '   sender:profiles!room_messages_sender_id_fkey(first_name)'
            ' )',
          )
          .eq('room_id', roomId)
          .order('pinned_at', ascending: false);
      _pinned = List<Map<String, dynamic>>.from(rows as List);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<CommunityProvider>();
      if (provider.rooms.isEmpty) await provider.loadRooms();
      _room = provider.rooms.firstWhere(
        (r) => r.slug == widget.slug,
        orElse: () => provider.rooms.isNotEmpty
            ? provider.rooms.first
            : ChatRoom(
                id: '',
                slug: widget.slug,
                name: widget.slug,
                description: null,
                category: 'general',
                sortOrder: 0,
              ),
      );
      if (_room != null && _room!.id.isNotEmpty) {
        await provider.openRoom(_room!.id);
        await _loadPinned(_room!.id);
        _scrollToEnd();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    context.read<CommunityProvider>().leaveRoom();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final provider = context.read<CommunityProvider>();
    _controller.clear();
    final err = await provider.send(text);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      _scrollToEnd();
    }
  }

  Future<void> _report(RoomMessage m) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report this message'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, reasonCtrl.text.trim()),
              child: const Text('Report')),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await context
          .read<CommunityProvider>()
          .report(m.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — our team will review this.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<ProfileProvider>().profile;
    final myProfileId = myProfile?.id;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final title = _room?.name ?? widget.slug;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/community'),
        ),
        title: Text(title),
      ),
      body: Column(
        children: [
          if (_room != null) _RoomHeader(room: _room!, pinned: _pinned),
          Expanded(
            child: provider.loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : provider.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingLg),
                          child: Text(
                            'No messages yet. Be the first to say hi.',
                            style: text.bodyMedium
                                ?.copyWith(color: appColors.subtleText),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingMd,
                            vertical: AppTheme.spacingSm),
                        itemCount: provider.messages.length,
                        itemBuilder: (_, i) {
                          final m = provider.messages[i];
                          final mine = m.senderId == myProfileId;
                          return _RoomMessageTile(
                            message: m,
                            isMine: mine,
                            colors: colors,
                            text: text,
                            appColors: appColors,
                            onOpenProfile: () =>
                                context.push('/browse/profile/${m.senderId}'),
                            onReport: mine ? null : () => _report(m),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(
                      color: colors.outlineVariant.withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: auth.isLoggedIn && myProfileId != null,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: auth.isLoggedIn
                            ? 'Type a message…'
                            : 'Sign in to chat',
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXl),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingMd,
                            vertical: AppTheme.spacingSm),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed:
                        (auth.isLoggedIn && myProfileId != null) ? _send : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomMessageTile extends StatelessWidget {
  final RoomMessage message;
  final bool isMine;
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;
  final VoidCallback onOpenProfile;
  final VoidCallback? onReport;

  const _RoomMessageTile({
    required this.message,
    required this.isMine,
    required this.colors,
    required this.text,
    required this.appColors,
    required this.onOpenProfile,
    required this.onReport,
  });

  String _timeLabel() {
    final now = DateTime.now();
    final d = message.createdAt.toLocal();
    if (now.difference(d).inDays == 0) {
      return DateFormat.jm().format(d);
    }
    return DateFormat.MMMd().add_jm().format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '(message removed by moderator)',
          style: text.bodySmall?.copyWith(
              color: appColors.subtleText, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onOpenProfile,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: colors.primaryContainer,
              backgroundImage: message.senderPhotoUrl != null
                  ? NetworkImage(message.senderPhotoUrl!)
                  : null,
              child: message.senderPhotoUrl == null
                  ? Icon(Icons.person, color: colors.primary, size: 20)
                  : null,
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onOpenProfile,
                      child: Text(
                        message.senderFirstName ?? 'Member',
                        style: text.labelLarge
                            ?.copyWith(color: colors.primary),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    Text(_timeLabel(),
                        style: text.labelSmall
                            ?.copyWith(color: appColors.subtleText)),
                    const Spacer(),
                    if (onReport != null)
                      IconButton(
                        icon: Icon(Icons.flag_outlined,
                            size: AppTheme.iconSm,
                            color: appColors.subtleText),
                        onPressed: onReport,
                        tooltip: 'Report',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(message.body, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatefulWidget {
  final ChatRoom room;
  final List<Map<String, dynamic>> pinned;
  const _RoomHeader({required this.room, required this.pinned});

  @override
  State<_RoomHeader> createState() => _RoomHeaderState();
}

class _RoomHeaderState extends State<_RoomHeader> {
  bool _rulesOpen = false;
  bool _pinnedOpen = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final visiblePinned = widget.pinned.where((p) {
      final msg = p['msg'] as Map?;
      if (msg == null) return false;
      return msg['deleted_at'] == null;
    }).toList();

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.room.description != null &&
              widget.room.description!.isNotEmpty)
            Text(widget.room.description!,
                style: text.bodySmall
                    ?.copyWith(color: appColors.subtleText)),
          if ((widget.room.description ?? '').isNotEmpty)
            const SizedBox(height: 4),
          Row(children: [
            InkWell(
              onTap: () => setState(() => _rulesOpen = !_rulesOpen),
              child: Chip(
                avatar: Icon(Icons.gavel,
                    size: 14, color: appColors.subtleText),
                label: Text(_rulesOpen ? 'Hide rules' : 'Rules',
                    style: text.labelSmall),
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (visiblePinned.isNotEmpty) ...[
              const SizedBox(width: AppTheme.spacingSm),
              InkWell(
                onTap: () => setState(() => _pinnedOpen = !_pinnedOpen),
                child: Chip(
                  avatar: Icon(Icons.push_pin,
                      size: 14, color: colors.primary),
                  label: Text(
                      '${visiblePinned.length} pinned',
                      style: text.labelSmall
                          ?.copyWith(color: colors.primary)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ]),
          if (_rulesOpen) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingSm),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                    color: colors.outlineVariant.withOpacity(0.3)),
              ),
              child: Text(
                  widget.room.rules ??
                      'Be kind. No spam. No hate. Report anything that feels off.',
                  style: text.bodySmall),
            ),
          ],
          if (_pinnedOpen && visiblePinned.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final pin in visiblePinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingSm, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withOpacity(0.35),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.push_pin,
                          size: 14, color: colors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${(pin['msg']?['sender']?['first_name']) ?? 'Member'}: ${pin['msg']?['body'] ?? ''}',
                          style: text.bodySmall?.copyWith(
                              color: colors.onPrimaryContainer),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

