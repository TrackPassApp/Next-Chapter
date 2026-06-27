import 'package:flutter/foundation.dart';
import '../repositories/block_repository.dart';

/// Owns the set of profile ids the signed-in user has blocked.
///
/// Lifecycle:
///   • [bindProfile] is called from main.dart once the profile is loaded.
///   • [refresh] re-pulls the list from Supabase.
///   • [blockUser] / [unblockUser] mutate the list and notify listeners
///     so BrowseProvider/MessagesProvider can react.
class BlockProvider extends ChangeNotifier {
  final BlockRepository _repo = BlockRepository.instance;
  Set<String> _blockedIds = {};
  String? _myProfileId;
  bool _loading = false;

  Set<String> get blockedIds => _blockedIds;
  bool get loading => _loading;
  bool hasBlocked(String profileId) => _blockedIds.contains(profileId);

  Future<void> bindProfile(String myProfileId) async {
    if (_myProfileId == myProfileId && _blockedIds.isNotEmpty) return;
    _myProfileId = myProfileId;
    await refresh();
  }

  void clear() {
    _myProfileId = null;
    _blockedIds = {};
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_myProfileId == null) return;
    _loading = true;
    notifyListeners();
    _blockedIds = await _repo.fetchMyBlockedIds();
    _loading = false;
    notifyListeners();
  }

  /// Block [otherProfileId] and update local state.
  Future<bool> blockUser(String otherProfileId) async {
    try {
      await _repo.blockUser(otherProfileId);
      _blockedIds = {..._blockedIds, otherProfileId};
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unblockUser(String otherProfileId) async {
    try {
      await _repo.unblockUser(otherProfileId);
      _blockedIds = _blockedIds.where((id) => id != otherProfileId).toSet();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
