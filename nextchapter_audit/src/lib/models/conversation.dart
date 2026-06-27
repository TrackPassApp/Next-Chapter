class Conversation {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String otherUserPhoto;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isRequest;
  final bool isOnline;

  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserPhoto,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isRequest = false,
    this.isOnline = false,
  });
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.isRead = false,
  });
}

class Report {
  final String id;
  final String reporterId;
  final String reportedUserId;
  final String reportedUserName;
  final String reason;
  final String? details;
  final DateTime createdAt;
  final String status;

  const Report({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.reportedUserName,
    required this.reason,
    this.details,
    required this.createdAt,
    this.status = 'pending',
  });
}
