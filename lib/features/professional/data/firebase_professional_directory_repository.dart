import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/expiring_async_cache.dart';
import '../../../core/in_flight_reads.dart';
import '../../../core/firebase_read_scope.dart';
import '../../../core/read_queue.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/professional_directory.dart';
import '../domain/professional_showcase.dart';

// Short lived, bounded media cache. Lists never download complete showcases.
class FirebaseProfessionalDirectoryRepository
    implements ProfessionalDirectoryRepository {
  FirebaseProfessionalDirectoryRepository(this.functions);
  final FirebaseFunctions functions;
  final _reads = InFlightReads(currentScope: firebaseReadScope);
  final _mediaCache = ExpiringAsyncCache<String, Object>(
    maxEntries: 96,
    maxBytes: 2 * 1024 * 1024,
    ttl: const Duration(seconds: 30),
    sizeOf: (value) => value is Uint8List ? value.length : 0,
  );
  final _mediaLoads = ReadQueue();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    Future<Map<String, dynamic>> invoke() async {
      try {
        final r = await functions
            .httpsCallable(
              name,
              options: HttpsCallableOptions(timeout: timeout),
            )
            .call<dynamic>(args);
        return Map<String, dynamic>.from(r.data as Map);
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found') throw const ProfessionalUnavailable();
        throw AuthFailure(
          e.message ?? 'Impossible de charger les professionnels. Réessaie.',
        );
      }
    }

    if (name == 'readPublicProfessionalMedia') {
      return _reads.runUnshared(invoke);
    }
    return _reads.run((name, jsonEncode(args)), invoke);
  }

  Future<T> _media<T extends Object>(
    String key,
    Future<T> Function(Duration remaining) load,
  ) async {
    return await _mediaCache.load(key, () => _mediaLoads.run(load)) as T;
  }

  @override
  Future<ProfessionalDirectoryPage> searchProfessionals(
    ProfessionalDirectoryFilters filters, {
    String? cursor,
  }) async {
    final m = await _call('listPublicProfessionals', {
      ...filters.toMap(),
      'cursor': ?cursor,
    });
    return ProfessionalDirectoryPage(
      (m['items'] as List)
          .map(
            (e) => ProfessionalListing.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      cursor: m['cursor'] as String?,
    );
  }

  @override
  Future<ProfessionalShowcase> readDirectoryProfessional(String id) async =>
      ProfessionalShowcase.fromMap(
        await _call('readPublicProfessionalProfile', {'professionalId': id}),
      );
  @override
  Future<Set<String>> checkDirectoryProfessionals(List<String> ids) async =>
      Set<String>.from(
        (await _call('checkPublicProfessionals', {
              'professionalIds': ids,
            }))['professionalIds']
            as List,
      );
  @override
  Future<ProfessionalMediaManifest> directoryMediaManifest(String id) => _media(
    '$id/manifest',
    (remaining) async {
      final m = await _call('readPublicProfessionalMedia', {
        'professionalId': id,
      }, timeout: remaining);
      return ProfessionalMediaManifest(
        cacheExpiresAt: DateTime.now().add(const Duration(seconds: 30)),
        portraitId: m['portraitId'] as String?,
        galleryIds: List<String>.from(m['galleryIds'] as List).take(3).toList(),
      );
    },
  );
  @override
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId) => _media(
    '$id/$photoId',
    (remaining) async => base64Decode(
      (await _call('readPublicProfessionalMedia', {
            'professionalId': id,
            'photoId': photoId,
          }, timeout: remaining))['base64']
          as String,
    ),
  );
  @override
  void clearDirectoryMedia(String id) {
    _mediaCache.invalidateWhere((key) => key.startsWith('$id/'));
  }
}
