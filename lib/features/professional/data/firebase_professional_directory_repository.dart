import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/professional_directory.dart';
import '../domain/professional_showcase.dart';

// Short lived, bounded media cache. Lists never download complete showcases.
class FirebaseProfessionalDirectoryRepository
    implements ProfessionalDirectoryRepository {
  FirebaseProfessionalDirectoryRepository(this.functions);
  final FirebaseFunctions functions;
  final _cache = <String, ({DateTime until, Object value, int bytes})>{};
  final _pending = <String, Future<Object>>{};
  final _waiters = Queue<Completer<void>>();
  int _running = 0, _bytes = 0;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final r = await functions.httpsCallable(name).call<dynamic>(args);
      return Map<String, dynamic>.from(r.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') throw const ProfessionalUnavailable();
      throw AuthFailure(
        e.message ?? 'Impossible de charger les professionnels. Réessaie.',
      );
    }
  }

  Future<T> _media<T extends Object>(
    String key,
    Future<T> Function() load,
  ) async {
    final cached = _cache.remove(key);
    if (cached != null) {
      _bytes -= cached.bytes;
      if (cached.until.isAfter(DateTime.now())) {
        _cache[key] = cached;
        _bytes += cached.bytes;
        return cached.value as T;
      }
    }
    final pending = _pending[key];
    if (pending != null) return await pending as T;
    final future = () async {
      if (_running >= 4) {
        final waiter = Completer<void>();
        _waiters.add(waiter);
        await waiter.future;
      } else {
        _running++;
      }
      try {
        final result = await load();
        final size = result is Uint8List ? result.length : 0;
        _cache[key] = (
          until: DateTime.now().add(const Duration(seconds: 30)),
          value: result,
          bytes: size,
        );
        _bytes += size;
        while (_cache.length > 96 || _bytes > 2 * 1024 * 1024) {
          _bytes -= _cache.remove(_cache.keys.first)!.bytes;
        }
        return result;
      } finally {
        if (_waiters.isNotEmpty) {
          _waiters.removeFirst().complete();
        } else {
          _running--;
        }
        _pending.remove(key);
      }
    }();
    _pending[key] = future;
    return future;
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
    () async {
      final m = await _call('readPublicProfessionalMedia', {
        'professionalId': id,
      });
      return ProfessionalMediaManifest(
        portraitId: m['portraitId'] as String?,
        galleryIds: List<String>.from(m['galleryIds'] as List).take(3).toList(),
      );
    },
  );
  @override
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId) => _media(
    '$id/$photoId',
    () async => base64Decode(
      (await _call('readPublicProfessionalMedia', {
            'professionalId': id,
            'photoId': photoId,
          }))['base64']
          as String,
    ),
  );
  @override
  void clearDirectoryMedia(String id) {
    for (final key in _cache.keys.where((k) => k.startsWith('$id/')).toList()) {
      _bytes -= _cache.remove(key)!.bytes;
    }
  }
}
