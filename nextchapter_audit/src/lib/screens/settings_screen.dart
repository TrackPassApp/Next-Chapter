import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/common/my_avatar_leading.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        leading: const MyAvatarLeading(),
        leadingWidth: 64,
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            children: [
              _SettingsSection(
                title: 'Account',
                children: [
                  _SettingsTile(icon: Icons.person_outline, title: 'Edit Profile', onTap: () {
                    context.go('/me/edit');
                  }),
                  _SettingsTile(icon: Icons.verified_user_outlined, title: 'Verification Status', onTap: () {
                    context.go('/me/verification');
                  }),
                  _SettingsTile(icon: Icons.block_outlined, title: 'Blocked Users', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No blocked users')));
                  }),
                ],
                colors: colors,
                text: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _SettingsSection(
                title: 'Demo & Beta Tools',
                children: [
                  _SettingsTile(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Populate demo conversations',
                    onTap: () => _seedDemoConversations(context, appColors),
                  ),
                ],
                colors: colors,
                text: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _SettingsSection(
                title: 'Support Next Chapter',
                children: [
                  _SettingsTile(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Support Next Chapter',
                    onTap: () => _showSupportDialog(context, colors, text, appColors),
                  ),
                ],
                colors: colors,
                text: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _SettingsSection(
                title: 'Legal',
                children: [
                  _SettingsTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () => context.go('/privacy')),
                  _SettingsTile(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () => context.go('/terms')),
                ],
                colors: colors,
                text: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              // Admin gateway — only visible to server-approved admins,
              // moderators, and super_admins. Never rendered for regular users.
              Builder(builder: (context) {
                final auth = context.watch<AuthProvider>();
                if (!auth.canModerate) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                  child: _SettingsSection(
                    title: 'Moderation',
                    children: [
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Admin Dashboard (${(auth.role ?? "").toUpperCase()})',
                        color: appColors.danger,
                        onTap: () => context.go('/admin'),
                      ),
                      _SettingsTile(
                        icon: Icons.bug_report_outlined,
                        title: 'Diagnostics',
                        onTap: () => context.push('/admin/diagnostics'),
                      ),
                    ],
                    colors: colors,
                    text: text,
                  ),
                );
              }),
              _SettingsSection(
                title: 'Danger Zone',
                children: [
                  _SettingsTile(
                    icon: Icons.logout,
                    title: 'Log Out',
                    color: appColors.warning,
                    onTap: () {
                      context.read<AuthProvider>().logout();
                      context.go('/');
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete Account',
                    color: appColors.danger,
                    onTap: () => _showDeleteDialog(context, colors, text, appColors),
                  ),
                ],
                colors: colors,
                text: text,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, ColorScheme colors, TextTheme text, AppColorsExtension appColors) {
    showDialog(
      context: context,
      builder: (_) => _DeleteAccountDialog(colors: colors, text: text, appColors: appColors),
    );
  }

  void _showSupportDialog(BuildContext context, ColorScheme colors, TextTheme text, AppColorsExtension appColors) {
    showDialog(
      context: context,
      builder: (_) => _SupportDialog(colors: colors, text: text, appColors: appColors),
    );
  }

  Future<void> _seedDemoConversations(BuildContext context, AppColorsExtension appColors) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = SupabaseService.client;
    if (db == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Supabase is not connected.')));
      return;
    }
    try {
      final n = await db.rpc('seed_demo_conversations_for_me');
      if (!context.mounted) return;
      // Force the inbox to refresh so the seeded conversations show up immediately.
      await context.read<MessagesProvider>().loadConversations();
      messenger.showSnackBar(SnackBar(
        content: Text(n is int && n > 0
            ? 'Seeded $n demo conversation${n == 1 ? "" : "s"}. Open Messages to see them.'
            : 'Demo conversations are already in your inbox.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not seed demo conversations: $e')));
    }
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final ColorScheme colors;
  final TextTheme text;

  const _SettingsSection({required this.title, required this.children, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleSmall?.copyWith(color: colors.primary)),
        const SizedBox(height: AppTheme.spacingSm),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile({required this.icon, required this.title, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: color ?? theme.colorScheme.onSurface),
      title: Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
      trailing: Icon(Icons.chevron_right, color: theme.extension<AppColorsExtension>()!.subtleText),
      onTap: onTap,
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _DeleteAccountDialog({required this.colors, required this.text, required this.appColors});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _deleting = false;
  bool _understand = false;
  final _confirmCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _error;

  static const _confirmPhrase = 'DELETE';

  bool get _canDelete =>
      _understand &&
      _confirmCtrl.text.trim().toUpperCase() == _confirmPhrase &&
      !_deleting;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final db = SupabaseService.client;

    try {
      if (db == null) {
        throw StateError('Supabase is not connected.');
      }
      // Server-authoritative soft delete. Redacts PII, purges photos + child
      // rows, writes moderation_log 'self_delete'. See migration 014.
      await db.rpc('request_account_deletion', params: {
        'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      });
      await auth.logout();
      if (!mounted) return;
      Navigator.pop(context);
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Could not delete account: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = widget.appColors;
    final text = widget.text;
    final colors = widget.colors;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: appColors.danger, size: 40),
      title: Text('Delete your account?', style: text.titleLarge),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This is a serious, mostly-permanent action. Please read the '
                'details below before confirming.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              _Section(
                title: 'Immediately',
                icon: Icons.flash_on_outlined,
                color: appColors.danger,
                items: const [
                  'Your profile, photos, prompts, interests, and other personal details are removed from the app.',
                  'You are hidden from Browse and cannot appear in new matches.',
                  'You cannot send new messages, and other users cannot start new conversations with you.',
                  'You are signed out on this device.',
                ],
                textStyle: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              _Section(
                title: 'Kept for safety (admin-only)',
                icon: Icons.shield_outlined,
                color: appColors.subtleText,
                items: const [
                  'Messages you sent stay visible to the people you sent them to and to platform moderators — needed to investigate reports.',
                  'Reports filed by or against your account remain.',
                  'The moderation log records that you self-deleted, when, and (if you shared it) why.',
                ],
                textStyle: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              _Section(
                title: 'After 30 days',
                icon: Icons.event_available_outlined,
                color: appColors.subtleText,
                items: const [
                  'A future automated job will permanently erase all remaining traces of your account. Until then, an admin can recover the account only in response to a legal or safety request.',
                ],
                textStyle: text,
              ),
              const SizedBox(height: AppTheme.spacingLg),

              TextField(
                controller: _reasonCtrl,
                enabled: !_deleting,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional — helps us improve)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              CheckboxListTile(
                value: _understand,
                onChanged: _deleting
                    ? null
                    : (v) => setState(() => _understand = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'I understand this deletes my profile and I cannot log back into this account.',
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),

              Text('Type DELETE to confirm:', style: text.bodySmall),
              const SizedBox(height: 4),
              TextField(
                controller: _confirmCtrl,
                enabled: !_deleting && _understand,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _confirmPhrase,
                  border: const OutlineInputBorder(),
                  errorText: _confirmCtrl.text.isNotEmpty &&
                          _confirmCtrl.text.trim().toUpperCase() != _confirmPhrase
                      ? 'Must match exactly'
                      : null,
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppTheme.spacingMd),
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingSm),
                  decoration: BoxDecoration(
                    color: appColors.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(color: appColors.danger.withOpacity(0.3)),
                  ),
                  child: Text(_error!,
                      style: text.bodySmall?.copyWith(color: appColors.danger)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: _canDelete ? _delete : null,
          style: FilledButton.styleFrom(
            backgroundColor: appColors.danger,
            foregroundColor: colors.onError,
            disabledBackgroundColor: appColors.danger.withOpacity(0.3),
          ),
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete my account'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
  final TextTheme textStyle;
  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: AppTheme.iconSm, color: color),
          const SizedBox(width: AppTheme.spacingSm),
          Text(title, style: textStyle.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          )),
        ]),
        const SizedBox(height: 4),
        ...items.map((s) => Padding(
              padding: const EdgeInsets.only(left: 28, top: 2, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: textStyle.bodySmall),
                  Expanded(child: Text(s, style: textStyle.bodySmall)),
                ],
              ),
            )),
      ],
    );
  }
}


