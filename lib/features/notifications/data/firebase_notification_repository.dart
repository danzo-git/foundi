import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../domain/notification_repository.dart';

class FirebaseNotificationRepository
    implements NotificationRepository, MessageReadRepository {
  FirebaseNotificationRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  CollectionReference<Map<String, dynamic>> _inbox(String uid) =>
      _db.collection('users/$uid/notifications');
  FoundiNotification _notification(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    return FoundiNotification(
      id: d.id,
      type: m['type'] as String,
      category: m['category'] as String,
      title: m['title'] as String,
      body: m['bodySafe'] as String,
      createdAt: m['occurredAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (m['occurredAt'] as num).toInt(),
            )
          : (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (m['readAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  Stream<List<FoundiNotification>> watchInbox(String uid, {int limit = 30}) =>
      _inbox(uid)
          .where('schemaVersion', isEqualTo: 9)
          .where('isGeneral', isEqualTo: true)
          .orderBy('occurredAt', descending: true)
          .limit(limit.clamp(1, 100))
          .snapshots()
          .map(
            (s) => s.docs.map(_notification).where((n) => n.isGeneral).toList(),
          );
  @override
  Future<List<FoundiNotification>> loadOlder(String uid, String afterId) async {
    final cursor = await _inbox(uid).doc(afterId).get();
    if (!cursor.exists) return [];
    final page = await _inbox(uid)
        .where('schemaVersion', isEqualTo: 9)
        .where('isGeneral', isEqualTo: true)
        .orderBy('occurredAt', descending: true)
        .startAfterDocument(cursor)
        .limit(30)
        .get();
    return page.docs.map(_notification).where((n) => n.isGeneral).toList();
  }

  @override
  Stream<int> watchUnread(String uid) => _db
      .doc('users/$uid/notificationState/inbox')
      .snapshots()
      .map(
        (s) => ((s.data()?['unreadCount'] as num?)?.toInt() ?? 0).clamp(
          0,
          1 << 31,
        ),
      );
  @override
  Future<void> markRead(String uid, String id) =>
      _db.runTransaction((tx) async {
        final ref = _inbox(uid).doc(id), saved = await tx.get(ref);
        if (saved.exists && saved.data()?['readAt'] == null) {
          tx.update(ref, {'readAt': FieldValue.serverTimestamp()});
        }
      });
  @override
  Future<void> markAllRead(String uid) async {
    // Freeze the upper boundary: notifications arriving during the action stay unread.
    final latest = await _inbox(uid)
        .where('schemaVersion', isEqualTo: 9)
        .where('isGeneral', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isEmpty) return;
    final boundary = latest.docs.first.get('createdAt');
    while (true) {
      final page = await _inbox(uid)
          .where('schemaVersion', isEqualTo: 9)
          .where('isGeneral', isEqualTo: true)
          .where('readAt', isNull: true)
          .where('createdAt', isLessThanOrEqualTo: boundary)
          .orderBy('createdAt')
          .limit(100)
          .get();
      if (page.docs.isEmpty) return;
      for (final d in page.docs) {
        await markRead(uid, d.id);
      }
    }
  }

  @override
  Future<NotificationTarget> resolve(String id) async {
    final r = await _functions
        .httpsCallable('resolveNotification')
        .call<Map<String, dynamic>>({'notificationId': id});
    return NotificationTarget(
      r.data['resourceType'] as String,
      r.data['resourceId'] as String,
    );
  }

  @override
  Stream<Map<String, bool>> watchPreferences(String uid) => _db
      .doc('users/$uid/notificationPreferences/push')
      .snapshots()
      .map(
        (s) => {
          for (final key in [
            'messages',
            'proposals',
            'opportunities',
            'account',
          ])
            key: s.data()?[key] != false,
          'messagePreview': s.data()?['messagePreview'] == true,
        },
      );
  @override
  Future<void> savePreferences(String uid, Map<String, bool> preferences) =>
      _db.doc('users/$uid/notificationPreferences/push').set(preferences);

  @override
  Stream<int> watchUnreadMessages(String uid) => _db
      .doc('users/$uid/messageState/inbox')
      .snapshots()
      .map(
        (s) => ((s.data()?['unreadCount'] as num?)?.toInt() ?? 0).clamp(
          0,
          1 << 31,
        ),
      );

  @override
  Future<void> markConversationRead(
    String conversationId,
    String messageId,
  ) async {
    bool more;
    do {
      final result = await _functions
          .httpsCallable('markConversationRead')
          .call<Map<String, dynamic>>({
            'conversationId': conversationId,
            'messageId': messageId,
          });
      more = result.data['more'] == true;
    } while (more);
  }
}
