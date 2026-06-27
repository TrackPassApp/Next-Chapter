import 'package:flutter/material.dart';
import '../../repositories/admin_repository.dart';
import '../../theme/theme.dart';
import 'admin_metrics_tab.dart' show adminErrorBox, AdminEmptyState, openAdminUserDialog;

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Resolved / Dismissed'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: const [
              _ReportsList(status: 'pending'),
              _ReportsList(status: 'resolved'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportsList extends StatefulWidget {
  final String status;
  const _ReportsList({required this.status});

  @override
  State<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends State<_ReportsList> {
  List<Map<String, dynamic>> _reports = [];
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
      // The "Resolved / Dismissed" tab pulls both statuses by listing each then merging.
      List<Map<String, dynamic>> rows;
      if (widget.status == 'pending') {
        rows = await AdminRepository.instance.listReports(status: 'pending');
      } else {
        final resolved = await AdminRepository.instance.listReports(status: 'resolved');
        final dismissed = await AdminRepository.instance.listReports(status: 'dismissed');
        rows = [...resolved, ...dismissed];
      }
      if (!mounted) return;
      setState(() {
        _reports = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load reports: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return adminErrorBox(context, _error!, _load);
    if (_reports.isEmpty) {
      return const AdminEmptyState(message: 'No reports here', icon: Icons.flag_outlined);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
        itemBuilder: (_, i) => _ReportRow(report: _reports[i], onChanged: _load, status: widget.status),
      ),
    );
  }
}

class _ReportRow extends StatefulWidget {
  final Map<String, dynamic> report;
  final VoidCallback onChanged;
  final String status;
  const _ReportRow({required this.report, required this.onChanged, required this.status});

  @override
  State<_ReportRow> createState() => _ReportRowState();
}

class _ReportRowState extends State<_ReportRow> {
  bool _busy = false;

  Future<String?> _promptNotes(String title) async {
    final ctrl = TextEditingController(text: widget.report['admin_notes'] as String? ?? '');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Admin notes')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _resolve(String action) async {
    final notes = await _promptNotes('Resolve as "$action"');
    if (notes == null) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.resolveReport(widget.report['id'] as String, action, notes: notes);
      widget.onChanged();
    } catch (e) {
      _showErr(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _dismiss() async {
    final notes = await _promptNotes('Dismiss report');
    if (notes == null) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.dismissReport(widget.report['id'] as String, notes: notes);
      widget.onChanged();
    } catch (e) {
      _showErr(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _suspendReported() async {
    final reportedProfileId = (widget.report['reported_user_id'] as String?) ?? '';
    if (reportedProfileId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.suspendUser(reportedProfileId, reason: 'Suspended via report ${widget.report['id']}');
      await AdminRepository.instance.resolveReport(widget.report['id'] as String, 'user_suspended');
      widget.onChanged();
    } catch (e) {
      _showErr(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteReported() async {
    final reportedProfileId = (widget.report['reported_user_id'] as String?) ?? '';
    if (reportedProfileId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.softDeleteUser(reportedProfileId, reason: 'Deleted via report ${widget.report['id']}');
      await AdminRepository.instance.resolveReport(widget.report['id'] as String, 'user_deleted');
      widget.onChanged();
    } catch (e) {
      _showErr(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showErr(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final r = widget.report;

    final reporter = (r['reporter'] as Map?)?.cast<String, dynamic>();
    final reported = (r['reported'] as Map?)?.cast<String, dynamic>();
    final reporterName = reporter?['first_name'] as String? ?? 'Unknown';
    final reportedName = reported?['first_name'] as String? ?? 'Unknown';
    final reportedId = r['reported_user_id'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    final details = r['details'] as String? ?? '';
    final severity = r['severity'] as String? ?? 'medium';
    final status = r['status'] as String? ?? 'pending';
    final adminNotes = r['admin_notes'] as String? ?? '';
    final actionTaken = r['action_taken'] as String? ?? '';

    final isPending = status == 'pending';

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SevBadge(severity: severity, appColors: appColors),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(child: Text(reason, style: text.titleSmall)),
              Text(status.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: isPending ? appColors.warning : appColors.success)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Wrap(
            spacing: AppTheme.spacingMd,
            children: [
              Text('Reporter: $reporterName', style: text.bodySmall),
              InkWell(
                onTap: reportedId.isEmpty ? null : () => openAdminUserDialog(context, reportedId).then((_) => widget.onChanged()),
                child: Text('Reported: $reportedName ↗', style: text.bodySmall?.copyWith(color: colors.primary)),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Text('“$details”', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (adminNotes.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Text('Notes: $adminNotes', style: text.bodySmall?.copyWith(color: appColors.subtleText)),
          ],
          if (actionTaken.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Text('Action: $actionTaken', style: text.bodySmall?.copyWith(color: appColors.success)),
          ],
          if (isPending) ...[
            const SizedBox(height: AppTheme.spacingMd),
            Wrap(
              spacing: AppTheme.spacingSm,
              runSpacing: AppTheme.spacingSm,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _resolve('action_taken'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Mark Resolved'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _dismiss,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Dismiss'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _suspendReported,
                  icon: Icon(Icons.person_off_outlined, size: 18, color: appColors.warning),
                  label: Text('Suspend User', style: TextStyle(color: appColors.warning)),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteReported,
                  icon: Icon(Icons.delete_outline, size: 18, color: appColors.danger),
                  label: Text('Delete User', style: TextStyle(color: appColors.danger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SevBadge extends StatelessWidget {
  final String severity;
  final AppColorsExtension appColors;
  const _SevBadge({required this.severity, required this.appColors});

  @override
  Widget build(BuildContext context) {
    final c = switch (severity) {
      'critical' => appColors.danger,
      'high' => appColors.warning,
      'medium' => appColors.warning.withOpacity(0.6),
      _ => appColors.subtleText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(severity.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontSize: 10)),
    );
  }
}
