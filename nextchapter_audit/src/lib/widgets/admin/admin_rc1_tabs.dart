import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';

/// Compose global announcements + view recent ones. Requires admin+ per RPC.
class AdminAnnouncementsTab extends StatefulWidget {
  const AdminAnnouncementsTab({super.key});

  @override
  State<AdminAnnouncementsTab> createState() => _AdminAnnouncementsTabState();
}

class _AdminAnnouncementsTabState extends State<AdminAnnouncementsTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = SupabaseService.client;
    if (db == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await db
          .from('announcements')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      _recent = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _broadcast() async {
    final t = _titleCtrl.text.trim();
    final b = _bodyCtrl.text.trim();
    if (t.length < 3 || b.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a short title and body.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final db = SupabaseService.client;
      await db?.rpc('admin_broadcast_announcement',
          params: {'p_title': t, 'p_body': b});
      _titleCtrl.clear();
      _bodyCtrl.clear();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement sent.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        Text('New announcement', style: text.titleSmall),
        const SizedBox(height: AppTheme.spacingSm),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
              labelText: 'Title', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppTheme.spacingSm),
        TextField(
          controller: _bodyCtrl,
          decoration: const InputDecoration(
              labelText: 'Body', border: OutlineInputBorder()),
          maxLines: 4,
        ),
        const SizedBox(height: AppTheme.spacingSm),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _sending ? null : _broadcast,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(_sending ? 'Sending…' : 'Broadcast to everyone'),
          ),
        ),
        const SizedBox(height: AppTheme.spacingLg),
        Text('Recent', style: text.titleSmall),
        const SizedBox(height: AppTheme.spacingSm),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (_recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No announcements yet.')),
          )
        else
          for (final a in _recent)
            Card(
              child: ListTile(
                title: Text(a['title'] ?? ''),
                subtitle: Text(a['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(
                  a['created_at']?.toString().substring(0, 10) ?? '',
                  style: text.labelSmall,
                ),
              ),
            ),
      ],
    );
  }
}

/// Success Stories moderation. Approve or reject pending stories.
class AdminStoriesTab extends StatefulWidget {
  const AdminStoriesTab({super.key});
  @override
  State<AdminStoriesTab> createState() => _AdminStoriesTabState();
}

class _AdminStoriesTabState extends State<AdminStoriesTab> {
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'pending';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = SupabaseService.client;
    if (db == null) return;
    setState(() => _loading = true);
    try {
      final rows = await db
          .from('success_stories')
          .select('id, title, body, status, created_at,'
              ' author:profiles!success_stories_author_id_fkey(id, first_name)')
          .eq('status', _filter)
          .order('created_at', ascending: false)
          .limit(200);
      _rows = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(String id, String status) async {
    final db = SupabaseService.client;
    try {
      await db?.rpc('admin_moderate_story', params: {
        'p_story_id': id,
        'p_status': status,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          for (final f in const ['pending', 'approved', 'rejected'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f),
                selected: _filter == f,
                onSelected: (_) {
                  setState(() => _filter = f);
                  _load();
                },
              ),
            ),
          const Spacer(),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: AppTheme.spacingSm),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const Center(child: Text('Nothing here.'))
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final s = _rows[i];
                        final author = (s['author'] as Map?)?['first_name'] ?? 'Member';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppTheme.spacingMd),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['title'] ?? '', style: Theme.of(context).textTheme.titleSmall),
                                Text('by $author', style: Theme.of(context).textTheme.labelSmall),
                                const SizedBox(height: 6),
                                Text(s['body'] ?? ''),
                                const SizedBox(height: 6),
                                if (_filter == 'pending')
                                  Row(children: [
                                    FilledButton(
                                      onPressed: () => _decide(s['id'] as String, 'approved'),
                                      child: const Text('Approve'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () => _decide(s['id'] as String, 'rejected'),
                                      child: const Text('Reject'),
                                    ),
                                  ]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Community moderation: create/rename/lock/delete rooms + view roster.
class AdminCommunityTab extends StatefulWidget {
  const AdminCommunityTab({super.key});
  @override
  State<AdminCommunityTab> createState() => _AdminCommunityTabState();
}

class _AdminCommunityTabState extends State<AdminCommunityTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = SupabaseService.client;
    if (db == null) return;
    setState(() => _loading = true);
    try {
      final rows = await db.from('chat_rooms').select().order('sort_order');
      _rooms = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createRoom() async {
    final slugCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final rulesCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New room'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: slugCtrl, decoration: const InputDecoration(labelText: 'Slug (lowercase, dashes)')),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              TextField(controller: rulesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Rules')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await SupabaseService.client?.rpc('admin_create_room', params: {
        'p_slug': slugCtrl.text.trim(),
        'p_name': nameCtrl.text.trim(),
        'p_description': descCtrl.text.trim(),
        'p_category': 'general',
        'p_rules': rulesCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _lockRoom(String id, bool locked) async {
    try {
      await SupabaseService.client?.rpc('admin_lock_room', params: {
        'p_room_id': id,
        'p_locked': !locked,
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteRoom(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('The room stops appearing in Community. Existing messages are preserved for admins.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.client?.rpc('admin_delete_room', params: {'p_room_id': id, 'p_reason': null});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('Chat rooms', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          FilledButton.icon(onPressed: _createRoom, icon: const Icon(Icons.add), label: const Text('New room')),
          const SizedBox(width: 8),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (_, i) {
                    final r = _rooms[i];
                    final locked = (r['is_locked'] as bool?) ?? false;
                    final active = (r['is_active'] as bool?) ?? true;
                    return Card(
                      child: ListTile(
                        leading: Icon(active ? Icons.forum : Icons.forum_outlined,
                            color: active ? null : Theme.of(context).disabledColor),
                        title: Text('${r['name']}${!active ? ' (deleted)' : ''}'),
                        subtitle: Text(r['slug'] ?? ''),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: locked ? 'Unlock' : 'Lock',
                              onPressed: active ? () => _lockRoom(r['id'] as String, locked) : null,
                              icon: Icon(locked ? Icons.lock : Icons.lock_open),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: active ? () => _deleteRoom(r['id'] as String, r['name'] as String) : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Deleted accounts — soft-deleted profiles list. Existing admin_users_tab
/// already filters, but a dedicated view keeps the spec's mental model.
class AdminDeletedTab extends StatefulWidget {
  const AdminDeletedTab({super.key});
  @override
  State<AdminDeletedTab> createState() => _AdminDeletedTabState();
}

class _AdminDeletedTabState extends State<AdminDeletedTab> {
  final _repo = AdminRepository.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _rows = await _repo.listUsers(deleted: true, limit: 300);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _restore(String id) async {
    await _repo.restoreUser(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) return const Center(child: Text('No deleted accounts.'));
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (_, i) {
        final r = _rows[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text(r['first_name'] ?? 'Deleted User'),
            subtitle: Text('deleted at ${r['deleted_at'] ?? '-'}'),
            trailing: TextButton(
              onPressed: () => _restore(r['id'] as String),
              child: const Text('Restore'),
            ),
          ),
        );
      },
    );
  }
}
