import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../services/supabase_service.dart';

/// Manages profile photo storage in Supabase Storage bucket [profile-photos]
/// and the corresponding rows in the [profile_photos] table.
///
/// Storage path convention: {user_id}/{uuid}.jpg
/// This ensures RLS storage policies scoped to auth.uid() work correctly.
class PhotoRepository {
  PhotoRepository._();
  static final PhotoRepository instance = PhotoRepository._();

  static const String _bucket = 'profile-photos';

  // ─── Upload ───────────────────────────────────────────────────────────────

  /// Upload [bytes] to Storage, insert a row into profile_photos, and return
  /// the signed URL. Returns null on failure.
  Future<String?> uploadPhoto({
    required String userId,
    required String profileId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;

    final storagePath = '$userId/$filename';

    await db.storage.from(_bucket).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(contentType: mimeType),
    );

    // Signed URL valid for 10 years — refreshable later.
    final signedUrl = await db.storage
        .from(_bucket)
        .createSignedUrl(storagePath, 60 * 60 * 24 * 365 * 10);

    // Determine display_order from existing photo count.
    final existing = await db
        .from('profile_photos')
        .select('id')
        .eq('profile_id', profileId);
    final order = (existing as List).length;

    await db.from('profile_photos').insert({
      'profile_id': profileId,
      'storage_path': storagePath,
      'display_url': signedUrl,
      'display_order': order,
    });

    return signedUrl;
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  /// Delete a single photo from Storage and its database row.
  Future<void> deletePhoto({
    required String photoId,
    required String storagePath,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await Future.wait<void>([
      db.storage.from(_bucket).remove([storagePath]).then((_) {}),
      db.from('profile_photos').delete().eq('id', photoId).then((_) {}),
    ]);
  }

  /// Delete all photos for a profile. Used during account deletion.
  Future<void> deleteAllPhotosForProfile(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return;

    final rows = await db
        .from('profile_photos')
        .select('id, storage_path')
        .eq('profile_id', profileId);

    final paths = (rows as List)
        .map((r) => r['storage_path'] as String)
        .toList();

    if (paths.isNotEmpty) {
      await db.storage.from(_bucket).remove(paths);
    }
    await db.from('profile_photos').delete().eq('profile_id', profileId);
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────

  /// Returns photo records (id, storage_path, display_url, display_order)
  /// for a given profile ordered by display_order.
  Future<List<Map<String, dynamic>>> fetchPhotos(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    final rows = await db
        .from('profile_photos')
        .select('id, storage_path, display_url, display_order')
        .eq('profile_id', profileId)
        .order('display_order');

    return List<Map<String, dynamic>>.from(rows as List);
  }
}
