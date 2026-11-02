import '../../requests/domain/request_repository.dart';

class SelectionResult {
  const SelectionResult(this.conversationId, this.alreadySelected);
  final String conversationId;
  final bool alreadySelected;
}

class Conversation {
  const Conversation({
    required this.id,
    required this.requestId,
    required this.selectedProposalId,
    required this.clientUid,
    required this.professionalUid,
    required this.clientName,
    required this.professionalName,
    required this.requestTitle,
    required this.status,
    required this.updatedAt,
    required this.requestSnapshot,
    this.lastMessagePreview = '',
    this.proposalStatus = 'discussing',
    this.archivedReason,
  });
  final String id,
      requestId,
      selectedProposalId,
      clientUid,
      professionalUid,
      clientName,
      professionalName,
      requestTitle,
      status,
      lastMessagePreview;
  final int updatedAt;
  final String proposalStatus;
  final String? archivedReason;
  final FoundiRequest requestSnapshot;
  String otherName(String uid) =>
      uid == clientUid ? professionalName : clientName;
  bool get active => status == 'active';
  factory Conversation.fromMap(String id, Map<String, dynamic> m) =>
      Conversation(
        id: id,
        requestId: m['requestId'] as String,
        selectedProposalId:
            (m['proposalId'] ?? m['selectedProposalId']) as String,
        clientUid: m['clientUid'] as String,
        professionalUid: m['professionalUid'] as String,
        clientName: m['clientName'] as String,
        professionalName: m['professionalName'] as String,
        requestTitle: m['requestTitle'] as String,
        status: m['status'] as String,
        proposalStatus: m['proposalStatus'] as String? ?? 'discussing',
        archivedReason: m['archivedReason'] as String?,
        updatedAt: (m['updatedAt'] as num).toInt(),
        lastMessagePreview: m['lastMessagePreview'] as String? ?? '',
        requestSnapshot: FoundiRequest.fromMap(
          m['requestId'] as String,
          Map<String, dynamic>.from(m['requestSnapshot']),
        ),
      );
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });
  final String id, senderUid, text;
  final int createdAt;
  factory ConversationMessage.fromMap(String id, Map<String, dynamic> m) =>
      ConversationMessage(
        id: id,
        senderUid: m['senderUid'] as String,
        text: m['text'] as String,
        createdAt: (m['createdAt'] as num).toInt(),
      );
}

class MessageBatch {
  const MessageBatch(this.messages, {this.fromCache = false});
  final List<ConversationMessage> messages;
  final bool fromCache;
}

abstract interface class ConversationRepository {
  Future<SelectionResult> selectProposal(String requestId, String proposalId);
  String newDecisionId(String requestId);
  Future<void> decideProposal(
    String requestId,
    String proposalId,
    String action, {
    required String decisionId,
    String? expectedRetainedProposalId,
    String reason = '',
  });
  Stream<FoundiRequest?> watchOwnSelection(String uid, String requestId);
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  });
  Stream<Conversation?> watchConversation(String id);
  Stream<MessageBatch> watchMessages(String id, {int limit = 30});
  String newMessageId(String conversationId);
  Future<void> sendConversationMessage(
    String conversationId,
    String messageId,
    String text,
  );
}
