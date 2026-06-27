import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class ReportDialog extends StatefulWidget {
  final String userName;

  const ReportDialog({super.key, required this.userName});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final _detailsController = TextEditingController();

  static const _reasons = [
    'Spam',
    'Scam',
    'Fake Profile',
    'Harassment',
    'Inappropriate Content',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
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
              onChanged: (v) => setState(() => _selectedReason = v),
              title: Text(reason, style: text.bodyMedium),
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: appColors.danger,
            )),
            const SizedBox(height: AppTheme.spacingMd),
            TextFormField(
              controller: _detailsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedReason == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'reason': _selectedReason,
                    'details': _detailsController.text,
                  });
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: appColors.danger,
            foregroundColor: colors.onError,
            minimumSize: const Size(100, 40),
          ),
          child: const Text('Report'),
        ),
      ],
    );
  }
}
