import 'dart:typed_data';
import '../../auth/domain/auth_repository.dart';

Future<void> openPrivatePdf(String uid, Uint8List bytes, String name) async {
  throw const AuthFailure(
    'L’ouverture PDF est indisponible sur cette plateforme.',
  );
}
