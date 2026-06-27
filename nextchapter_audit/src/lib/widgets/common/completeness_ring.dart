import 'package:flutter/material.dart';

/// Small circular ring showing profile completeness 0–100.
/// Used in Edit Profile, Profile Detail, and Settings.
class CompletenessRing extends StatelessWidget {
  final int score;
  final double size;
  final Color? color;
  final Color? backgroundColor;
  final bool showLabel;

  const CompletenessRing({
    super.key,
    required this.score,
    this.size = 56,
    this.color,
    this.backgroundColor,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = score.clamp(0, 100);
    final ringColor = color ??
        (clamped >= 80
            ? scheme.primary
            : clamped >= 50
                ? scheme.tertiary
                : scheme.secondary);
    final bg = backgroundColor ?? scheme.surfaceContainerHighest;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: clamped / 100,
              strokeWidth: size / 10,
              color: ringColor,
              backgroundColor: bg,
            ),
          ),
          if (showLabel)
            Text('$clamped%',
                style: TextStyle(
                  fontSize: size / 4.2,
                  fontWeight: FontWeight.w600,
                  color: ringColor,
                )),
        ],
      ),
    );
  }
}
