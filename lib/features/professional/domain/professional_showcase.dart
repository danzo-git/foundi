import 'dart:convert';
import 'dart:typed_data';

class ShowcasePhoto {
  const ShowcasePhoto(this.bytes, {this.id});

  final Uint8List bytes;
  final String? id;

  factory ShowcasePhoto.fromMap(Map<String, dynamic> data) => ShowcasePhoto(
    base64Decode(data['base64'] as String),
    id: data['id'] as String,
  );

  Map<String, String> toSaveMap() {
    final savedId = id;
    return savedId == null ? {'base64': base64Encode(bytes)} : {'id': savedId};
  }
}

class ProfessionalShowcase {
  const ProfessionalShowcase({
    this.revision = 0,
    this.name = '',
    this.trade = '',
    this.area = '',
    this.bio = '',
    this.portrait,
    this.cover,
    this.gallery = const [],
    this.professionalId,
    this.requestActivity,
  });

  static const maxGallery = 6;
  static const maxInputBytes = 2 * 1024 * 1024;

  final int revision;
  final String name, trade, area, bio;
  final ShowcasePhoto? portrait, cover;
  final List<ShowcasePhoto> gallery;
  // Routing identity returned by public profile reads, never saved by the editor.
  final String? professionalId;
  final ProfessionalRequestActivity? requestActivity;

  factory ProfessionalShowcase.fromMap(Map<String, dynamic> data) {
    ShowcasePhoto? photo(Object? value) => value == null
        ? null
        : ShowcasePhoto.fromMap(Map<String, dynamic>.from(value as Map));
    return ProfessionalShowcase(
      revision: (data['revision'] as num).toInt(),
      name: data['name'] as String,
      trade: data['trade'] as String,
      area: data['area'] as String,
      bio: data['bio'] as String,
      professionalId: data['professionalId'] as String?,
      requestActivity: data['requestActivity'] is Map
          ? ProfessionalRequestActivity.fromMap(
              Map<String, dynamic>.from(data['requestActivity'] as Map),
            )
          : null,
      portrait: photo(data['portrait']),
      cover: photo(data['cover']),
      gallery: (data['gallery'] as List).map((item) => photo(item)!).toList(),
    );
  }

  Map<String, dynamic> toSaveMap() => {
    'revision': revision,
    'name': name,
    'trade': trade,
    'area': area,
    'bio': bio,
    'portrait': portrait?.toSaveMap(),
    'cover': cover?.toSaveMap(),
    'gallery': gallery.map((photo) => photo.toSaveMap()).toList(),
  };
}

class ProfessionalRequestActivity {
  const ProfessionalRequestActivity({
    required this.categoryId,
    required this.categoryLabel,
    required this.specialtyId,
    required this.specialtyLabel,
  });
  final String categoryId, categoryLabel, specialtyId, specialtyLabel;
  factory ProfessionalRequestActivity.fromMap(Map<String, dynamic> data) =>
      ProfessionalRequestActivity(
        categoryId: data['categoryId'] as String,
        categoryLabel: data['categoryLabel'] as String,
        specialtyId: data['specialtyId'] as String,
        specialtyLabel: data['specialtyLabel'] as String,
      );
}

abstract interface class ProfessionalShowcaseRepository {
  Future<ProfessionalShowcase?> readShowcase({String? proposalId});
  Future<ProfessionalShowcase> saveShowcase(ProfessionalShowcase profile);
}
