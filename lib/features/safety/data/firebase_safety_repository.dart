import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/safety_repository.dart';

class FirebaseSafetyRepository implements SafetyRepository {
  @override
  Future<List<SafetyNotice>> notices() async {
    final v = await _call('listSafetyNotices', {});
    if (v['notices'] is! List) {
      throw const AuthFailure(
        'Le service des avis doit être mis à jour. Réessaie plus tard.',
      );
    }
    return (v['notices'] as List).map((raw) {
      final n = Map<String, dynamic>.from(raw as Map);
      return SafetyNotice(
        id: n['id'] as String,
        text: n['text'] as String,
        acknowledgedAt: n['acknowledgedAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (n['acknowledgedAt'] as num).toInt(),
              )
            : null,
      );
    }).toList();
  }

  @override
  Future<void> acknowledgeNotice(String id) async {
    await _call('acknowledgeSafetyNotice', {'noticeId': id});
  }

  final FirebaseFunctions functions;
  FirebaseSafetyRepository({FirebaseFunctions? functions})
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
      throw AuthFailure(_safetyFailureMessage(e));
    }
  }

  @override
  Future<void> report(
    SafetyTarget target,
    String reason,
    String comment,
  ) async {
    await _call('submitSafetyReport', {
      ...target.toMap(),
      'reason': reason,
      'comment': comment,
    });
  }

  @override
  Future<SafetyContext> context(SafetyTarget target) async {
    final v = await _call('readSafetyContext', target.toMap());
    return SafetyContext(
      own: v['own'] == true,
      blocked: v['blocked'] == true,
      contactAllowed: v['contactAllowed'] == true,
    );
  }

  @override
  Future<void> block(SafetyTarget target) async {
    await _call('blockUser', target.toMap());
  }

  @override
  Future<void> unblockTarget(SafetyTarget target) async {
    await _call('unblockSafetyTarget', target.toMap());
  }

  @override
  Future<void> unblock(String uid) async {
    await _call('unblockUser', {'blockedUid': uid});
  }

  @override
  Future<BlockedPage> blocked({String? cursor}) async {
    final v = await _call('listBlockedUsers', {'cursor': ?cursor});
    return BlockedPage([
      for (final u in v['items'] as List)
        BlockedUser(u['uid'] as String, u['label'] as String),
    ], cursor: v['cursor'] as String?);
  }
}

String _safetyFailureMessage(FirebaseFunctionsException error) {
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
      'Le service de sécurité est temporairement indisponible. Réessaie plus tard.',
    'not-found' when generic =>
      'Le service de sécurité est indisponible sur le serveur. Réessaie plus tard.',
    'unauthenticated' => 'Reconnecte-toi pour continuer.',
    'deadline-exceeded' =>
      'Le serveur ne répond pas. Vérifie ta connexion et réessaie.',
    'permission-denied' when generic =>
      'Cette action n’est pas autorisée pour ton compte.',
    'resource-exhausted' when message.isEmpty =>
      'La limite d’actions est atteinte. Réessaie plus tard.',
    _ => generic ? 'Action indisponible. Réessaie plus tard.' : message,
  };
}
