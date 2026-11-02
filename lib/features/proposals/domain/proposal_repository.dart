class ProposalDraft {
  const ProposalDraft({
    required this.description,
    this.amount,
    this.delay = '',
  });
  final String description, delay;
  final int? amount;
  Map<String, dynamic> toMap() => {
    'description': description.trim(),
    'amount': amount,
    'delay': delay.trim(),
  };
}

class Proposal {
  const Proposal({
    required this.id,
    required this.requestId,
    required this.requestTitle,
    required this.professionalUid,
    required this.clientUid,
    required this.professionalName,
    required this.description,
    required this.status,
    required this.createdAt,
    this.amount,
    this.delay = '',
  });
  final String id,
      requestId,
      requestTitle,
      professionalUid,
      clientUid,
      professionalName,
      description,
      status,
      delay;
  final int createdAt;
  final int? amount;
  String get statusLabel =>
      status == 'sent' ? 'Envoyée' : 'Statut indisponible';
  factory Proposal.fromMap(String id, Map<String, dynamic> m) => Proposal(
    id: id,
    requestId: m['requestId'] as String,
    requestTitle: m['requestTitle'] as String,
    professionalUid: m['professionalUid'] as String,
    clientUid: m['clientUid'] as String,
    professionalName: m['professionalName'] as String,
    description: m['description'] as String,
    status: m['status'] as String,
    createdAt: (m['createdAt'] as num).toInt(),
    amount: (m['amount'] as num?)?.toInt(),
    delay: m['delay'] as String? ?? '',
  );
}

class ProposalAccess {
  const ProposalAccess(this.canSend, this.proposalId);
  final bool canSend;
  final String? proposalId;
}

abstract interface class ProposalRepository {
  Future<ProposalAccess> proposalAccess(String requestId);
  Future<Proposal> sendProposal(String requestId, ProposalDraft draft);
  Stream<List<Proposal>> watchSentProposals(String uid);
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  });
  Stream<Proposal?> watchProposal(String id);
  Future<bool> proposalApproval(String id);
}
