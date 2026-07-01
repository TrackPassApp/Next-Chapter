import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class ChatRoom {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String category;
  final int sortOrder;
  final String? rules;
  final bool isLocked;

  ChatRoom({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    required this.category,
    required this.sortOrder,
    this.rules,
    this.isLocked = false,
  });

  factory ChatRoom.fromMap(Map<String, dynamic> m) => ChatRoom(
        id: m['id'] as String,
        slug: m['slug'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        category: (m['category'] as String?) ?? 'general',
        sortOrder: (m['sort_order'] as int?) ?? 100,
        rules: m['rules'] as String?,
        isLocked: (m['is_locked'] as bool?) ?? false,
      );
}

class RoomMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String? senderFirstName;
  final String? senderPhotoUrl;
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;

  RoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.senderFirstName,
    this.senderPhotoUrl,
    required this.body,
    required this.createdAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory RoomMessage.fromMap(Map<String, dynamic> m) {
    final sender = m['sender'] as Map<String, dynamic>?;
    final photos = (sender?['profile_photos'] as List?) ?? const [];
    String? url;
    if (photos.isNotEmpty) {
      final first = photos.first as Map<String, dynamic>;
      url = first['photo_url'] as String?;
    }
    return RoomMessage(
      id: m['id'] as String,
      roomId: m['room_id'] as String,
      senderId: m['sender_id'] as String,
      senderFirstName: sender?['first_name'] as String?,
      senderPhotoUrl: url,
      body: m['body'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      deletedAt: m['deleted_at'] == null
          ? null
          : DateTime.parse(m['deleted_at'] as String),
    );
  }
}

/// Data access for the Community Chat Rooms feature (B11).
class CommunityRepository {
  CommunityRepository._();
  static final CommunityRepository instance = CommunityRepository._();

  Future<List<ChatRoom>> listRooms() async {
    final db = SupabaseService.client;
    if (db == null) return [];
    final rows = await db
        .from('chat_rooms')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return (rows as List)
        .map((r) => ChatRoom.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<RoomMessage>> fetchMessages(
    String roomId, {
    int limit = 100,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return [];
    final rows = await db
        .from('room_messages')
        .select(
          'id, room_id, sender_id, body, created_at, deleted_at,'
          ' sender:profiles!room_messages_sender_id_fkey('
          '   id, first_name,'
          '   profile_photos(photo_url, sort_order)'
          ' )',
        )
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .limit(limit);
    return (rows as List)
        .map((r) => RoomMessage.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<RoomMessage?> sendMessage({
    required String roomId,
    required String senderProfileId,
    required String body,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    final inserted = await db
        .from('room_messages')
        .insert({
          'room_id': roomId,
          'sender_id': senderProfileId,
          'body': body,
        })
        .select(
          'id, room_id, sender_id, body, created_at, deleted_at,'
          ' sender:profiles!room_messages_sender_id_fkey('
          '   id, first_name,'
          '   profile_photos(photo_url, sort_order)'
          ' )',
        )
        .single();
    return RoomMessage.fromMap(inserted);
  }

  Future<void> reportMessage(String messageId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('report_room_message', params: {
      'target_message_id': messageId,
      'reason': reason,
    });
  }

  Future<void> deleteMessage(String messageId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_delete_room_message', params: {
      'target_message_id': messageId,
      'reason': reason,
    });
  }

  RealtimeChannel subscribeToRoom({
    required String roomId,
    required void Function(String rawMessageId) onInsert,
  }) {
    final db = SupabaseService.client!;
    final channel = db.channel('room:$roomId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'room_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) {
        final id = payload.newRecord['id'] as String?;
        if (id != null) onInsert(id);
      },
    ).subscribe();
    return channel;
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.removeChannel(channel);
  }
}
