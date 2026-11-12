import 'dart:typed_data';

const maxRequestPhotos = 3;
const maxRequestPhotoBytes = 5 * 1024 * 1024;

typedef RequestPhotoReader =
    Future<Uint8List> Function(String requestId, String photoId);

abstract interface class PublicRequestPhotoRepository {
  Future<Uint8List> readPublicRequestPhoto(String requestId, String photoId);
}

class LocalRequestPhoto {
  const LocalRequestPhoto({
    required this.id,
    required this.bytes,
    required this.contentType,
  });

  final String id, contentType;
  final Uint8List bytes;
}

abstract interface class RequestPhotoRepository {
  /// Returns true if the request was already published after an uncertain reply.
  Future<bool> uploadRequestPhoto(String requestId, LocalRequestPhoto photo);
  Future<void> discardRequestPhotos(String requestId, List<String> photoIds);
  Future<Uint8List> readRequestPhoto(String requestId, String photoId);
}
