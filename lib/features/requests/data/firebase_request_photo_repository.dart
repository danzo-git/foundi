import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/domain/auth_repository.dart';
import '../domain/request_photo_repository.dart';

class FirebaseRequestPhotoRepository
    implements RequestPhotoRepository, PublicRequestPhotoRepository {
  FirebaseRequestPhotoRepository(this.functions, {this.endpointBase});

  final FirebaseFunctions functions;
  final String? endpointBase;
  final _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 3),
      followRedirects: false,
    ),
  );

  String get _base =>
      endpointBase ??
      'https://europe-west1-${functions.app.options.projectId}.cloudfunctions.net';

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instanceFor(
      app: functions.app,
    ).currentUser?.getIdToken();
    if (token == null) {
      throw const AuthFailure('Reconnecte-toi pour accéder aux photos.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  AuthFailure _failure(DioException error, String fallback) {
    Object? data = error.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } on FormatException {
        return AuthFailure(fallback);
      }
    }
    final problem = data is Map ? data['error'] : null;
    final message = problem is Map ? problem['message'] : null;
    return AuthFailure(message is String ? message : fallback);
  }

  @override
  Future<bool> uploadRequestPhoto(
    String requestId,
    LocalRequestPhoto photo,
  ) async {
    try {
      final response = await _http.post<Map<String, dynamic>>(
        '$_base/uploadRequestPhoto',
        queryParameters: {'requestId': requestId, 'photoId': photo.id},
        data: photo.bytes,
        options: Options(
          contentType: photo.contentType,
          headers: await _headers(),
        ),
      );
      if (response.data?['published'] == true) return true;
      if (response.data?['ready'] != true) {
        throw const AuthFailure('Envoi de la photo non confirmé. Réessaie.');
      }
      return false;
    } on DioException catch (error) {
      throw _failure(
        error,
        'Envoi de la photo non confirmé. Vérifie ta connexion puis réessaie.',
      );
    }
  }

  @override
  Future<void> discardRequestPhotos(
    String requestId,
    List<String> photoIds,
  ) async {
    try {
      await functions.httpsCallable('discardRequestPhotos').call({
        'requestId': requestId,
        'photoIds': photoIds,
      });
    } on FirebaseFunctionsException catch (error) {
      throw AuthFailure(
        error.message ?? 'Retrait des photos non confirmé. Réessaie.',
      );
    }
  }

  @override
  Future<Uint8List> readRequestPhoto(String requestId, String photoId) =>
      _readPhoto(requestId, photoId, isPublic: false);

  @override
  Future<Uint8List> readPublicRequestPhoto(String requestId, String photoId) =>
      _readPhoto(requestId, photoId, isPublic: true);

  Future<Uint8List> _readPhoto(
    String requestId,
    String photoId, {
    required bool isPublic,
  }) async {
    final endpoint = isPublic ? 'readPublicRequestPhoto' : 'readRequestPhoto';
    try {
      final response = await _http.get<List<int>>(
        '$_base/$endpoint',
        queryParameters: {'requestId': requestId, 'photoId': photoId},
        options: Options(
          responseType: ResponseType.bytes,
          headers: isPublic ? null : await _headers(),
        ),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (error) {
      throw _failure(
        error,
        'Photo indisponible. Vérifie ta connexion puis réessaie.',
      );
    }
  }
}
