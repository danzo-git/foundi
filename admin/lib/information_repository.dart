import 'package:cloud_functions/cloud_functions.dart';

abstract interface class InformationRepository {
  Future<Map<String, dynamic>> list({Map<String, dynamic>? cursor});
  Future<void> save(Map<String, dynamic> input);
}

class InformationFailure implements Exception {
  const InformationFailure(this.message);
  final String message;
}

class FirebaseInformationRepository implements InformationRepository {
  FirebaseInformationRepository({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFunctions functions;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    try {
      return Map<String, dynamic>.from(
        (await functions.httpsCallable(name).call<dynamic>(input)).data as Map,
      );
    } on FirebaseFunctionsException catch (e) {
      throw InformationFailure(switch (e.code) {
        'aborted' =>
          'Cette annonce a changé. Ferme le formulaire et actualise la liste.',
        'permission-denied' || 'unauthenticated' =>
          'Accès refusé. Reconnecte-toi avec un compte administrateur.',
        'invalid-argument' || 'resource-exhausted' =>
          e.message ?? 'Vérifie les champs et la date de fin.',
        _ => 'Les annonces sont momentanément indisponibles. Réessaie.',
      });
    }
  }

  @override
  Future<Map<String, dynamic>> list({Map<String, dynamic>? cursor}) =>
      _call('listAdminFoundiInformation', {'cursor': ?cursor});
  @override
  Future<void> save(Map<String, dynamic> input) async {
    await _call('saveFoundiInformation', input);
  }
}
