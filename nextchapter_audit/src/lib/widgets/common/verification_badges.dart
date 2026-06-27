import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Compact verification badge strip. Used on profile cards, profile detail,
/// conversation tiles, chat header, etc.
///
/// Renders a tiny verified-shield + the count of approved kinds, OR full
/// labels when [expanded] is true.
class VerificationBadges extends StatelessWidget {
  final bool email;
  final bool phone;
  final bool selfie;
  final bool id;
  final bool expanded;
  final double scale;

  const VerificationBadges({
    super.key,
    required this.email,
    required this.phone,
    required this.selfie,
    required this.id,
    this.expanded = false,
    this.scale = 1.0,
  });

  /// Convenience constructor: pulls flags from a verification_status row.
  factory VerificationBadges.fromRow(Map<String, dynamic>? row, {bool expanded = false, double scale = 1.0}) {
    return VerificationBadges(
      email:  row?['email_verified']  == true,
      phone:  row?['phone_verified']  == true,
      selfie: row?['selfie_verified'] == true,
      id:     row?['id_verified']     == true,
      expanded: expanded,
      scale: scale,
    );
  }

  int get _count => (email ? 1 : 0) + (phone ? 1 : 0) + (selfie ? 1 : 0) + (id ? 1 : 0);
  bool get _any => _count > 0;

  @override
  Widget build(BuildContext context) {
    if (!_any) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    if (!expanded) {
      // Compact shield + count, designed for tight UI (card overlays, tile leading).
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
        decoration: BoxDecoration(
          color: appColors.verified.withOpacity(0.18),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: appColors.verified.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 12 * scale, color: appColors.verified),
            SizedBox(width: 3 * scale),
            Text('$_count/4',
                style: text.labelSmall?.copyWith(color: appColors.verified, fontSize: 10 * scale, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    // Expanded inline pills for Profile Detail.
    Widget pill(String label, bool ok) {
      final c = ok ? appColors.verified : appColors.subtleText;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(ok ? 0.20 : 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.verified : Icons.radio_button_unchecked, size: 12, color: c),
            const SizedBox(width: 3),
            Text(label, style: text.labelSmall?.copyWith(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        pill('Email', email),
        pill('Phone', phone),
        pill('Selfie', selfie),
        pill('ID', id),
      ],
    );
  }
}
