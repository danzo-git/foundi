import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/request_repository.dart';

class FirebaseRequestRepository
    implements
        RequestRepository,
        RequestManagementRepository,
        OpportunityRepository,
        ExplorerRepository {
  FirebaseRequestRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
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

  Stream<List<FoundiRequest>> _watch(Query<Map<String, dynamic>> query) =>
      query.snapshots().map(
        (s) => s.docs
            .map((d) => FoundiRequest.fromMap(d.id, d.data()))
            .where((r) => r.status != 'deleted')
            .toList(),
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
  );
  @override
  Stream<FoundiRequest?> watchPublicDetail(String id) => _db
      .doc('requests/$id')
      .snapshots()
      .map((s) => s.exists ? FoundiRequest.fromMap(s.id, s.data()!) : null);
}
