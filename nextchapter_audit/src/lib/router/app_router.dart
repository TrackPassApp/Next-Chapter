import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/browse_provider.dart';
import '../providers/messages_provider.dart';
import '../screens/landing_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/browse_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/profile_detail_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/privacy_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/app_shell.dart';
import '../screens/diagnostics_screen.dart';

class AppRouter {
  static GoRouter router(AuthProvider authProvider) => GoRouter(
    initialLocation: '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      // While the initial session is being restored from storage, show nothing.
      if (authProvider.isLoading) {
        // ignore: avoid_print
        print('[router] loc=${state.matchedLocation} -> SKIP (loading)');
        return null;
      }

      final loggedIn = authProvider.isLoggedIn;
      final loc = state.matchedLocation;

      final isAuthRoute = loc == '/login' || loc == '/signup' || loc == '/forgot-password';
      // Note: /diagnostics is intentionally NOT in this public list.
      // It is restricted below to debug builds or signed-in admins.
      final isPublic = loc == '/' || loc == '/privacy' || loc == '/terms' || isAuthRoute;

      // TEMP DIAGNOSTIC — remove once Test 2 passes.
      // ignore: avoid_print
      print('[router] loc=$loc loggedIn=$loggedIn isAdmin=${authProvider.isAdmin} isPublic=$isPublic');

      // Standard logged-out gating.
      if (!loggedIn && !isPublic && loc != '/diagnostics') {
        // ignore: avoid_print
        print('[router] -> /login (logged out + not public)');
        return '/login';
      }
      if (loggedIn && (loc == '/' || isAuthRoute)) {
        // ignore: avoid_print
        print('[router] -> /browse (logged in on landing or auth route)');
        return '/browse';
      }

      // Admin-only gating. Defense-in-depth — AdminScreen also self-guards.
      if (loc == '/admin' && !authProvider.isAdmin) {
        // ignore: avoid_print
        print('[router] -> ${loggedIn ? "/browse" : "/login"} (admin guard, isAdmin=false)');
        return loggedIn ? '/browse' : '/login';
      }

      // Diagnostics route: debug builds OR signed-in admins only.
      if (loc == '/diagnostics' && !kDebugMode && !authProvider.isAdmin) {
        // ignore: avoid_print
        print('[router] -> ${loggedIn ? "/browse" : "/"} (diagnostics guard)');
        return loggedIn ? '/browse' : '/';
      }

      // ignore: avoid_print
      print('[router] -> (no redirect) stay on $loc');
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
      GoRoute(path: '/diagnostics', builder: (_, __) => const DiagnosticsScreen()),
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
