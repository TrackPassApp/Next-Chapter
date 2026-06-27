import '../models/user_profile.dart';
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

  /// Load all active profiles for the browse screen.
  Future<List<UserProfile>> fetchAllProfiles({String? excludeUserId}) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    var query = db
        .from('profiles')
        .select()
        .eq('is_suspended', false)
        .eq('is_deleted', false);

    final rows = await query;

    final List<UserProfile> result = [];
    for (final row in rows) {
      // Skip the logged-in user's own profile from browse results.
      if (excludeUserId != null && row['user_id'] == excludeUserId) continue;
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
    final photosFuture = db.from('profile_photos')
        .select()
        .eq('profile_id', profileId)
        .order('display_order')
        .then((r) => r as List);
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
      aboutMe: row['about_me'] as String? ?? '',
      photoUrls: photos.map((p) => p['display_url'] as String).toList(),
      interests: interests.map((i) => i['interest'] as String).toList(),
      lookingFor: lookingFor.map((l) => l['looking_for'] as String).toList(),
      lifeSituation: lifeSit.map((s) => s['life_situation'] as String).toList(),
      modes: (row['modes'] as List?)?.map((m) => m.toString()).toList() ?? const ['date'],
      prompts: promptsRows.map<PromptAnswer>((r) => PromptAnswer(
        promptKey: r['prompt_key'] as String,
        answer: r['answer'] as String,
        position: (r['position'] as num?)?.toInt() ?? 0,
      )).toList(),
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
