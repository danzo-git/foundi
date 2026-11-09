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
  });

  static const maxGallery = 6;
  static const maxInputBytes = 2 * 1024 * 1024;

  final int revision;
  final String name, trade, area, bio;
  final ShowcasePhoto? portrait, cover;
  final List<ShowcasePhoto> gallery;

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

abstract interface class ProfessionalShowcaseRepository {
  Future<ProfessionalShowcase?> readShowcase({String? proposalId});
  Future<ProfessionalShowcase> saveShowcase(ProfessionalShowcase profile);
}
