import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../models/user_profile.dart';
import '../providers/block_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/profile_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/common/completeness_ring.dart';
import '../widgets/common/report_dialog.dart';
import '../widgets/common/verification_badges.dart';

/// Renders a user's profile. Used both for other users (Browse → Profile)
/// and for the signed-in user's own profile (My Profile tab).
///
/// Layout is intentionally simple: AppBar + scrolling ListView. The
/// previous SliverAppBar version was unreliable inside the shell's nested
/// Scaffold and frequently rendered blank.
class ProfileDetailScreen extends StatefulWidget {
  final String profileId;
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  // Supabase profile.id is a UUID. Anything else is a legacy/mock id and
  // must never be sent to the database — it always fails. We catch it here
  // and bounce the user back to Browse instead of showing a broken page.
  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  int _photoIndex = 0;

  @override
  void initState() {
    super.initState();
    // Guard against legacy numeric ids like /profile/2 from old bundles or
    // bookmarks. Bounce out of the page before we ever query Supabase.
    if (!_uuidRe.hasMatch(widget.profileId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That profile link is outdated. Returning to Browse.')),
        );
        context.go('/browse');
      });
      return;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.profileId != widget.profileId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!SupabaseService.isConfigured || SupabaseService.client == null) {
      setState(() {
        _loading = false;
        _error = 'Supabase is not connected.';
      });
      return;
    }

    try {
      // Always re-fetch from Supabase. We deliberately do NOT use the
      // ProfileProvider cache here because that cache is initialised at
      // login and may be missing photos/prompts/interests the user added
      // later. A fresh fetch via _assembleProfile guarantees the full body.
      final p = await ProfileRepository.instance.fetchProfileById(widget.profileId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
        _error = p == null ? 'This profile is unavailable.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load profile: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off_outlined, size: 56, color: appColors.subtleText),
                const SizedBox(height: AppTheme.spacingMd),
                Text(_error ?? 'Profile not found', style: text.titleMedium),
                const SizedBox(height: AppTheme.spacingMd),
                ElevatedButton(onPressed: () => context.go('/browse'), child: const Text('Back to Browse')),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final ownId = context.watch<ProfileProvider>().profile?.id;
    final isOwn = ownId != null && ownId == profile.id;
    final photos = profile.photoUrls;
    final currentPhoto = photos.isNotEmpty ? photos[_photoIndex.clamp(0, photos.length - 1)] : null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isOwn ? 'My Profile' : 'Profile'),
            const SizedBox(width: AppTheme.spacingSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
              child: Text(
                AppConfig.buildLabel,
                style: text.labelSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (isOwn)
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/me/edit').then((_) => _load()),
            )
          else
            Consumer<BlockProvider>(
              builder: (_, blockProvider, __) {
                final blocked = blockProvider.hasBlocked(profile.id);
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) => _onMenu(v, profile, appColors, colors, blocked: blocked),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 20), SizedBox(width: 8), Text('Report')])),
                    PopupMenuItem(
                      value: blocked ? 'unblock' : 'block',
                      child: Row(children: [
                        Icon(blocked ? Icons.lock_open : Icons.block, size: 20),
                        const SizedBox(width: 8),
                        Text(blocked ? 'Unblock' : 'Block'),
                      ]),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // Any exception thrown by any widget below this Builder is caught
          // here and rendered as a big red panel on the screen so it can
          // never silently blank out the body again. This runs in profile
          // and release mode, not just debug.
          try {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  children: _buildBody(
                    context: context,
                    profile: profile,
                    isOwn: isOwn,
                    photos: photos,
                    currentPhoto: currentPhoto,
                    colors: colors,
                    text: text,
                    appColors: appColors,
                  ),
                ),
              ),
            );
          } catch (e, st) {
            return _InlineError(error: e, stack: st, appColors: appColors, text: text);
          }
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: isOwn
                  ? ElevatedButton.icon(
                      onPressed: () {
                        if (!profile.isComplete) {
                          context.go('/welcome');
                        } else {
                          context.push('/me/edit').then((_) => _load());
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(profile.isComplete ? 'Edit Profile' : 'Complete Profile'),
                    )
                  : Consumer<BlockProvider>(
                      builder: (_, blockProvider, __) {
                        final blocked = blockProvider.hasBlocked(profile.id);
                        if (blocked) {
                          return OutlinedButton.icon(
                            onPressed: () => _confirmUnblock(profile),
                            icon: const Icon(Icons.lock_open),
                            label: Text('Unblock ${profile.firstName} to message'),
                          );
                        }
                        return ElevatedButton.icon(
                          onPressed: () => _openConversation(profile),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text('Message ${profile.firstName} — Free'),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chips(List<String> items, Color color) {
    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: AppTheme.spacingSm,
      children: items
          .map((i) => Chip(
                label: Text(i),
                backgroundColor: color.withOpacity(0.4),
                side: BorderSide.none,
              ))
          .toList(),
    );
  }

  Widget _kv(String label, String value, TextTheme text, AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: text.bodySmall?.copyWith(color: c.subtleText))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: text.bodyMedium)),
        ],
      ),
    );
  }

  /// Validate the URL before we hand it to CachedNetworkImage.
  /// Returns null (so the caller renders the initials placeholder) for:
  ///   * null / empty / whitespace
  ///   * strings that do not parse as absolute http(s) URIs
  /// CachedNetworkImage assumes the URL is valid; a bogus value (empty
  /// string, "null", asset:// paths, storage:… paths) throws before the
  /// error widget ever gets a chance to display, which used to blank the
  /// whole tile.
  static String? _safeImageUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.hasAbsolutePath) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return s;
  }

  /// The scrolling body content. Extracted so the outer Builder can wrap
  /// it in a try/catch — any exception thrown by any widget below is
  /// intercepted and rendered as a big red panel with the file/line stack
  /// instead of silently blanking the Profile Detail body.
  List<Widget> _buildBody({
    required BuildContext context,
    required UserProfile profile,
    required bool isOwn,
    required List<String> photos,
    required String? currentPhoto,
    required ColorScheme colors,
    required TextTheme text,
    required AppColorsExtension appColors,
  }) {
    final validCurrent = _safeImageUrl(currentPhoto);
    return [
      // DEBUG PROBE — a plain red 100-tall Container inserted as the first
      // child of the profile ListView. If this box does not show up when
      // opening a profile, the ListView itself is not being reached (which
      // points at a nested-Scaffold layout bug) and we will drop the inner
      // Scaffold entirely.
      Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 8),
        color: const Color(0xFFFF1744),
        alignment: Alignment.center,
        child: const Text(
          'DEBUG PROBE — profile body reached',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      // Main photo.
      AspectRatio(
        aspectRatio: 4 / 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: validCurrent == null
              ? _NoPhotoPlaceholder(
                  colors: colors,
                  appColors: appColors,
                  text: text,
                  firstName: profile.firstName,
                  isOwn: isOwn,
                  onAdd: isOwn ? () => context.push('/me/edit') : null,
                )
              : CachedNetworkImage(
                  imageUrl: validCurrent,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: colors.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => _NoPhotoPlaceholder(
                    colors: colors,
                    appColors: appColors,
                    text: text,
                    firstName: profile.firstName,
                    isOwn: isOwn,
                    onAdd: isOwn ? () => context.push('/me/edit') : null,
                    broken: true,
                  ),
                ),
        ),
      ),
      if (photos.length > 1) ...[
        const SizedBox(height: AppTheme.spacingSm),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingSm),
            itemBuilder: (_, i) {
              final thumbUrl = _safeImageUrl(photos[i]);
              return GestureDetector(
                onTap: () => setState(() => _photoIndex = i),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                      color: i == _photoIndex ? colors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: thumbUrl == null
                        ? Container(
                            width: 56, height: 56,
                            color: colors.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_not_supported_outlined,
                                size: 20, color: appColors.subtleText),
                          )
                        : CachedNetworkImage(
                            imageUrl: thumbUrl,
                            width: 56, height: 56, fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: colors.surfaceContainerHighest),
                            errorWidget: (_, __, ___) => Container(
                              width: 56, height: 56,
                              color: colors.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(Icons.broken_image_outlined,
                                  size: 20, color: appColors.subtleText),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],

      const SizedBox(height: AppTheme.spacingLg),

      // Name + age + online + edit / completeness.
      Row(
        children: [
          Expanded(
            child: Text('${profile.firstName}, ${profile.age}', style: text.headlineSmall),
          ),
          if (profile.isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: appColors.online, borderRadius: BorderRadius.circular(AppTheme.radiusXl)),
              child: Text('Online', style: text.labelSmall?.copyWith(color: Colors.white)),
            ),
          if (isOwn) ...[
            const SizedBox(width: AppTheme.spacingMd),
            CompletenessRing(score: profile.completenessScore, size: 48),
          ],
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Icon(Icons.location_on_outlined, size: 16, color: appColors.subtleText),
          const SizedBox(width: 4),
          Text('${profile.city}, ${profile.state}', style: text.bodyMedium?.copyWith(color: appColors.subtleText)),
        ],
      ),

      if (profile.hasAnyVerification) ...[
        const SizedBox(height: AppTheme.spacingMd),
        VerificationBadges(
          email: profile.emailVerified,
          phone: profile.phoneVerified,
          selfie: profile.selfieVerified,
          id: profile.idVerified,
          expanded: true,
        ),
      ] else if (isOwn) ...[
        const SizedBox(height: AppTheme.spacingMd),
        _EmptyHint(
          icon: Icons.verified_outlined,
          text: 'You have no verifications yet.',
          actionLabel: 'Get verified',
          onAction: () => context.push('/me/verification'),
        ),
      ],

      if (profile.modes.isNotEmpty) ...[
        const SizedBox(height: AppTheme.spacingMd),
        Wrap(
          spacing: AppTheme.spacingSm,
          runSpacing: AppTheme.spacingSm,
          children: profile.modes
              .map((m) => _ModeBadge(label: ModeOptions.label(m), colors: colors, text: text))
              .toList(),
        ),
      ],

      _Section(
        title: 'About Me',
        icon: Icons.person_outline,
        child: profile.aboutMe.isNotEmpty
            ? Text(profile.aboutMe, style: text.bodyLarge)
            : _EmptyHint(
                icon: Icons.edit_note_outlined,
                text: isOwn ? 'Tell people who you are — even one line helps.' : 'No bio yet.',
                actionLabel: isOwn ? 'Add bio' : null,
                onAction: isOwn ? () => context.push('/me/edit') : null,
              ),
      ),

      _Section(
        title: isOwn ? 'My Story' : 'Their Story',
        icon: Icons.format_quote_outlined,
        child: profile.prompts.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: profile.prompts.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.promptKey, style: text.labelMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(p.answer, style: text.bodyLarge),
                    ],
                  ),
                )).toList(),
              )
            : _EmptyHint(
                icon: Icons.format_quote_outlined,
                text: isOwn ? 'Answer a few prompts to add personality.' : 'No prompts yet.',
                actionLabel: isOwn ? 'Add prompts' : null,
                onAction: isOwn ? () => context.push('/me/edit') : null,
              ),
      ),

      _Section(
        title: 'Looking For',
        icon: Icons.favorite_outline,
        child: profile.lookingFor.isNotEmpty
            ? _chips(profile.lookingFor, colors.primaryContainer)
            : _EmptyHint(
                icon: Icons.favorite_outline,
                text: isOwn ? 'Tell people what you\'re open to.' : 'Not specified.',
                actionLabel: isOwn ? 'Set preferences' : null,
                onAction: isOwn ? () => context.push('/me/edit') : null,
              ),
      ),

      _Section(
        title: 'Interests',
        icon: Icons.interests_outlined,
        child: profile.interests.isNotEmpty
            ? _chips(profile.interests, colors.secondaryContainer)
            : _EmptyHint(
                icon: Icons.interests_outlined,
                text: isOwn ? 'Add interests so others can connect.' : 'No interests listed.',
                actionLabel: isOwn ? 'Add interests' : null,
                onAction: isOwn ? () => context.push('/me/edit') : null,
              ),
      ),

      _Section(
        title: 'Life Situation',
        icon: Icons.timeline_outlined,
        child: profile.lifeSituation.isNotEmpty
            ? _chips(profile.lifeSituation, colors.tertiaryContainer)
            : _EmptyHint(
                icon: Icons.timeline_outlined,
                text: isOwn ? 'Share where you are in life.' : 'Not specified.',
                actionLabel: isOwn ? 'Add details' : null,
                onAction: isOwn ? () => context.push('/me/edit') : null,
              ),
      ),

      _Section(
        title: 'Details',
        icon: Icons.info_outline,
        child: Column(
          children: [
            _kv('Gender', profile.gender, text, appColors),
            _kv('Status', profile.relationshipStatus, text, appColors),
            _kv('Location', '${profile.city}, ${profile.state}', text, appColors),
          ],
        ),
      ),
      const SizedBox(height: AppTheme.spacingXxl),
    ];
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _openConversation(UserProfile profile) async {
    final messages = context.read<MessagesProvider>();
    final myProfileId = context.read<ProfileProvider>().profileId;
    if (myProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish your profile first to start a conversation.')),
      );
      return;
    }
    if (messages.myProfileId == null) await messages.bindProfile(myProfileId);
    final mode = profile.modes.isNotEmpty ? profile.modes.first : 'date';
    final convId = await messages.startConversationWith(profile.id, mode: mode);
    if (!mounted) return;
    if (convId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start conversation.')));
      return;
    }
    context.go('/messages/$convId');
  }

  Future<void> _confirmUnblock(UserProfile profile) async {
    final ok = await context.read<BlockProvider>().unblockUser(profile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '${profile.firstName} unblocked' : 'Could not unblock.')),
    );
  }

  void _onMenu(String value, UserProfile profile, AppColorsExtension appColors, ColorScheme colors, {required bool blocked}) {
    if (value == 'report') {
      showDialog(
        context: context,
        builder: (_) => ReportDialog(userName: profile.firstName, reportedProfileId: profile.id),
      ).then((result) {
        if (result != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted. We will review it promptly.')),
          );
        }
      });
    } else if (value == 'block') {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Block ${profile.firstName}?'),
          content: const Text('They will no longer see you or be able to message you. Existing conversations become hidden for both of you.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: appColors.danger, foregroundColor: colors.onError),
              child: const Text('Block'),
            ),
          ],
        ),
      ).then((confirm) async {
        if (confirm != true || !mounted) return;
        final ok = await context.read<BlockProvider>().blockUser(profile.id);
        if (!mounted) return;
        if (ok) {
          await context.read<MessagesProvider>().loadConversations();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${profile.firstName} has been blocked')));
          context.go('/browse');
        }
      });
    } else if (value == 'unblock') {
      _confirmUnblock(profile);
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: AppTheme.iconMd, color: colors.primary),
            const SizedBox(width: AppTheme.spacingSm),
            Text(title, style: text.titleMedium),
          ]),
          const SizedBox(height: AppTheme.spacingSm),
          child,
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  final TextTheme text;
  const _ModeBadge({required this.label, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: colors.primary.withOpacity(0.4)),
      ),
      child: Text(label, style: text.labelMedium?.copyWith(color: colors.onPrimaryContainer, fontWeight: FontWeight.w600)),
    );
  }
}

