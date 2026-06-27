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
    if (!auth.isAdmin) {
      return _GuardScreen(
        title: 'Forbidden',
        message: 'This screen is restricted to platform administrators.',
        icon: Icons.lock_outline,
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Text('Admin Dashboard'),
              const SizedBox(width: AppTheme.spacingMd),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: 2),
                decoration: BoxDecoration(
                  color: appColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: appColors.danger.withOpacity(0.3)),
                ),
                child: Text('ADMIN', style: text.labelSmall?.copyWith(color: appColors.danger, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => context.go('/browse'),
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: const Text('Exit admin'),
            ),
            const SizedBox(width: AppTheme.spacingMd),
          ],
          bottom: TabBar(
            isScrollable: false,
            labelColor: colors.primary,
            unselectedLabelColor: colors.onSurfaceVariant,
            indicatorColor: colors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.flag_outlined), text: 'Reports'),
              Tab(icon: Icon(Icons.verified_outlined), text: 'Verification'),
              Tab(icon: Icon(Icons.history), text: 'Moderation Log'),
            ],
          ),
        ),
        body: const Padding(
          padding: EdgeInsets.all(AppTheme.spacingMd),
          child: TabBarView(
            children: [
              AdminMetricsTab(),
              AdminUsersTab(),
              AdminReportsTab(),
              AdminVerificationTab(),
              AdminLogTab(),
            ],
          ),
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
