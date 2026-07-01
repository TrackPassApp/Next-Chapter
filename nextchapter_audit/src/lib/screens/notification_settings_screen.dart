import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _keys = <String, String>{
    'private_message':       'Private messages',
    'room_reply':            'Community room replies',
    'mention':               'Mentions',
    'verification_approved': 'Verification approved',
    'verification_denied':   'Verification denied',
    'moderator_warning':     'Moderator warnings',
    'admin_announcement':    'Admin announcements',
    'match_new':             'New matches (future)',
  };

  Map<String, bool> _prefs = {for (final k in _keys.keys) k: true};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = SupabaseService.client;
    if (db == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await db
          .from('notification_preferences')
          .select()
          .maybeSingle();
      if (row == null) {
        // Insert defaults for the current user.
        final userId = db.auth.currentUser?.id;
        if (userId != null) {
          await db.from('notification_preferences').insert({'user_id': userId});
        }
      } else {
        for (final k in _keys.keys) {
          _prefs[k] = (row[k] as bool?) ?? true;
        }
      }
    } catch (_) {/* keep defaults */}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(String key, bool value) async {
    final db = SupabaseService.client;
    if (db == null) return;
    setState(() {
      _prefs[key] = value;
      _saving = true;
    });
    try {
      await db.from('notification_preferences').update(
        {key: value, 'updated_at': DateTime.now().toIso8601String()},
      ).eq('user_id', db.auth.currentUser!.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/notifications'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingSm),
                      child: Text(
                        'Choose which alerts you want to receive.',
                        style: text.bodyMedium
                            ?.copyWith(color: appColors.subtleText),
                      ),
                    ),
                    for (final entry in _keys.entries)
                      SwitchListTile(
                        title: Text(entry.value),
                        value: _prefs[entry.key] ?? true,
                        onChanged:
                            _saving ? null : (v) => _save(entry.key, v),
                      ),
                    const SizedBox(height: AppTheme.spacingMd),
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingSm),
                      child: Text(
                        'You can change these any time. Turning something off '
                        'means we simply skip the alert — nothing you have '
                        'already received is deleted.',
                        style: text.bodySmall
                            ?.copyWith(color: appColors.subtleText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
