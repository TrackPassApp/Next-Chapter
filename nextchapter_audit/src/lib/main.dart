import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/profile_provider.dart';
import 'router/app_router.dart';
import 'services/supabase_service.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Defensive bootstrap for sandboxed preview environments where the
  // browser locale tag or third-party font CDN may be unavailable.
  // Safe to keep in production; safe to remove when running locally.
  Intl.defaultLocale = 'en_US';
  GoogleFonts.config.allowRuntimeFetching = false;

  await SupabaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final MessagesProvider _messagesProvider;
  late final ProfileProvider _profileProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _messagesProvider = MessagesProvider();
    _profileProvider = ProfileProvider();

    // Load profile whenever the auth state changes (login, session restore, logout).
    _authProvider.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final userId = _authProvider.userId;
    if (userId != null) {
      _profileProvider.loadProfile(userId);
    } else {
      _profileProvider.clear();
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _authProvider.dispose();
    _profileProvider.dispose();
    _messagesProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _messagesProvider),
        ChangeNotifierProvider.value(value: _profileProvider),
      ],
      child: MaterialApp.router(
        title: 'Next Chapter',
        theme: AppTheme.lightTheme,
        routerConfig: AppRouter.router(_authProvider),
      ),
    );
  }
}