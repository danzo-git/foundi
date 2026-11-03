import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/rich_conversation_repository.dart';

class FirebaseRichConversationRepository implements RichConversationRepository {
  FirebaseRichConversationRepository(
    this.functions, {
    this.endpointBase,
    Dio? http,
    this.auth,
    this.callable,
    this.accessToken,
  }) : _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 3),
               sendTimeout: const Duration(minutes: 3),
             ),
           );
  final FirebaseFunctions functions;
  final String? endpointBase;
  final FirebaseAuth? auth;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  callable;
  final Future<String> Function()? accessToken;
  final Dio _http;
  String get _base =>
      endpointBase ??
      'https://europe-west1-${functions.app.options.projectId}.cloudfunctions.net';
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (callable != null) return callable!(name, data);
    try {
      return (await functions
              .httpsCallable(name)
              .call<Map<String, dynamic>>(data))
          .data;
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(e.message ?? 'Opération non confirmée. Réessaie.');
    }
  }

  Future<Map<String, String>> _headers() async {
    if (accessToken != null) {
      return {'Authorization': 'Bearer ${await accessToken!()}'};
    }
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw const AuthFailure('Reconnecte-toi pour continuer.');
    return {'Authorization': 'Bearer ${await user.getIdToken()}'};
  }

  @override
  Future<String> sendAttachment(
    String conversationId,
    String messageId,
    AttachmentDraft draft, {
    required AttachmentCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    final reserved = await _call('prepareConversationAttachment', {
      'conversationId': conversationId,
      'messageId': messageId,
      ...draft.toMap(),
    });
    if (reserved['state'] == 'ready') return 'ready';
    if (cancellation.requested) {
      return cancelAttachment(conversationId, messageId);
    }
    if (['cancelled', 'expired', 'rejected'].contains(reserved['state'])) {
      throw const AuthFailure(
        'Cet envoi est annulé, expiré ou refusé. Choisis à nouveau le fichier.',
      );
    }
    final cancel = CancelToken();
    cancellation.onCancel = () => cancel.cancel();
    try {
      final response = await _http.post<Map<String, dynamic>>(
        '$_base/uploadConversationAttachment',
        data: Stream.value(draft.bytes),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {
            ...await _headers(),
            'Content-Length': draft.bytes.length,
            'X-Conversation-Id': conversationId,
            'X-Message-Id': messageId,
          },
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) =>
            onProgress(total > 0 ? sent / total : 0),
      );
      return response.data?['state'] as String? ?? 'processing';
    } on DioException catch (e) {
      if (cancellation.requested) {
        return cancelAttachment(conversationId, messageId);
      }
      final data = e.response?.data;
      throw AuthFailure(
        data is Map
            ? (data['error']?['message'] as String? ??
                  'Envoi non confirmé. Réessaie.')
            : 'Envoi non confirmé. Vérifie ta connexion et réessaie.',
      );
    } finally {
      cancellation.onCancel = null;
    }
  }

  @override
  Future<String> cancelAttachment(
    String conversationId,
    String messageId,
  ) async =>
      (await _call('cancelConversationAttachment', {
            'conversationId': conversationId,
            'messageId': messageId,
          }))['state']
          as String;
  @override
  Future<Uint8List> readAttachment(
    String conversationId,
    String messageId,
  ) async {
    try {
      final response = await _http.get<List<int>>(
        '$_base/readConversationAttachment',
        queryParameters: {
          'conversationId': conversationId,
          'messageId': messageId,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: await _headers(),
        ),
      );
      return Uint8List.fromList(response.data!);
    } on DioException {
      throw const AuthFailure(
        'Fichier indisponible, hors ligne ou accès refusé. Réessaie.',
      );
    }
  }

  @override
  Future<void> shareContact(
    String conversationId,
    String messageId,
    String phoneNumber,
  ) async {
    await _call('sendConversationMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
      'type': 'contact',
      'phoneNumber': phoneNumber,
      'consent': true,
    });
  }
}
