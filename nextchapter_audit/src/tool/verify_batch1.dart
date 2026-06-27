// Verification harness for Batch 1 — AppConfig only (no Flutter imports).
//
// Proves that --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...
// reach AppConfig at runtime. SupabaseService.isConfigured uses the exact same
// AppConfig getters, so if AppConfig has correct values, SupabaseService does too.

import 'package:next_chapter/config/app_config.dart';

void main() {
  final url = AppConfig.supabaseUrl;
  final key = AppConfig.supabaseAnonKey;

  print('--- AppConfig values at runtime ---');
  print('URL length:  ${url.length}');
  print('URL prefix:  ${url.isEmpty ? "(empty)" : url.substring(0, url.length.clamp(0, 40))}');
  print('Key length:  ${key.length}');
  print('Key parts:   ${key.isEmpty ? 0 : key.split('.').length}');

  // Reimplement the same isConfigured rule SupabaseService uses, so we can
  // verify it without importing the Flutter-only SupabaseService here.
  bool isConfigured() {
    if (url.isEmpty || key.isEmpty) return false;
    return key.split('.').length == 3;
  }

  print('');
  print('isConfigured:   ${isConfigured()}');
  print('would mock?:    ${!isConfigured()}  (true means app would enter mock mode)');
  print('');
  print(isConfigured() ? 'VERIFY_OK' : 'VERIFY_REFUSED_CLEANLY');
}
