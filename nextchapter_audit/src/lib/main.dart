import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/block_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/profile_provider.dart';
import 'router/app_router.dart';
import 'services/supabase_service.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Visible runtime errors ──────────────────────────────────────────────
  // By default, Flutter Web release builds replace exceptions in `build()`
  // with an empty grey box. That is exactly how Profile Detail looked
  // "blank with just the Message button" — a `TypeError` in the rendering
  // path swallowed the entire body. From now on, every build-time exception
  // shows a clearly visible red panel inside the failing widget with the
  // file, line, and exception text, even in release mode.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final stack = details.stack?.toString().split('\n').take(6).join('\n') ?? '';
    return Material(
      color: const Color(0xFFFFEBEE),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(children: [
                Icon(Icons.error_outline, color: Color(0xFFB71C1C), size: 20),
                SizedBox(width: 8),
                Text('Render error',
                    style: TextStyle(
                      color: Color(0xFFB71C1C),
                      fontWeight: FontWeight.w700,
                    )),
              ]),
              const SizedBox(height: 6),
              SelectableText(
                details.exceptionAsString(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFB71C1C),
                ),
              ),
              if (stack.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  stack,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF7F0000),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  };

  // Surface uncaught framework errors to the console so the diagnostics page
  // can pick them up later if we want. Keep the default printing too.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

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
  late final BlockProvider _blockProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _messagesProvider = MessagesProvider();
    _profileProvider = ProfileProvider();
    _blockProvider = BlockProvider();

    // Load profile whenever the auth state changes (login, session restore, logout).
    _authProvider.addListener(_onAuthChanged);
    // Bind the messaging provider to the user's profile id once it's loaded.
    _profileProvider.addListener(_onProfileChanged);
  }

  void _onAuthChanged() {
    final userId = _authProvider.userId;
    if (userId != null) {
      _profileProvider.loadProfile(userId);
    } else {
      _profileProvider.clear();
      _messagesProvider.clear();
      _blockProvider.clear();
    }
  }

  void _onProfileChanged() {
    final profileId = _profileProvider.profileId;
    if (profileId != null && _messagesProvider.myProfileId != profileId) {
      _messagesProvider.bindProfile(profileId);
      _blockProvider.bindProfile(profileId);
    } else if (profileId == null && _messagesProvider.myProfileId != null) {
      _messagesProvider.clear();
      _blockProvider.clear();
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _profileProvider.removeListener(_onProfileChanged);
    _authProvider.dispose();
    _profileProvider.dispose();
    _messagesProvider.dispose();
    _blockProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _messagesProvider),
        ChangeNotifierProvider.value(value: _profileProvider),
        ChangeNotifierProvider.value(value: _blockProvider),
      ],
      child: MaterialApp.router(
        title: 'Next Chapter',
        theme: AppTheme.lightTheme,
        routerConfig: AppRouter.router(_authProvider, profileProvider: _profileProvider),
      ),
    );
  }
}