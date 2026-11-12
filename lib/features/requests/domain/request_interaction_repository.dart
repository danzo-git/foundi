import '../../professional/domain/professional_showcase.dart';
import 'request_repository.dart';

class RecommendationProfessional {
  const RecommendationProfessional({
    required this.id,
    required this.name,
    this.categories = const [],
    this.specialties = const [],
    this.zones = const [],
  });

  final String id, name;
  final List<String> categories, specialties, zones;

  factory RecommendationProfessional.fromMap(Map<String, dynamic> data) {
    List<String> labels(String field) => (data[field] as List).cast<String>();
    return RecommendationProfessional(
      id: data['id'] as String,
      name: data['name'] as String,
      categories: labels('categories'),
      specialties: labels('specialties'),
      zones: labels('zones'),
    );
  }
}

class RecommendationPage {
  const RecommendationPage(this.items, {this.cursor});
  final List<RecommendationProfessional> items;
  final String? cursor;
}

class RequestEngagement {
  const RequestEngagement({
    this.likeCount = 0,
    this.recommendationCount,
    this.responseCount,
  });
  final int likeCount;
  final int? recommendationCount, responseCount;

  factory RequestEngagement.fromMap(Map<String, dynamic> data) =>
      RequestEngagement(
        likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
        recommendationCount: (data['recommendationCount'] as num?)?.toInt(),
        responseCount: (data['responseCount'] as num?)?.toInt(),
      );
}

abstract interface class RequestInteractionRepository {
  Stream<RequestEngagement> watchRequestEngagement(String requestId);
  Stream<int> watchRequestLikes(String requestId);
  Stream<bool> watchMyRequestLike(String requestId, String uid);
  Future<void> setRequestLike(String requestId, bool liked);
  Future<RecommendationPage> searchRecommendationProfessionals(
    String requestId,
    String query, {
    String? cursor,
  });
  Future<bool> recommendRequestProfessional(
    String requestId,
    String professionalId,
  );
  Future<ProfessionalShowcase> readRequestRecommendation(
    String recommendationId,
  );
}

abstract interface class RequestInteractionSource {
  RequestInteractionRepository get interactions;
}

extension RequestInteractions on RequestRepository {
  RequestInteractionRepository? get interactionRepository {
    final repository = this;
    return repository is RequestInteractionSource
        ? (repository as RequestInteractionSource).interactions
        : null;
  }
}
