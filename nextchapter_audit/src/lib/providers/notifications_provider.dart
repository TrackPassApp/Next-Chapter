import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;
import '../services/supabase_service.dart';

class AppNotification {
  final String id;
  final String kind;
  final String title;
  final String? body;
  final String? link;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.link,
    this.payload = const {},
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        link: m['link'] as String?,
        payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        readAt: m['read_at'] == null ? null : DateTime.parse(m['read_at']),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Light-weight notifications store. Reads from public.notifications, listens
/// on Supabase Realtime, and exposes an unread count for the AppShell.
///
/// Push notifications are NOT wired here — the table + triggers give the app
/// everything it needs to display a bell + list. When FCM/OneSignal is chosen,
/// a client-side subscription to `notifications` can also forward to native
/// push.
class NotificationsProvider extends ChangeNotifier {
  final List<AppNotification> _items = [];
  bool _loading = false;
  RealtimeChannel? _channel;
  String? _userId;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => n.isUnread).length;
  bool get loading => _loading;

  Future<void> bindUser(String? userId) async {
    if (_userId == userId && _channel != null) return;
    _userId = userId;
    if (userId == null) {
      await _stopStream();
      _items.clear();
      notifyListeners();
      return;
    }
    await refresh();
    await _startStream(userId);
  }

  Future<void> refresh() async {
    final db = SupabaseService.client;
    if (db == null || _userId == null) return;
    _loading = true;
    notifyListeners();
    try {
      final rows = await db
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      _items
        ..clear()
        ..addAll((rows as List)
            .map((r) => AppNotification.fromMap(r as Map<String, dynamic>)));
    } catch (_) {
      // silent — this is a best-effort feed
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _startStream(String userId) async {
    await _stopStream();
    final db = SupabaseService.client;
    if (db == null) return;
    final channel = db.channel('notif:$userId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isEmpty) return;
        _items.insert(0, AppNotification.fromMap(row));
        notifyListeners();
      },
    ).subscribe();
    _channel = channel;
  }

  Future<void> _stopStream() async {
    final db = SupabaseService.client;
    if (_channel != null && db != null) {
      await db.removeChannel(_channel!);
    }
    _channel = null;
  }

  Future<void> markAllRead() async {
    final db = SupabaseService.client;
    if (db == null) return;
    try {
      await db.rpc('mark_notifications_read', params: {'ids': null});
      final now = DateTime.now();
      for (var i = 0; i < _items.length; i++) {
        if (_items[i].isUnread) {
          _items[i] = AppNotification(
            id: _items[i].id,
            kind: _items[i].kind,
            title: _items[i].title,
            body: _items[i].body,
            link: _items[i].link,
            payload: _items[i].payload,
            readAt: now,
            createdAt: _items[i].createdAt,
          );
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> deleteOne(String id) async {
    final db = SupabaseService.client;
    if (db == null) return;
    try {
      await db.from('notifications').delete().eq('id', id);
      _items.removeWhere((n) => n.id == id);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> deleteAll() async {
    final db = SupabaseService.client;
    if (db == null || _userId == null) return;
    try {
      await db.from('notifications').delete().eq('user_id', _userId!);
      _items.clear();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markOneRead(String id) async {
    final db = SupabaseService.client;
    if (db == null) return;
    try {
      await db.rpc('mark_notifications_read', params: {'ids': [id]});
      final i = _items.indexWhere((n) => n.id == id);
      if (i >= 0 && _items[i].isUnread) {
        _items[i] = AppNotification(
          id: _items[i].id,
          kind: _items[i].kind,
          title: _items[i].title,
          body: _items[i].body,
          link: _items[i].link,
          payload: _items[i].payload,
          readAt: DateTime.now(),
          createdAt: _items[i].createdAt,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }
}
