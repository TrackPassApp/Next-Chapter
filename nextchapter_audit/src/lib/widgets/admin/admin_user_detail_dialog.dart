import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';

/// Full admin view of a single user with all moderation actions.
class AdminUserDetailDialog extends StatefulWidget {
  final String profileId;
  const AdminUserDetailDialog({super.key, required this.profileId});

  @override
  State<AdminUserDetailDialog> createState() => _AdminUserDetailDialogState();
}

class _AdminUserDetailDialogState extends State<AdminUserDetailDialog> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  bool _busy = false;

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
      final s = await AdminRepository.instance.fetchUserSummary(widget.profileId);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load user: $e';
      });
    }
  }

  Future<String?> _promptReason(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason / notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
    return result;
  }

  Future<void> _runAction(String label, Future<void> Function() fn) async {
    final reason = await _promptReason(label);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label complete')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SizedBox(
          width: width * 0.85,
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
              : _error != null
                  ? Padding(padding: const EdgeInsets.all(32), child: Text(_error!))
                  : _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final profile = (_summary!['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final verification = (_summary!['verification'] as Map?)?.cast<String, dynamic>() ?? {};
    final reportsAgainst = (_summary!['reports_against'] as List?) ?? [];
    final reportsFiled = (_summary!['reports_filed'] as List?) ?? [];
    final iBlocked = (_summary!['i_have_blocked'] as List?) ?? [];
    final blockedMe = (_summary!['blocked_me'] as List?) ?? [];
    final photoCount = (_summary!['photo_count'] as num?)?.toInt() ?? 0;

    final firstName = (profile['first_name'] as String?) ?? '—';
    final city = (profile['city'] as String?) ?? '';
    final state = (profile['state'] as String?) ?? '';
    final isSuspended = profile['is_suspended'] == true;
    final isDeleted = profile['is_deleted'] == true;
    final score = (profile['completeness_score'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header.
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(color: colors.primaryContainer.withOpacity(0.3)),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primary,
                child: Text(firstName.isNotEmpty ? firstName[0] : '?',
                    style: text.titleMedium?.copyWith(color: colors.onPrimary)),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(firstName, style: text.titleLarge),
                        const SizedBox(width: AppTheme.spacingSm),
                        if (isSuspended) _StatusPill(label: 'SUSPENDED', color: appColors.danger),
                        const SizedBox(width: 4),
                        if (isDeleted) _StatusPill(label: 'DELETED', color: appColors.subtleText),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${city.isEmpty ? "" : "$city, "}$state • completeness $score • $photoCount photo(s)',
                      style: text.bodySmall,
                    ),
                    SelectableText('Profile ID: ${profile['id']}',
                        style: text.labelSmall?.copyWith(color: appColors.subtleText)),
                  ],
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
        ),
        // Body.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Actions row.
                Wrap(
                  spacing: AppTheme.spacingSm,
                  runSpacing: AppTheme.spacingSm,
                  children: [
                    if (!isSuspended)
                      _ActionButton(
                        label: 'Suspend',
                        icon: Icons.person_off_outlined,
                        color: appColors.danger,
                        disabled: _busy,
                        onPressed: () => _runAction(
                          'Suspend user',
                          () => AdminRepository.instance.suspendUser(widget.profileId, reason: null),
                        ),
                      )
                    else
                      _ActionButton(
                        label: 'Unsuspend',
                        icon: Icons.person_outline,
                        color: appColors.success,
                        disabled: _busy,
                        onPressed: () => _runAction(
                          'Unsuspend user',
                          () => AdminRepository.instance.unsuspendUser(widget.profileId, reason: null),
                        ),
                      ),
                    if (!isDeleted)
                      _ActionButton(
                        label: 'Soft Delete',
                        icon: Icons.delete_outline,
                        color: appColors.warning,
                        disabled: _busy,
                        onPressed: () => _runAction(
                          'Soft delete user',
                          () => AdminRepository.instance.softDeleteUser(widget.profileId, reason: null),
                        ),
                      )
                    else
                      _ActionButton(
                        label: 'Restore',
                        icon: Icons.restore,
                        color: appColors.success,
                        disabled: _busy,
                        onPressed: () => _runAction(
                          'Restore user',
                          () => AdminRepository.instance.restoreUser(widget.profileId, reason: null),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingLg),

                _SectionHeader(label: 'Verification status'),
                _VerificationGrid(
                  profileId: widget.profileId,
                  verification: verification,
                  onChanged: _load,
                  disabled: _busy,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                _SectionHeader(label: 'Reports against this user (${reportsAgainst.length})'),
                if (reportsAgainst.isEmpty)
                  Text('No reports.', style: text.bodySmall)
                else
                  ...reportsAgainst.map((r) => _ReportLine(report: r as Map<String, dynamic>)),
                const SizedBox(height: AppTheme.spacingLg),

                _SectionHeader(label: 'Reports filed by this user (${reportsFiled.length})'),
                if (reportsFiled.isEmpty)
                  Text('No reports filed.', style: text.bodySmall)
                else
                  ...reportsFiled.map((r) => _ReportLine(report: r as Map<String, dynamic>)),
                const SizedBox(height: AppTheme.spacingLg),

                _SectionHeader(label: 'Users they have blocked (${iBlocked.length})'),
                if (iBlocked.isEmpty)
                  Text('—', style: text.bodySmall)
                else
                  SelectableText(iBlocked.join(', '), style: text.bodySmall),
                const SizedBox(height: AppTheme.spacingLg),

                _SectionHeader(label: 'Users who have blocked them (${blockedMe.length})'),
                if (blockedMe.isEmpty)
                  Text('—', style: text.bodySmall)
                else
                  SelectableText(blockedMe.join(', '), style: text.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Small reusable bits ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontSize: 10)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool disabled;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onPressed, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: disabled ? null : onPressed,
      icon: Icon(icon, color: color, size: 18),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: color.withOpacity(0.5))),
    );
  }
}

class _ReportLine extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportLine({required this.report});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    final reason = report['reason'] as String? ?? '';
    final status = report['status'] as String? ?? 'pending';
    final severity = report['severity'] as String? ?? 'medium';
    final createdAt = report['created_at'] as String? ?? '';
    final details = report['details'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: _severityColor(severity, appColors)),
          ),
          Expanded(
            child: Text(
              '$reason  •  $severity  •  $status  •  ${createdAt.substring(0, createdAt.length >= 10 ? 10 : createdAt.length)}'
              '${details.isNotEmpty ? "\n    “$details”" : ""}',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(String s, AppColorsExtension c) {
    switch (s) {
      case 'critical':
        return c.danger;
      case 'high':
        return c.warning;
      case 'medium':
        return c.warning.withOpacity(0.6);
      default:
        return c.subtleText;
    }
  }
}

class _VerificationGrid extends StatelessWidget {
  final String profileId;
  final Map<String, dynamic> verification;
  final VoidCallback onChanged;
  final bool disabled;

  const _VerificationGrid({required this.profileId, required this.verification, required this.onChanged, required this.disabled});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    final kinds = const [
      ('email', 'Email'),
      ('phone', 'Phone'),
      ('selfie', 'Selfie'),
      ('id', 'Government ID'),
    ];

    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: AppTheme.spacingSm,
      children: kinds.map((k) {
        final flag = verification['${k.$1}_verified'] == true;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: 6),
          decoration: BoxDecoration(
            color: flag ? appColors.success.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: flag ? appColors.success.withOpacity(0.4) : Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                flag ? Icons.verified : Icons.radio_button_unchecked,
                color: flag ? appColors.success : appColors.subtleText,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(k.$2, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: AppTheme.spacingSm),
              TextButton(
                onPressed: disabled
                    ? null
                    : () async {
                        await AdminRepository.instance.setVerification(
                          profileId: profileId,
                          kind: k.$1,
                          value: !flag,
                        );
                        onChanged();
                      },
                style: TextButton.styleFrom(minimumSize: const Size(40, 28), padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(flag ? 'Revoke' : 'Approve'),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
