import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/information_repository.dart';

class FirebaseInformationRepository implements InformationRepository {
  FirebaseInformationRepository(this.functions);
  final FirebaseFunctions functions;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    try {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call<Map<String, dynamic>>(input);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') throw const InformationUnavailable();
      throw const AuthFailure(
        'Les informations sont momentanément indisponibles.',
      );
    }
  }

  @override
  Future<List<FoundiInformation>> listInformation({
    bool featuredOnly = false,
  }) async {
    final data = await _call('listFoundiInformation', {
      'featuredOnly': featuredOnly,
    });
    return (data['items'] as List)
        .map(
          (item) => FoundiInformation.fromMap({
            ...Map<String, dynamic>.from(item),
            'serverNow': data['serverNow'],
          }),
        )
        .toList();
  }

  @override
  Future<FoundiInformation> readInformation(String id) async =>
      FoundiInformation.fromMap(
        await _call('readFoundiInformation', {'id': id}),
      );
}
