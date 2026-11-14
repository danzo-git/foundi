import 'dart:convert';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../auth/domain/auth_repository.dart';
import '../auth/data/google_session.dart';
import 'privacy_repository.dart';

class FirebasePrivacyRepository extends PrivacyRepository {
  FirebasePrivacyRepository({
    required this.signOut,
    required this.endpointBase,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  static const receiptKey = 'foundi.accountDeletion.receipt.v1';
  static const cacheCleanupKey = 'foundi.accountDeletion.clearCache.v1';
  final Future<void> Function() signOut;
  final String endpointBase;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  Map<String, dynamic>? _receipt;
  @override
  bool get pending => _receipt != null;
  @override
  String? get receiptExport => _receipt == null ? null : jsonEncode(_receipt);
  @override
  bool get hasPassword =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ==
      true;
  @override
  bool get hasGoogle =>
      _auth.currentUser?.providerData.any(
        (p) => p.providerId == 'google.com',
      ) ==
      true;
  Future<void> initialize() async {
    final text = (await SharedPreferences.getInstance()).getString(receiptKey);
    if (text == null) return;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (['requestId', 'receiptToken'].every(
        (k) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value[k] as String? ?? ''),
      )) {
        _receipt = value;
      }
    } catch (_) {
      /* No untrusted receipt is sent. */
    }
  }

  String _opaque() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<void> request({String? password, bool google = false}) async {
    final hadReceipt = _receipt != null;
    if (_receipt != null) {
      try {
        await status();
        try {
          await signOut().timeout(const Duration(seconds: 10));
        } catch (_) {
          /* Tracking already proves acceptance. */
        }
        await _auth.signOut();
        notifyListeners();
        return;
      } on AuthFailure {
        /* A saved, unconfirmed request may be resubmitted with the same capability. */
      }
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Reconnecte-toi pour vérifier ton identité.');
    }
    try {
      if (google && hasGoogle) {
        if (kIsWeb) {
          await user.reauthenticateWithPopup(
            GoogleAuthProvider()
              ..setCustomParameters({'prompt': 'select_account'}),
          );
        } else {
          await initializeGoogleSession();
          final account = await GoogleSignIn.instance.authenticate();
          final token = account.authentication.idToken;
          if (token == null) {
            throw const AuthFailure('La vérification Google a été annulée.');
          }
          await user.reauthenticateWithCredential(
            GoogleAuthProvider.credential(idToken: token),
          );
        }
      } else if (hasPassword && password != null && password.isNotEmpty) {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
      } else {
        throw const AuthFailure(
          'Vérifie ton identité avec ton mode de connexion habituel.',
        );
      }
      if (_auth.currentUser?.uid != user.uid) {
        throw const AuthFailure('Le compte connecté a changé. Recommence.');
      }
      await user.getIdToken(true);
      final candidate =
          _receipt ?? {'requestId': _opaque(), 'receiptToken': _opaque()};
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool(cacheCleanupKey, true) ||
          !await preferences.setString(receiptKey, jsonEncode(candidate))) {
        throw const AuthFailure(
          'Impossible d’enregistrer le suivi sur cet appareil. La demande n’a pas été envoyée.',
        );
      }
      _receipt = candidate;
      try {
        await _functions.httpsCallable('requestAccountDeletion').call({
          ..._receipt!,
          'confirm': true,
        });
      } on FirebaseFunctionsException catch (e) {
        if ([
          'invalid-argument',
          'failed-precondition',
          'unauthenticated',
          'not-found',
        ].contains(e.code)) {
          if (!hadReceipt) {
            _receipt = null;
            await (await SharedPreferences.getInstance()).remove(receiptKey);
          }
          throw AuthFailure(
            e.code == 'not-found'
                ? 'La suppression automatique n’est pas encore activée. Contacte kouamedenzel09@gmail.com.'
                : e.message ?? 'La demande n’a pas été acceptée.',
          );
        }
        notifyListeners();
        throw const AuthFailure(
          'L’envoi doit être vérifié. Le suivi est conservé sur cet appareil.',
        );
      }
      try {
        await signOut().timeout(const Duration(seconds: 10));
      } catch (_) {
        /* Always invalidate the local Firebase session. */
      }
      await _auth.signOut();
      notifyListeners();
    } on FirebaseAuthException {
      throw const AuthFailure(
        'Identité non confirmée. Vérifie tes identifiants ou réessaie.',
      );
    } on GoogleSignInException {
      throw const AuthFailure('Vérification Google annulée ou indisponible.');
    }
  }

  Future<Map<String, dynamic>> _post(String action) async {
    if (_receipt == null) {
      throw const AuthFailure('Aucun suivi enregistré sur cet appareil.');
    }
    try {
      final response = await _http.post<Map<String, dynamic>>(
        '$endpointBase/$action',
        data: _receipt,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return response.data!;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const AuthFailure(
          'L’envoi n’est pas confirmé. Réessaie depuis le compte connecté ou contacte l’assistance.',
        );
      }
      throw const AuthFailure(
        'Suivi momentanément indisponible. Réessaie sans effacer les données de cet appareil.',
      );
    }
  }

  @override
  Future<DeletionStatus> status() async =>
      DeletionStatus.fromMap(await _post('readAccountDeletionStatus'));
  @override
  Future<void> retry() async {
    await _post('retryAccountDeletion');
  }

  @override
  Future<void> closeCompletedReceipt() async {
    if ((await status()).state != 'completed') {
      throw const AuthFailure('La suppression n’est pas terminée.');
    }
    await forgetLocalReceipt();
  }

  @override
  Future<void> forgetLocalReceipt() async {
    try {
      await signOut().timeout(const Duration(seconds: 10));
    } catch (_) {
      /* Always clear the Firebase session. */
    }
    await _auth.signOut();
    if (!await (await SharedPreferences.getInstance()).remove(receiptKey)) {
      throw const AuthFailure('Impossible de fermer le suivi local. Réessaie.');
    }
    _receipt = null;
    notifyListeners();
  }
}
