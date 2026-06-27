import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../services/supabase_service.dart';

/// Data access for messaging: conversations, messages, read state, realtime.
///
/// Architecture notes:
///   • All FK columns reference public.profiles(id) — NOT auth.users.id.
///     The caller must pass the user's profile_id, not auth user id.
///   • Sending a message inserts into public.messages with a fresh
///     client_message_id (uuid). The unique (conversation_id, client_message_id)
///     constraint protects against duplicate inserts from realtime echo or
///     network retries.
///   • Unread state is derived from conversation_participants.last_read_at vs
///     message.created_at — no per-message read row required for B5.
///   • messages.kind is currently 'text' for Beta; attachments can be added
///     later by introducing 'photo','gif','voice' kinds and an `attachments`
///     child table without touching this repo's public API.
class MessageRepository {
  MessageRepository._();
  static final MessageRepository instance = MessageRepository._();

  static const _uuid = Uuid();

  // ─── Conversations ───────────────────────────────────────────────────────

  /// Find an existing 1-1 conversation between [myProfileId] and
  /// [otherProfileId] or create one. Returns the conversation id.
  Future<String?> findOrCreateDirectConversation({
    required String otherProfileId,
    String mode = 'date',
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    final response = await db.rpc(
      'find_or_create_dm',
      params: {'other_profile_id': otherProfileId, 'conv_mode': mode},
    );
    return response as String?;
  }

  /// Fetch the full conversation list for [myProfileId], newest first.
  ///
  /// Done in 1 + N reads (N = # of conversations the user is in). For Beta
  /// volumes that is fine. A future optimisation could be a single SQL view.
  Future<List<Conversation>> fetchConversations(String myProfileId) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    // Step 1 — fetch all (conversation, last_read_at) rows for me, joined to
    // the conversation row for sort order and request flag.
    final List<dynamic> rows = await db
        .from('conversation_participants')
        .select('''
          last_read_at,
          conversation_id,
          conversations:conversations!inner (
            id, mode, is_request, last_message_at, created_at, created_by
          )
        ''')
        .eq('profile_id', myProfileId)
        .order('last_message_at', referencedTable: 'conversations', ascending: false);

    final results = <Conversation>[];

    for (final row in rows) {
      final convRow = row['conversations'] as Map<String, dynamic>;
      final convId = convRow['id'] as String;
      final lastReadIso = row['last_read_at'] as String?;
      final lastReadAt = DateTime.tryParse(lastReadIso ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

      // Other participant (1-1 DM assumed for Beta).
      final otherRows = await db
          .from('conversation_participants')
          .select('profile_id, profiles:profiles!inner(id, first_name, is_online, last_active)')
          .eq('conversation_id', convId)
          .neq('profile_id', myProfileId)
          .limit(1);

      if ((otherRows as List).isEmpty) continue;
      final otherProfileRow = otherRows.first['profiles'] as Map<String, dynamic>;
      final otherProfileId = otherProfileRow['id'] as String;

      // Other participant's primary photo (separate read, photos table is
      // tiny so cheap).
      final photoRows = await db
          .from('profile_photos')
          .select('display_url')
          .eq('profile_id', otherProfileId)
          .order('display_order')
          .limit(1);
      final photoUrl = (photoRows as List).isNotEmpty
          ? (photoRows.first['display_url'] as String?) ?? ''
          : '';

      // Most recent non-deleted message.
      final msgRows = await db
          .from('messages')
          .select('body, created_at, sender_id, kind, deleted_at')
          .eq('conversation_id', convId)
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: false)
          .limit(1);
      String lastBody = '';
      DateTime lastTime = DateTime.tryParse(convRow['last_message_at']?.toString() ?? '') ?? DateTime.now();
      if ((msgRows as List).isNotEmpty) {
        lastBody = msgRows.first['body'] as String? ?? '';
        lastTime = DateTime.tryParse(msgRows.first['created_at']?.toString() ?? '') ?? lastTime;
      }

      // Unread count = messages from the other person created strictly after
      // my last_read_at. Single round-trip via head:true + count.
      final unreadResp = await db
          .from('messages')
          .select('id')
          .eq('conversation_id', convId)
          .neq('sender_id', myProfileId)
          .gt('created_at', lastReadAt.toIso8601String())
          .filter('deleted_at', 'is', null)
          .count(CountOption.exact);
      final unreadCount = unreadResp.count;

      results.add(Conversation(
        id: convId,
        otherUserId: otherProfileId,
        otherUserName: otherProfileRow['first_name'] as String? ?? '',
        otherUserPhoto: photoUrl,
        lastMessage: lastBody,
        lastMessageTime: lastTime,
        unreadCount: unreadCount,
        isRequest: convRow['is_request'] as bool? ?? false,
        isOnline: otherProfileRow['is_online'] as bool? ?? false,
      ));
    }

    // Already sorted by last_message_at desc via PostgREST.
    return results;
  }

  // ─── Messages ────────────────────────────────────────────────────────────

  /// Fetch the message history for a conversation, oldest → newest.
  Future<List<ChatMessage>> fetchMessages(String conversationId, {int limit = 200}) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    final rows = await db
        .from('messages')
        .select('id, sender_id, body, created_at, kind, deleted_at')
        .eq('conversation_id', conversationId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: true)
        .limit(limit);

    return (rows as List)
        .map((r) => _mapMessage(r as Map<String, dynamic>))
        .toList();
  }

  /// Send a text message. Returns the inserted [ChatMessage] or null on failure.
  Future<ChatMessage?> sendMessage({
    required String conversationId,
    required String senderProfileId,
    required String body,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;

    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    final row = await db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderProfileId,
      'body': trimmed,
      'kind': 'text',
      'client_message_id': _uuid.v4(),
    }).select('id, sender_id, body, created_at, kind, deleted_at').single();

    return _mapMessage(row);
  }

  /// Bump the caller's last_read_at on this conversation.
  Future<void> markRead(String conversationId) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('mark_conversation_read', params: {'conv_id': conversationId});
  }

  // ─── Realtime ────────────────────────────────────────────────────────────

  /// Subscribe to new messages for one conversation. Returns the channel so
  /// the caller can `removeChannel()` it on dispose.
  RealtimeChannel subscribeToConversation({
    required String conversationId,
    required void Function(ChatMessage) onInsert,
  }) {
    final db = SupabaseService.client!;
    final channel = db.channel('conv:$conversationId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        if (record.isEmpty) return;
        onInsert(_mapMessage(record));
      },
    ).subscribe();
    return channel;
  }

  /// Subscribe to all message inserts (the conversation list listens to this
  /// to refresh ordering and unread counts).
  RealtimeChannel subscribeToInbox({
    required void Function() onAnyMessage,
  }) {
    final db = SupabaseService.client!;
    final channel = db.channel('inbox:any');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_) => onAnyMessage(),
    ).subscribe();
    return channel;
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.removeChannel(channel);
  }

  // ─── Mapping ─────────────────────────────────────────────────────────────

  ChatMessage _mapMessage(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      senderId: row['sender_id'] as String,
      text: row['body'] as String? ?? '',
      timestamp: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      isRead: false, // unread state lives on the conversation, not per-message
    );
  }
}
