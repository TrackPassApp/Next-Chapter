import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../theme/theme.dart';

/// Circular avatar that lives in the top-left of every main app screen.
///
/// Behaviour:
///   • Shows the user's primary photo if they have one.
///   • Falls back to a person icon if no photo is uploaded.
///   • Tap → if profile is complete and saved → /profile/:myProfileId
///         → if profile exists but is incomplete → /welcome
///         → if no profile yet                  → /edit-profile
///         → if logged out                      → /login
///
/// Designed to be used as `AppBar.leading`.
class MyAvatarLeading extends StatelessWidget {
  const MyAvatarLeading({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final profileId = context.watch<ProfileProvider>().profileId;
    final loggedIn = context.watch<AuthProvider>().isLoggedIn;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final hasPhoto = profile != null && profile.photoUrls.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(left: AppTheme.spacingMd),
      child: GestureDetector(
        onTap: () => _openMyProfile(context, loggedIn: loggedIn, profileId: profileId, isComplete: profile?.isComplete ?? false),
        child: Tooltip(
          message: 'My profile',
          child: CircleAvatar(
            radius: 18,
            backgroundColor: colors.surfaceContainerHighest,
            backgroundImage: hasPhoto ? CachedNetworkImageProvider(profile.photoUrls.first) : null,
            child: hasPhoto
                ? null
                : Icon(Icons.person, size: 22, color: appColors.subtleText),
          ),
        ),
      ),
    );
  }

  void _openMyProfile(BuildContext context, {required bool loggedIn, required String? profileId, required bool isComplete}) {
    if (!loggedIn) {
      context.go('/login');
      return;
    }
    if (profileId == null) {
      context.go('/me/edit');
      return;
    }
    if (!isComplete) {
      context.go('/welcome');
      return;
    }
    // Open the My Profile branch (which renders the public profile detail
    // with Edit instead of Message/Block/Report).
    context.go('/me');
  }
}
