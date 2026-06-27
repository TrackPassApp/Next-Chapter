import '../services/supabase_service.dart';

class ReportRepository {
  ReportRepository._();
  static final ReportRepository instance = ReportRepository._();

  /// Submits a report against [reportedProfileId]. Returns the new report id
  /// on success, or null if Supabase is unavailable / the call failed.
  ///
  /// All reports land in public.reports with status='pending' — picked up by
  /// the admin queue in Batch B7.
  Future<String?> submit({
    required String reportedProfileId,
    required String reason,
    String details = '',
  }) async {
    final db = SupabaseService.client;
    if (db == null) return null;
    try {
      final id = await db.rpc('report_user', params: {
        'reported_profile_id': reportedProfileId,
        'reason': reason,
        'details': details,
      });
      return id as String?;
    } catch (_) {
      return null;
    }
  }
}
