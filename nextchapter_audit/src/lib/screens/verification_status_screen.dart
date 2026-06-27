import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/verification_repository.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';

/// User-facing Verification Center.
///
/// Lists all four verification kinds with current status and an entry point
/// to submit (or resend) a request. Replaces the old quick-dialog from
/// Settings — fixes the previous refresh loop and broken close behaviour.
class VerificationStatusScreen extends StatefulWidget {
  const VerificationStatusScreen({super.key});

  @override
  State<VerificationStatusScreen> createState() => _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends State<VerificationStatusScreen> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profileId = context.read<ProfileProvider>().profileId;
    if (profileId == null) {
      setState(() {
        _loading = false;
        _error = 'Finish your profile first to manage verification.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await VerificationRepository.instance.fetchMyStatus(profileId);
      final r = await VerificationRepository.instance.fetchMyRequests(profileId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _requests = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load verification status: $e';
      });
    }
  }

  Map<String, dynamic>? _latestRequest(String kind) {
    for (final r in _requests) {
      if (r['kind'] == kind) return r;
    }
    return null;
  }

  // ─── Email ────────────────────────────────────────────────────────────────
  Future<void> _resendEmail() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.resendEmailVerification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Verification email sent — check your inbox.' : 'Could not send verification email. Try again later.'),
    ));
  }

  // ─── Phone ───────────────────────────────────────────────────────────────
  Future<void> _submitPhone() async {
    final ctrl = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Phone Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+1 555 123 4567',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              'SMS verification is coming soon. For Beta, we securely store your number and our team will review your request.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (phone == null || phone.isEmpty) return;
    final id = await VerificationRepository.instance.submitPhone(phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(id == null ? 'Could not submit. Try again later.' : 'Phone verification request submitted.'),
    ));
    _load();
  }

  // ─── Selfie / ID upload ───────────────────────────────────────────────────
  Future<void> _submitDocument(String kind) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: kind == 'selfie' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;

    final authUserId = context.read<AuthProvider>().userId;
    if (authUserId == null) return;

    final Uint8List bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';

    final id = await VerificationRepository.instance.submitDocument(
      kind: kind,
      authUserId: authUserId,
      bytes: bytes,
      mimeType: mime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(id == null
          ? 'Upload failed. Please try again.'
          : '${kind == 'selfie' ? "Selfie" : "ID"} submitted. Status: Pending Review.'),
    ));
    _load();
  }

  Future<void> _cancelRequest(String requestId) async {
    await VerificationRepository.instance.cancelRequest(requestId);
    _load();
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Center'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorBox(text, appColors)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppTheme.spacingMd),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.shield_outlined, color: colors.primary),
                                const SizedBox(width: AppTheme.spacingMd),
                                Expanded(
                                  child: Text(
                                    'Verification is free and helps keep the community safe. '
                                    'Your documents are private and only reviewed by our moderation team.',
                                    style: text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingLg),

                          _VerifySection(
                            icon: Icons.email_outlined,
                            title: 'Email',
                            verified: auth.isEmailVerified || _status?['email_verified'] == true,
                            requestStatus: null,
                            primaryActionLabel:
                                (auth.isEmailVerified || _status?['email_verified'] == true) ? null : 'Resend verification email',
                            onPrimary: _resendEmail,
                            description: 'Confirms your sign-in email. Required for password reset and account recovery.',
                          ),
                          _VerifySection(
                            icon: Icons.phone_outlined,
                            title: 'Phone',
                            verified: _status?['phone_verified'] == true,
                            requestStatus: _latestRequest('phone')?['status'] as String?,
                            primaryActionLabel: _status?['phone_verified'] == true
                                ? 'Update phone number'
                                : (_latestRequest('phone')?['status'] == 'pending' ? null : 'Add phone number'),
                            onPrimary: _submitPhone,
                            secondaryActionLabel: _latestRequest('phone')?['status'] == 'pending' ? 'Cancel request' : null,
                            onSecondary: () {
                              final r = _latestRequest('phone');
                              if (r != null) _cancelRequest(r['id'] as String);
                            },
                            description: 'SMS verification placeholder. Your number is stored securely and reviewed by our team.',
                          ),
                          _VerifySection(
                            icon: Icons.face_outlined,
                            title: 'Selfie',
                            verified: _status?['selfie_verified'] == true,
                            requestStatus: _latestRequest('selfie')?['status'] as String?,
                            primaryActionLabel: _status?['selfie_verified'] == true
                                ? 'Replace selfie'
                                : (_latestRequest('selfie')?['status'] == 'pending' ? null : 'Take a selfie'),
                            onPrimary: () => _submitDocument('selfie'),
                            secondaryActionLabel: _latestRequest('selfie')?['status'] == 'pending' ? 'Cancel request' : null,
                            onSecondary: () {
                              final r = _latestRequest('selfie');
                              if (r != null) _cancelRequest(r['id'] as String);
                            },
                            description: 'A clear photo of your face. Used to confirm you match your profile photos.',
                          ),
                          _VerifySection(
                            icon: Icons.badge_outlined,
                            title: 'Government ID',
                            verified: _status?['id_verified'] == true,
                            requestStatus: _latestRequest('id')?['status'] as String?,
                            primaryActionLabel: _status?['id_verified'] == true
                                ? 'Replace ID'
                                : (_latestRequest('id')?['status'] == 'pending' ? null : 'Upload ID'),
                            onPrimary: () => _submitDocument('id'),
                            secondaryActionLabel: _latestRequest('id')?['status'] == 'pending' ? 'Cancel request' : null,
                            onSecondary: () {
                              final r = _latestRequest('id');
                              if (r != null) _cancelRequest(r['id'] as String);
                            },
                            description: 'Driver\'s license, passport, or state ID. Documents are encrypted in transit and only seen by moderators.',
                          ),
                          const SizedBox(height: AppTheme.spacingLg),
                          if (!SupabaseService.isConfigured)
                            Text('⚠ Supabase is not connected — submissions will not be saved.',
                                style: text.bodySmall?.copyWith(color: appColors.danger)),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _errorBox(TextTheme text, AppColorsExtension appColors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: appColors.danger),
            const SizedBox(height: AppTheme.spacingSm),
            Text(_error!, style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.spacingMd),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _VerifySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool verified;
  final String? requestStatus;
  final String? primaryActionLabel;
  final VoidCallback? onPrimary;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondary;
  final String description;

  const _VerifySection({
    required this.icon,
    required this.title,
    required this.verified,
    required this.requestStatus,
    required this.primaryActionLabel,
    required this.onPrimary,
    this.secondaryActionLabel,
    this.onSecondary,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColorsExtension>()!;

    final (statusLabel, statusColor) = _statusLabel(verified, requestStatus, appColors);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
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
              Icon(icon, color: colors.primary),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(child: Text(title, style: text.titleMedium)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(statusLabel,
                    style: text.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(description, style: text.bodySmall?.copyWith(color: appColors.subtleText)),
          if (primaryActionLabel != null || secondaryActionLabel != null) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Row(
              children: [
                if (primaryActionLabel != null)
                  OutlinedButton.icon(
                    onPressed: onPrimary,
                    icon: Icon(verified ? Icons.refresh : Icons.add, size: 18),
                    label: Text(primaryActionLabel!),
                  ),
                if (secondaryActionLabel != null) ...[
                  const SizedBox(width: AppTheme.spacingSm),
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryActionLabel!, style: TextStyle(color: appColors.danger)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _statusLabel(bool verified, String? requestStatus, AppColorsExtension c) {
    if (verified) return ('VERIFIED', c.success);
    switch (requestStatus) {
      case 'pending':
        return ('PENDING REVIEW', c.warning);
      case 'rejected':
        return ('REJECTED', c.danger);
      case 'cancelled':
        return ('CANCELLED', c.subtleText);
      default:
        return ('NOT VERIFIED', c.subtleText);
    }
  }
}
