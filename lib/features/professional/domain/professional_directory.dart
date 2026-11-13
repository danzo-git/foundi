import 'dart:typed_data';
import '../../auth/domain/auth_repository.dart';
import 'professional_showcase.dart';

class ProfessionalDirectoryFilters {
  const ProfessionalDirectoryFilters({
    this.query = '',
    this.categoryId,
    this.specialtyId,
    this.zoneId,
  });
  final String query;
  final String? categoryId, specialtyId, zoneId;
  Map<String, dynamic> toMap() => {
    'query': query.trim(),
    if (categoryId != null) 'categoryId': categoryId,
    if (specialtyId != null) 'specialtyId': specialtyId,
    if (zoneId != null) 'zoneId': zoneId,
  };
}

class ProfessionalListing {
  const ProfessionalListing({
    required this.professionalId,
    required this.name,
    required this.trade,
    this.categories = const [],
    this.specialties = const [],
    this.zones = const [],
    this.portraitId,
  });
  final String professionalId, name, trade;
  final List<String> categories, specialties, zones;
  final String? portraitId;
  factory ProfessionalListing.fromMap(Map<String, dynamic> m) =>
      ProfessionalListing(
        professionalId: m['professionalId'] as String,
        name: m['name'] as String,
        trade: m['trade'] as String,
        categories: List<String>.from(m['categories'] as List),
        specialties: List<String>.from(m['specialties'] as List),
        zones: List<String>.from(m['zones'] as List),
        portraitId: m['portraitId'] as String?,
      );
}

class ProfessionalDirectoryPage {
  const ProfessionalDirectoryPage(this.items, {this.cursor});
  final List<ProfessionalListing> items;
  final String? cursor;
}

class ProfessionalMediaManifest {
  const ProfessionalMediaManifest({
    this.portraitId,
    this.galleryIds = const [],
  });
  final String? portraitId;
  final List<String> galleryIds;
}

class ProfessionalUnavailable extends AuthFailure {
  const ProfessionalUnavailable()
    : super('Ce professionnel n’est plus disponible.');
}

abstract interface class ProfessionalDirectoryRepository {
  Future<ProfessionalDirectoryPage> searchProfessionals(
    ProfessionalDirectoryFilters filters, {
    String? cursor,
  });
  Future<ProfessionalShowcase> readDirectoryProfessional(String id);
  Future<Set<String>> checkDirectoryProfessionals(List<String> ids);
  Future<ProfessionalMediaManifest> directoryMediaManifest(String id);
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId);
  void clearDirectoryMedia(String id);
}
