import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/rich_conversation_repository.dart';
import 'pdf_access_stub.dart'
    if (dart.library.io) 'pdf_access_io.dart'
    if (dart.library.js_interop) 'pdf_access_web.dart'
    as pdf;

abstract interface class ConversationMediaActions {
  bool get supportsCamera;
  Future<AttachmentDraft?> pickImage({bool camera = false});
  Future<AttachmentDraft?> pickPdf();
  Future<void> openPdf(String uid, Uint8List bytes, String name);
  Future<void> callPhone(String number);
}

class PlatformConversationMediaActions implements ConversationMediaActions {
  const PlatformConversationMediaActions();
  @override
  bool get supportsCamera =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  Future<AttachmentDraft?> _pick(String type) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: type == 'image'
          ? ['jpg', 'jpeg', 'png', 'webp']
          : ['pdf'],
    );
    if (file == null) return null;
    final length = file.lengthSync() ?? await file.length();
    if (length == null || length > (type == 'image' ? 10 : 15) * 1048576) {
      throw const AuthFailure(
        'Fichier trop volumineux. Image : 10 Mio maximum ; PDF : 15 Mio maximum.',
      );
    }
    final bytes = await file.readAsBytes();
    return AttachmentDraft(bytes: bytes, originalName: file.name, type: type);
  }

  @override
  Future<AttachmentDraft?> pickImage({bool camera = false}) async {
    if (!camera) return _pick('image');
    if (!supportsCamera) {
      throw const AuthFailure(
        'Appareil photo indisponible sur cette plateforme.',
      );
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > 10 * 1048576) {
      throw const AuthFailure('Image trop volumineuse (10 Mio maximum).');
    }
    return AttachmentDraft(
      bytes: await file.readAsBytes(),
      originalName: file.name,
      type: 'image',
    );
  }

  @override
  Future<AttachmentDraft?> pickPdf() => _pick('pdf');
  @override
  Future<void> openPdf(String uid, Uint8List bytes, String name) =>
      pdf.openPrivatePdf(uid, bytes, name);
  @override
  Future<void> callPhone(String number) async {
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(number) ||
        !await launchUrl(
          Uri(scheme: 'tel', path: number),
          mode: LaunchMode.externalApplication,
        )) {
      throw const AuthFailure(
        'L’action Appeler est indisponible ici. Tu peux copier le numéro.',
      );
    }
  }
}
