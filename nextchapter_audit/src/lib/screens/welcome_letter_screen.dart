import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';
import 'founder_letter_screen.dart';

/// One-time post-onboarding wrapper around the founder letter. Only route to
/// this from OnboardingScreen._finish() the very first time. After the user
/// taps the CTA, they land on /browse.
class WelcomeLetterScreen extends StatelessWidget {
  const WelcomeLetterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
              child: FounderLetterView(
                onDismiss: () => context.go('/browse'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
