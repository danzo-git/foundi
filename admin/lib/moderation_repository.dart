import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

abstract interface class ModerationRepository {
  Future<ModerationAttachment> readAttachment(String reportId);
  Future<Map<String, dynamic>> list(Map<String, dynamic> filters);
  Future<Map<String, dynamic>> detail(String id);
  Future<void> decide(Map<String, dynamic> input);
}

class FirebaseModerationRepository implements ModerationRepository {
  @override
  Future<ModerationAttachment> readAttachment(String reportId) async {
    final user = FirebaseAuth.instanceFor(app: functions.app).currentUser;
    final token = await user?.getIdToken();
    if (token == null) {
      throw const ModerationFailure(
        'Reconnecte-toi pour consulter cette preuve.',
      );
    }
    const emulated =
        bool.fromEnvironment('USE_EMULATORS') ||
        bool.fromEnvironment('USE_FIREBASE_EMULATORS');
    final base = emulated
        ? 'http://127.0.0.1:${const int.fromEnvironment('FUNCTIONS_EMULATOR_PORT', defaultValue: 5001)}/${functions.app.options.projectId}/europe-west1'
        : 'https://europe-west1-${functions.app.options.projectId}.cloudfunctions.net';
    final response = await http
        .get(
          Uri.parse(
            '$base/readSafetyReportAttachment',
          ).replace(queryParameters: {'reportId': reportId}),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw const ModerationFailure(
        'Preuve indisponible, expirée ou accès refusé.',
      );
    }
    return ModerationAttachment(
      response.bodyBytes,
      response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  final FirebaseFunctions functions;
  FirebaseModerationRepository({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    try {
      return Map<String, dynamic>.from(
        (await functions.httpsCallable(name).call<dynamic>(input)).data as Map,
      );
    } on FirebaseFunctionsException catch (e) {
      throw ModerationFailure(_moderationFailureMessage(e));
    }
  }

  @override
  Future<Map<String, dynamic>> list(Map<String, dynamic> filters) =>
      _call('listSafetyReports', filters);
  @override
  Future<Map<String, dynamic>> detail(String id) =>
      _call('readSafetyReport', {'reportId': id});
  @override
  Future<void> decide(Map<String, dynamic> input) async {
    await _call('decideSafetyReport', input);
  }
}

String _moderationFailureMessage(FirebaseFunctionsException error) {
  final code = error.code.replaceFirst('functions/', '');
  final message = error.message?.trim() ?? '';
  final generic =
      message.isEmpty ||
      RegExp(
        r'^(not[ _-]?found|internal|unknown|unavailable|permission[ _-]?denied|unauthenticated)(\s*\[\d+\])?$',
        caseSensitive: false,
      ).hasMatch(message);
  return switch (code) {
    'internal' || 'unknown' || 'unavailable' =>
      'Le service de modération est indisponible. Réessaie plus tard ou vérifie la configuration du serveur.',
    'not-found' when generic =>
      'Le service de modération n’est pas accessible. Vérifie son activation sur le serveur.',
    'unauthenticated' => 'Reconnecte-toi à Foundi Admin pour continuer.',
    'permission-denied' when generic =>
      'Ton compte ne dispose pas des droits de modération.',
    'deadline-exceeded' =>
      'Le serveur ne répond pas. Vérifie la connexion et réessaie.',
    _ => generic ? 'Service indisponible. Réessaie plus tard.' : message,
  };
}

class ModerationFailure implements Exception {
  const ModerationFailure(this.message);
  final String message;
}

class ModerationAttachment {
  const ModerationAttachment(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

const moderationStatuses = {
  'new': 'Nouveaux',
  'in_progress': 'En cours d’examen',
  'resolved': 'Traités',
  'dismissed': 'Classés sans suite',
};
const moderationReasons = {
  'fraud': 'Arnaque / fraude',
  'harassment': 'Harcèlement / menaces',
  'inappropriate': 'Contenu inapproprié',
  'spam': 'Spam / publicité abusive',
  'impersonation': "Usurpation d’identité",
  'other': 'Autre',
};
const moderationTypes = {
  'request': 'Demande',
  'professional': 'Profil professionnel',
  'conversation': 'Conversation',
  'message': 'Message',
};
const moderationActions = {
  'take': 'Commencer l’examen',
  'reopen': 'Réexaminer le dossier',
  'dismiss': 'Classer sans suite',
  'hide': 'Masquer le contenu public',
  'restore_content': 'Restaurer le contenu public',
  'warn': 'Avertir',
  'suspend': 'Suspendre le compte',
  'restore_account': 'Restaurer le compte',
};
