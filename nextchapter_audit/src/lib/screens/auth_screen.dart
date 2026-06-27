import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';

class AuthScreen extends StatefulWidget {
  final bool isSignUp;
  const AuthScreen({super.key, this.isSignUp = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _isSignUp;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  DateTime? _dob;
  bool _obscure = true;
  bool _loading = false;
  bool _agreeTerms = false;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.isSignUp;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms and Privacy Policy')),
      );
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();

    if (_isSignUp) {
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your date of birth')),
        );
        setState(() => _loading = false);
        return;
      }
      final result = await auth.signUp(_emailController.text, _passwordController.text, _dob!);
      setState(() => _loading = false);
      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Signup failed. Please try again.')),
        );
      } else if (!auth.isEmailVerified) {
        // Supabase requires email confirmation — inform the user.
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Verify Your Email'),
            content: const Text(
              'We sent a confirmation link to your email address. '
              'Please check your inbox and click the link to activate your account, then log in.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _isSignUp = false);
                },
                child: const Text('Go to Login'),
              ),
            ],
          ),
        );
      } else {
        context.go('/browse');
      }
    } else {
      final result = await auth.login(_emailController.text, _passwordController.text);
      setState(() => _loading = false);
      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Login failed. Please try again.')),
        );
      } else {
        context.go('/browse');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isSignUp ? 'Create Your Account' : 'Welcome Back',
                          style: text.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.spacingSm),
                        Text(
                          _isSignUp ? 'Join a community built on real connections' : 'Sign in to continue your journey',
                          style: text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.spacingLg),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
                        ),
                        const SizedBox(height: AppTheme.spacingMd),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => v != null && v.length >= 6 ? null : 'Min 6 characters',
                        ),
                        if (_isSignUp) ...[
                          const SizedBox(height: AppTheme.spacingMd),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Confirm Password', prefixIcon: Icon(Icons.lock_outline)),
                            validator: (v) => v == _passwordController.text ? null : 'Passwords do not match',
                          ),
                          const SizedBox(height: AppTheme.spacingMd),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime(2000),
                                firstDate: DateTime(1920),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) setState(() => _dob = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date of Birth',
                                prefixIcon: Icon(Icons.cake_outlined),
                              ),
                              child: Text(
                                _dob != null
                                    ? '${_dob!.month}/${_dob!.day}/${_dob!.year}'
                                    : 'Must be 18+',
                                style: text.bodyMedium?.copyWith(
                                  color: _dob != null ? colors.onSurface : appColors.subtleText,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingMd),
                          CheckboxListTile(
                            value: _agreeTerms,
                            onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Wrap(
                              children: [
                                Text('I agree to the ', style: text.bodySmall),
                                GestureDetector(
                                  onTap: () => context.go('/terms'),
                                  child: Text('Terms', style: text.bodySmall?.copyWith(color: colors.primary, decoration: TextDecoration.underline)),
                                ),
                                Text(' and ', style: text.bodySmall),
                                GestureDetector(
                                  onTap: () => context.go('/privacy'),
                                  child: Text('Privacy Policy', style: text.bodySmall?.copyWith(color: colors.primary, decoration: TextDecoration.underline)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppTheme.spacingLg),
                        ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
                              : Text(_isSignUp ? 'Create Account' : 'Log In'),
                        ),
                        if (!_isSignUp) ...[
                          const SizedBox(height: AppTheme.spacingSm),
                          TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            child: const Text('Forgot Password?'),
                          ),
                        ],
                        const SizedBox(height: AppTheme.spacingMd),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_isSignUp ? 'Already have an account? ' : 'New here? ', style: text.bodySmall),
                            GestureDetector(
                              onTap: () => setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp ? 'Log In' : 'Create Account',
                                style: text.bodySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
