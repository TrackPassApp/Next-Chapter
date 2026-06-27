import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../repositories/photo_repository.dart';
import '../services/supabase_service.dart';

/// Holds the signed-in user's own [UserProfile] and exposes save/photo actions.
///
/// Lifecycle:
///   - Created globally in main.dart alongside AuthProvider.
///   - Call [loadProfile(userId)] after login / session restore.
///   - Call [clear()] on logout.
class ProfileProvider extends ChangeNotifier {
  UserProfile? _profile;
  String? _profileId;  // profiles.id (UUID), separate from auth user id
  bool _loading = false;
  String? _error;

  // Photo records keyed by DB row — needed for delete (we need storage_path).
  List<Map<String, dynamic>> _photoRecords = [];

  UserProfile? get profile => _profile;
  String? get profileId => _profileId;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasProfile => _profile != null && _profile!.firstName.isNotEmpty;
  List<Map<String, dynamic>> get photoRecords => _photoRecords;

  // ─── Load ─────────────────────────────────────────────────────────────────

  Future<void> loadProfile(String userId) async {
    if (SupabaseService.client == null) {
      _error = 'Supabase not connected — cannot load profile. '
          '${SupabaseService.configurationError ?? SupabaseService.initError ?? ""}';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final p = await ProfileRepository.instance.fetchMyProfile(userId);
      _profile = p;
      _profileId = p?.id;
      if (p != null) {
        _photoRecords = await PhotoRepository.instance.fetchPhotos(p.id);
      }
    } catch (e) {
      _error = 'Failed to load profile.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _profile = null;
    _profileId = null;
    _photoRecords = [];
    _error = null;
    notifyListeners();
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  /// Upsert profile core fields and all related lists atomically.
  Future<bool> saveProfile({
    required String userId,
    required String firstName,
    required DateTime dateOfBirth,
    required String city,
    required String state,
    required String gender,
    required String relationshipStatus,
    required String aboutMe,
    required List<String> lookingFor,
    required List<String> interests,
    required List<String> lifeSituation,
    required bool isEmailVerified,
  }) async {
    if (SupabaseService.client == null) {
      _error = 'Cannot save — Supabase is not connected. '
          '${SupabaseService.configurationError ?? SupabaseService.initError ?? ""}';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Upsert core profile row.
      final id = await ProfileRepository.instance.upsertProfile(
        userId: userId,
        firstName: firstName,
        dateOfBirth: dateOfBirth,
        city: city,
        state: state,
        gender: gender,
        relationshipStatus: relationshipStatus,
        aboutMe: aboutMe,
      );

      if (id == null) {
        _error = 'Failed to save profile. Please try again.';
        _loading = false;
        notifyListeners();
        return false;
      }

      _profileId = id;

      // Save child tables in parallel.
      await Future.wait([
        ProfileRepository.instance.saveInterests(id, interests),
        ProfileRepository.instance.saveLookingFor(id, lookingFor),
        ProfileRepository.instance.saveLifeSituation(id, lifeSituation),
        ProfileRepository.instance.ensureVerificationStatus(id, emailVerified: isEmailVerified),
      ]);

      // Reload the full assembled profile so the UI reflects what's in the DB.
      final updated = await ProfileRepository.instance.fetchMyProfile(userId);
      _profile = updated;
      _photoRecords = await PhotoRepository.instance.fetchPhotos(id);

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Save failed: ${e.toString()}';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── Photos ───────────────────────────────────────────────────────────────

  Future<bool> uploadPhoto({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (SupabaseService.client == null) return false;
    if (_profileId == null) return false;

    _loading = true;
    notifyListeners();

    try {
      const uuid = Uuid();
      final ext = mimeType.contains('png') ? 'png' : 'jpg';
      final filename = '${uuid.v4()}.$ext';

      final url = await PhotoRepository.instance.uploadPhoto(
        userId: userId,
        profileId: _profileId!,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );

      if (url != null) {
        // Refresh photos from DB.
        _photoRecords = await PhotoRepository.instance.fetchPhotos(_profileId!);
        // Update the cached profile's photoUrls list.
        _profile = _profile?.copyWith(
          photoUrls: _photoRecords.map((r) => r['display_url'] as String).toList(),
        );
      }

      _loading = false;
      notifyListeners();
      return url != null;
    } catch (e) {
      _error = 'Photo upload failed.';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Full account deletion: remove photos from Storage, then delete the profile
  /// row (which cascades to all child tables via ON DELETE CASCADE).
  Future<void> deleteAccount(String userId) async {
    if (SupabaseService.client == null) return;

    if (_profileId != null) {
      await PhotoRepository.instance.deleteAllPhotosForProfile(_profileId!);
    }
    await ProfileRepository.instance.deleteProfile(userId);
    clear();
  }

  Future<bool> deletePhoto(String photoId) async {
    if (SupabaseService.client == null) return false;
    if (_profileId == null) return false;

    final record = _photoRecords.firstWhere(
      (r) => r['id'] == photoId,
      orElse: () => {},
    );
    if (record.isEmpty) return false;

    _loading = true;
    notifyListeners();

    try {
      await PhotoRepository.instance.deletePhoto(
        photoId: photoId,
        storagePath: record['storage_path'] as String,
      );

      _photoRecords = await PhotoRepository.instance.fetchPhotos(_profileId!);
      _profile = _profile?.copyWith(
        photoUrls: _photoRecords.map((r) => r['display_url'] as String).toList(),
      );

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Photo delete failed.';
      _loading = false;
      notifyListeners();
      return false;
    }
  }
}
