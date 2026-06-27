import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../services/supabase_service.dart';

/// Live browse feed backed by Supabase.
///
/// Server-side filters (state, age range, modes, completeness, suspended,
/// deleted, blocked) live in [ProfileRepository.fetchAllProfiles]. The
/// remaining filters (city, looking_for, interests, free-text search,
/// verified-only) are applied in memory because they sit in child tables
/// or are textual contains() matches.
class BrowseProvider extends ChangeNotifier {
  List<UserProfile> _allProfiles = [];
  List<UserProfile> _filteredProfiles = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;
  Set<String> _blockedProfileIds = {};

  String? _stateFilter;
  String? _cityFilter;
  RangeValues _ageRange = const RangeValues(18, 100);
  List<String> _interestFilters = [];
  List<String> _lookingForFilters = [];
  List<String> _modeFilters = [];
  bool _verifiedOnly = false;
  String _searchQuery = '';

  List<UserProfile> get profiles => _filteredProfiles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get stateFilter => _stateFilter;
  String? get cityFilter => _cityFilter;
  RangeValues get ageRange => _ageRange;
  List<String> get interestFilters => _interestFilters;
  List<String> get lookingForFilters => _lookingForFilters;
  List<String> get modeFilters => _modeFilters;
  bool get verifiedOnly => _verifiedOnly;
  String get searchQuery => _searchQuery;
  bool get hasActiveFilters =>
      _stateFilter != null ||
      (_cityFilter != null && _cityFilter!.isNotEmpty) ||
      _ageRange.start != 18 || _ageRange.end != 100 ||
      _interestFilters.isNotEmpty ||
      _lookingForFilters.isNotEmpty ||
      _modeFilters.isNotEmpty ||
      _verifiedOnly;

  // ─── Load ────────────────────────────────────────────────────────────────

  /// Fetch profiles from Supabase using the current server-side filter set.
  /// Re-call this whenever a server-side filter (state, age, modes) changes.
  Future<void> loadProfiles({
    String? currentUserId,
    Set<String> blockedProfileIds = const {},
  }) async {
    _currentUserId = currentUserId;
    _blockedProfileIds = blockedProfileIds;

    if (SupabaseService.client == null) {
      _error = 'Supabase is not connected — cannot load profiles.';
      _allProfiles = [];
      _filteredProfiles = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await ProfileRepository.instance.fetchAllProfiles(
        currentUserId: currentUserId,
        stateName: _stateFilter,
        ageMin: _ageRange.start.round() == 18 ? null : _ageRange.start.round(),
        ageMax: _ageRange.end.round() == 100 ? null : _ageRange.end.round(),
        modes: _modeFilters,
        excludedProfileIds: blockedProfileIds.toList(),
      );
      _allProfiles = fetched;
      _applyFilters();
    } catch (e) {
      _error = 'Failed to load profiles: ${e.toString()}';
      _allProfiles = [];
      _filteredProfiles = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Setters that hit the server ─────────────────────────────────────────

  Future<void> setStateFilter(String? state) async {
    _stateFilter = state;
    await loadProfiles(currentUserId: _currentUserId, blockedProfileIds: _blockedProfileIds);
  }

  Future<void> setAgeRange(RangeValues range) async {
    _ageRange = range;
    await loadProfiles(currentUserId: _currentUserId, blockedProfileIds: _blockedProfileIds);
  }

  Future<void> toggleMode(String mode) async {
    if (_modeFilters.contains(mode)) {
      _modeFilters.remove(mode);
    } else {
      _modeFilters.add(mode);
    }
    await loadProfiles(currentUserId: _currentUserId, blockedProfileIds: _blockedProfileIds);
  }

  // ─── Setters that only re-filter in memory ───────────────────────────────

  void setCityFilter(String? city) {
    _cityFilter = (city == null || city.isEmpty) ? null : city;
    _applyFilters();
    notifyListeners();
  }

  void toggleInterest(String interest) {
    if (_interestFilters.contains(interest)) {
      _interestFilters.remove(interest);
    } else {
      _interestFilters.add(interest);
    }
    _applyFilters();
    notifyListeners();
  }

  void toggleLookingFor(String option) {
    if (_lookingForFilters.contains(option)) {
      _lookingForFilters.remove(option);
    } else {
      _lookingForFilters.add(option);
    }
    _applyFilters();
    notifyListeners();
  }

  void setVerifiedOnly(bool value) {
    _verifiedOnly = value;
    _applyFilters();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  Future<void> clearFilters() async {
    _stateFilter = null;
    _cityFilter = null;
    _ageRange = const RangeValues(18, 100);
    _interestFilters = [];
    _lookingForFilters = [];
    _modeFilters = [];
    _verifiedOnly = false;
    _searchQuery = '';
    await loadProfiles(currentUserId: _currentUserId, blockedProfileIds: _blockedProfileIds);
  }

  // ─── Filtering ───────────────────────────────────────────────────────────

  void _applyFilters() {
    _filteredProfiles = _allProfiles.where((profile) {
      if (_cityFilter != null &&
          !profile.city.toLowerCase().contains(_cityFilter!.toLowerCase())) {
        return false;
      }
      if (_interestFilters.isNotEmpty &&
          !_interestFilters.any((i) => profile.interests.contains(i))) {
        return false;
      }
      if (_lookingForFilters.isNotEmpty &&
          !_lookingForFilters.any((l) => profile.lookingFor.contains(l))) {
        return false;
      }
      if (_verifiedOnly && !profile.hasAnyVerification) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!profile.firstName.toLowerCase().contains(q) &&
            !profile.city.toLowerCase().contains(q) &&
            !profile.state.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}
