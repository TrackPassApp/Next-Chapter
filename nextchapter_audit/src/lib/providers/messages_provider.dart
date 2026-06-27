import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../models/conversation.dart';
import '../repositories/message_repository.dart';
import '../services/supabase_service.dart';

/// Live messaging state backed by Supabase.
///
/// Lifecycle from main.dart:
///   • Provider is constructed once globally.
///   • Call [bindProfile(myProfileId)] after auth + profile load.
///   • Call [clear()] on logout.
class MessagesProvider extends ChangeNotifier {
  final MessageRepository _repo = MessageRepository.instance;

  String? _myProfileId;
  List<Conversation> _conversations = [];
  List<ChatMessage> _currentMessages = [];
  String? _activeConversationId;
  bool _isLoading = false;
  bool _loadingMessages = false;
  String? _error;
  int _selectedTab = 0;

  RealtimeChannel? _inboxChannel;
  RealtimeChannel? _activeConvChannel;

  // ─── Getters ─────────────────────────────────────────────────────────────

  List<Conversation> get conversations => _selectedTab == 0
      ? _conversations.where((c) => !c.isRequest).toList()
      : _conversations.where((c) => c.isRequest).toList();
  List<ChatMessage> get currentMessages => _currentMessages;
  bool get isLoading => _isLoading;
  bool get loadingMessages => _loadingMessages;
  String? get error => _error;
  int get selectedTab => _selectedTab;
  int get unreadCount => _conversations.fold(0, (sum, c) => sum + c.unreadCount);
  int get requestCount => _conversations.where((c) => c.isRequest).length;
  String? get myProfileId => _myProfileId;
  String? get activeConversationId => _activeConversationId;

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  /// Wire up the provider with the signed-in user's profile id and start the
  /// inbox realtime listener.
  Future<void> bindProfile(String myProfileId) async {
    if (_myProfileId == myProfileId && _inboxChannel != null) return;
    _myProfileId = myProfileId;
    await _startInboxListener();
    await loadConversations();
  }

  void clear() {
    _myProfileId = null;
    _conversations = [];
    _currentMessages = [];
    _activeConversationId = null;
    _error = null;
    _selectedTab = 0;
    _disposeChannels();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeChannels();
    super.dispose();
  }

  void _disposeChannels() {
    if (_inboxChannel != null) {
      _repo.removeChannel(_inboxChannel!);
      _inboxChannel = null;
    }
    if (_activeConvChannel != null) {
      _repo.removeChannel(_activeConvChannel!);
      _activeConvChannel = null;
    }
  }

  Future<void> _startInboxListener() async {
    if (_inboxChannel != null) {
      await _repo.removeChannel(_inboxChannel!);
      _inboxChannel = null;
    }
    if (SupabaseService.client == null) return;
    _inboxChannel = _repo.subscribeToInbox(onAnyMessage: () {
      // Any insert anywhere → refresh my conversation list. RLS filters out
      // anything I shouldn't see, so this is safe.
      loadConversations();
    });
  }

  // ─── Tab ─────────────────────────────────────────────────────────────────

  void setTab(int tab) {
    _selectedTab = tab;
    notifyListeners();
  }

  // ─── Conversations ───────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    if (_myProfileId == null) return;
    if (SupabaseService.client == null) {
      _error = 'Supabase is not connected.';
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _conversations = await _repo.fetchConversations(_myProfileId!);
    } catch (e) {
      _error = 'Failed to load conversations.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Find or create a 1-1 conversation with [otherProfileId] and return its id.
  /// Used by the "Message X" button on Profile Detail.
  Future<String?> startConversationWith(String otherProfileId, {String mode = 'date'}) async {
    if (SupabaseService.client == null) return null;
    final convId = await _repo.findOrCreateDirectConversation(
      otherProfileId: otherProfileId,
      mode: mode,
    );
    if (convId != null) {
      // Best-effort refresh so the new conversation shows in the inbox.
      unawaited(loadConversations());
    }
    return convId;
  }

  // ─── Messages ────────────────────────────────────────────────────────────

  /// Open a conversation: load history, subscribe to realtime, mark as read.
  Future<void> openConversation(String conversationId) async {
    if (_myProfileId == null) return;
    _activeConversationId = conversationId;
    _loadingMessages = true;
    notifyListeners();

    try {
      _currentMessages = await _repo.fetchMessages(conversationId);
    } catch (_) {
      _currentMessages = [];
    }
    _loadingMessages = false;
    notifyListeners();

    // Mark this conversation as read.
    unawaited(_markActiveRead());

    // Wire realtime for THIS conversation.
    if (_activeConvChannel != null) {
      await _repo.removeChannel(_activeConvChannel!);
      _activeConvChannel = null;
    }
    if (SupabaseService.client == null) return;
    _activeConvChannel = _repo.subscribeToConversation(
      conversationId: conversationId,
      onInsert: (msg) {
        // De-dup against optimistic insert that already exists.
        if (_currentMessages.any((m) => m.id == msg.id)) return;
        _currentMessages = [..._currentMessages, msg];
        notifyListeners();
        // If the new message came from someone else, mark as read.
        if (msg.senderId != _myProfileId) {
          unawaited(_markActiveRead());
        }
      },
    );
  }

  Future<void> closeActiveConversation() async {
    _activeConversationId = null;
    _currentMessages = [];
    if (_activeConvChannel != null) {
      await _repo.removeChannel(_activeConvChannel!);
      _activeConvChannel = null;
    }
    notifyListeners();
  }

  Future<void> _markActiveRead() async {
    if (_activeConversationId == null) return;
    await _repo.markRead(_activeConversationId!);
    // Optimistically zero out this conversation's unread badge.
    _conversations = _conversations
        .map((c) => c.id == _activeConversationId ? c.copyWith(unreadCount: 0) : c)
        .toList();
    notifyListeners();
  }

  /// Send a text message in the active conversation (optimistic + realtime).
  Future<bool> sendMessage(String text) async {
    if (_myProfileId == null || _activeConversationId == null) return false;
    final body = text.trim();
    if (body.isEmpty) return false;

    // Optimistic insert with a tombstone id we replace once the server returns.
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      senderId: _myProfileId!,
      text: body,
      timestamp: DateTime.now(),
    );
    _currentMessages = [..._currentMessages, optimistic];
    notifyListeners();

    try {
      final saved = await _repo.sendMessage(
        conversationId: _activeConversationId!,
        senderProfileId: _myProfileId!,
        body: body,
      );
      if (saved != null) {
        _currentMessages = _currentMessages
            .map((m) => m.id == tempId ? saved : m)
            .toList();
        notifyListeners();
        return true;
      } else {
        _removeOptimistic(tempId);
        return false;
      }
    } catch (_) {
      _removeOptimistic(tempId);
      return false;
    }
  }

  void _removeOptimistic(String tempId) {
    _currentMessages = _currentMessages.where((m) => m.id != tempId).toList();
    notifyListeners();
  }
}