/// Initials + soft gradient when a profile has no usable photo. Lifted out
/// of the AspectRatio so we can reuse it for both "no photo at all" and
/// "photo URL 404" cases without breaking the layout.
class _NoPhotoPlaceholder extends StatelessWidget {
  final ColorScheme colors;
  final AppColorsExtension appColors;
  final TextTheme text;
  final String firstName;
  final bool isOwn;
  final bool broken;
  final VoidCallback? onAdd;
  const _NoPhotoPlaceholder({
    required this.colors,
    required this.appColors,
    required this.text,
    required this.firstName,
    required this.isOwn,
    this.broken = false,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer,
            colors.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(initial, style: text.displayMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.bold,
            )),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            broken ? 'Photo unavailable' : 'No photo yet',
            style: text.bodyMedium?.copyWith(color: appColors.subtleText),
          ),
          if (isOwn && onAdd != null) ...[
            const SizedBox(height: AppTheme.spacingSm),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add photo'),
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Soft, consistent empty-state used inside profile sections so the page
/// never looks blank — even for a brand-new user with no prompts/interests.
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyHint({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tt = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppTheme.iconMd, color: appColors.subtleText),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Text(text, style: tt.bodyMedium?.copyWith(color: appColors.subtleText)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppTheme.spacingSm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Rendered in place of the profile body when any widget below the try/catch
/// throws. Shows the exception text, first six stack frames, and lets the
/// user copy or return to Browse — nothing is silent.
class _InlineError extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  final AppColorsExtension appColors;
  final TextTheme text;
  const _InlineError({
    required this.error,
    required this.stack,
    required this.appColors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final frames = stack.toString().split('\n').take(8).join('\n');
    final fullText = 'Profile Detail render error\n\n$error\n\n$frames';
    return Container(
      color: const Color(0xFFFFEBEE),
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.error_outline, color: Color(0xFFB71C1C), size: 22),
              SizedBox(width: 8),
              Text(
                'Profile Detail render error',
                style: TextStyle(
                  color: Color(0xFFB71C1C),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ]),
            const SizedBox(height: AppTheme.spacingMd),
            SelectableText(
              error.toString(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFB71C1C),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            const Text(
              'Stack (first 8 frames):',
              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF7F0000)),
            ),
            const SizedBox(height: 4),
            SelectableText(
              frames,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF7F0000),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Wrap(
              spacing: AppTheme.spacingSm,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error report copied to clipboard')),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Copy error'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/browse'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to Browse'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
