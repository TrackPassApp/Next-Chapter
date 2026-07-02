import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';

/// Small dialog embedded in Edit Profile so members can submit a success
/// story without navigating away. Categorised + optional member tag.
/// Never publishes until an admin approves via the admin Stories tab.
class SubmitStoryDialog extends StatefulWidget {
  const SubmitStoryDialog({super.key});

  @override
  State<SubmitStoryDialog> createState() => _SubmitStoryDialogState();
}

class _SubmitStoryDialogState extends State<SubmitStoryDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _tagQueryCtrl = TextEditingController();

  String _kind = 'friendship';
  Map<String, dynamic>? _taggedProfile;
  bool _submitting = false;

  static const _kinds = <String, String>{
    'dating':           'Dating',
    'friendship':       'Friendship',
    'activity_partner': 'Activity partner',
    'community':        'Community',
    'marriage':         'Marriage',
    'other':            'Other',
  };

  Future<List<Map<String, dynamic>>> _search(String q) async {
    final db = SupabaseService.client;
    if (db == null || q.trim().length < 2) return [];
    try {
      final rows = await db
          .from('profiles')
          .select('id, first_name, city, state')
          .eq('is_complete', true)
          .eq('is_deleted', false)
          .ilike('first_name', '%${q.trim()}%')
          .limit(6);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> _submit() async {
    final t = _titleCtrl.text.trim();
    final b = _bodyCtrl.text.trim();
    if (t.length < 3 || b.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a short title and a few sentences of story.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final db = SupabaseService.client;
      await db?.rpc('submit_success_story', params: {
        'p_title': t,
        'p_body': b,
        'p_kind': _kind,
        'p_tagged_profile_id': _taggedProfile?['id'],
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Thanks — an admin will review your story before it goes live.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return AlertDialog(
      title: const Text('Share your Next Chapter story'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                enabled: !_submitting,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'I met my best friend',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              TextField(
                controller: _bodyCtrl,
                enabled: !_submitting,
                maxLength: 2000,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Your story',
                  hintText: 'What happened, in your own words.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              DropdownButtonFormField<String>(
                value: _kind,
                decoration: const InputDecoration(
                  labelText: 'What kind of success?',
                  border: OutlineInputBorder(),
                ),
                items: _kinds.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _kind = v ?? 'other'),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text('Tag another member (optional)',
                  style: text.labelMedium),
              const SizedBox(height: 4),
              if (_taggedProfile != null)
                Chip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text(_taggedProfile!['first_name'] ?? ''),
                  onDeleted: _submitting
                      ? null
                      : () => setState(() => _taggedProfile = null),
                )
              else
                TextField(
                  controller: _tagQueryCtrl,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    hintText: 'Search first name…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              if (_taggedProfile == null && _tagQueryCtrl.text.length >= 2)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _search(_tagQueryCtrl.text),
                  builder: (_, snap) {
                    final results = snap.data ?? const [];
                    if (results.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: results
                          .map((p) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline),
                                title: Text(p['first_name'] ?? ''),
                                subtitle: Text([p['city'], p['state']]
                                    .where((s) =>
                                        (s as String?)?.isNotEmpty == true)
                                    .join(', ')),
                                onTap: () => setState(() {
                                  _taggedProfile = p;
                                  _tagQueryCtrl.clear();
                                }),
                              ))
                          .toList(),
                    );
                  },
                ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                'Stories are reviewed by an admin before appearing publicly.',
                style: text.labelSmall
                    ?.copyWith(color: appColors.subtleText),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit for review'),
        ),
      ],
    );
  }
}