class _SupportDialog extends StatelessWidget {
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _SupportDialog({
    required this.colors,
    required this.text,
    required this.appColors,
  });

  Future<void> _launchDonate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = AppConfig.donateUrl.trim();
    if (url.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Donation link coming soon. Thanks for wanting to help!'),
      ));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = AppConfig.donateUrl.trim();
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = AppConfig.donateUrl.trim().isNotEmpty;

    return AlertDialog(
      icon: Icon(Icons.volunteer_activism_outlined,
          color: colors.primary, size: 40),
      title: Text('Support Next Chapter', style: text.titleLarge),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Free-forever pledge — this is the promise B11 must protect.
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withOpacity(0.35),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: AppTheme.iconSm, color: colors.primary),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Text(
                        'Messaging is 100% free — always. No paywalls, no '
                        'subscriptions, no "pay to see who liked you".',
                        style: text.bodySmall
                            ?.copyWith(color: colors.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              Text(
                'Next Chapter is built and run by a tiny team. If you want to '
                'chip in for hosting, moderation, and safety tools, a one-time '
                'donation goes a long way.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacingSm),

              _SupportRow(
                icon: Icons.check_circle_outline,
                label: 'One-time only — never a subscription.',
                text: text,
                color: appColors.subtleText,
              ),
              _SupportRow(
                icon: Icons.check_circle_outline,
                label: 'Donating never changes what you see or who sees you.',
                text: text,
                color: appColors.subtleText,
              ),
              _SupportRow(
                icon: Icons.check_circle_outline,
                label: 'Your data is never sold. Ever.',
                text: text,
                color: appColors.subtleText,
              ),

              if (!hasUrl) ...[
                const SizedBox(height: AppTheme.spacingMd),
                Text(
                  'A donation link will appear here soon. Thanks for wanting '
                  'to support the app.',
                  style: text.bodySmall
                      ?.copyWith(color: appColors.subtleText),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (hasUrl)
          TextButton.icon(
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.copy_outlined, size: AppTheme.iconSm),
            label: const Text('Copy link'),
          ),
        FilledButton.icon(
          onPressed: () => _launchDonate(context),
          icon: const Icon(Icons.favorite_outline, size: AppTheme.iconSm),
          label: Text(hasUrl ? 'Donate' : 'Notify me'),
        ),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextTheme text;
  final Color color;

  const _SupportRow({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.iconSm, color: color),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Text(label, style: text.bodySmall?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
