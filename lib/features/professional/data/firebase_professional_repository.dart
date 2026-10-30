import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/professional_repository.dart';

class FirebaseProfessionalRepository implements ProfessionalRepository {
  FirebaseProfessionalRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  @override
  Stream<ProfessionalProfile> watchProfile(String uid) => _db
      .doc('professionalProfiles/$uid')
      .snapshots()
      .map((s) => ProfessionalProfile.fromMap(s.data()));
  @override
  Stream<List<ProfessionalDocument>> watchDocuments(String uid) => _db
      .collection('professionalProfiles/$uid/documents')
      .snapshots()
      .map(
        (s) => s.docs
            .map(
              (d) => ProfessionalDocument(
                d.id,
                d.data()['name'] as String? ?? '',
                d.data()['state'] == 'ready',
              ),
            )
            .toList(),
      );
  @override
  Stream<ProfessionalCatalog> watchCatalog() => _db
      .doc('referenceData/professionalOnboarding')
      .snapshots()
      .map((s) => ProfessionalCatalog.fromMap(s.data()));
  @override
  Future<ProfessionalCatalog> loadCatalog() async {
    try {
      return ProfessionalCatalog.fromMap(
        (await _db.doc('referenceData/professionalOnboarding').get()).data(),
      );
    } on FirebaseException catch (_) {
      throw const AuthFailure(
        'Impossible de charger les références. Vérifie ta connexion puis réessaie.',
      );
    }
  }

  Future<void> _call(
    String name, [
    Map<String, dynamic>? data,
    int retries = 0,
  ]) async {
    try {
      await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 120),
            ),
          )
          .call(data);
    } on FirebaseFunctionsException catch (e) {
      // Only retry operations that can safely save the same input again after
      // a temporary failure or a lost server response.
      if (retries > 0 &&
          const [
            'unavailable',
            'deadline-exceeded',
            'internal',
            'unknown',
          ].contains(e.code)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        return _call(name, data, retries - 1);
      }
      throw AuthFailure(switch (e.code) {
        'failed-precondition' ||
        'invalid-argument' ||
        'aborted' => e.message ?? 'Vérifie ton dossier puis réessaie.',
        'permission-denied' =>
          'Tu ne disposes pas des droits nécessaires pour cette action.',
        'unauthenticated' => 'Reconnecte-toi pour continuer.',
        _ =>
          'Impossible d’enregistrer le dossier. Vérifie ta connexion puis réessaie.',
      });
    }
  }

  @override
  Future<void> start() => _call('startProfessionalProfile', null, 2);
  @override
  Future<void> saveActivity(
    ProfessionalActivity activity, {
    required bool complete,
  }) => _call('saveProfessionalActivity', {
    'activity': activity.toMap(),
    'complete': complete,
  }, 2);
  @override
  Future<void> uploadDocument(String kind, String name, Uint8List bytes) =>
      _call('uploadProfessionalDocument', {
        'kind': kind,
        'name': name,
        'base64': base64Encode(bytes),
      });
  @override
  Future<void> submit({required bool certified}) =>
      _call('submitProfessionalProfile', {'certified': certified});
  @override
  Future<void> checkAccess() => _call('checkProfessionalAccess');
}
