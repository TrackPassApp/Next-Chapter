import '../services/supabase_service.dart';

/// Block list state lives in BlockProvider. This repository is the
/// data-access layer only.
class BlockRepository {
  BlockRepository._();
  static final BlockRepository instance = BlockRepository._();

  /// Profiles that the current user has blocked.
  /// Returns an empty set if Supabase isn't connected.
  Future<Set<String>> fetchMyBlockedIds() async {
    final db = SupabaseService.client;
    if (db == null) return {};
    final rows = await db.from('user_blocks').select('blocked_id');
    return {for (final r in (rows as List)) r['blocked_id'] as String};
  }

  /// Profiles that have blocked the current user.
  /// Note: regular RLS hides this from a user. Only admins can read all blocks,
  /// so for non-admin callers this will return an empty set. We still query so
  /// admin views can use the same method.
  Future<Set<String>> fetchBlockedMeIds(String myProfileId) async {
    final db = SupabaseService.client;
    if (db == null) return {};
    final rows = await db.from('user_blocks').select('blocker_id').eq('blocked_id', myProfileId);
    return {for (final r in (rows as List)) r['blocker_id'] as String};
  }

  Future<void> blockUser(String targetProfileId) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('block_user', params: {'target_profile_id': targetProfileId});
  }

  Future<void> unblockUser(String targetProfileId) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('unblock_user', params: {'target_profile_id': targetProfileId});
  }
}
