import 'package:flutter/material.dart';
import '../theme/theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Terms of Service', style: text.headlineMedium),
                const SizedBox(height: AppTheme.spacingSm),
                Text('Last updated: June 2026', style: text.bodySmall?.copyWith(color: appColors.subtleText)),
                const SizedBox(height: AppTheme.spacingLg),
                _Section(title: 'Eligibility', body: 'You must be at least 18 years old to use Next Chapter. By creating an account, you confirm that you are 18 or older.', text: text),
                _Section(title: 'Free Services', body: 'Next Chapter provides free profile browsing and unlimited messaging. Core features will always remain free. We believe meaningful connections should not be locked behind paywalls.', text: text),
                _Section(title: 'User Conduct', body: 'You agree to treat all users with respect. Harassment, spam, scams, fake profiles, and inappropriate content are strictly prohibited and will result in account suspension or termination.', text: text),
                _Section(title: 'Safety Features', body: 'We provide blocking and reporting tools. Blocked users cannot message or view each other. Reports are reviewed by our moderation team promptly.', text: text),
                _Section(title: 'Verification', body: 'Verification is voluntary and free. It helps build trust within the community. Verification status is displayed on profiles to help users make informed decisions.', text: text),
                _Section(title: 'Content Guidelines', body: 'Users are responsible for the content they share. Profile photos and information must be accurate and appropriate. We reserve the right to remove content that violates our guidelines.', text: text),
                _Section(title: 'Account Termination', body: 'We may suspend or terminate accounts that violate these terms. Users may delete their own accounts at any time, which will remove all personal data from active systems.', text: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  final TextTheme text;

  const _Section({required this.title, required this.body, required this.text});

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
