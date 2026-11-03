import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web/web.dart' as web;
import '../../auth/domain/auth_repository.dart';

final _urls = <String>{};
StreamSubscription<User?>? _identity;
String? _uid;
void _clear() {
  for (final url in _urls) {
    web.URL.revokeObjectURL(url);
  }
  _urls.clear();
}

Future<void> openPrivatePdf(String uid, Uint8List bytes, String name) async {
  _identity ??= FirebaseAuth.instance.authStateChanges().listen((u) {
    if (u?.uid != _uid) {
      _uid = u?.uid;
      _clear();
    }
  });
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw const AuthFailure('Reconnecte-toi pour ouvrir ce fichier.');
  }
  _uid = uid;
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  _urls.add(url);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(minutes: 1), () {
    if (_urls.remove(url)) web.URL.revokeObjectURL(url);
  });
}
