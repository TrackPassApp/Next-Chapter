import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/mock_data_service.dart';

class BrowseProvider extends ChangeNotifier {
  List<UserProfile> _allProfiles = [];
  List<UserProfile> _filteredProfiles = [];
  bool _isLoading = false;
  String? _error;

  String? _stateFilter;
  String? _cityFilter;
  RangeValues _ageRange = const RangeValues(18, 100);
  List<String> _interestFilters = [];
  List<String> _lookingForFilters = [];
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
  bool get verifiedOnly => _verifiedOnly;
  String get searchQuery => _searchQuery;
  bool get hasActiveFilters =>
      _stateFilter != null ||
      _cityFilter != null ||
      _ageRange != const RangeValues(18, 100) ||
      _interestFilters.isNotEmpty ||
      _lookingForFilters.isNotEmpty ||
      _verifiedOnly;

  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    _allProfiles = List.from(MockDataService.profiles);
    _applyFilters();
    _isLoading = false;
    notifyListeners();
  }

  void setStateFilter(String? state) {
    _stateFilter = state;
    _applyFilters();
    notifyListeners();
  }

  void setCityFilter(String? city) {
    _cityFilter = city;
    _applyFilters();
    notifyListeners();
  }

  void setAgeRange(RangeValues range) {
    _ageRange = range;
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

  void clearFilters() {
    _stateFilter = null;
    _cityFilter = null;
    _ageRange = const RangeValues(18, 100);
    _interestFilters = [];
    _lookingForFilters = [];
    _verifiedOnly = false;
    _searchQuery = '';
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    _filteredProfiles = _allProfiles.where((profile) {
      if (_stateFilter != null && profile.state != _stateFilter) return false;
      if (_cityFilter != null && _cityFilter!.isNotEmpty &&
          !profile.city.toLowerCase().contains(_cityFilter!.toLowerCase())) return false;
      if (profile.age < _ageRange.start || profile.age > _ageRange.end) return false;
      if (_interestFilters.isNotEmpty &&
          !_interestFilters.any((i) => profile.interests.contains(i))) return false;
      if (_lookingForFilters.isNotEmpty &&
          !_lookingForFilters.any((l) => profile.lookingFor.contains(l))) return false;
      if (_verifiedOnly && !profile.hasAnyVerification) return false;
      if (_searchQuery.isNotEmpty &&
          !profile.firstName.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !profile.city.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !profile.state.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      return true;
    }).toList();
  }
}
