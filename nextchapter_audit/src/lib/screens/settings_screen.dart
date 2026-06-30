import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
                title: 'Legal',
                children: [
                  _SettingsTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () => context.go('/privacy')),
                  _SettingsTile(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () => context.go('/terms')),
                ],
                colors: colors,
                text: text,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _SettingsSection(
                title: 'Danger Zone',
                children: [
                  _SettingsTile(
                    icon: Icons.bug_report_outlined,
                    title: 'Run Diagnostics',
                    onTap: () => context.push('/diagnostics'),
                  ),
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
              const SizedBox(height: AppTheme.spacingLg),
              // Build label — lets the user verify the deployed bundle is
              // actually the latest one. Tap to copy.
              Center(
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: AppConfig.buildLabel));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Build label copied to clipboard')),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd,
                      vertical: AppTheme.spacingSm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_outlined,
                            size: AppTheme.iconSm, color: appColors.subtleText),
                        const SizedBox(width: AppTheme.spacingSm),
                        Text(
                          'Build: ${AppConfig.buildLabel}',
                          style: text.bodySmall?.copyWith(
                            color: appColors.subtleText,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
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

  Future<void> _delete() async {
    setState(() => _deleting = true);

    final auth = context.read<AuthProvider>();
    final profileProvider = context.read<ProfileProvider>();

    try {
      final userId = auth.userId;
      if (userId != null) {
        // Delete all profile data from Supabase (cascade deletes photos, interests, etc.)
        await profileProvider.deleteAccount(userId);
      }
      await auth.logout();
    } catch (_) {
      // Even if DB deletion partially fails, sign the user out.
      await auth.logout();
    }

    if (mounted) {
      Navigator.pop(context);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delete Account?', style: widget.text.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('This will permanently remove:', style: widget.text.bodyMedium),
          const SizedBox(height: AppTheme.spacingSm),
          ...['Your profile and photos', 'All messages and conversations', 'All personal data'].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingXs),
              child: Row(children: [
                Icon(Icons.remove_circle_outline, size: AppTheme.iconSm, color: widget.appColors.danger),
                const SizedBox(width: AppTheme.spacingSm),
                Text(item, style: widget.text.bodySmall),
              ]),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text('This action cannot be undone.', style: widget.text.bodySmall?.copyWith(color: widget.appColors.danger, fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        TextButton(onPressed: _deleting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _deleting ? null : _delete,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.appColors.danger,
            foregroundColor: widget.colors.onError,
            minimumSize: const Size(80, 40),
          ),
          child: _deleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Delete Account'),
        ),
      ],
    );
  }
}
