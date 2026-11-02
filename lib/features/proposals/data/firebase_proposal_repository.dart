import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/proposal_repository.dart';

class FirebaseProposalRepository implements ProposalRepository {
  FirebaseProposalRepository(this._db, this._functions);
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
      throw AuthFailure(e.message ?? 'Opération non confirmée. Réessaie.');
    }
  }

  @override
  Future<ProposalAccess> proposalAccess(String requestId) async {
    final m = await _call('proposalAccess', {'requestId': requestId});
    return ProposalAccess(m['canSend'] == true, m['proposalId'] as String?);
  }

  @override
  Future<Proposal> sendProposal(String requestId, ProposalDraft draft) async {
    final m = await _call('sendProposal', {
      'requestId': requestId,
      'proposal': draft.toMap(),
    });
    return Proposal.fromMap(m['id'] as String, m);
  }

  Stream<List<Proposal>> _watch(Query<Map<String, dynamic>> q) => q
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map((d) => Proposal.fromMap(d.id, d.data())).toList());
  @override
  Stream<List<Proposal>> watchSentProposals(String uid) => _watch(
    _db.collection('proposals').where('professionalUid', isEqualTo: uid),
  );
  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('proposals')
        .where('clientUid', isEqualTo: uid);
    if (requestId != null) {
      q = q.where('requestId', isEqualTo: requestId);
    }
    return _watch(q);
  }

  @override
  Stream<Proposal?> watchProposal(String id) => _db
      .doc('proposals/$id')
      .snapshots()
      .map((s) => s.exists ? Proposal.fromMap(s.id, s.data()!) : null);
  @override
  Future<bool> proposalApproval(String id) async =>
      (await _call('proposalApproval', {'proposalId': id}))['approved'] == true;
}
