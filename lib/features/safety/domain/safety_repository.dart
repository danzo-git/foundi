class SafetyTarget {
  const SafetyTarget(this.type, this.id, {this.conversationId});
  final String type, id;
  final String? conversationId;
  Map<String, dynamic> toMap() => {
    'targetType': type,
    'targetId': id,
    if (conversationId != null) 'conversationId': conversationId,
  };
  String get label => switch (type) {
    'request' => 'la demande',
    'professional' => 'le professionnel',
    'message' => 'le message',
    _ => 'la conversation',
  };
  String get key => '$type:$id:${conversationId ?? ''}';
}

const safetyReasons = <String, String>{
  'fraud': 'Arnaque / fraude',
  'harassment': 'Harcèlement / menaces',
  'inappropriate': 'Contenu inapproprié',
  'spam': 'Spam / publicité abusive',
  'impersonation': "Usurpation d’identité",
  'other': 'Autre',
};

class SafetyContext {
  const SafetyContext({
    this.own = false,
    this.blocked = false,
    this.contactAllowed = true,
  });
  final bool own, blocked, contactAllowed;
}

class BlockedUser {
  const BlockedUser(this.uid, this.label);
  final String uid, label;
}

class BlockedPage {
  const BlockedPage(this.items, {this.cursor});
  final List<BlockedUser> items;
  final String? cursor;
}

abstract interface class SafetyRepository {
  Future<List<SafetyNotice>> notices();
  Future<void> acknowledgeNotice(String id);
  Future<void> report(SafetyTarget target, String reason, String comment);
  Future<SafetyContext> context(SafetyTarget target);
  Future<void> block(SafetyTarget target);
  Future<void> unblockTarget(SafetyTarget target);
  Future<void> unblock(String uid);
  Future<BlockedPage> blocked({String? cursor});
}

class SafetyNotice {
  const SafetyNotice({
    required this.id,
    required this.text,
    this.acknowledgedAt,
  });
  final String id, text;
  final DateTime? acknowledgedAt;
  bool get acknowledged => acknowledgedAt != null;
}
