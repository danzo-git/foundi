import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../requests/domain/request_repository.dart';
import '../domain/conversation_repository.dart';

class FirebaseConversationRepository implements ConversationRepository {
  FirebaseConversationRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      return (await _functions
              .httpsCallable(name)
              .call<Map<String, dynamic>>(data))
          .data;
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(
        e.message ??
            'Opération non confirmée. Vérifie ta connexion et réessaie.',
      );
    }
  }

  @override
  Future<SelectionResult> selectProposal(
    String requestId,
    String proposalId,
  ) async {
    final m = await _call('selectProposal', {
      'requestId': requestId,
      'proposalId': proposalId,
    });
    return SelectionResult(
      m['conversationId'] as String,
      m['alreadySelected'] == true,
    );
  }

  @override
  String newDecisionId(String requestId) =>
      _db.collection('userRequests').doc().id;
  @override
  Future<void> decideProposal(
    String requestId,
    String proposalId,
    String action, {
    required String decisionId,
    String? expectedRetainedProposalId,
    String reason = '',
  }) async {
    await _call('decideProposal', {
      'requestId': requestId,
      'proposalId': proposalId,
      'action': action,
      'decisionId': decisionId,
      'expectedRetainedProposalId': expectedRetainedProposalId,
      'reason': reason,
    });
  }

  @override
  Stream<FoundiRequest?> watchOwnSelection(String uid, String requestId) => _db
      .doc('userRequests/$uid/items/$requestId')
      .snapshots()
      .map((s) => s.exists ? FoundiRequest.fromMap(s.id, s.data()!) : null);
  @override
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  }) => _db
      .collection('conversations')
      .where(asProfessional ? 'professionalUid' : 'clientUid', isEqualTo: uid)
      .orderBy('updatedAt', descending: true)
      .limit(30)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => Conversation.fromMap(d.id, d.data())).toList(),
      );
  @override
  Stream<Conversation?> watchConversation(String id) => _db
      .doc('conversations/$id')
      .snapshots()
      .map((s) => s.exists ? Conversation.fromMap(s.id, s.data()!) : null);
  @override
  Stream<MessageBatch> watchMessages(String id, {int limit = 30}) => _db
      .collection('conversations/$id/messages')
      .orderBy('createdAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true)
      .limit(limit.clamp(1, 100))
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => MessageBatch(
          s.docs
              .map((d) => ConversationMessage.fromMap(d.id, d.data()))
              .toList(),
          fromCache: s.metadata.isFromCache,
          hasPendingWrites: s.metadata.hasPendingWrites,
        ),
      );
  @override
  String newMessageId(String conversationId) =>
      _db.collection('conversations/$conversationId/messages').doc().id;
  @override
  Future<void> sendConversationMessage(
    String conversationId,
    String messageId,
    String text,
  ) async {
    await _call('sendConversationMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
      'text': text,
    });
  }
}
