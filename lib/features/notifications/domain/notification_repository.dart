class FoundiNotification {
  const FoundiNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });
  final String id, type, category, title, body;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get unread => readAt == null;
  bool get isGeneral => !['message.created', 'chat_message'].contains(type);
}

class NotificationTarget {
  const NotificationTarget(this.type, this.id);
  final String type, id;
}

abstract interface class NotificationRepository {
  Stream<List<FoundiNotification>> watchInbox(String uid, {int limit = 30});
  Future<List<FoundiNotification>> loadOlder(String uid, String afterId);
  Stream<int> watchUnread(String uid);
  Future<void> markRead(String uid, String id);
  Future<void> markAllRead(String uid);
  Future<NotificationTarget> resolve(String id);
  Stream<Map<String, bool>> watchPreferences(String uid);
  Future<void> savePreferences(String uid, Map<String, bool> preferences);
}

abstract interface class PushPermission {
  Future<String> status();
  Future<void> enable();
}

abstract interface class MessageReadRepository {
  Stream<int> watchUnreadMessages(String uid);
  Future<void> markConversationRead(String conversationId, String messageId);
}
