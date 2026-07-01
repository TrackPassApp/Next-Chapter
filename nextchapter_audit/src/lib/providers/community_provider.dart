import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../repositories/community_repository.dart';
import '../services/supabase_service.dart';

/// State for the Community Chat feature.
///   • Lists the (small, seeded) set of public rooms.
///   • Streams messages for one open room via Supabase Realtime.
///   • Sends and reports messages.
class CommunityProvider extends ChangeNotifier {
  final CommunityRepository _repo = CommunityRepository.instance;

  List<ChatRoom> _rooms = [];
  bool _loadingRooms = false;
  String? _error;

  String? _openRoomId;
  List<RoomMessage> _messages = [];
  bool _loadingMessages = false;
  RealtimeChannel? _channel;

  String? _myProfileId;

  List<ChatRoom> get rooms => List.unmodifiable(_rooms);
  bool get loadingRooms => _loadingRooms;
  String? get error => _error;
  String? get openRoomId => _openRoomId;
  List<RoomMessage> get messages => List.unmodifiable(_messages);
  bool get loadingMessages => _loadingMessages;

  void bindProfile(String? profileId) {
    _myProfileId = profileId;
  }

  Future<void> loadRooms() async {
    if (SupabaseService.client == null) {
      _error = 'Supabase is not connected.';
      notifyListeners();
      return;
    }
    _loadingRooms = true;
    _error = null;
    notifyListeners();
    try {
      _rooms = await _repo.listRooms();
    } catch (e) {
      _error = 'Failed to load community rooms.';
    } finally {
      _loadingRooms = false;
      notifyListeners();
    }
  }

  Future<void> openRoom(String roomId) async {
    _openRoomId = roomId;
    _messages = [];
    _loadingMessages = true;
    notifyListeners();
    try {
      _messages = await _repo.fetchMessages(roomId);
    } catch (_) {
      _messages = [];
    }
    _loadingMessages = false;
    notifyListeners();

    await _restartChannel(roomId);
  }

  Future<void> _restartChannel(String roomId) async {
    if (_channel != null) {
      await _repo.removeChannel(_channel!);
      _channel = null;
    }
    if (SupabaseService.client == null) return;
    _channel = _repo.subscribeToRoom(
      roomId: roomId,
      onInsert: (msgId) async {
        // Fresh row landed. Refetch just the tail to hydrate the sender join.
        try {
          final fresh = await _repo.fetchMessages(roomId, limit: 100);
          _messages = fresh;
          notifyListeners();
        } catch (_) {}
      },
    );
  }

  Future<void> leaveRoom() async {
    if (_channel != null) {
      await _repo.removeChannel(_channel!);
      _channel = null;
    }
    _openRoomId = null;
    _messages = [];
    notifyListeners();
  }

  Future<String?> send(String body) async {
    final myId = _myProfileId;
    final roomId = _openRoomId;
    if (myId == null || roomId == null) return 'You must be signed in.';
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final msg = await _repo.sendMessage(
        roomId: roomId,
        senderProfileId: myId,
        body: trimmed,
      );
      if (msg != null && !_messages.any((m) => m.id == msg.id)) {
        _messages = [..._messages, msg];
        notifyListeners();
      }
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<void> report(String messageId, {String? reason}) async {
    await _repo.reportMessage(messageId, reason: reason);
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('room_messages_insert_self')) {
      return "You can't post right now (your account may be muted or suspended).";
    }
    return 'Message failed: $s';
  }

  @override
  void dispose() {
    if (_channel != null) {
      _repo.removeChannel(_channel!);
      _channel = null;
    }
    super.dispose();
  }
}
