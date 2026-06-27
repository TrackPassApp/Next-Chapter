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