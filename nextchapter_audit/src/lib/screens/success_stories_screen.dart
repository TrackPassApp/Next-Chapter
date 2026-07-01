import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

class SuccessStoriesScreen extends StatefulWidget {
  const SuccessStoriesScreen({super.key});

  @override
  State<SuccessStoriesScreen> createState() => _SuccessStoriesScreenState();
}

class _SuccessStoriesScreenState extends State<SuccessStoriesScreen> {
  List<Map<String, dynamic>> _stories = [];
  bool _loading = true;

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
    setState(() => _loading = true);
    try {
      final rows = await db
          .from('success_stories')
          .select('id, title, body, created_at, author:profiles!success_stories_author_id_fkey(id, first_name)')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(200);
      _stories = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openSubmit() async {
    final myProfile = context.read<ProfileProvider>().profile;
    if (myProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish your profile first.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => const _SubmitStoryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Success Stories'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/community'),
        ),
        actions: [
          IconButton(
            tooltip: 'Share yours',
            onPressed: _openSubmit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _stories.isEmpty
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingXl),
                      child: Column(children: [
                        Icon(Icons.stars_outlined,
                            size: 56, color: appColors.subtleText),
                        const SizedBox(height: AppTheme.spacingMd),
                        Text('No stories yet.', style: text.titleMedium),
                        const SizedBox(height: AppTheme.spacingSm),
                        Text(
                          'Met someone through Next Chapter? Share the moment '
                          'that mattered to you.',
                          style: text.bodySmall
                              ?.copyWith(color: appColors.subtleText),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.spacingMd),
                        FilledButton.icon(
                          onPressed: _openSubmit,
                          icon: const Icon(Icons.add),
                          label: const Text('Share yours'),
                        ),
                      ]),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd,
                        vertical: AppTheme.spacingSm),
                    itemCount: _stories.length,
                    itemBuilder: (_, i) {
                      final s = _stories[i];
                      final author = (s['author'] as Map?)?['first_name'] ?? 'Member';
                      final dt = DateTime.parse(s['created_at']).toLocal();
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['title'] as String,
                                  style: text.titleMedium
                                      ?.copyWith(color: colors.primary)),
                              const SizedBox(height: 4),
                              Text('$author • ${DateFormat.yMMMd().format(dt)}',
                                  style: text.labelSmall
                                      ?.copyWith(color: appColors.subtleText)),
                              const SizedBox(height: AppTheme.spacingSm),
                              Text(s['body'] as String,
                                  style: text.bodyMedium?.copyWith(height: 1.5)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _SubmitStoryDialog extends StatefulWidget {
  const _SubmitStoryDialog();
  @override
  State<_SubmitStoryDialog> createState() => _SubmitStoryDialogState();
}

class _SubmitStoryDialogState extends State<_SubmitStoryDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _submitting = false;

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
    return AlertDialog(
      title: const Text('Share your story'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'I met my best friend',
                border: OutlineInputBorder(),
              ),
              maxLength: 120,
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: _bodyCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Your story',
                border: OutlineInputBorder(),
              ),
              maxLines: 6,
              maxLength: 2000,
            ),
          ],
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
              : const Text('Submit'),
        ),
      ],
    );
  }
}
