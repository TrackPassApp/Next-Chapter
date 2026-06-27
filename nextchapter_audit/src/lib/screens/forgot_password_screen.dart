import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final result = await context
        .read<AuthProvider>()
        .sendPasswordReset(_emailController.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      setState(() => _sent = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Failed to send reset email.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                GestureDetector(
                  onTap: () => context.go('/'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingSm),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Icon(Icons.favorite, size: AppTheme.iconLg, color: colors.primary),
                      ),
                      const SizedBox(width: AppTheme.spacingSm),
                      Text('Next Chapter', style: text.headlineSmall?.copyWith(color: colors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXl),
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    border: Border.all(color: colors.outlineVariant.withOpacity(0.2)),
                    boxShadow: [BoxShadow(color: colors.shadow.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: _sent ? _buildSuccess(context, colors, text) : _buildForm(colors, text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ColorScheme colors, TextTheme text) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset Password', style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            "Enter your email address and we'll send you a link to reset your password.",
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingLg),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: AppTheme.spacingLg),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                  )
                : const Text('Send Reset Link'),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, ColorScheme colors, TextTheme text) {
    final appColors = Theme.of(context).extension<AppColorsExtension>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 56, color: appColors.success),
        const SizedBox(height: AppTheme.spacingMd),
        Text('Check Your Email', style: text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: AppTheme.spacingSm),
        Text(
          'If an account exists for ${_emailController.text}, you will receive a password reset link shortly.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingLg),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
