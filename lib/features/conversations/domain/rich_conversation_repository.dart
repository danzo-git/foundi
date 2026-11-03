import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../auth/domain/auth_repository.dart';

class AttachmentDraft {
  AttachmentDraft({
    required this.bytes,
    required this.originalName,
    required this.type,
  }) {
    final ext = originalName.split('.').last.toLowerCase();
    contentType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => '',
    };
    if (!['image', 'pdf'].contains(type) ||
        bytes.isEmpty ||
        bytes.length > (type == 'image' ? 10 : 15) * 1048576 ||
        contentType.isEmpty ||
        (type == 'pdf') != (contentType == 'application/pdf')) {
      throw const AuthFailure(
        'Choisis une image JPEG, PNG ou WebP de 10 Mio maximum, ou un PDF de 15 Mio maximum.',
      );
    }
    digest = sha256.convert(bytes).toString();
  }
  final Uint8List bytes;
  final String originalName, type;
  late final String contentType, digest;
  Map<String, dynamic> toMap() => {
    'type': type,
    'originalName': originalName,
    'contentType': contentType,
    'sizeBytes': bytes.length,
    'sha256': digest,
  };
}

class AttachmentCancellation {
  bool requested = false;
  void Function()? onCancel;
  void cancel() {
    requested = true;
    onCancel?.call();
  }
}

abstract interface class RichConversationRepository {
  Future<String> sendAttachment(
    String conversationId,
    String messageId,
    AttachmentDraft draft, {
    required AttachmentCancellation cancellation,
    required void Function(double) onProgress,
  });
  Future<String> cancelAttachment(String conversationId, String messageId);
  Future<Uint8List> readAttachment(String conversationId, String messageId);
  Future<void> shareContact(
    String conversationId,
    String messageId,
    String phoneNumber,
  );
}
