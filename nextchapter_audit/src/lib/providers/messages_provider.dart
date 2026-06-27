import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../services/mock_data_service.dart';

class MessagesProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  List<ChatMessage> _currentMessages = [];
  bool _isLoading = false;
  int _selectedTab = 0;

  List<Conversation> get conversations =>
      _selectedTab == 0
          ? _conversations.where((c) => !c.isRequest).toList()
          : _conversations.where((c) => c.isRequest).toList();
  List<ChatMessage> get currentMessages => _currentMessages;
  bool get isLoading => _isLoading;
  int get selectedTab => _selectedTab;
  int get unreadCount => _conversations.fold(0, (sum, c) => sum + c.unreadCount);
  int get requestCount => _conversations.where((c) => c.isRequest).length;

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 300));
    _conversations = List.from(MockDataService.conversations);
    _isLoading = false;
    notifyListeners();
  }

  void setTab(int tab) {
    _selectedTab = tab;
    notifyListeners();
  }

  Future<void> loadMessages(String conversationId) async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 200));
    _currentMessages = MockDataService.getMessages(conversationId);
    _isLoading = false;
    notifyListeners();
  }

  void sendMessage(String text) {
    _currentMessages.add(ChatMessage(
      id: 'new_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      text: text,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void deleteConversation(String id) {
    _conversations.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}
