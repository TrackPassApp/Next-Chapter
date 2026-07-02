import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_metrics_tab.dart' show adminErrorBox, AdminEmptyState, openAdminUserDialog;

class AdminVerificationTab extends StatefulWidget {
  const AdminVerificationTab({super.key});

  @override
  State<AdminVerificationTab> createState() => _AdminVerificationTabState();
}

class _AdminVerificationTabState extends State<AdminVerificationTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminRepository.instance.listVerificationQueue();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load verification queue: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return adminErrorBox(context, _error!, _load);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.primary, size: 18),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: Text(
                  'Lists users with any unverified field (Email · Phone · Selfie · Government ID). '
                  'Approve / revoke each flag manually for Beta. User-side upload flows for selfie / ID arrive in B8.',
                  style: text.bodySmall,
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingMd),
        if (_rows.isEmpty)
          const Expanded(child: AdminEmptyState(message: 'All users fully verified — nothing pending.', icon: Icons.verified_outlined))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
                itemBuilder: (_, i) {
                  final row = _rows[i];
                  final profile = (row['profile'] as Map?)?.cast<String, dynamic>() ?? {};
                  final profileId = profile['id'] as String? ?? '';
                  final name = profile['first_name'] as String? ?? '—';
                  final city = profile['city'] as String? ?? '';
                  final state = profile['state'] as String? ?? '';
                  final isMobile = MediaQuery.sizeOf(context).width < 700;
                  final badges = Wrap(
                    spacing: AppTheme.spacingXs,
                    runSpacing: 4,
                    children: [
                      _VBadge(label: 'Email',  verified: row['email_verified']  == true, appColors: appColors),
                      _VBadge(label: 'Phone',  verified: row['phone_verified']  == true, appColors: appColors),
                      _VBadge(label: 'Selfie', verified: row['selfie_verified'] == true, appColors: appColors),
                      _VBadge(label: 'ID',     verified: row['id_verified']     == true, appColors: appColors),
                    ],
                  );
                  final reviewBtn = OutlinedButton(
                    onPressed: profileId.isEmpty
                        ? null
                        : () => openAdminUserDialog(context, profileId).then((_) => _load()),
                    child: const Text('Review'),
                  );
                  return Container(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                  backgroundColor: colors.primaryContainer,
                                  child: Text(name.isNotEmpty ? name[0] : '?',
                                      style: text.titleSmall
                                          ?.copyWith(color: colors.primary)),
                                ),
                                const SizedBox(width: AppTheme.spacingMd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: text.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                        '${city.isEmpty ? "" : "$city, "}$state',
                                        style: text.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                reviewBtn,
                              ]),
                              const SizedBox(height: AppTheme.spacingSm),
                              badges,
                            ],
                          )
                        : Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: colors.primaryContainer,
                                child: Text(name.isNotEmpty ? name[0] : '?',
                                    style: text.titleSmall
                                        ?.copyWith(color: colors.primary)),
                              ),
                              const SizedBox(width: AppTheme.spacingMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: text.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                      '${city.isEmpty ? "" : "$city, "}$state',
                                      style: text.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              badges,
                              const SizedBox(width: AppTheme.spacingSm),
                              reviewBtn,
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _VBadge extends StatelessWidget {
  final String label;
  final bool verified;
  final AppColorsExtension appColors;
  const _VBadge({required this.label, required this.verified, required this.appColors});

  @override
  Widget build(BuildContext context) {
    final color = verified ? appColors.success : appColors.subtleText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.check : Icons.close, size: 12, color: color),
          const SizedBox(width: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}
