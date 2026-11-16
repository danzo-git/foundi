import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'conversation_visibility.dart';
import '../../../core/latest_async_refresh.dart';
import '../../../core/in_flight_reads.dart';
import '../../../core/firebase_read_scope.dart';
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
  static const _readTimeout = Duration(seconds: 12);
  final _avatarReads = InFlightReads(currentScope: firebaseReadScope);
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
  ) {
    final ids = conversationIds.toSet().toList()..sort();
    return _avatarReads.run<Map<String, String>>(
      ('conversation-avatars', ids.join('|')),
      () async {
        final result = await _call('resolveConversationAvatars', {
          'conversationIds': ids,
        });
        final avatars = result['avatars'];
        return avatars is Map
            ? {
                for (final entry in avatars.entries)
                  if (entry.key is String && entry.value is String)
                    entry.key as String: entry.value as String,
              }
            : {};
      },
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      return (await _functions
              .httpsCallable(
                name,
                options: name == 'resolveConversationAvatars'
                    ? HttpsCallableOptions(timeout: const Duration(seconds: 20))
                    : null,
              )
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
    var stateReady = false;
    final refresh = LatestAsyncRefresh((current) async {
      final page = first;
      if (page == null || !stateReady) return;
      var expired = false;
      bool stillCurrent() => !expired && current();
      try {
        final rows =
            await loadVisibleConversationRows<
                  QueryDocumentSnapshot<Map<String, dynamic>>
                >(
                  firstPage: page,
                  idOf: (d) => d.id,
                  isCurrent: stillCurrent,
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
                )
                .timeout(_readTimeout);
        if (current()) {
          // A new preview/order for the same IDs does not invalidate the
          // visibility check. Apply its latest values rather than waiting for
          // a quiet inbox before allowing the first result to appear.
          final latest = {for (final d in first ?? page) d.id: d};
          final conversations =
              rows.map((d) {
                final value = latest[d.id] ?? d;
                return Conversation.fromMap(value.id, value.data());
              }).toList()..sort((a, b) {
                final byDate = b.updatedAt.compareTo(a.updatedAt);
                return byDate != 0 ? byDate : b.id.compareTo(a.id);
              });
          controller.add(conversations);
        }
      } catch (e, stack) {
        if (current()) controller.addError(e, stack);
      } finally {
        // A timed-out native read can still finish later; stop its pagination.
        expired = true;
      }
    });

    void fail(Object error, StackTrace stack) {
      first = null;
      stateReady = false;
      refresh.invalidate();
      controller.addError(error, stack);
    }

    final source = query.limit(30).snapshots().listen((snapshot) {
      final previous = first;
      first = snapshot.docs;
      final sameIds =
          previous != null &&
          previous.length == first!.length &&
          previous
              .map((d) => d.id)
              .toSet()
              .containsAll(first!.map((d) => d.id));
      if (stateReady) refresh.request(invalidateCurrent: !sameIds);
    }, onError: fail);
    final state = _db
        .doc('users/$uid/conversationState/inbox')
        .snapshots()
        .listen((_) {
          stateReady = true;
          refresh.request();
        }, onError: fail);
    final local = _visibilityChanges.stream
        .where((changed) => changed == uid)
        .listen((_) => refresh.request());
    controller.onCancel = () async {
      refresh.close();
      await Future.wait([source.cancel(), state.cancel(), local.cancel()]);
    };
  });
  @override
  Stream<Conversation?> watchConversation(String id) async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield null;
      return;
    }
    yield* watchVisibleConversation<Conversation>(
      isCurrent: () => FirebaseAuth.instance.currentUser?.uid == uid,
      conversation: _db
          .doc('conversations/$id')
          .snapshots()
          .map((s) => s.exists ? Conversation.fromMap(s.id, s.data()!) : null),
      deletion: _db
          .doc('users/$uid/deletedConversations/$id')
          .snapshots(includeMetadataChanges: true)
          .map((s) => (exists: s.exists, fromCache: s.metadata.isFromCache)),
    );
  }

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
