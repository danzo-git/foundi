import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../auth/domain/auth_repository.dart';

final _files = <String, File>{};
StreamSubscription<User?>? _identity;
String? _uid;
int _generation = 0;
Future<void> _clear() async {
  _generation++;
  final files = List<File>.of(_files.values);
  _files.clear();
  for (final file in files) {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* A viewer may temporarily lock its file. A timed retry follows. */
    }
  }
}

Future<void> openPrivatePdf(String uid, Uint8List bytes, String name) async {
  _identity ??= FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user?.uid != _uid) {
      _uid = user?.uid;
      unawaited(_clear());
    }
  });
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw const AuthFailure('Reconnecte-toi pour ouvrir ce fichier.');
  }
  if (_uid != uid) {
    _uid = uid;
    await _clear();
  }
  final session = _generation, dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}foundi-v82-${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  _files[file.path] = file;
  await file.writeAsBytes(bytes, flush: true);
  Future<void> remove() async {
    try {
      if (await file.exists()) await file.delete();
      _files.remove(file.path);
    } on FileSystemException {
      Timer(const Duration(minutes: 1), () => unawaited(remove()));
    }
  }

  Timer(const Duration(minutes: 5), () => unawaited(remove()));
  if (session != _generation || FirebaseAuth.instance.currentUser?.uid != uid) {
    await remove();
    throw const AuthFailure('Session modifiée. Rouvre le document.');
  }
  final result = await OpenFilex.open(file.path, type: 'application/pdf');
  if (result.type != ResultType.done) {
    await remove();
    throw const AuthFailure(
      'Aucune application PDF disponible ou ouverture refusée.',
    );
  }
}
