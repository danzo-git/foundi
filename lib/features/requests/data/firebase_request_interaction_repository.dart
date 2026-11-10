import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../professional/domain/professional_showcase.dart';
import '../domain/request_interaction_repository.dart';

class FirebaseRequestInteractionRepository
    implements RequestInteractionRepository {
  FirebaseRequestInteractionRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Stream<int> watchRequestLikes(String requestId) => _db
      .doc('requestEngagement/$requestId')
      .snapshots()
      .map((doc) => (doc.data()?['likeCount'] as num?)?.toInt() ?? 0);

  @override
  Stream<bool> watchMyRequestLike(String requestId, String uid) => _db
      .doc('requestEngagement/$requestId/likes/$uid')
      .snapshots()
      .map((doc) => doc.exists);

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    try {
      return (await _functions
              .httpsCallable(name)
              .call<Map<String, dynamic>>(arguments))
          .data;
    } on FirebaseFunctionsException catch (error) {
      throw AuthFailure(switch (error.code) {
        'permission-denied' ||
        'failed-precondition' ||
        'not-found' ||
        'resource-exhausted' ||
        'invalid-argument' => error.message ?? 'Cette action est indisponible.',
        'unauthenticated' => 'Connecte-toi pour continuer.',
        _ => 'Impossible de confirmer cette action. Réessaie.',
      });
    }
  }

  @override
  Future<void> setRequestLike(String requestId, bool liked) async {
    await _call('setRequestLike', {'requestId': requestId, 'liked': liked});
  }

  @override
  Future<RecommendationPage> searchRecommendationProfessionals(
    String requestId,
    String query, {
    String? cursor,
  }) async {
    final data = await _call('searchRecommendationProfessionals', {
      'requestId': requestId,
      'query': query,
      'cursor': ?cursor,
    });
    return RecommendationPage(
      (data['items'] as List)
          .map(
            (value) => RecommendationProfessional.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      cursor: data['cursor'] as String?,
    );
  }

  @override
  Future<bool> recommendRequestProfessional(
    String requestId,
    String professionalId,
  ) async =>
      (await _call('recommendRequestProfessional', {
        'requestId': requestId,
        'professionalId': professionalId,
      }))['alreadyRecommended'] ==
      true;

  @override
  Future<ProfessionalShowcase> readRequestRecommendation(
    String recommendationId,
  ) async => ProfessionalShowcase.fromMap(
    await _call('readRequestRecommendation', {
      'recommendationId': recommendationId,
    }),
  );
}
