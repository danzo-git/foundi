class RequestDraft {
  const RequestDraft({
    required this.categoryId,
    required this.specialtyId,
    required this.zoneId,
    required this.title,
    required this.description,
    this.budget,
  });
  final String categoryId, specialtyId, zoneId, title, description;
  final int? budget;
  Map<String, dynamic> toMap() => {
    'categoryId': categoryId,
    'specialtyId': specialtyId,
    'zoneId': zoneId,
    'title': title.trim(),
    'description': description.trim(),
    'budget': budget,
  };
  static int? parseBudget(String text) {
    final value = text.trim().replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
    if (value.isEmpty) return null;
    if (!RegExp(r'^\d{1,12}$').hasMatch(value)) {
      throw const FormatException('Budget invalide');
    }
    return int.parse(value);
  }
}

class FoundiRequest {
  const FoundiRequest({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryLabel,
    required this.specialtyLabel,
    required this.zoneLabel,
    required this.status,
    required this.createdAt,
    this.budget,
    this.revision,
    this.categoryId = '',
    this.specialtyId = '',
    this.zoneId = '',
  });
  final String categoryId, specialtyId, zoneId;
  final String id,
      title,
      description,
      categoryLabel,
      specialtyLabel,
      zoneLabel,
      status;
  final int? revision;
  final DateTime? createdAt;
  final int? budget;
  String get category => [
    categoryLabel,
    if (specialtyLabel.isNotEmpty) specialtyLabel,
  ].join(' · ');
  String get budgetLabel =>
      budget == null ? 'Budget à discuter' : '${formatFcfa(budget!)} FCFA';
  String get statusLabel => switch (status) {
    'published' => 'Publiée',
    'closed' => 'Clôturée',
    'deleted' => 'Supprimée',
    _ => status,
  };
  factory FoundiRequest.fromMap(String id, Map<String, dynamic> data) =>
      FoundiRequest(
        id: id,
        revision: ((data['updatedAt'] ?? data['createdAt']) as num?)?.toInt(),
        categoryId: data['categoryId'] as String? ?? '',
        specialtyId: data['specialtyId'] as String? ?? '',
        zoneId: data['zoneId'] as String? ?? '',
        title: data['title'] as String,
        description: data['description'] as String,
        categoryLabel: data['categoryLabel'] as String,
        specialtyLabel: data['specialtyLabel'] as String? ?? '',
        zoneLabel: data['zoneLabel'] as String,
        status: data['status'] as String,
        createdAt: data['createdAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (data['createdAt'] as num).toInt(),
              )
            : null,
        budget: (data['budget'] as num?)?.toInt(),
      );
}

String formatFcfa(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]} ',
);

abstract interface class RequestRepository {
  String newId();
  Future<FoundiRequest> publish(String id, RequestDraft draft);
  Stream<List<FoundiRequest>> watchPublic();
  Stream<List<FoundiRequest>> watchMine(String uid);
  Stream<FoundiRequest?> watchPublicDetail(String id);
}

abstract interface class RequestManagementRepository {
  Future<FoundiRequest> manage(
    String id,
    String action, {
    RequestDraft? draft,
    int? expectedRevision,
  });
}

class OpportunityPage {
  const OpportunityPage(this.items, this.cursor);
  final List<FoundiRequest> items;
  final Map<String, dynamic>? cursor;
}

abstract interface class OpportunityRepository {
  Future<OpportunityPage> opportunities({
    List<String>? categoryIds,
    List<String>? specialtyIds,
    List<String>? zoneIds,
    Map<String, dynamic>? cursor,
  });
}

class ExplorerFilters {
  const ExplorerFilters({this.categoryId, this.specialtyId, this.zoneId});
  final String? categoryId, specialtyId, zoneId;
  bool get isEmpty =>
      categoryId == null && specialtyId == null && zoneId == null;
  bool matches(FoundiRequest r) =>
      r.status == 'published' &&
      (categoryId == null || r.categoryId == categoryId) &&
      (specialtyId == null || r.specialtyId == specialtyId) &&
      (zoneId == null || r.zoneId == zoneId);
}

abstract interface class ExplorerRepository {
  Stream<List<FoundiRequest>> watchExplore({
    ExplorerFilters filters = const ExplorerFilters(),
  });
}
