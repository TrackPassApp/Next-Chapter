import 'package:flutter/material.dart';
import '../../repositories/report_repository.dart';
import '../../theme/theme.dart';

class ReportDialog extends StatefulWidget {
  /// Display name of the user being reported.
  final String userName;

  /// The profile id of the user being reported. Required to persist the report.
  final String reportedProfileId;

  const ReportDialog({
    super.key,
    required this.userName,
    required this.reportedProfileId,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;
  String? _error;

  static const _reasons = [
    'Spam',
    'Scam',
    'Fake Profile',
    'Harassment',
    'Inappropriate Content',
    'Underage',
    'Other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final id = await ReportRepository.instance.submit(
      reportedProfileId: widget.reportedProfileId,
      reason: _selectedReason!,
      details: _detailsController.text.trim(),
    );
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _submitting = false;
        _error = 'Could not submit report. Please try again.';
      });
      return;
    }
    Navigator.pop(context, {
      'reportId': id,
      'reason': _selectedReason,
      'details': _detailsController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return AlertDialog(
      title: Text('Report ${widget.userName}', style: text.titleLarge),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select a reason:', style: text.bodyMedium),
            const SizedBox(height: AppTheme.spacingMd),
            ..._reasons.map((reason) => RadioListTile<String>(
                  value: reason,
                  groupValue: _selectedReason,
                  onChanged: _submitting ? null : (v) => setState(() => _selectedReason = v),
                  title: Text(reason, style: text.bodyMedium),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: appColors.danger,
                )),
            const SizedBox(height: AppTheme.spacingMd),
            TextFormField(
              controller: _detailsController,
              maxLines: 3,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppTheme.spacingSm),
              Text(_error!, style: text.bodySmall?.copyWith(color: appColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_selectedReason == null || _submitting) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: appColors.danger,
            foregroundColor: colors.onError,
            minimumSize: const Size(100, 40),
          ),
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Report'),
        ),
      ],
    );
  }
}
