import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _firestore = firestore ?? FirebaseFirestore.instance {
    _auth.userChanges().listen((user) {
      if (_firstAuthEvent) {
        _firstAuthEvent = false;
        if (!_mutating &&
            user?.providerData.any((p) => p.providerId == 'google.com') ==
                true) {
          _restoredGoogleUid = user!.uid;
        }
      }
      if (!_mutating) unawaited(_observe(user));
    }, onError: _publishError);
  }

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final _changes = StreamController<FoundiUser?>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  Future<void>? _googleInitialization;
  FoundiUser? _currentUser;
  Object? _lastError;
  bool _ready = false;
  bool _mutating = false;
  int _generation = 0;
  bool _firstAuthEvent = true;
  String? _restoredGoogleUid;

  late final Stream<FoundiUser?> _stream = Stream.multi((controller) {
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
    if (_lastError != null) {
      controller.addError(_lastError!);
    } else if (_ready) {
      controller.add(_currentUser);
    }
  }, isBroadcast: true);

  @override
  FoundiUser? get currentUser => _currentUser;
  @override
  Stream<FoundiUser?> authStateChanges() => _stream;

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _firestore.collection('users').doc(uid);

  void _publish(FoundiUser? user) {
    _currentUser = user;
    _ready = true;
    _lastError = null;
    _changes.add(user);
  }

  void _publishError(Object error, [StackTrace? stack]) {
    _lastError = const AuthFailure(
      'Impossible de charger ton compte. Vérifie ta connexion puis réessaie.',
    );
    _changes.addError(_lastError!, stack);
  }

  Future<void> _observe(User? user) async {
    final generation = ++_generation;
    await _profileSubscription?.cancel();
    if (generation != _generation) return;
    if (user == null) {
      _publish(null);
      return;
    }
    // Accounts already connected with Google before this upgrade retain access.
    // A pending registration created by the new flow already has a profile, so
    // its explicit confirmation is preserved across application restarts.
    if (_restoredGoogleUid == user.uid) {
      _restoredGoogleUid = null;
      try {
        final ref = _profile(user.uid);
        await _firestore.runTransaction((transaction) async {
          if (!(await transaction.get(ref)).exists) {
            final name = user.displayName ?? '';
            transaction.set(ref, {
              'fullName': name.length > 100 ? name.substring(0, 100) : name,
              'phone': '',
              'profession': '',
              'registrationConfirmed': true,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });
      } catch (error, stack) {
        if (generation == _generation) _publishError(error, stack);
        return;
      }
      if (generation != _generation) return;
    }
    _profileSubscription = _profile(user.uid).snapshots().listen(
      (snapshot) {
        if (_mutating ||
            generation != _generation ||
            _auth.currentUser?.uid != user.uid) {
          return;
        }
        final data = snapshot.data() ?? <String, dynamic>{};
        _publish(
          FoundiUser(
            id: user.uid,
            email: user.email ?? '',
            displayName: user.displayName,
            emailVerified: user.emailVerified,
            hasPassword: user.providerData.any(
              (p) => p.providerId == 'password',
            ),
            hasGoogle: user.providerData.any(
              (p) => p.providerId == 'google.com',
            ),
            profile: AccountProfile(
              fullName: data['fullName'] as String? ?? user.displayName ?? '',
              phone: data['phone'] as String? ?? '',
              profession: data['profession'] as String? ?? '',
              registrationConfirmed: data['registrationConfirmed'] == true,
              registrationPath: data['registrationPath'] as String? ?? 'client',
              preferredMode: data['preferredMode'] as String? ?? 'client',
              termsVersion: data['termsVersion'] as String? ?? '',
            ),
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (generation == _generation && !_mutating) {
          _publishError(error, stack);
        }
      },
    );
  }

  Future<T> _safe<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw AuthFailure(_message(error.code));
    }
  }

  Future<void> _pauseSession(Future<void> Function() operation) async {
    if (_mutating) throw const AuthFailure('Une opération est déjà en cours.');
    _mutating = true;
    ++_generation;
    try {
      await _safe(operation);
    } finally {
      _mutating = false;
      await _observe(_auth.currentUser);
    }
  }

  Future<void> _writeProfile(AccountProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Reconnecte-toi pour continuer.');
    final ref = _profile(user.uid);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      transaction.set(ref, {
        'fullName': profile.fullName.trim(),
        'phone': profile.phone,
        'profession': profile.profession.trim(),
        'registrationConfirmed': profile.registrationConfirmed,
        'registrationPath': profile.registrationPath,
        'preferredMode': profile.preferredMode,
        'termsVersion': profile.termsVersion,
        if (profile.termsVersion.isNotEmpty &&
            existing.data()?['termsVersion'] != profile.termsVersion)
          'termsAcceptedAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    if (profile.fullName.trim() != user.displayName) {
      await user.updateDisplayName(profile.fullName.trim());
    }
  }

  @override
  Future<void> registerWithPassword({
    required String email,
    required String password,
    required AccountProfile profile,
  }) => _pauseSession(() async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    await _writeProfile(profile.copyWith(registrationConfirmed: true));
  });

  @override
  Future<void> signInWithPassword(String email, String password) =>
      _pauseSession(() async {
        await _auth.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(),
          password: password,
        );
      });

  @override
  Future<EmailChallenge> requestEmailCode() => _safe(() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Connecte-toi pour vérifier ton e-mail.');
    }
    final result = await _functions
        .httpsCallable('requestEmailCode')
        .call<Map<String, dynamic>>();
    final now = DateTime.now();
    return EmailChallenge(
      id: result.data['challengeId'] as String,
      email: user.email!,
      expiresAt: now.add(
        Duration(seconds: (result.data['expiresInSeconds'] as num).toInt()),
      ),
      resendAt: now.add(
        Duration(seconds: (result.data['resendAfterSeconds'] as num).toInt()),
      ),
    );
  });

  Future<void> _reload() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  }

  @override
  Future<void> refreshUser() => _pauseSession(_reload);

  @override
  Future<void> verifyEmailCode(EmailChallenge challenge, String code) =>
      _pauseSession(() async {
        if (_auth.currentUser?.email != challenge.email) {
          throw const AuthFailure(
            'Demande un nouveau code pour cette adresse.',
          );
        }
        final result = await _functions
            .httpsCallable('verifyEmailCode')
            .call<Map<String, dynamic>>({
              'challengeId': challenge.id,
              'code': code,
            });
        if (result.data['verified'] != true) {
          throw const AuthFailure('La vérification n’a pas abouti. Réessaie.');
        }
        await _reload();
      });

  @override
  Future<void> changeRegistrationEmail(String email, String password) =>
      _pauseSession(() async {
        final user = _auth.currentUser;
        if (user?.email == null) {
          throw const AuthFailure('Reconnecte-toi pour continuer.');
        }
        await user!.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
        await _auth.currentUser!.getIdToken(true);
        final normalized = email.trim().toLowerCase();
        await _functions
            .httpsCallable('changeRegistrationEmail')
            .call<Map<String, dynamic>>({'email': normalized});
        await _auth.signInWithEmailAndPassword(
          email: normalized,
          password: password,
        );
      });

  @override
  Future<void> sendPasswordReset(String email) => _safe(() async {
    try {
      await _auth.setLanguageCode('fr');
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') rethrow;
    }
  });

  @override
  Future<void> saveProfile(AccountProfile profile) => _pauseSession(
    () => _writeProfile(profile.copyWith(registrationConfirmed: true)),
  );

  @override
  Future<void> confirmGoogleRegistration({
    String registrationPath = 'client',
    String termsVersion = '',
  }) => _pauseSession(() async {
    final user = _auth.currentUser;
    if (user == null ||
        !user.providerData.any((p) => p.providerId == 'google.com')) {
      throw const AuthFailure('Reconnecte-toi avec Google.');
    }
    await _profile(user.uid).update({
      'registrationConfirmed': true,
      'registrationPath': registrationPath,
      'termsVersion': termsVersion,
      if (termsVersion.isNotEmpty)
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> signInWithGoogle({
    required bool registering,
    String registrationPath = 'client',
    String termsVersion = '',
  }) => _pauseSession(() async {
    UserCredential credential;
    try {
      if (kIsWeb) {
        credential = await _auth.signInWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        );
      } else {
        if (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS) {
          throw const AuthFailure(
            'La connexion Google est disponible sur Android, iOS et le Web.',
          );
        }
        await (_googleInitialization ??= GoogleSignIn.instance.initialize());
        final account = await GoogleSignIn.instance.authenticate();
        final token = account.authentication.idToken;
        if (token == null) {
          throw const AuthFailure('Google n’a pas confirmé la connexion.');
        }
        credential = await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: token),
        );
      }
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return;
      throw const AuthFailure(
        'Impossible de se connecter avec Google. Réessaie.',
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        return;
      }
      rethrow;
    }
    final user = credential.user!;
    final ref = _profile(user.uid);
    final name = user.displayName ?? '';
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (!existing.exists) {
        transaction.set(ref, {
          'fullName': name.length > 100 ? name.substring(0, 100) : name,
          'phone': '',
          'profession': '',
          'registrationPath': registering ? registrationPath : 'client',
          'preferredMode': 'client',
          'termsVersion': registering ? termsVersion : '',
          if (registering && termsVersion.isNotEmpty)
            'termsAcceptedAt': FieldValue.serverTimestamp(),
          'registrationConfirmed':
              registering || credential.additionalUserInfo?.isNewUser != true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (registering) {
        transaction.update(ref, {
          'registrationConfirmed': true,
          'registrationPath': registrationPath,
          if (termsVersion.isNotEmpty &&
              existing.data()?['termsVersion'] != termsVersion) ...{
            'termsVersion': termsVersion,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  });

  @override
  Future<LegalDocuments> loadLegalDocuments() => _safe(() async {
    final data = (await _firestore.doc('legalDocuments/current').get()).data();
    if (data?['published'] != true) return const LegalDocuments();
    return LegalDocuments(
      version: data?['version'] as String? ?? '',
      terms: data?['terms'] as String? ?? '',
      privacy: data?['privacy'] as String? ?? '',
    );
  });
  @override
  Future<void> acceptLegal(String version) => _pauseSession(() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure('Reconnecte-toi pour continuer.');
    await _profile(uid).update({
      'termsVersion': version,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
  @override
  Future<void> setPreferredMode(String mode) => _safe(() async {
    if (!['client', 'professional'].contains(mode) || _auth.currentUser == null) {
      throw const AuthFailure('Mode indisponible.');
    }
    await _profile(_auth.currentUser!.uid).update({
      'preferredMode': mode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> signOut() => _pauseSession(() async {
    await _auth.signOut();
    if (!kIsWeb && _googleInitialization != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        /* Firebase is already signed out. */
      }
    }
  });

  String _message(String code) => switch (code) {
    'invalid-email' => 'Saisis une adresse e-mail valide.',
    'email-already-in-use' || 'already-exists' || 'auth/email-already-exists' =>
      'Cette adresse possède déjà un compte. Connecte-toi ou définis ton mot de passe.',
    'wrong-password' ||
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'user-not-found' => 'L’e-mail ou le mot de passe est incorrect.',
    'weak-password' || 'password-does-not-meet-requirements' =>
      'Choisis un mot de passe plus long respectant les critères demandés.',
    'invalid-argument' => 'Vérifie les informations saisies.',
    'unauthenticated' =>
      'Ce code est incorrect ou a déjà été utilisé. Reconnecte-toi si nécessaire.',
    'deadline-exceeded' => 'Ce code a expiré. Demande un nouveau code.',
    'resource-exhausted' || 'too-many-requests' =>
      'Trop de tentatives. Patiente quelques minutes avant de réessayer.',
    'network-request-failed' ||
    'unavailable' => 'La connexion est indisponible. Réessaie dans un instant.',
    'permission-denied' =>
      'Le compte ne peut pas être chargé. Réessaie ou contacte l’assistance.',
    'user-disabled' =>
      'Ce compte ne peut pas se connecter. Contacte l’assistance.',
    'operation-not-allowed' || 'not-found' =>
      'Ce mode de connexion n’est pas encore disponible. Réessaie plus tard.',
    'failed-precondition' =>
      'Termine les informations de ton inscription ou actualise ton compte.',
    'requires-recent-login' ||
    'user-token-expired' ||
    'invalid-user-token' => 'Reconnecte-toi pour confirmer cette modification.',
    'account-exists-with-different-credential' =>
      'Connecte-toi avec la méthode déjà associée à cette adresse.',
    'popup-blocked' =>
      'Autorise la fenêtre Google dans ton navigateur puis réessaie.',
    _ => 'Impossible de terminer la connexion. Réessaie dans un instant.',
  };
}
