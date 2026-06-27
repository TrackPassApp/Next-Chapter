import 'package:flutter/material.dart';
import '../theme/theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Privacy Policy', style: text.headlineMedium),
                const SizedBox(height: AppTheme.spacingSm),
                Text('Last updated: June 2026', style: text.bodySmall?.copyWith(color: appColors.subtleText)),
                const SizedBox(height: AppTheme.spacingLg),
                _PolicySection(title: 'Our Promise', body: 'Next Chapter will never sell, rent, give away, or share user personal information with advertisers, data brokers, or third-party marketers. Your data belongs to you.', text: text),
                _PolicySection(title: 'Data We Collect', body: 'We collect only the information necessary to provide our service: your profile information, messages, and usage data needed to improve the platform.', text: text),
                _PolicySection(title: 'How We Use Your Data', body: 'Your data is used exclusively to provide you with the Next Chapter experience — matching, messaging, and keeping the platform safe. We do not use your data for advertising targeting.', text: text),
                _PolicySection(title: 'Account Deletion', body: 'When you delete your account, we immediately remove your active profile, photos, messages, and personal data from our active systems. We believe in true data portability and deletion.', text: text),
                _PolicySection(title: 'Verification Data', body: 'Verification is for safety purposes only — never for monetization. Verification data is stored securely and used only to confirm your identity to other users.', text: text),
                _PolicySection(title: 'Third-Party Services', body: 'We use trusted infrastructure providers (hosting, storage) to operate the platform. These providers are contractually bound to protect your data and cannot use it for their own purposes.', text: text),
                _PolicySection(title: 'Contact', body: 'Questions about your privacy? Contact us at privacy@nextchapter.example.com', text: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  final TextTheme text;

  const _PolicySection({required this.title, required this.body, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppTheme.spacingSm),
          Text(body, style: text.bodyLarge),
        ],
      ),
    );
  }
}
