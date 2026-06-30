import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/profile_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

/// Live diagnostics — one page to see every piece of the app's runtime
/// state without opening browser devtools. Visible at /#/diagnostics.
///
/// Each row reports either:
///   PASS  — green, all good
///   FAIL  — red, broken (with the actual error string)
///   INFO  — neutral, just data
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _running = false;
  final List<_Row> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _rows.clear();
    });

    // 1. Build metadata.
    _add('Build label', AppConfig.buildLabel, _RowStatus.info,
        detail: 'If you do not see this on the screen and on the page footer, your browser is still loading an old bundle.');

    // 2. Supabase config.
    final url = SupabaseService.resolvedUrl;
    final key = SupabaseService.resolvedKey;
    _add('Supabase URL',
        url.isEmpty ? 'EMPTY' : url,
        url.isEmpty ? _RowStatus.fail : _RowStatus.pass);
    _add('Supabase Anon Key',
        key.isEmpty ? 'EMPTY' : '${key.substring(0, 24)}… (${key.split('.').length} JWT segments)',
        key.isEmpty ? _RowStatus.fail : _RowStatus.pass);
    _add('Supabase initialised',
        SupabaseService.initError == null
            ? 'OK'
            : 'FAILED: ${SupabaseService.initError}',
        SupabaseService.initError == null ? _RowStatus.pass : _RowStatus.fail);
    _add('Mock mode',
        SupabaseService.client == null ? 'YES (no real backend)' : 'NO',
        SupabaseService.client == null ? _RowStatus.fail : _RowStatus.pass);

    // 3. Auth state.
    final auth = context.read<AuthProvider>();
    _add('Logged in', auth.isLoggedIn ? 'YES' : 'NO',
        auth.isLoggedIn ? _RowStatus.pass : _RowStatus.info,
        detail: 'Sign in to populate the user/profile rows below.');
    _add('User ID', auth.userId ?? '(none)', _RowStatus.info);
    _add('Email', auth.email ?? '(none)', _RowStatus.info);
    _add('Email verified', auth.isEmailVerified ? 'YES' : 'NO',
        auth.isLoggedIn
            ? (auth.isEmailVerified ? _RowStatus.pass : _RowStatus.fail)
            : _RowStatus.info);
    _add('Admin role (JWT app_metadata.role)',
        auth.user?.appMetadata['role']?.toString() ?? '(none)',
        auth.isAdmin ? _RowStatus.pass : _RowStatus.info,
        detail: auth.isAdmin
            ? 'Admin guard will let you reach /admin.'
            : 'Not an admin — /admin will redirect to /browse.');

    setState(() {}); // flush partial results

    // 4. Profile fetch (own).
    final pp = context.read<ProfileProvider>();
    _add('Own profile ID (from ProfileProvider)',
        pp.profileId ?? '(none — onboarding not started)',
        pp.profileId != null ? _RowStatus.pass : _RowStatus.info);
    _add('Own profile cached', pp.profile == null ? 'NO' : 'YES',
        pp.profile != null ? _RowStatus.pass : _RowStatus.info);
    if (pp.profile != null) {
      final p = pp.profile!;
      _add('  ↳ first_name', p.firstName, _RowStatus.info);
      _add('  ↳ is_complete', p.isComplete.toString(),
          p.isComplete ? _RowStatus.pass : _RowStatus.info);
      _add('  ↳ photos count', p.photoUrls.length.toString(), _RowStatus.info);
      _add('  ↳ prompts count', p.prompts.length.toString(), _RowStatus.info);
      _add('  ↳ interests count', p.interests.length.toString(), _RowStatus.info);
      _add('  ↳ modes', p.modes.join(', '), _RowStatus.info);
    }

    // 5. Browse fetch — proves anon RLS lets us see public profiles.
    if (SupabaseService.client != null) {
      try {
        final list = await ProfileRepository.instance.fetchAllProfiles(
          currentUserId: auth.userId,
          limit: 50,
        );
        _add('Browse fetch (fetchAllProfiles)',
            '${list.length} profile${list.length == 1 ? '' : 's'} returned',
            list.isNotEmpty ? _RowStatus.pass : _RowStatus.fail,
            detail: list.isEmpty
                ? 'No public profiles visible. RLS may be blocking SELECT, or no profiles are seeded. Run migration 007_b9_demo_seed.sql.'
                : 'First few: ${list.take(5).map((p) => "${p.firstName} (${p.id.substring(0, 8)}…)").join(", ")}');
        // 6. Profile-by-id round-trip on the first row.
        if (list.isNotEmpty) {
          final first = list.first;
          try {
            final single = await ProfileRepository.instance.fetchProfileById(first.id);
            _add('fetchProfileById round-trip',
                single == null
                    ? 'NULL — profile is in Browse but cannot be fetched by id'
                    : 'OK — ${single.firstName} (${single.photoUrls.length} photos)',
                single == null ? _RowStatus.fail : _RowStatus.pass,
                detail: single == null
                    ? 'This means RLS, is_suspended, or is_deleted is blocking the single-row read.'
                    : 'Profile detail screen will render this person.');
          } catch (e) {
            _add('fetchProfileById round-trip', 'EXCEPTION: $e', _RowStatus.fail);
          }
        }
      } catch (e) {
        _add('Browse fetch (fetchAllProfiles)', 'EXCEPTION: $e', _RowStatus.fail);
      }

      // 7. Demo seed presence — quick sanity, identifies whether 007 ran.
      try {
        final db = SupabaseService.client!;
        final demo = await db
            .from('profiles')
            .select('id, first_name')
            .like('id', '%-aaaa-%')
            .limit(20);
        _add('Demo seed (uuids with -aaaa-)',
            '${(demo as List).length} rows',
            (demo).isEmpty ? _RowStatus.fail : _RowStatus.pass,
            detail: (demo as List).isEmpty
                ? 'Demo profiles not present. Run migration 007_b9_demo_seed.sql then 009_fix_demo_photo_urls.sql.'
                : (demo as List).map((r) => r['first_name']).join(', '));
      } catch (e) {
        _add('Demo seed check', 'EXCEPTION: $e', _RowStatus.fail);
      }
    }

    if (mounted) setState(() => _running = false);
  }

  void _add(String label, String value, _RowStatus status, {String? detail}) {
    _rows.add(_Row(label: label, value: value, status: status, detail: detail));
    if (mounted) setState(() {});
  }

  String _exportText() {
    final buf = StringBuffer()
      ..writeln('Next Chapter Diagnostics')
      ..writeln('Build: ${AppConfig.buildLabel}')
      ..writeln('At: ${DateTime.now().toIso8601String()}')
      ..writeln('-' * 40);
    for (final r in _rows) {
      buf.writeln('[${r.status.name.toUpperCase()}] ${r.label}: ${r.value}');
      if (r.detail != null) buf.writeln('  ${r.detail}');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/browse'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _exportText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostics copied to clipboard')),
              );
            },
          ),
          IconButton(
            tooltip: 'Re-run',
            icon: const Icon(Icons.refresh),
            onPressed: _run,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            children: [
              if (_running)
                LinearProgressIndicator(color: colors.primary),
              const SizedBox(height: AppTheme.spacingSm),
              ..._rows.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(AppTheme.spacingSm),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(
                    color: r.status == _RowStatus.fail
                        ? appColors.danger.withOpacity(0.4)
                        : r.status == _RowStatus.pass
                            ? appColors.success.withOpacity(0.4)
                            : colors.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusChip(r.status, appColors, text),
                        const SizedBox(width: AppTheme.spacingSm),
                        Expanded(
                          child: SelectableText(r.label,
                              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(r.value,
                        style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
                    if (r.detail != null) ...[
                      const SizedBox(height: 4),
                      Text(r.detail!,
                          style: text.bodySmall?.copyWith(color: appColors.subtleText)),
                    ],
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(_RowStatus s, AppColorsExtension c, TextTheme t) {
    final (label, color) = switch (s) {
      _RowStatus.pass => ('PASS', c.success),
      _RowStatus.fail => ('FAIL', c.danger),
      _RowStatus.info => ('INFO', c.subtleText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(label,
          style: t.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

enum _RowStatus { pass, fail, info }

class _Row {
  final String label;
  final String value;
  final _RowStatus status;
  final String? detail;
  const _Row({required this.label, required this.value, required this.status, this.detail});
}
