/// Build-time configuration for Next Chapter.
///
/// No credential values belong in this file. Supply them with `--dart-define`.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appUrl = String.fromEnvironment('APP_URL');

  static const adsEnabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: false,
  );

  static const donateUrl = String.fromEnvironment('DONATE_URL');
  static const bmcUrl = String.fromEnvironment('BMC_URL');
  static const paypalUrl = String.fromEnvironment('PAYPAL_URL');
  static const stripeUrl = String.fromEnvironment('STRIPE_URL');

  /// Development-only fallback. Production builds fail closed unless this is
  /// deliberately enabled with `--dart-define=ALLOW_MOCK_MODE=true`.
  static const allowMockMode = bool.fromEnvironment(
    'ALLOW_MOCK_MODE',
    defaultValue: false,
  );
}
