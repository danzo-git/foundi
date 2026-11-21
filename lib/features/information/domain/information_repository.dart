class FoundiInformation {
  const FoundiInformation({
    required this.id,
    required this.version,
    required this.title,
    required this.summary,
    required this.endsAt,
    this.body = '',
    this.publishedAt,
    DateTime? validUntil,
  }) : validUntil = validUntil ?? endsAt;
  final String id, version, title, summary, body;
  final DateTime endsAt;
  // Relative to server time when supplied, so a mis-set phone clock does not extend visibility.
  final DateTime validUntil;
  final DateTime? publishedAt;
  String get dismissalKey => '$id:$version';
  factory FoundiInformation.fromMap(Map<String, dynamic> data) =>
      FoundiInformation(
        id: data['id'] as String,
        version: data['version'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        body: data['body'] as String? ?? '',
        endsAt: DateTime.fromMillisecondsSinceEpoch(
          (data['endsAt'] as num).toInt(),
        ),
        validUntil: data['serverNow'] == null
            ? null
            : DateTime.now().add(
                Duration(
                  milliseconds:
                      ((data['endsAt'] as num) - (data['serverNow'] as num))
                          .toInt(),
                ),
              ),
        publishedAt: data['publishedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (data['publishedAt'] as num).toInt(),
              ),
      );
}

class InformationUnavailable implements Exception {
  const InformationUnavailable();
}

abstract interface class InformationRepository {
  Future<List<FoundiInformation>> listInformation({bool featuredOnly = false});
  Future<FoundiInformation> readInformation(String id);
}
