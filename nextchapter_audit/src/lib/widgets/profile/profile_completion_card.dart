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
    final profile = context.read<ProfileProvider>().profile;
    final myId = profile?.id;
    final db = SupabaseService.client;
    if (myId == null || db == null) return;
    try {
      // Single source of truth: the score stored on profiles.completeness_score
      // (server trigger-maintained). This matches what Edit Profile shows.
      final row = await db
          .from('profiles')
          .select('completeness_score')
          .eq('id', myId)
          .maybeSingle();
      final s = (row?['completeness_score'] as int?) ?? profile?.completenessScore ?? 0;

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
          _score = s;
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
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: isMobile ? AppTheme.spacingSm : AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Profile $_score% complete',
                    style: text.titleSmall),
              ),
              TextButton(
                onPressed: () => context.go('/me/edit'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Improve'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _score! / 100,
              minHeight: 6,
              backgroundColor: colors.surfaceContainerLow,
              color: colors.primary,
            ),
          ),
          // On mobile keep the card tight — one line of suggestion text.
          // On wider screens show the full chip wrap so power users see all.
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            if (isMobile)
              Text(
                'Next: ${_suggestions.first.label.toLowerCase()}',
                style: text.labelSmall
                    ?.copyWith(color: colors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
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
                      backgroundColor:
                          colors.primaryContainer.withOpacity(0.5),
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
