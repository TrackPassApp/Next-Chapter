import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/browse_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/profile_provider.dart';
import '../screens/landing_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/browse_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/profile_detail_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/activity_screen.dart';
import '../screens/about_screen.dart';
import '../screens/community_screen.dart';
import '../screens/founder_letter_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/room_chat_screen.dart';
import '../screens/success_stories_screen.dart';
import '../screens/welcome_letter_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/my_profile_screen.dart';
import '../screens/privacy_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/app_shell.dart';
import '../screens/verification_status_screen.dart';

class AppRouter {
  static GoRouter router(AuthProvider authProvider, {ProfileProvider? profileProvider}) => GoRouter(
    initialLocation: '/',
    refreshListenable: profileProvider == null
        ? authProvider
        : Listenable.merge([authProvider, profileProvider]),
    redirect: (context, state) {
      if (authProvider.isLoading) return null;

      final loggedIn = authProvider.isLoggedIn;
      final loc = state.matchedLocation;

      final isAuthRoute = loc == '/login' || loc == '/signup' || loc == '/forgot-password';
      final isPublic = loc == '/' || loc == '/privacy' || loc == '/terms' || isAuthRoute;

      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && (loc == '/' || isAuthRoute)) return '/browse';

      // Logged-in users with an incomplete profile are funneled to the
      // onboarding wizard ONLY when they try to use the social surfaces
      // (browse / inbox / activity). They can still reach their own profile,
      // settings, verification, edit-profile, etc. — so the app never feels
      // like a dead-end while they're filling things in.
      const _gatedForIncomplete = {'/browse', '/inbox', '/activity', '/community'};
      if (loggedIn && _gatedForIncomplete.contains(loc)) {
        try {
          final pp = Provider.of<ProfileProvider>(context, listen: false);
          if (pp.profile != null && !pp.profile!.isComplete) {
            return '/welcome';
          }
        } catch (_) {
          // Provider not in scope (rare); skip the check.
        }
      }

      if (loc == '/welcome' && !loggedIn) return '/login';
      if (loc == '/welcome' && loggedIn) {
        try {
          final pp = Provider.of<ProfileProvider>(context, listen: false);
          if (pp.profile != null && pp.profile!.isComplete) return '/browse';
        } catch (_) {}
      }

      if (loc.startsWith('/admin') && !authProvider.canModerate) {
        return loggedIn ? '/browse' : '/login';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const AuthScreen(isSignUp: true)),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/welcome-letter', builder: (_, __) => const WelcomeLetterScreen()),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(path: '/about/letter', builder: (_, __) => const FounderLetterScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/notifications/settings',
          builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(path: '/stories', builder: (_, __) => const SuccessStoriesScreen()),
      GoRoute(
        path: '/messages/:id',
        builder: (context, state) => ChangeNotifierProvider.value(
          value: context.read<MessagesProvider>(),
          child: ChatScreen(conversationId: state.pathParameters['id']!),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/browse',
              builder: (context, _) => ChangeNotifierProvider(
                create: (_) => BrowseProvider()..loadProfiles(),
                child: const BrowseScreen(),
              ),
              routes: [
                GoRoute(
                  path: 'profile/:id',
                  builder: (_, state) => ProfileDetailScreen(profileId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/activity', builder: (_, __) => const ActivityScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/community',
              builder: (_, __) => const CommunityScreen(),
              routes: [
                GoRoute(
                  path: ':slug',
                  builder: (_, state) =>
                      RoomChatScreen(slug: state.pathParameters['slug']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/inbox', builder: (_, __) => const MessagesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/me',
              builder: (_, __) => const MyProfileScreen(),
              routes: [
                GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
                GoRoute(path: 'verification', builder: (_, __) => const VerificationStatusScreen()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          ]),
        ],
      ),
      // Top-level fallbacks for legacy / direct links (kept so existing
      // context.go('/profile/:id') etc. doesn't break). The detail screen
      // itself validates that :id is a UUID — anything else (e.g. an old
      // numeric '/profile/2' bookmark) is bounced safely back to /browse.
      GoRoute(
        path: '/profile/:id',
        redirect: (_, state) {
          final id = state.pathParameters['id'] ?? '';
          // Forward UUIDs into the canonical in-shell route so the bottom
          // navigation stays mounted.
          final uuidRe = RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          );
          if (uuidRe.hasMatch(id)) return '/browse/profile/$id';
          // Legacy mock numeric ids (id='2', '7' …) just go home.
          return '/browse';
        },
        builder: (_, __) => const SizedBox.shrink(),
      ),
      GoRoute(path: '/verification', builder: (_, __) => const VerificationStatusScreen()),
      GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
    ],
  );
}
