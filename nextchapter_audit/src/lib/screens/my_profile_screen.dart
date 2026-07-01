import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/theme.dart';
import '../widgets/profile/profile_completion_card.dart';
import '../widgets/support/support_next_chapter_card.dart';
import 'profile_detail_screen.dart';

/// "My Profile" tab.
///
/// Routes intelligently:
///   • Logged out → /login
///   • No profile yet → /edit-profile
///   • Incomplete profile → /welcome (onboarding)
///   • Otherwise → renders ProfileDetailScreen for the user's own profile,
///     which already shows the Edit Profile button for own profile and
///     hides Block/Report.
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;

    if (!auth.isLoggedIn) {
      return _placeholder(text, colors, 'Sign in to view your profile',
          actionLabel: 'Log in', onAction: () => context.go('/login'));
    }
    if (profile.profileId == null) {
      return _placeholder(text, colors, 'Set up your profile to get started',
          actionLabel: 'Create profile', onAction: () => context.go('/me/edit'));
    }
    if (profile.profile != null && !profile.profile!.isComplete) {
      return _placeholder(text, colors, 'Finish your profile to see how others see you',
          actionLabel: 'Complete profile', onAction: () => context.go('/welcome'));
    }

    // Render the public profile detail screen for own profile, with a small
    // Support Next Chapter banner above it (never a paywall).
    return Column(
      children: [
        const SupportNextChapterCard(variant: SupportVariant.banner),
        const ProfileCompletionCard(),
        Expanded(child: ProfileDetailScreen(profileId: profile.profileId!)),
      ],
    );
  }

  Widget _placeholder(TextTheme text, ColorScheme colors, String message,
      {required String actionLabel, required VoidCallback onAction}) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle_outlined, size: 56, color: colors.primary),
              const SizedBox(height: AppTheme.spacingMd),
              Text(message, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingMd),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
