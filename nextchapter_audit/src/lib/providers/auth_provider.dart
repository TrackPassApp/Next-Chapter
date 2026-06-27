import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/supabase_service.dart';

/// Authentication result with an optional error message for the UI.
class AuthResult {
  final bool success;
  final String? errorMessage;
  const AuthResult({required this.success, this.errorMessage});
}

/// Wraps Supabase Auth and exposes login state to the widget tree.
///
/// Behaviour:
/// - Listens to [SupabaseClient.auth.onAuthStateChange] so session is always
///   in sync — page refresh, tab restore, token refresh, sign-out from another
///   tab all update state automatically.
/// - Falls back to a lightweight mock mode when Supabase env vars are absent,
///   so the app remains runnable without a backend during development.
class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _loading = true; // true while we wait for the initial session check
  bool _isMockMode = false;

  // Mock-mode fallback fields (used only when Supabase is not configured)
  bool _mockLoggedIn = false;
  bool _mockIsAdmin = false;
  String? _mockEmail;

  StreamSubscription<AuthState>? _authSub;

  AuthProvider() {
    _init();
  }

  // ─── Public getters ───────────────────────────────────────────────────────

  bool get isLoggedIn => _isMockMode ? _mockLoggedIn : _user != null;
  bool get isLoading => _loading;
  bool get isMockMode => _isMockMode;

  /// The authenticated Supabase user, or null in mock mode / logged out.
  User? get user => _user;

  /// Stable user ID usable as a foreign key in all tables.
  /// Returns null in mock mode — callers should treat null as "not authenticated".
  String? get userId => _isMockMode ? null : _user?.id;

  String? get email => _isMockMode ? _mockEmail : _user?.email;

  /// Server-controlled admin check.
  ///
  /// Reads `app_metadata.role` from the Supabase JWT. `app_metadata` is
  /// writable ONLY by the service role (i.e. Supabase dashboard or a server
  /// using the service key) — never by the user themselves. This closes the
  /// privilege-escalation hole present in the previous implementation, which
  /// read from `user_metadata` (user-writable) and also hard-coded an email.
  ///
  /// To grant admin to a user, run in the Supabase SQL editor:
  ///   UPDATE auth.users
  ///   SET raw_app_meta_data =
  ///     COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
  ///   WHERE email = '<their email>';
  /// Then have the user sign out and sign back in so the JWT is reissued.
  bool get isAdmin {
    if (_isMockMode) return _mockIsAdmin;
    final role = _user?.appMetadata['role'];
    return role == 'admin' ||
        role == 'super_admin' ||
        role == 'moderator';
  }

  bool get isEmailVerified {
    if (_isMockMode) return true;
    return _user?.emailConfirmedAt != null;
  }

  // ─── Initialisation ───────────────────────────────────────────────────────

  Future<void> _init() async {
    // Use client null-check (not just isConfigured) so that a failed
    // Supabase.initialize() also triggers mock mode with a visible error.
    final supabaseClient = SupabaseService.client;
    if (supabaseClient == null) {
      _isMockMode = true;
      _loading = false;
      notifyListeners();
      return;
    }

    // Restore session that Supabase persisted in localStorage (web) or
    // secure storage (mobile) from a previous app run.
    _user = supabaseClient.auth.currentUser;
    _loading = false;
    notifyListeners();

    // Subscribe to future auth state changes for the lifetime of the provider.
    _authSub = supabaseClient.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      notifyListeners();
    });
  }

  // ─── Auth actions ─────────────────────────────────────────────────────────

  /// Sign in with email and password.
  Future<AuthResult> login(String email, String password) async {
    if (_isMockMode) return _mockLogin(email, password);

    try {
      final res = await SupabaseService.db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user == null) {
        return const AuthResult(success: false, errorMessage: 'Login failed. Check your credentials.');
      }
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, errorMessage: e.message);
    } catch (_) {
      return const AuthResult(success: false, errorMessage: 'An unexpected error occurred. Please try again.');
    }
  }

  /// Create a new account. Returns false when the user is under 18.
  Future<AuthResult> signUp(String email, String password, DateTime dob) async {
    final age = DateTime.now().difference(dob).inDays ~/ 365;
    if (age < 18) {
      return const AuthResult(success: false, errorMessage: 'You must be 18 or older to join.');
    }

    if (_isMockMode) return _mockSignUp(email, password, dob);

    try {
      final res = await SupabaseService.db.auth.signUp(
        email: email.trim(),
        password: password,
        // Where the Supabase confirmation email link should redirect to.
        // When empty, Supabase uses the project's Site URL dashboard setting.
        emailRedirectTo:
            AppConfig.appUrl.isEmpty ? null : AppConfig.appUrl,
        data: {
          'date_of_birth': dob.toIso8601String(),
        },
      );
      if (res.user == null) {
        return const AuthResult(success: false, errorMessage: 'Signup failed. Please try again.');
      }
      // Supabase may return a user with email unconfirmed depending on project
      // settings. The caller should check [isEmailVerified] and show a
      // "check your email" message accordingly.
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, errorMessage: e.message);
    } catch (_) {
      return const AuthResult(success: false, errorMessage: 'An unexpected error occurred. Please try again.');
    }
  }

  /// Send a password reset email.
  Future<AuthResult> sendPasswordReset(String email) async {
    if (_isMockMode) {
      return const AuthResult(success: true);
    }
    try {
      await SupabaseService.db.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'io.supabase.nextchapter://reset-password',
      );
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, errorMessage: e.message);
    } catch (_) {
      return const AuthResult(success: false, errorMessage: 'Failed to send reset email. Please try again.');
    }
  }

  /// Sign out and clear local session.
  Future<void> logout() async {
    if (_isMockMode) {
      _mockLoggedIn = false;
      _mockIsAdmin = false;
      _mockEmail = null;
      notifyListeners();
      return;
    }
    await SupabaseService.db.auth.signOut();
    // _user is cleared automatically by the onAuthStateChange listener.
  }

  // ─── Mock fallbacks ───────────────────────────────────────────────────────

  Future<AuthResult> _mockLogin(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _mockLoggedIn = true;
    _mockIsAdmin = email == 'admin@nextchapter.com';
    _mockEmail = email;
    notifyListeners();
    return const AuthResult(success: true);
  }

  Future<AuthResult> _mockSignUp(String email, String password, DateTime dob) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _mockLoggedIn = true;
    _mockEmail = email;
    notifyListeners();
    return const AuthResult(success: true);
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
