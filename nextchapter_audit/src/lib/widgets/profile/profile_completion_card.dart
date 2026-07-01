import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';

/// Encourages profile completion without nagging. Fetches the server-computed
/// score once, offers a short list of suggested next steps.
class ProfileCompletionCard extends StatefulWidget {
  const ProfileCompletionCard({super.key});

  @override
  State<ProfileCompletionCard> createState() => _ProfileCompletionCardState();
}

class _ProfileCompletionCardState extends State<ProfileCompletionCard> {
  int? _score;
  List<_Suggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myId = context.read<ProfileProvider>().profileId;
    final db = SupabaseService.client;
    if (myId == null || db == null) return;
    try {
      final s = await db.rpc('profile_completion',
          params: {'target_profile_id': myId});
      final photos = await db
          .from('profile_photos')
          .select('id')
          .eq('profile_id', myId);
      final prompts = await db
          .from('profile_prompts')
          .select('id')
          .eq('profile_id', myId);
      final interests = await db
          .from('profile_interests')
          .select('id')
          .eq('profile_id', myId);
      final vs = await db
          .from('verification_status')
          .select()
          .eq('profile_id', myId)
          .maybeSingle();
      final profile =
          context.read<ProfileProvider>().profile;

      final suggestions = <_Suggestion>[];
      if ((photos as List).length < 3) {
        suggestions.add(_Suggestion(
            Icons.photo_camera_outlined, 'Add another picture', '/me/edit'));
      }
      if ((prompts as List).length < 3) {
        suggestions.add(_Suggestion(
            Icons.chat_outlined, 'Answer another prompt', '/me/edit'));
      }
      if ((interests as List).length < 3) {
        suggestions.add(_Suggestion(
            Icons.tag_outlined, 'Add more interests', '/me/edit'));
      }
      if (profile?.aboutMe == null || (profile?.aboutMe ?? '').length < 20) {
        suggestions.add(_Suggestion(
            Icons.article_outlined, 'Complete About Me', '/me/edit'));
      }
      if (vs != null && !(vs['phone_verified'] as bool? ?? false)) {
        suggestions.add(_Suggestion(
            Icons.phone_outlined, 'Verify your phone', '/me/verification'));
      }
      if (vs != null && !(vs['id_verified'] as bool? ?? false)) {
        suggestions.add(_Suggestion(Icons.badge_outlined,
            'Verify your identity', '/me/verification'));
      }

      if (mounted) {
        setState(() {
          _score = (s as int?) ?? 0;
          _suggestions = suggestions.take(4).toList();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_score == null || _score == 100) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Profile $_score% complete',
                    style: text.titleSmall),
              ),
              TextButton(
                onPressed: () => context.go('/me/edit'),
                child: const Text('Improve'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _score! / 100,
              minHeight: 6,
              backgroundColor: colors.surfaceContainerLow,
              color: colors.primary,
            ),
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    avatar: Icon(s.icon, size: 14, color: colors.primary),
                    label: Text(s.label,
                        style: text.labelSmall
                            ?.copyWith(color: colors.primary)),
                    onPressed: () => context.go(s.route),
                    backgroundColor: colors.primaryContainer.withOpacity(0.5),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Suggestion {
  final IconData icon;
  final String label;
  final String route;
  _Suggestion(this.icon, this.label, this.route);
}
