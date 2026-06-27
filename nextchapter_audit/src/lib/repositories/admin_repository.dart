import '../services/supabase_service.dart';

/// Admin-only data access. All writes go through SECURITY DEFINER RPCs that
/// re-check `is_admin()` server-side, so this layer doesn't need to.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  // ─── Dashboard metrics ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchMetrics() async {
    final db = SupabaseService.client;
    if (db == null) return {};
    final res = await db.rpc('admin_dashboard_metrics');
    return (res as Map?)?.cast<String, dynamic>() ?? {};
  }

  // ─── Users ───────────────────────────────────────────────────────────────

  /// Search/filter users for the admin list. Falls back to plain listing
  /// when query is empty.
  Future<List<Map<String, dynamic>>> listUsers({
    String query = '',
    bool? suspended,
    bool? deleted,
    int limit = 200,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    dynamic q = db.from('profiles').select();

    if (query.isNotEmpty) {
      // first_name OR city OR state contains query (case-insensitive).
      q = q.or(
        'first_name.ilike.%$query%,'
        'city.ilike.%$query%,'
        'state.ilike.%$query%',
      );
    }
    if (suspended != null) q = q.eq('is_suspended', suspended);
    if (deleted != null) q = q.eq('is_deleted', deleted);

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>?> fetchUserSummary(String profileId) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    final res = await db.rpc('admin_user_summary', params: {'target_profile_id': profileId});
    return (res as Map?)?.cast<String, dynamic>();
  }

  Future<void> suspendUser(String profileId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_suspend_user', params: {'target_profile_id': profileId, 'reason': reason});
  }

  Future<void> unsuspendUser(String profileId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_unsuspend_user', params: {'target_profile_id': profileId, 'reason': reason});
  }

  Future<void> softDeleteUser(String profileId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_soft_delete_user', params: {'target_profile_id': profileId, 'reason': reason});
  }

  Future<void> restoreUser(String profileId, {String? reason}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_restore_user', params: {'target_profile_id': profileId, 'reason': reason});
  }

  // ─── Reports ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listReports({
    String status = 'pending',
    int limit = 200,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return [];

    // Join reporter + reported names in a single round-trip.
    final rows = await db
        .from('reports')
        .select('''
          *,
          reporter:profiles!reports_reporter_id_fkey(id, first_name),
          reported:profiles!reports_reported_user_id_fkey(id, first_name, is_suspended, is_deleted)
        ''')
        .eq('status', status)
        .order('severity', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> resolveReport(String reportId, String actionTaken, {String? notes}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_resolve_report', params: {
      'report_id': reportId,
      'action_taken': actionTaken,
      'notes': notes,
    });
  }

  Future<void> dismissReport(String reportId, {String? notes}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_dismiss_report', params: {'report_id': reportId, 'notes': notes});
  }

  /// Update editable admin fields (severity, admin_notes). Uses the existing
  /// admin UPDATE policy on public.reports.
  Future<void> updateReportFields(String reportId, {String? severity, String? adminNotes}) async {
    final db = SupabaseService.client;
    if (db == null) return;
    final payload = <String, dynamic>{};
    if (severity != null) payload['severity'] = severity;
    if (adminNotes != null) payload['admin_notes'] = adminNotes;
    if (payload.isEmpty) return;
    await db.from('reports').update(payload).eq('id', reportId);
  }

  // ─── Verification queue ──────────────────────────────────────────────────

  /// Users with at least one verification field that is NOT yet verified.
  /// (For Beta we just list users; B8 will add per-kind submission queues.)
  Future<List<Map<String, dynamic>>> listVerificationQueue({int limit = 200}) async {
    final db = SupabaseService.client;
    if (db == null) return [];
    final rows = await db
        .from('verification_status')
        .select('''
          *,
          profile:profiles!verification_status_profile_id_fkey(id, first_name, city, state, is_suspended, is_deleted)
        ''')
        .or('email_verified.eq.false,phone_verified.eq.false,selfie_verified.eq.false,id_verified.eq.false')
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> setVerification({
    required String profileId,
    required String kind, // email | phone | selfie | id
    required bool value,
    String? notes,
  }) async {
    final db = SupabaseService.client;
    if (db == null) return;
    await db.rpc('admin_set_verification', params: {
      'target_profile_id': profileId,
      'kind': kind,
      'value': value,
      'notes': notes,
    });
  }

  // ─── Moderation log ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listModerationLog({int limit = 200}) async {
    final db = SupabaseService.client;
    if (db == null) return [];
    final rows = await db
        .from('moderation_log')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
