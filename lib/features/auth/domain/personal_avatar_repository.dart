import 'dart:convert';
import 'dart:typed_data';

class PersonalAvatarState {
  const PersonalAvatarState({
    this.hasPhoto = false,
    this.published = false,
    this.publicId,
    this.version,
    this.preview,
  });
  final bool hasPhoto, published;
  final String? publicId, version;
  final Uint8List? preview;
  factory PersonalAvatarState.fromMap(Map<String, dynamic> data) =>
      PersonalAvatarState(
        hasPhoto: data['hasPhoto'] == true,
        published: data['published'] == true,
        publicId: data['publicId'] as String?,
        version: data['version'] as String?,
        preview: data['preview'] is String
            ? base64Decode(data['preview'] as String)
            : null,
      );
}

abstract interface class PersonalAvatarRepository {
  Future<PersonalAvatarState> personalAvatarState();
  Future<PersonalAvatarState> savePersonalAvatar({
    Uint8List? bytes,
    String? contentType,
    required bool publish,
  });
  Future<void> removePersonalAvatar();
}
