import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/profile_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/common/completeness_ring.dart';
import '../widgets/common/report_dialog.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String profileId;
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  int _photoIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // If viewing own profile, reuse the provider so we always show the freshest copy.
    final auth = context.read<AuthProvider>();
    final own = context.read<ProfileProvider>().profile;
    if (own != null && own.id == widget.profileId) {
      setState(() {
        _profile = own;
        _loading = false;
      });
      return;
    }

    if (!SupabaseService.isConfigured || SupabaseService.client == null) {
      setState(() {
        _loading = false;
        _error = 'Supabase is not connected.';
      });
      return;
    }

    try {
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
        _error = 'Could not load profile.';
      });
    }

    // Silence unused warning — auth is read for future block/report enforcement.
    auth.userId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                Icon(Icons.person_off_outlined, size: 64, color: appColors.subtleText),
                const SizedBox(height: AppTheme.spacingMd),
                Text(_error ?? 'Profile not found', style: text.titleMedium),
                const SizedBox(height: AppTheme.spacingMd),
                ElevatedButton(onPressed: () => context.pop(), child: const Text('Go back')),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final ownId = context.watch<ProfileProvider>().profile?.id;
    final isOwn = ownId != null && ownId == profile.id;
    final headerPhoto = profile.photoUrls.isNotEmpty ? profile.photoUrls[_photoIndex.clamp(0, profile.photoUrls.length - 1)] : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: isMobile ? 360 : 420,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (headerPhoto != null)
                    CachedNetworkImage(
                      imageUrl: headerPhoto,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: colors.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => Container(
                        color: colors.surfaceContainerHighest,
                        child: Icon(Icons.person, size: 80, color: appColors.subtleText),
                      ),
                    )
                  else
                    Container(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.person, size: 96, color: appColors.subtleText),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppTheme.spacingMd,
                    right: AppTheme.spacingMd,
                    bottom: AppTheme.spacingMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${profile.firstName}, ${profile.age}',
                                style: text.headlineMedium?.copyWith(color: Colors.white),
                              ),
                            ),
                            if (profile.isOnline)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: appColors.online,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                                ),
                                child: Text('Online', style: text.labelSmall?.copyWith(color: Colors.white)),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacingXs),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.white70),
                            const SizedBox(width: AppTheme.spacingXs),
                            Text('${profile.city}, ${profile.state}', style: text.bodyMedium?.copyWith(color: Colors.white70)),
                          ],
                        ),
                        if (profile.hasAnyVerification) ...[
                          const SizedBox(height: AppTheme.spacingSm),
                          _VerificationBadges(profile: profile, text: text, appColors: appColors),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: isOwn
                ? [
                    IconButton(
                      tooltip: 'Edit profile',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => context.push('/edit-profile').then((_) => _load()),
                    ),
                  ]
                : [
                    Consumer<BlockProvider>(
                      builder: (_, blockProvider, __) {
                        final blocked = blockProvider.hasBlocked(profile.id);
                        return PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) => _onMenu(value, profile, appColors, colors, blocked: blocked),
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
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo thumb strip — only when 2+ photos.
                      if (profile.photoUrls.length > 1)
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: profile.photoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingSm),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => setState(() => _photoIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                                  border: Border.all(
                                    color: i == _photoIndex ? colors.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                                  child: CachedNetworkImage(
                                    imageUrl: profile.photoUrls[i],
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (profile.photoUrls.length > 1) const SizedBox(height: AppTheme.spacingMd),

                      // Modes + completeness ring header for own profile.
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: AppTheme.spacingSm,
                              runSpacing: AppTheme.spacingSm,
                              children: profile.modes
                                  .map((m) => _ModeBadge(label: ModeOptions.label(m), colors: colors, text: text))
                                  .toList(),
                            ),
                          ),
                          if (isOwn) ...[
                            const SizedBox(width: AppTheme.spacingMd),
                            CompletenessRing(score: profile.completenessScore, size: 56),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingLg),

                      if (profile.aboutMe.trim().isNotEmpty)
                        _ProfileSection(
                          title: 'About Me',
                          icon: Icons.person_outline,
                          child: Text(profile.aboutMe, style: text.bodyLarge),
                          colors: colors,
                          text: text,
                        ),

                      if (profile.prompts.isNotEmpty)
                        _ProfileSection(
                          title: 'Their Story',
                          icon: Icons.format_quote_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: profile.prompts
                                .map((p) => _PromptCard(prompt: p, colors: colors, text: text))
                                .toList(),
                          ),
                          colors: colors,
                          text: text,
                        ),

                      if (profile.lookingFor.isNotEmpty)
                        _ProfileSection(
                          title: 'Looking For',
                          icon: Icons.favorite_outline,
                          child: Wrap(
                            spacing: AppTheme.spacingSm,
                            runSpacing: AppTheme.spacingSm,
                            children: profile.lookingFor
                                .map((l) => Chip(
                                      label: Text(l),
                                      backgroundColor: colors.primaryContainer.withOpacity(0.5),
                                      side: BorderSide.none,
                                    ))
                                .toList(),
                          ),
                          colors: colors,
                          text: text,
                        ),

                      if (profile.interests.isNotEmpty)
                        _ProfileSection(
                          title: 'Interests',
                          icon: Icons.interests_outlined,
                          child: Wrap(
                            spacing: AppTheme.spacingSm,
                            runSpacing: AppTheme.spacingSm,
                            children: profile.interests
                                .map((i) => Chip(
                                      label: Text(i),
                                      backgroundColor: colors.secondaryContainer.withOpacity(0.5),
                                      side: BorderSide.none,
                                    ))
                                .toList(),
                          ),
                          colors: colors,
                          text: text,
                        ),

                      if (profile.lifeSituation.isNotEmpty)
                        _ProfileSection(
                          title: 'Life Situation',
                          icon: Icons.auto_awesome_outlined,
                          child: Wrap(
                            spacing: AppTheme.spacingSm,
                            runSpacing: AppTheme.spacingSm,
                            children: profile.lifeSituation
                                .map((l) => Chip(
                                      label: Text(l),
                                      backgroundColor: colors.tertiaryContainer.withOpacity(0.5),
                                      side: BorderSide.none,
                                    ))
                                .toList(),
                          ),
                          colors: colors,
                          text: text,
                        ),

                      _ProfileSection(
                        title: 'Details',
                        icon: Icons.info_outline,
                        child: Column(
                          children: [
                            _DetailRow(label: 'Gender', value: profile.gender, text: text, appColors: appColors),
                            _DetailRow(label: 'Status', value: profile.relationshipStatus, text: text, appColors: appColors),
                            _DetailRow(label: 'Location', value: '${profile.city}, ${profile.state}', text: text, appColors: appColors),
                          ],
                        ),
                        colors: colors,
                        text: text,
                      ),
                      const SizedBox(height: AppTheme.spacingXl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: isOwn
                  ? ElevatedButton.icon(
                      onPressed: () {
                        // Incomplete own profile → onboarding wizard; complete → editor.
                        if (!profile.isComplete) {
                          context.go('/welcome');
                        } else {
                          context.push('/edit-profile').then((_) => _load());
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

  Future<void> _openConversation(UserProfile profile) async {
    final messages = context.read<MessagesProvider>();
    final myProfileId = context.read<ProfileProvider>().profileId;
    if (myProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish your profile first to start a conversation.')),
      );
      return;
    }

    if (messages.myProfileId == null) {
      await messages.bindProfile(myProfileId);
    }

    final mode = profile.modes.isNotEmpty ? profile.modes.first : 'date';
    final convId = await messages.startConversationWith(profile.id, mode: mode);

    if (!mounted) return;
    if (convId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start conversation. Please try again.')),
      );
      return;
    }
    context.go('/messages/$convId');
  }

  Future<void> _confirmUnblock(UserProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Unblock ${profile.firstName}?'),
        content: const Text('They will be able to message you and see you in browse again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unblock')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await context.read<BlockProvider>().unblockUser(profile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '${profile.firstName} unblocked' : 'Could not unblock. Try again.')),
    );
  }

  void _onMenu(String value, UserProfile profile, AppColorsExtension appColors, ColorScheme colors, {required bool blocked}) {
    if (value == 'report') {
      showDialog(
        context: context,
        builder: (_) => ReportDialog(
          userName: profile.firstName,
          reportedProfileId: profile.id,
        ),
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
          content: const Text(
            'They will no longer be able to message or see your profile. '
            'Any existing conversation will be hidden from both of you.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: appColors.danger,
                foregroundColor: colors.onError,
                minimumSize: const Size(80, 40),
              ),
              child: const Text('Block'),
            ),
          ],
        ),
      ).then((confirm) async {
        if (confirm != true || !mounted) return;
        final messages = context.read<MessagesProvider>();
        // Close any open conversation with this person so we don't sit on a now-RLS-hidden row.
        await messages.closeActiveConversation();
        final ok = await context.read<BlockProvider>().blockUser(profile.id);
        if (!mounted) return;
        if (ok) {
          // Refresh inbox so the blocked conversation disappears.
          await messages.loadConversations();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${profile.firstName} has been blocked')),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not block. Please try again.')),
          );
        }
      });
    } else if (value == 'unblock') {
      _confirmUnblock(profile);
    }
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

class _PromptCard extends StatelessWidget {
  final PromptAnswer prompt;
  final ColorScheme colors;
  final TextTheme text;
  const _PromptCard({required this.prompt, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(prompt.promptKey, style: text.labelMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(prompt.answer, style: text.bodyLarge?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

class _VerificationBadges extends StatelessWidget {
  final UserProfile profile;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _VerificationBadges({required this.profile, required this.text, required this.appColors});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.spacingSm,
      children: [
        if (profile.emailVerified) _badge('Email', appColors.verified),
        if (profile.phoneVerified) _badge('Phone', appColors.verified),
        if (profile.selfieVerified) _badge('Selfie', appColors.verified),
        if (profile.idVerified) _badge('ID', appColors.success),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: text.labelSmall?.copyWith(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final ColorScheme colors;
  final TextTheme text;

  const _ProfileSection({required this.title, required this.icon, required this.child, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppTheme.iconMd, color: colors.primary),
              const SizedBox(width: AppTheme.spacingSm),
              Text(title, style: text.titleMedium),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _DetailRow({required this.label, required this.value, required this.text, required this.appColors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: text.bodySmall?.copyWith(color: appColors.subtleText))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}
