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
        _photoRecords = await PhotoRepository.instance.fetchPhotos(
          p.id,
          primaryPhotoId: p.primaryPhotoId,
        );
        _profile = p.copyWith(
          photoUrls: _photoRecords
              .map((record) => record['display_url'] as String)
              .toList(),
        );
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
    List<String> modes = const ['date'],
    List<PromptAnswer> prompts = const [],
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
      // Compute completeness here so the DB score stays accurate.
      final photoCount = _photoRecords.length;
      final score = UserProfile.computeCompleteness(
        firstName: firstName,
        dateOfBirth: dateOfBirth,
        city: city,
        state: state,
        gender: gender,
        relationshipStatus: relationshipStatus,
        aboutMe: aboutMe,
        modes: modes,
        lookingFor: lookingFor,
        interests: interests,
        lifeSituation: lifeSituation,
        prompts: prompts,
        photoCount: photoCount,
      );

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
        modes: modes,
        isComplete: score >= 60,
        completenessScore: score,
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
        ProfileRepository.instance.savePrompts(id, prompts),
        ProfileRepository.instance.ensureVerificationStatus(id, emailVerified: isEmailVerified),
      ]);

      // Reload non-photo profile fields. Photo ordering is managed by the
      // dedicated atomic photo RPC and must not be replaced by a stale read
      // when the user saves unrelated profile fields.
      final updated = await ProfileRepository.instance.fetchMyProfile(userId);
      if (updated != null) {
        _profile = updated.copyWith(
          photoUrls: _photoRecords
              .map((record) => record['display_url'] as String)
              .toList(),
        );
      }

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
    if (SupabaseService.client == null) {
      _error = 'Photo upload is unavailable because Supabase is not connected. '
          '${SupabaseService.configurationError ?? SupabaseService.initError ?? ""}';
      notifyListeners();
      return false;
    }

    // A restored browser session can reach Edit Profile before ProfileProvider
    // has finished loading. Resolve that race here instead of silently
    // returning a generic upload failure.
    if (_profileId == null) {
      await loadProfile(userId);
    }
    if (_profileId == null) {
      _error = 'Your profile could not be loaded. Save your profile once, then '
          'try uploading the photo again.';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = null;
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
        _photoRecords = await PhotoRepository.instance.fetchPhotos(
          _profileId!,
          primaryPhotoId: _profile?.primaryPhotoId,
        );
        // Update the cached profile's photoUrls list.
        _profile = _profile?.copyWith(
          photoUrls: _photoRecords.map((r) => r['display_url'] as String).toList(),
        );
      }

      _loading = false;
      notifyListeners();
      return url != null;
    } catch (e, st) {
      debugPrint('uploadPhoto failed: $e\n$st');
      _error = 'Photo upload failed: $e';
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

      _photoRecords = await PhotoRepository.instance.fetchPhotos(
        _profileId!,
        primaryPhotoId: _profile?.primaryPhotoId,
      );
      _profile = _profile?.copyWith(
        photoUrls: _photoRecords.map((r) => r['display_url'] as String).toList(),
      );

      _loading = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('deletePhoto failed: $e\n$st');
      _error = 'Photo delete failed: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Promote the given photo to primary. Refreshes the local cache so the
  /// browse card + profile detail immediately reflect the new main photo.
  Future<bool> setPrimaryPhoto(String photoId) async {
    if (SupabaseService.client == null) return false;
    if (_profileId == null) return false;
    _loading = true;
    notifyListeners();
    try {
      await PhotoRepository.instance
          .setPrimary(profileId: _profileId!, photoId: photoId);

      // The RPC has already committed the authoritative database order.
      // Reorder local state from the exact clicked ID instead of immediately
      // replacing it with a potentially stale follow-up read.
      final selectedIndex =
          _photoRecords.indexWhere((record) => record['id'] == photoId);
      if (selectedIndex < 0) {
        throw StateError('The selected photo is missing from local state.');
      }
      final reordered = _photoRecords
          .map((record) => Map<String, dynamic>.from(record))
          .toList();
      final selected = reordered.removeAt(selectedIndex);
      reordered.insert(0, selected);
      for (var i = 0; i < reordered.length; i++) {
        reordered[i]['display_order'] = i;
      }
      _photoRecords = reordered;
      _profile = _profile?.copyWith(
        primaryPhotoId: photoId,
        photoUrls:
            reordered.map((record) => record['display_url'] as String).toList(),
      );
      _loading = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      // Surface the actual error to the UI so silent failures stop looking
      // like success. The debugPrint captures the stack trace in devtools.
      debugPrint('setPrimaryPhoto failed: $e\n$st');
      _error = 'Could not set primary photo: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

}
