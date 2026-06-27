import 'package:flutter/foundation.dart';
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
import '../screens/admin_screen.dart';
import '../screens/privacy_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/app_shell.dart';
import '../screens/verification_status_screen.dart';
import '../screens/diagnostics_screen.dart';

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

      if (!loggedIn && !isPublic && loc != '/diagnostics') return '/login';
      if (loggedIn && (loc == '/' || isAuthRoute)) return '/browse';

      // Logged-in users with an incomplete profile go to the wizard.
      // We read profileProvider via Provider.of(context, listen:false) to
      // avoid wiring it into refreshListenable (auth changes are what drive
      // re-evaluation; profile completion changes trigger a manual go).
      if (loggedIn && loc != '/welcome' && loc != '/admin' && loc != '/diagnostics') {
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

      if (loc == '/admin' && !authProvider.isAdmin) {
        return loggedIn ? '/browse' : '/login';
      }

      if (loc == '/diagnostics' && !kDebugMode && !authProvider.isAdmin) {
        return loggedIn ? '/browse' : '/';
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
      GoRoute(path: '/diagnostics', builder: (_, __) => const DiagnosticsScreen()),
      GoRoute(path: '/verification', builder: (_, __) => const VerificationStatusScreen()),
      GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
      GoRoute(
        path: '/profile/:id',
        builder: (_, state) => ProfileDetailScreen(profileId: state.pathParameters['id']!),
      ),
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
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inbox',
              builder: (context, _) => const MessagesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
}
