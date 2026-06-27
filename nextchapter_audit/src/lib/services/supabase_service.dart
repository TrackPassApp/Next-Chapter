import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Central access point for the Supabase client.
///
/// Credentials are stored in lib/config/app_config.dart (gitignored).
/// No credentials appear in any other source file.
class SupabaseService {
  SupabaseService._();

  // Read from AppConfig — the single credential source of truth.
  static String get resolvedUrl => AppConfig.supabaseUrl;
  static String get resolvedKey => AppConfig.supabaseAnonKey;

  /// Non-null when initialization failed — contains a human-readable reason.
  static String? _initError;
  static String? get initError => _initError;

  /// True only when both credentials are structurally valid.
  static bool get isConfigured {
    final url = resolvedUrl;
    final key = resolvedKey;
    if (url.isEmpty || key.isEmpty) return false;
    // A Supabase anon key is a JWT: exactly 3 dot-separated segments.
    final parts = key.split('.');
    if (parts.length != 3) return false;
    return true;
  }

  /// Human-readable explanation of why isConfigured is false (or null if OK).
  static String? get configurationError {
    if (resolvedUrl.isEmpty) return 'supabaseUrl is empty in app_config.dart';
    if (resolvedKey.isEmpty) return 'supabaseAnonKey is empty in app_config.dart';
    final parts = resolvedKey.split('.');
    if (parts.length != 3) {
      return 'supabaseAnonKey is malformed — expected 3 JWT segments '
          '(header.payload.signature), got ${parts.length}. '
          'The key in app_config.dart is truncated.';
    }
    if (_initError != null) return 'Supabase.initialize() threw: $_initError';
    return null;
  }

  /// Call once from main() before runApp().
  static Future<void> initialize() async {
    _initError = null;

    if (!isConfigured) {
      // Do NOT silently swallow this — log the reason so it surfaces in diagnostics.
      _initError = configurationError ?? 'Unknown configuration error';
      return;
    }

    try {
      await Supabase.initialize(
        url: resolvedUrl,
        anonKey: resolvedKey,
      );
    } catch (e) {
      _initError = e.toString();
    }
  }

  /// Returns the live Supabase client, or null when not configured / init failed.
  static SupabaseClient? get client {
    if (!isConfigured || _initError != null) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Convenience getter — throws a descriptive error when not available.
  static SupabaseClient get db {
    final c = client;
    if (c == null) {
      throw StateError(
        'Supabase client is unavailable.\n'
        'Reason: ${configurationError ?? _initError ?? "Unknown"}\n'
        'Open lib/config/app_config.dart and fix supabaseUrl / supabaseAnonKey.',
      );
    }
    return c;
  }
}
