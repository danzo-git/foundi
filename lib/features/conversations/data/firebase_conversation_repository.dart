import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'conversation_visibility.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../requests/domain/request_repository.dart';
import '../domain/conversation_repository.dart';

class FirebaseConversationRepository
    implements
        ConversationRepository,
        ConversationAvatarRepository,
        ConversationDeletionRepository {
  FirebaseConversationRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final _visibilityChanges = StreamController<String>.broadcast();
  @override
  Future<void> deleteConversation(
    String id, {
    required String viewerUid,
  }) async {
    final result = await _call('deleteConversation', {
      'conversationId': id,
      'viewerUid': viewerUid,
    });
    if (result['deleted'] != true) {
      throw const AuthFailure('Suppression non confirmée. Réessaie.');
    }
    _visibilityChanges.add(viewerUid);
  }

  @override
  Future<Map<String, String>> resolveConversationAvatars(
    List<String> conversationIds,
  ) async {
    final result = await _call('resolveConversationAvatars', {
      'conversationIds': conversationIds,
    });
    final avatars = result['avatars'];
    return avatars is Map
        ? {
            for (final entry in avatars.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          }
        : {};
  }

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
  }) => Stream<List<Conversation>>.multi((controller) {
    final query = _db
        .collection('conversations')
        .where(asProfessional ? 'professionalUid' : 'clientUid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? first;
    var generation = 0, active = true;
    Future<void> refresh() async {
      final page = first;
      if (page == null) return;
      final version = ++generation;
      bool current() => active && version == generation;
      try {
        final rows =
            await loadVisibleConversationRows<
              QueryDocumentSnapshot<Map<String, dynamic>>
            >(
              firstPage: page,
              idOf: (d) => d.id,
              isCurrent: current,
              deletedIds: (ids) async =>
                  (await _db
                          .collection('users/$uid/deletedConversations')
                          .where(FieldPath.documentId, whereIn: ids)
                          .limit(30)
                          .get(const GetOptions(source: Source.server)))
                      .docs
                      .map((d) => d.id)
                      .toSet(),
              nextPage: (last) async =>
                  (await query
                          .startAfterDocument(last)
                          .limit(30)
                          .get(const GetOptions(source: Source.server)))
                      .docs,
            );
        if (current()) {
          controller.add(
            rows.map((d) => Conversation.fromMap(d.id, d.data())).toList(),
          );
        }
      } catch (e, stack) {
        if (current()) controller.addError(e, stack);
      }
    }

    final source = query.limit(30).snapshots().listen((snapshot) {
      first = snapshot.docs;
      refresh();
    }, onError: controller.addError);
    final state = _db
        .doc('users/$uid/conversationState/inbox')
        .snapshots()
        .listen((_) => refresh(), onError: controller.addError);
    final local = _visibilityChanges.stream
        .where((changed) => changed == uid)
        .listen((_) => refresh());
    controller.onCancel = () async {
      active = false;
      generation++;
      await Future.wait([source.cancel(), state.cancel(), local.cancel()]);
    };
  });
  @override
  Stream<Conversation?> watchConversation(String id) =>
      Stream<Conversation?>.multi((controller) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          controller.add(null);
          controller.close();
          return;
        }
        DocumentSnapshot<Map<String, dynamic>>? chat;
        var visible = false, known = false, active = true;
        void publish() {
          if (active && known && chat != null) {
            controller.add(
              visible && chat!.exists
                  ? Conversation.fromMap(chat!.id, chat!.data()!)
                  : null,
            );
          }
        }

        final source = _db.doc('conversations/$id').snapshots().listen((s) {
          chat = s;
          publish();
        }, onError: controller.addError);
        final marker = _db
            .doc('users/$uid/deletedConversations/$id')
            .snapshots(includeMetadataChanges: true)
            .listen((s) {
              if (s.metadata.isFromCache && !s.exists) return;
              known = true;
              visible = !s.exists;
              publish();
            }, onError: controller.addError);
        controller.onCancel = () async {
          active = false;
          await Future.wait([source.cancel(), marker.cancel()]);
        };
      });
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
