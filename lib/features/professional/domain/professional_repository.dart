import 'dart:typed_data';

enum ProfessionalStatus {
  none,
  draft,
  pending,
  approved,
  rejected,
  needsChanges,
  suspended,
}

class ProfessionalActivity {
  const ProfessionalActivity({
    this.type = 'independent',
    this.businessName = '',
    this.categoryIds = const [],
    this.specialtyIds = const [],
    this.zoneIds = const [],
    this.description = '',
  });
  final String type, businessName, description;
  final List<String> categoryIds, specialtyIds, zoneIds;
  Map<String, dynamic> toMap() => {
    'type': type,
    'businessName': businessName,
    'categoryIds': categoryIds,
    'specialtyIds': specialtyIds,
    'zoneIds': zoneIds,
    'description': description,
  };
  factory ProfessionalActivity.fromMap(Map<String, dynamic> data) =>
      ProfessionalActivity(
        type: data['type'] as String? ?? 'independent',
        businessName: data['businessName'] as String? ?? '',
        categoryIds: List<String>.from(data['categoryIds'] ?? []),
        specialtyIds: List<String>.from(data['specialtyIds'] ?? []),
        zoneIds: List<String>.from(data['zoneIds'] ?? []),
        description: data['description'] as String? ?? '',
      );
}

class ProfessionalProfile {
  const ProfessionalProfile({
    this.status = ProfessionalStatus.none,
    this.step = 2,
    this.reviewReason = '',
    this.activity = const ProfessionalActivity(),
  });
  final ProfessionalStatus status;
  final int step;
  final String reviewReason;
  final ProfessionalActivity activity;
  bool get approved => status == ProfessionalStatus.approved;
  factory ProfessionalProfile.fromMap(Map<String, dynamic>? data) =>
      data == null
      ? const ProfessionalProfile()
      : ProfessionalProfile(
          status: ProfessionalStatus.values.firstWhere(
            (s) =>
                (s == ProfessionalStatus.needsChanges
                    ? 'needs_changes'
                    : s.name) ==
                data['status'],
            orElse: () => ProfessionalStatus.suspended,
          ),
          reviewReason: data['reviewReason'] as String? ?? '',
          step: data['onboardingStep'] as int? ?? 2,
          activity: ProfessionalActivity.fromMap(data),
        );
}

class ReferenceChoice {
  const ReferenceChoice(this.id, this.label);
  final String id, label;
  factory ReferenceChoice.fromMap(Map<String, dynamic> map) =>
      ReferenceChoice(map['id'] as String, map['label'] as String);
}

class ProfessionalCategory extends ReferenceChoice {
  const ProfessionalCategory(
    super.id,
    super.label,
    this.specialties,
    this.requirements,
  );
  final List<ReferenceChoice> specialties;
  final Map<String, List<String>> requirements;
}

class ProfessionalCatalog {
  const ProfessionalCatalog({
    this.enabled = false,
    this.categories = const [],
    this.zones = const [],
    this.documents = const [],
  });
  final bool enabled;
  final List<ProfessionalCategory> categories;
  final List<ReferenceChoice> zones, documents;
  List<ReferenceChoice>? requiredFor(ProfessionalActivity activity) {
    if (!enabled ||
        activity.categoryIds.isEmpty ||
        activity.zoneIds.isEmpty ||
        activity.zoneIds.any((id) => !zones.any((z) => z.id == id))) {
      return null;
    }
    final selected = categories
        .where((c) => activity.categoryIds.contains(c.id))
        .toList();
    if (selected.length != activity.categoryIds.length ||
        activity.specialtyIds.any(
          (id) => !selected.any((c) => c.specialties.any((s) => s.id == id)),
        ) ||
        (selected.any((c) => c.specialties.isNotEmpty) &&
            activity.specialtyIds.isEmpty)) {
      return null;
    }
    final required = <String>{'identity'};
    for (final id in activity.categoryIds) {
      final category = categories.where((c) => c.id == id).firstOrNull;
      final requirements = category?.requirements[activity.type];
      if (requirements == null) return null;
      required.addAll(requirements);
    }
    if (required.any((id) => !documents.any((d) => d.id == id))) return null;
    return documents.where((d) => required.contains(d.id)).toList();
  }

  factory ProfessionalCatalog.fromMap(Map<String, dynamic>? data) {
    if (data == null || data['enabled'] != true) {
      return const ProfessionalCatalog();
    }
    List<Map<String, dynamic>> active(dynamic values) => (values as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .where((v) => v['active'] != false)
        .toList();
    return ProfessionalCatalog(
      enabled: true,
      categories: active(data['categories'])
          .map(
            (c) => ProfessionalCategory(
              c['id'],
              c['label'],
              active(c['specialties']).map(ReferenceChoice.fromMap).toList(),
              (c['requirements'] as Map? ?? {}).map(
                (key, value) =>
                    MapEntry(key as String, List<String>.from(value)),
              ),
            ),
          )
          .toList(),
      zones: activeGeographicChoices(data['zones']),
      documents: active(
        data['documentTypes'],
      ).map(ReferenceChoice.fromMap).toList(),
    );
  }
}

class ProfessionalDocument {
  const ProfessionalDocument(this.kind, this.name, this.ready);
  final String kind, name;
  final bool ready;
}

abstract interface class ProfessionalRepository {
  Stream<ProfessionalProfile> watchProfile(String uid);
  Stream<List<ProfessionalDocument>> watchDocuments(String uid);
  Future<ProfessionalCatalog> loadCatalog();
  Stream<ProfessionalCatalog> watchCatalog();
  Future<void> start();
  Future<void> saveActivity(
    ProfessionalActivity activity, {
    required bool complete,
  });
  Future<void> uploadDocument(String kind, String name, Uint8List bytes);
  Future<void> submit({required bool certified});
  Future<void> checkAccess();
}

// Legacy flat zones remain valid. All consumers inherit ancestor activation.
List<ReferenceChoice> activeGeographicChoices(dynamic values) {
  final all = (values as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  final result = <ReferenceChoice>[];
  for (final zone in all) {
    final labels = <String>[];
    final visited = <String>{};
    Map<String, dynamic>? current = zone;
    bool valid = true;
    while (current != null) {
      if (current['active'] == false || !visited.add(current['id'] as String)) {
        valid = false;
        break;
      }
      labels.insert(0, current['label'] as String);
      final parent = current['parentId'];
      current = parent == null
          ? null
          : all.where((z) => z['id'] == parent).firstOrNull;
      if (parent != null && current == null) {
        valid = false;
        break;
      }
    }
    if (valid) {
      result.add(ReferenceChoice(zone['id'] as String, labels.join(' › ')));
    }
  }
  return result;
}
