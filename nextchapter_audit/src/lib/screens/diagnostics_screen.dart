import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

/// Temporary diagnostics screen — accessible at /diagnostics
/// Shows whether Supabase credentials loaded correctly and mock mode is off.
/// Remove or restrict this route before production launch.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final Map<String, _DiagResult> _results;

  @override
  void initState() {
    super.initState();
    _results = _runDiagnostics();
  }

  Map<String, _DiagResult> _runDiagnostics() {
    final url = SupabaseService.resolvedUrl;
    final key = SupabaseService.resolvedKey;
    final configured = SupabaseService.isConfigured;
    final clientAvailable = SupabaseService.client != null;
    final initError = SupabaseService.initError;
    final configError = SupabaseService.configurationError;

    final urlLoaded = url.isNotEmpty;
    final keyLoaded = key.isNotEmpty;
    final keyParts = key.split('.');
    final keyIsValidJwt = keyParts.length == 3;

    final String urlDisplay = urlLoaded ? url : '(empty — not loaded)';
    // Show only first 40 chars of the key for security
    final String keyDisplay = keyLoaded
        ? '${key.substring(0, key.length.clamp(0, 40))}… (${keyParts.length} JWT segments)'
        : '(empty — not loaded)';

    final String initDetail = initError != null
        ? 'FAILED: $initError'
        : (clientAvailable ? 'Client created successfully' : 'isConfigured = false');

    final String configDetail = configError ?? 'OK — no configuration errors';

    return {
      'SUPABASE_URL Loaded': _DiagResult(
        pass: urlLoaded,
        value: urlLoaded ? 'YES' : 'NO',
        detail: urlDisplay,
      ),
      'SUPABASE_ANON_KEY Loaded': _DiagResult(
        pass: keyLoaded && keyIsValidJwt,
        value: !keyLoaded
            ? 'NO — empty'
            : !keyIsValidJwt
                ? 'MALFORMED — ${keyParts.length} segments (need 3)'
                : 'YES — valid JWT',
        detail: keyDisplay,
      ),
      'Configuration Valid': _DiagResult(
        pass: configured,
        value: configured ? 'YES' : 'NO',
        detail: configDetail,
      ),
      'Supabase.initialize() succeeded': _DiagResult(
        pass: configured && initError == null,
        value: !configured
            ? 'SKIPPED (bad config)'
            : initError != null
                ? 'FAILED'
                : 'YES',
        detail: initDetail,
      ),
      'Mock Mode Active': _DiagResult(
        pass: !clientAvailable,
        invertPass: true,
        value: clientAvailable ? 'NO ✓' : 'YES ✗',
        detail: clientAvailable
            ? 'Real Supabase backend is active'
            : 'App is using mock mode — no data will persist',
      ),
      'Supabase Client Accessible': _DiagResult(
        pass: clientAvailable,
        value: clientAvailable ? 'YES' : 'NO',
        detail: clientAvailable
            ? 'SupabaseService.client returns a live client'
            : 'SupabaseService.client returns null',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final allPass = _results.values.every((r) => r.isGreen);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase Diagnostics'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/browse'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            children: [
              // ── Status banner ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: allPass
                      ? appColors.success.withOpacity(0.12)
                      : appColors.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color: allPass
                        ? appColors.success.withOpacity(0.4)
                        : appColors.danger.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      allPass ? Icons.check_circle_outline : Icons.error_outline,
                      color: allPass ? appColors.success : appColors.danger,
                      size: AppTheme.iconLg,
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Text(
                        allPass
                            ? 'Supabase is connected. Mock mode is OFF.'
                            : 'Supabase is NOT connected. App is in mock mode.',
                        style: text.titleSmall?.copyWith(
                          color: allPass ? appColors.success : appColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Individual checks ──────────────────────────────────────────
              ...(_results.entries.map((entry) {
                final result = entry.value;
                final isGreen = result.isGreen;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isGreen ? Icons.check_circle : Icons.cancel,
                        color: isGreen ? appColors.success : appColors.danger,
                        size: AppTheme.iconMd,
                      ),
                      const SizedBox(width: AppTheme.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacingSm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isGreen
                                        ? appColors.success.withOpacity(0.15)
                                        : appColors.danger.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                  ),
                                  child: Text(
                                    result.value,
                                    style: text.labelSmall?.copyWith(
                                      color: isGreen ? appColors.success : appColors.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              result.detail,
                              style: text.bodySmall?.copyWith(color: appColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              })),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Help text ──────────────────────────────────────────────────
              if (!allPass) ...[
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to fix mock mode',
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                      Text(
                        '1. Open lib/config/app_config.dart\n'
                        '2. Verify supabaseUrl and supabaseAnonKey are set\n'
                        '3. Ensure the URL has no /rest/v1/ suffix\n'
                        '4. Rebuild the app\n'
                        '5. Return to /diagnostics to re-check',
                        style: text.bodySmall?.copyWith(height: 1.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
              ],

              OutlinedButton.icon(
                onPressed: () => setState(() => _results.addAll(_runDiagnostics())),
                icon: const Icon(Icons.refresh),
                label: const Text('Re-run Diagnostics'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagResult {
  final bool pass;
  final bool invertPass;
  final String value;
  final String detail;

  const _DiagResult({
    required this.pass,
    required this.value,
    required this.detail,
    this.invertPass = false,
  });

  bool get isGreen => invertPass ? !pass : pass;
}
