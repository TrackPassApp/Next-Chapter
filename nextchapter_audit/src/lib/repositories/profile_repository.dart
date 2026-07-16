import '../models/user_profile.dart';
import 'photo_repository.dart';
import '../services/supabase_service.dart';

/// Data-access layer for the [profiles] table and its child tables.
/// Never call Supabase directly from widgets or providers — go through here.
class ProfileRepository {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  // ─── Fetch ────────────────────────────────────────────────────────────────

  /// Load the profile for the currently logged-in user.
  /// Returns null if no profile row exists yet.
  Future<UserProfile?> fetchMyProfile(String userId) async {
    final db = SupabaseService.client;
    if (db == null) return null;

    final row = await db
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;

    final profileId = row['id'] as String;
    return _assembleProfile(profileId, row, db);
  }

  /// Load any profile by its profile.id (not user_id).
  Future<UserProfile?> fetchProfileById(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return null;

    final row = await db
        .from('profiles')
        .select()
        .eq('id', profileId)
        .eq('is_suspended', false)
        .eq('is_deleted', false)
        .maybeSingle();

    if (row == null) return null;
    return _assembleProfile(profileId, row, db);
  }

  /// Load profiles for the browse screen with server-side filters.
  ///
  /// Filtering applied at the database layer:
  ///   - excludes suspended and deleted rows
  ///   - excludes incomplete profiles UNLESS they belong to [currentUserId]
  ///   - optional [stateName] equality match
  ///   - optional [ageMin]/[ageMax] via date_of_birth window
  ///   - optional [modes] overlap (any mode in [modes])
  ///   - optional [excludedProfileIds] (e.g., users I've blocked)
  ///   - hard [limit] on rows returned (default 200 — fine for Beta)
  ///
  /// Note: interests / looking_for / life_situation filtering still happens
  /// in-memory on the caller side because those live in child tables.
  Future<List<UserProfile>> fetchAllProfiles({
    String? currentUserId,
    String? stateName,
    int? ageMin,
    int? ageMax,
    List<String> modes = const [],
    List<String> excludedProfileIds = const [],
    int limit = 200,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    dynamic query = db
        .from('profiles')
        .select()
        .eq('is_suspended', false)
        .eq('is_deleted', false);

    // Show incomplete profiles only if they belong to the current user.
    if (currentUserId != null) {
      query = query.or('is_complete.eq.true,user_id.eq.$currentUserId');
    } else {
      query = query.eq('is_complete', true);
    }

    if (stateName != null && stateName.isNotEmpty) {
      query = query.eq('state', stateName);
    }

    // Convert age range → date_of_birth window.
    if (ageMin != null || ageMax != null) {
      final now = DateTime.now();
      if (ageMin != null) {
        // Max DoB so that age >= ageMin.
        final maxDob = DateTime(now.year - ageMin, now.month, now.day);
        query = query.lte('date_of_birth', maxDob.toIso8601String().split('T').first);
      }
      if (ageMax != null) {
        // Min DoB so that age <= ageMax.
        final minDob = DateTime(now.year - ageMax - 1, now.month, now.day);
        query = query.gte('date_of_birth', minDob.toIso8601String().split('T').first);
      }
    }

    if (modes.isNotEmpty) {
      // overlaps operator → "modes && ARRAY['date','friend']"
      query = query.overlaps('modes', modes);
    }

    if (excludedProfileIds.isNotEmpty) {
      // not.in.(uuid1,uuid2)
      final csv = excludedProfileIds.join(',');
      query = query.not('id', 'in', '($csv)');
    }

    final rows = await query
        .order('completeness_score', ascending: false)
        .order('updated_at', ascending: false)
        .limit(limit);

    final List<UserProfile> result = [];
    for (final row in (rows as List)) {
      final profileId = row['id'] as String;
      final profile = await _assembleProfile(profileId, row, db);
      result.add(profile);
    }
    return result;
  }

  // ─── Upsert ───────────────────────────────────────────────────────────────

  /// Create or update the core profile row.
  Future<String?> upsertProfile({
    required String userId,
    required String firstName,
    required DateTime dateOfBirth,
    required String city,
    required String state,
    required String gender,
    required String relationshipStatus,
    required String aboutMe,
    List<String>? modes,
    bool? isComplete,
    int? completenessScore,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;

    final data = <String, dynamic>{
      'user_id': userId,
      'first_name': firstName,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'city': city,
      'state': state,
      'gender': gender,
      'relationship_status': relationshipStatus,
      'about_me': aboutMe,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (modes != null) data['modes'] = modes;
    if (isComplete != null) data['is_complete'] = isComplete;
    if (completenessScore != null) data['completeness_score'] = completenessScore;

    final result = await db
        .from('profiles')
        .upsert(data, onConflict: 'user_id')
        .select('id')
        .single();

    return result['id'] as String?;
  }

  /// Mark a profile complete (called at end of onboarding wizard).
  Future<void> markComplete(String userId, {int completenessScore = 60}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.from('profiles').update({
      'is_complete': true,
      'completeness_score': completenessScore,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  /// Replace all interests for a profile (delete-then-insert pattern).
  Future<void> saveInterests(String profileId, List<String> interests) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await db.from('profile_interests').delete().eq('profile_id', profileId);
    if (interests.isEmpty) return;

    await db.from('profile_interests').insert(
      interests.map((i) => {'profile_id': profileId, 'interest': i}).toList(),
    );
  }

  /// Replace all looking_for entries for a profile.
  Future<void> saveLookingFor(String profileId, List<String> lookingFor) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await db.from('profile_looking_for').delete().eq('profile_id', profileId);
    if (lookingFor.isEmpty) return;

    await db.from('profile_looking_for').insert(
      lookingFor.map((l) => {'profile_id': profileId, 'looking_for': l}).toList(),
    );
  }

  /// Replace all life_situation entries for a profile.
  Future<void> saveLifeSituation(String profileId, List<String> lifeSituation) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await db.from('profile_life_situation').delete().eq('profile_id', profileId);
    if (lifeSituation.isEmpty) return;

    await db.from('profile_life_situation').insert(
      lifeSituation.map((s) => {'profile_id': profileId, 'life_situation': s}).toList(),
    );
  }

  /// Replace all Hinge-style prompts for a profile. Caps at 3.
  Future<void> savePrompts(String profileId, List<PromptAnswer> prompts) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.from('profile_prompts').delete().eq('profile_id', profileId);
    if (prompts.isEmpty) return;
    final rows = prompts.take(3).toList().asMap().entries.map((e) => {
          'profile_id': profileId,
          'prompt_key': e.value.promptKey,
          'answer': e.value.answer,
          'position': e.key,
        }).toList();
    await db.from('profile_prompts').insert(rows);
  }

  /// Ensure a verification_status row exists for the profile.
  Future<void> ensureVerificationStatus(String profileId, {bool emailVerified = false}) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await db.from('verification_status').upsert(
      {
        'profile_id': profileId,
        'email_verified': emailVerified,
        'phone_verified': false,
        'selfie_verified': false,
        'id_verified': false,
      },
      onConflict: 'profile_id',
    );
  }

  // ─── Hard delete (account deletion) ──────────────────────────────────────

  /// Permanently delete the profile and cascade to all child tables.
  Future<void> deleteProfile(String userId) async {
    final db = SupabaseService.client;
    if (db == null) return;

    await db.from('profiles').delete().eq('user_id', userId);
  }

  // ─── Internal assembly ────────────────────────────────────────────────────

  Future<UserProfile> _assembleProfile(
    String profileId,
    Map<String, dynamic> row,
    dynamic db,
  ) async {
    // Fetch related rows in parallel.
    final primaryPhotoId = row['primary_photo_id']?.toString();
    final photosFuture = PhotoRepository.instance.fetchPhotos(
      profileId,
      primaryPhotoId: primaryPhotoId,
    );
    final interestsFuture = db.from('profile_interests')
        .select()
        .eq('profile_id', profileId)
        .then((r) => r as List);
    final lookingForFuture = db.from('profile_looking_for')
        .select()
        .eq('profile_id', profileId)
        .then((r) => r as List);
    final lifeSitFuture = db.from('profile_life_situation')
        .select()
        .eq('profile_id', profileId)
        .then((r) => r as List);
    final verFuture = db.from('verification_status')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle()
        .then((r) => r as Map<String, dynamic>?);
    final promptsFuture = db.from('profile_prompts')
        .select()
        .eq('profile_id', profileId)
        .order('position')
        .then((r) => r as List);

    final photos      = await photosFuture;
    final interests   = await interestsFuture;
    final lookingFor  = await lookingForFuture;
    final lifeSit     = await lifeSitFuture;
    final verRow      = await verFuture;
    final promptsRows = await promptsFuture;

    final dobRaw = row['date_of_birth'];
    final dob = dobRaw != null
        ? DateTime.tryParse(dobRaw.toString()) ?? DateTime(1980)
        : DateTime(1980);

    return UserProfile(
      id: profileId,
      firstName: row['first_name'] as String? ?? '',
      dateOfBirth: dob,
      city: row['city'] as String? ?? '',
      state: row['state'] as String? ?? '',
      gender: row['gender'] as String? ?? '',
      relationshipStatus: row['relationship_status'] as String? ?? '',
      primaryPhotoId: primaryPhotoId,
      aboutMe: row['about_me'] as String? ?? '',
      // Defensive null filtering on every child-row pluck. A single NULL
      // value here (e.g. a profile_photos row with no display_url) used to
      // throw a TypeError at runtime which propagated up the widget tree
      // and silently blanked the Profile Detail body in release mode.
      photoUrls: photos
          .map((p) => p['display_url']?.toString())
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList(),
      interests: interests
          .map((i) => i['interest']?.toString())
          .whereType<String>()
          .toList(),
      lookingFor: lookingFor
          .map((l) => l['looking_for']?.toString())
          .whereType<String>()
          .toList(),
      lifeSituation: lifeSit
          .map((s) => s['life_situation']?.toString())
          .whereType<String>()
          .toList(),
      modes: (row['modes'] as List?)?.map((m) => m.toString()).toList() ?? const ['date'],
      prompts: promptsRows
          .map<PromptAnswer?>((r) {
            final key = r['prompt_key']?.toString();
            final ans = r['answer']?.toString();
            if (key == null || key.isEmpty || ans == null) return null;
            return PromptAnswer(
              promptKey: key,
              answer: ans,
              position: (r['position'] as num?)?.toInt() ?? 0,
            );
          })
          .whereType<PromptAnswer>()
          .toList(),
      isComplete: row['is_complete'] as bool? ?? false,
      completenessScore: (row['completeness_score'] as num?)?.toInt() ?? 0,
      emailVerified: verRow?['email_verified'] as bool? ?? false,
      phoneVerified: verRow?['phone_verified'] as bool? ?? false,
      selfieVerified: verRow?['selfie_verified'] as bool? ?? false,
      idVerified: verRow?['id_verified'] as bool? ?? false,
      isOnline: row['is_online'] as bool? ?? false,
      lastActive: DateTime.tryParse(row['last_active']?.toString() ?? '') ?? DateTime.now(),
      isSuspended: row['is_suspended'] as bool? ?? false,
    );
  }
}
