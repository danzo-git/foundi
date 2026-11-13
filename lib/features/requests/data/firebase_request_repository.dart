import '../../conversations/domain/conversation_repository.dart';
import '../../conversations/data/firebase_conversation_repository.dart';
import '../../conversations/domain/rich_conversation_repository.dart';
import '../../conversations/data/firebase_rich_conversation_repository.dart';
import 'dart:typed_data';
import '../../proposals/domain/proposal_repository.dart';
import '../../proposals/data/firebase_proposal_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../professional/domain/professional_showcase.dart';
import '../../professional/domain/professional_directory.dart';
import '../../professional/data/firebase_professional_directory_repository.dart';
import '../domain/request_repository.dart';
import '../domain/request_photo_repository.dart';
import '../domain/request_interaction_repository.dart';
import 'firebase_request_interaction_repository.dart';
import 'firebase_request_photo_repository.dart';

class FirebaseRequestRepository
    implements
        RequestRepository,
        ProfessionalDirectoryRepository,
        DirectRequestRepository,
        RequestRespondentsRepository,
        RequestRespondentProfileRepository,
        RequestInteractionSource,
        RequestPhotoRepository,
        PublicRequestPhotoRepository,
        RequestManagementRepository,
        OpportunityRepository,
        ExplorerRepository,
        ProposalRepository,
        ConversationRepository,
        RichConversationRepository {
  FirebaseRequestRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    this.attachmentEndpointBase,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  late final _directory = FirebaseProfessionalDirectoryRepository(_functions);
  @override
  Future<ProfessionalDirectoryPage> searchProfessionals(
    ProfessionalDirectoryFilters filters, {
    String? cursor,
  }) => _directory.searchProfessionals(filters, cursor: cursor);
  @override
  Future<ProfessionalShowcase> readDirectoryProfessional(String id) =>
      _directory.readDirectoryProfessional(id);
  @override
  Future<Set<String>> checkDirectoryProfessionals(List<String> ids) =>
      _directory.checkDirectoryProfessionals(ids);
  @override
  Future<ProfessionalMediaManifest> directoryMediaManifest(String id) =>
      _directory.directoryMediaManifest(id);
  @override
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId) =>
      _directory.readDirectoryThumbnail(id, photoId);
  @override
  void clearDirectoryMedia(String id) => _directory.clearDirectoryMedia(id);
  @override
  late final interactions = FirebaseRequestInteractionRepository(
    _db,
    _functions,
  );
  final String? attachmentEndpointBase;
  late final _photos = FirebaseRequestPhotoRepository(
    _functions,
    endpointBase: attachmentEndpointBase,
  );
  @override
  Future<bool> uploadRequestPhoto(String requestId, LocalRequestPhoto photo) =>
      _photos.uploadRequestPhoto(requestId, photo);
  @override
  Future<void> discardRequestPhotos(String requestId, List<String> photoIds) =>
      _photos.discardRequestPhotos(requestId, photoIds);
  @override
  Future<Uint8List> readRequestPhoto(String requestId, String photoId) =>
      _photos.readRequestPhoto(requestId, photoId);
  @override
  Future<Uint8List> readPublicRequestPhoto(String requestId, String photoId) =>
      _photos.readPublicRequestPhoto(requestId, photoId);
  late final RichConversationRepository _rich =
      FirebaseRichConversationRepository(
        _functions,
        endpointBase: attachmentEndpointBase,
      );
  @override
  Future<String> sendAttachment(
    String conversationId,
    String messageId,
    AttachmentDraft draft, {
    required AttachmentCancellation cancellation,
    required void Function(double) onProgress,
  }) => _rich.sendAttachment(
    conversationId,
    messageId,
    draft,
    cancellation: cancellation,
    onProgress: onProgress,
  );
  @override
  Future<String> cancelAttachment(String conversationId, String messageId) =>
      _rich.cancelAttachment(conversationId, messageId);
  @override
  Future<Uint8List> readAttachment(String conversationId, String messageId) =>
      _rich.readAttachment(conversationId, messageId);
  @override
  Future<void> shareContact(
    String conversationId,
    String messageId,
    String phoneNumber,
  ) => _rich.shareContact(conversationId, messageId, phoneNumber);
  late final ProposalRepository _proposals = FirebaseProposalRepository(
    _db,
    _functions,
  );
  late final ConversationRepository _conversations =
      FirebaseConversationRepository(_db, _functions);
  @override
  Future<SelectionResult> selectProposal(String requestId, String proposalId) =>
      _conversations.selectProposal(requestId, proposalId);
  @override
  String newDecisionId(String requestId) =>
      _conversations.newDecisionId(requestId);
  @override
  Future<void> decideProposal(
    String requestId,
    String proposalId,
    String action, {
    required String decisionId,
    String? expectedRetainedProposalId,
    String reason = '',
  }) => _conversations.decideProposal(
    requestId,
    proposalId,
    action,
    decisionId: decisionId,
    expectedRetainedProposalId: expectedRetainedProposalId,
    reason: reason,
  );
  @override
  Stream<FoundiRequest?> watchOwnSelection(String uid, String requestId) =>
      _conversations.watchOwnSelection(uid, requestId);
  @override
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  }) => _conversations.watchConversations(uid, asProfessional: asProfessional);
  @override
  Stream<Conversation?> watchConversation(String id) =>
      _conversations.watchConversation(id);
  @override
  Stream<MessageBatch> watchMessages(String id, {int limit = 30}) =>
      _conversations.watchMessages(id, limit: limit);
  @override
  String newMessageId(String id) => _conversations.newMessageId(id);
  @override
  Future<void> sendConversationMessage(
    String id,
    String messageId,
    String text,
  ) => _conversations.sendConversationMessage(id, messageId, text);
  @override
  Future<ProposalAccess> proposalAccess(String id) =>
      _proposals.proposalAccess(id);
  @override
  Future<Proposal> sendProposal(String id, ProposalDraft draft) =>
      _proposals.sendProposal(id, draft);
  @override
  Stream<List<Proposal>> watchSentProposals(String uid) =>
      _proposals.watchSentProposals(uid);
  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) => _proposals.watchReceivedProposals(uid, requestId: requestId);
  @override
  Stream<Proposal?> watchProposal(String id) => _proposals.watchProposal(id);
  @override
  Future<bool> proposalApproval(String id) => _proposals.proposalApproval(id);
  @override
  Stream<List<FoundiRequest>> watchExplore({
    ExplorerFilters filters = const ExplorerFilters(),
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('requests')
        .where('status', isEqualTo: 'published');
    if (filters.categoryId != null) {
      query = query.where('categoryId', isEqualTo: filters.categoryId);
    }
    if (filters.specialtyId != null) {
      query = query.where('specialtyId', isEqualTo: filters.specialtyId);
    }
    if (filters.zoneId != null) {
      query = query.where('zoneId', isEqualTo: filters.zoneId);
    }
    query = query
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    return _watch(query.limit(30));
  }

  @override
  Future<OpportunityPage> opportunities({
    List<String>? categoryIds,
    List<String>? specialtyIds,
    List<String>? zoneIds,
    Map<String, dynamic>? cursor,
  }) async {
    try {
      final response = await _functions
          .httpsCallable('listOpportunities')
          .call<Map<String, dynamic>>({
            'categoryIds': ?categoryIds,
            'specialtyIds': ?specialtyIds,
            'zoneIds': ?zoneIds,
            'cursor': ?cursor,
          });
      final data = response.data;
      return OpportunityPage(
        (data['items'] as List).map((v) {
          final m = Map<String, dynamic>.from(v);
          return FoundiRequest.fromMap(m['id'] as String, m);
        }).toList(),
        data['cursor'] == null
            ? null
            : Map<String, dynamic>.from(data['cursor']),
      );
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(e.message ?? 'Opportunités indisponibles. Réessaie.');
    }
  }

  @override
  Future<FoundiRequest> manage(
    String id,
    String action, {
    RequestDraft? draft,
    int? expectedRevision,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('manageRequest')
          .call<Map<String, dynamic>>({
            'requestId': id,
            'action': action,
            'expectedRevision': ?expectedRevision,
            if (draft != null) 'request': draft.toMap(),
          });
      return FoundiRequest.fromMap(id, result.data);
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(e.message ?? 'Modification non confirmée. Réessaie.');
    }
  }

  @override
  String newId() => _db.collection('requests').doc().id;
  @override
  Future<FoundiRequest> publishDirect(
    String id,
    String professionalId,
    RequestDraft draft,
  ) async {
    try {
      final result = await _functions
          .httpsCallable('publishDirectRequest')
          .call<Map<String, dynamic>>({
            'requestId': id,
            'professionalId': professionalId,
            'request': draft.toMap(),
          });
      return FoundiRequest.fromMap(id, result.data);
    } on FirebaseFunctionsException catch (error) {
      throw AuthFailure(
        error.code == 'not-found'
            ? 'Les demandes directes ne sont pas encore disponibles.'
            : error.code == 'resource-exhausted'
            ? 'Tu as atteint la limite de publication. Réessaie plus tard.'
            : error.message ??
                  'Envoi non confirmé. Réessaie : la demande ne sera envoyée qu’une fois.',
      );
    }
  }

  @override
  Stream<List<FoundiRequest>> watchDirectRequests(String professionalId) =>
      _watch(
        _db
            .collection('directRequests')
            .where('directProfessionalId', isEqualTo: professionalId)
            .where('status', whereIn: ['published', 'closed', 'in_discussion'])
            .orderBy('createdAt', descending: true)
            .limit(50),
        resolveDirectAuthors: true,
      );
  @override
  Stream<FoundiRequest?> watchDirectRequest(String id) => _db
      .doc('directRequests/$id')
      .snapshots()
      .asyncMap(
        (s) async => s.exists
            ? (await _parseRequests([
                (id: s.id, data: s.data()!),
              ], resolveDirectAuthors: true)).single
            : null,
      );
  @override
  Future<FoundiRequest> publish(String id, RequestDraft draft) async {
    try {
      final result = await _functions
          .httpsCallable('publishRequest')
          .call<Map<String, dynamic>>({
            'requestId': id,
            'request': draft.toMap(),
          });
      return FoundiRequest.fromMap(result.data['id'] as String, result.data);
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(switch (e.code) {
        'resource-exhausted' =>
          'Tu as atteint la limite de publication. Réessaie plus tard.',
        'failed-precondition'
            when e.message ==
                'Vérifie ton adresse e-mail avant de publier une demande.' =>
          '${e.message} Termine la vérification dans Foundi avec le code reçu par e-mail, puis réessaie.',
        'invalid-argument' ||
        'failed-precondition' ||
        'already-exists' => e.message ?? 'Vérifie ta demande.',
        'unauthenticated' => 'Connecte-toi pour publier ta demande.',
        'permission-denied' => 'Ce compte ne peut pas publier pour le moment.',
        _ =>
          'Publication non confirmée. Réessaie : une même demande ne sera publiée qu’une fois.',
      });
    }
  }

  Future<List<FoundiRequest>> _parseRequests(
    List<({String id, Map<String, dynamic> data})> records, {
    bool resolveDirectAuthors = false,
  }) async {
    final legacy = resolveDirectAuthors
        ? records
              .where(
                (r) =>
                    r.data['directProfessionalId'] != null &&
                    r.data['status'] != 'deleted' &&
                    (r.data['requesterName'] as String? ?? '').trim().isEmpty,
              )
              .toList()
        : [];
    var authors = <String, dynamic>{};
    if (legacy.isNotEmpty) {
      try {
        final result = await _functions
            .httpsCallable('readDirectRequestAuthors')
            .call<Map<String, dynamic>>({
              'requestIds': legacy.map((r) => r.id).toList(),
            });
        authors = Map<String, dynamic>.from(result.data['authors'] as Map);
      } on FirebaseFunctionsException catch (_) {
        throw const AuthFailure(
          'Impossible de charger le nom des demandeurs. Réessaie.',
        );
      }
    }
    return records
        .map(
          (r) => FoundiRequest.fromMap(r.id, {
            ...r.data,
            if (authors[r.id] case final String name) 'requesterName': name,
          }),
        )
        .where((r) => r.status != 'deleted')
        .toList();
  }

  Stream<List<FoundiRequest>> _watch(
    Query<Map<String, dynamic>> query, {
    bool resolveDirectAuthors = false,
  }) => query.snapshots().asyncMap(
    (s) => _parseRequests([
      for (final d in s.docs) (id: d.id, data: d.data()),
    ], resolveDirectAuthors: resolveDirectAuthors),
  );
  @override
  Stream<List<FoundiRequest>> watchPublic() => _watch(
    _db
        .collection('requests')
        .where('status', isEqualTo: 'published')
        .orderBy('createdAt', descending: true)
        .limit(30),
  );
  @override
  Stream<List<FoundiRequest>> watchMine(String uid) => _watch(
    _db
        .collection('userRequests/$uid/items')
        .orderBy('createdAt', descending: true)
        .limit(50),
    resolveDirectAuthors: true,
  );
  @override
  Stream<FoundiRequest?> watchPublicDetail(String id) => _db
      .doc('requests/$id')
      .snapshots()
      .map((s) => s.exists ? FoundiRequest.fromMap(s.id, s.data()!) : null);

  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('listRequestRespondents')
          .call<Map<String, dynamic>>({
            'requestId': requestId,
            'offset': offset,
          });
      final data = result.data;
      return RequestRespondentsPage(
        total: (data['total'] as num).toInt(),
        canViewProposals: data['canViewProposals'] == true,
        nextOffset: (data['nextOffset'] as num?)?.toInt(),
        items: [
          for (final item in data['items'] as List)
            RequestRespondent(
              item['name'] as String,
              List<String>.from(item['activity'] as List),
              professionalId: item['professionalId'] as String?,
            ),
        ],
      );
    } on FirebaseFunctionsException catch (error) {
      throw AuthFailure(switch (error.code) {
        'not-found' => 'Cette demande n’est plus publique.',
        _ => 'Impossible de charger les réponses. Réessaie.',
      });
    }
  }

  @override
  Future<ProfessionalShowcase> readRequestRespondentProfile(
    String requestId,
    String professionalId,
  ) async {
    try {
      final result = await _functions
          .httpsCallable('readRequestRespondentProfile')
          .call<Map<String, dynamic>>({
            'requestId': requestId,
            'professionalId': professionalId,
          });
      return ProfessionalShowcase.fromMap(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw AuthFailure(switch (error.code) {
        'not-found' => 'Ce profil professionnel n’est plus disponible.',
        _ => 'Impossible de charger le profil. Réessaie.',
      });
    }
  }
}
