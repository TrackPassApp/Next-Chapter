import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';
import '../services/supabase_service.dart';

/// User-facing verification data access.
///
/// Email is intentionally NOT submitted via this repo — email status comes
/// straight from Supabase Auth (via AuthProvider.isEmailVerified). The admin
/// dashboard reads `verification_status.email_verified` which is set by the
/// auth bootstrap trigger; this repo handles phone / selfie / id only.
class VerificationRepository {
  VerificationRepository._();
  static final VerificationRepository instance = VerificationRepository._();

  static const _uuid = Uuid();
  static const _bucket = 'verification-docs';

  /// Latest status row for the signed-in user. May be null if Supabase is offline.
  Future<Map<String, dynamic>?> fetchMyStatus(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    final res = await db
        .from('verification_status')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res);
  }

  /// Returns all verification requests for the signed-in user (any status),
  /// newest first.
  Future<List<Map<String, dynamic>>> fetchMyRequests(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return [];
    final rows = await db
        .from('verification_requests')
        .select()
        .eq('profile_id', profileId)
        .order('submitted_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Submit a phone verification request (SMS coming later — server stores
  /// the number and admin can manually approve for Beta).
  Future<String?> submitPhone(String phoneNumber) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    final id = await db.rpc('submit_verification_request', params: {
      'kind': 'phone',
      'phone_number': phoneNumber,
      'storage_path': null,
    });
    return id as String?;
  }

  /// Upload a selfie or ID document to the private bucket and submit a request.
  /// Returns the new request id on success.
  ///
  /// [authUserId] must be the user's auth.uid() so the storage path matches
  /// the per-user RLS folder rule.
  Future<String?> submitDocument({
    required String kind, // 'selfie' or 'id'
    required String authUserId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    assert(kind == 'selfie' || kind == 'id');
    final db = SupabaseService.client;
    if (db == null) return null;

    // {auth_uid}/{kind}_{uuid}.ext  → satisfies the storage policy.
    final ext = _extFor(mimeType);
    final path = '$authUserId/${kind}_${_uuid.v4()}$ext';

    await db.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    final id = await db.rpc('submit_verification_request', params: {
      'kind': kind,
      'phone_number': null,
      'storage_path': path,
    });
    return id as String?;
  }

  /// Cancel a pending request (RLS only allows the owner to cancel their own).
  Future<void> cancelRequest(String requestId) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db
        .from('verification_requests')
        .update({'status': 'cancelled', 'reviewed_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', requestId);
  }

  /// Generate a temporary signed URL for a verification doc — used by the
  /// admin dialog. Returns null if Supabase is offline or the call fails.
  Future<String?> signedDocUrl(String storagePath, {int expiresInSeconds = 60 * 10}) async {
    final db = SupabaseService.client;
    if (db == null || storagePath.isEmpty) return null;
    try {
      return await db.storage.from(_bucket).createSignedUrl(storagePath, expiresInSeconds);
    } catch (_) {
      return null;
    }
  }

  String _extFor(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/heic':
      case 'image/heif':
        return '.heic';
      default:
        return '.jpg';
    }
  }
}
