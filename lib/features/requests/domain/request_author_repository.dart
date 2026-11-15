import '../../professional/domain/professional_showcase.dart';
import '../../auth/domain/auth_repository.dart';

class RequestAuthorUnavailable extends AuthFailure {
  const RequestAuthorUnavailable()
    : super('Le profil de cet auteur n’est plus disponible.');
}

class RequestAuthorProfile {
  const RequestAuthorProfile({
    required this.name,
    this.avatarKey,
    this.professional,
  });
  final String name;
  final String? avatarKey;
  final ProfessionalShowcase? professional;
  factory RequestAuthorProfile.fromMap(Map<String, dynamic> data) =>
      RequestAuthorProfile(
        name: data['name'] as String,
        avatarKey: data['avatarKey'] as String?,
        professional: data['professional'] is Map
            ? ProfessionalShowcase.fromMap(
                Map<String, dynamic>.from(data['professional'] as Map),
              )
            : null,
      );
}

abstract interface class RequestAuthorRepository {
  Future<RequestAuthorProfile> readRequestAuthor(String requestId);
}
