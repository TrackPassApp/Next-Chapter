import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';
import '../widgets/admin/admin_metrics_tab.dart';
import '../widgets/admin/admin_users_tab.dart';
import '../widgets/admin/admin_reports_tab.dart';
import '../widgets/admin/admin_verification_tab.dart';
import '../widgets/admin/admin_log_tab.dart';
import '../widgets/admin/admin_roles_tab.dart';
import '../widgets/admin/admin_rc1_tabs.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    // Web-only: show a friendly block on mobile.
    if (!kIsWeb) {
      return _GuardScreen(
        title: 'Desktop required',
        message: 'The Admin Dashboard is web-only. Please open Next Chapter in a desktop browser.',
        icon: Icons.computer_outlined,
      );
    }

    // Defence-in-depth admin guard. The router already redirects non-admins,
    // but if this screen ever renders without the role, refuse.
    if (!auth.canModerate) {
      return _GuardScreen(
        title: 'Forbidden',
        message: 'This screen is restricted to platform administrators and moderators.',
        icon: Icons.lock_outline,
      );
    }

    // Role-adaptive tab set.
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.dashboard_outlined),    text: 'Overview'),
      const Tab(icon: Icon(Icons.people_outline),        text: 'Users'),
      const Tab(icon: Icon(Icons.flag_outlined),         text: 'Reports'),
      const Tab(icon: Icon(Icons.verified_outlined),     text: 'Verification'),
      const Tab(icon: Icon(Icons.forum_outlined),        text: 'Community'),
      const Tab(icon: Icon(Icons.stars_outlined),        text: 'Stories'),
      const Tab(icon: Icon(Icons.campaign_outlined),     text: 'Announcements'),
      const Tab(icon: Icon(Icons.person_off_outlined),   text: 'Deleted'),
      const Tab(icon: Icon(Icons.history),               text: 'Moderation Log'),
      const Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'Roles'),
    ];
    final pages = <Widget>[
      const AdminMetricsTab(),
      const AdminUsersTab(),
      const AdminReportsTab(),
      const AdminVerificationTab(),
      const AdminCommunityTab(),
      const AdminStoriesTab(),
      const AdminAnnouncementsTab(),
      const AdminDeletedTab(),
      const AdminLogTab(),
      const AdminRolesTab(),
    ];

    final roleLabel = (auth.role ?? 'unknown').toUpperCase();
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: isMobile ? 8 : NavigationToolbar.kMiddleSpacing,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  isMobile ? 'Admin' : 'Admin Dashboard',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: isMobile ? AppTheme.spacingSm : AppTheme.spacingMd),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: 2),
                decoration: BoxDecoration(
                  color: appColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: appColors.danger.withOpacity(0.3)),
                ),
                child: Text(
                  roleLabel,
                  style: text.labelSmall?.copyWith(
                    color: appColors.danger,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (isMobile)
              IconButton(
                tooltip: 'Exit admin',
                onPressed: () => context.go('/browse'),
                icon: const Icon(Icons.exit_to_app),
              )
            else
              TextButton.icon(
                onPressed: () => context.go('/browse'),
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Exit admin'),
              ),
            SizedBox(width: isMobile ? 4 : AppTheme.spacingMd),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: colors.primary,
            unselectedLabelColor: colors.onSurfaceVariant,
            indicatorColor: colors.primary,
            tabs: tabs,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: TabBarView(children: pages),
        ),
      ),
    );
  }
}

class _GuardScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  const _GuardScreen({required this.title, required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: appColors.subtleText),
              const SizedBox(height: AppTheme.spacingMd),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingSm),
              Text(message, style: text.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingLg),
              ElevatedButton(
                onPressed: () => context.go('/browse'),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// End of admin shell.
