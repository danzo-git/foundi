class AccountProfile {
  const AccountProfile({
    this.fullName = '',
    this.phone = '',
    this.profession = '',
    this.registrationConfirmed = false,
  });
  final String fullName;
  final String phone;
  final String profession;
  final bool registrationConfirmed;

  bool get isComplete =>
      fullName.trim().length >= 2 &&
      RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone) &&
      profession.trim().isNotEmpty;
}

class FoundiUser {
  const FoundiUser({
    required this.id,
    required this.email,
    this.displayName,
    required this.emailVerified,
    required this.hasPassword,
    required this.hasGoogle,
    this.profile = const AccountProfile(),
  });
  final String id;
  final String email;
  final String? displayName;
  final bool emailVerified;
  final bool hasPassword;
  final bool hasGoogle;
  final AccountProfile profile;

  bool get needsPasswordSetup => !hasPassword && !hasGoogle;
  bool get needsGoogleConfirmation =>
      hasGoogle && !profile.registrationConfirmed;
  bool get needsClassicProfile => !hasGoogle && !profile.isComplete;
}

class EmailChallenge {
  const EmailChallenge({
    required this.id,
    required this.email,
    required this.expiresAt,
    required this.resendAt,
  });
  final String id;
  final String email;
  final DateTime expiresAt;
  final DateTime resendAt;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

abstract interface class AuthRepository {
  FoundiUser? get currentUser;
  Stream<FoundiUser?> authStateChanges();
  Future<void> signInWithPassword(String email, String password);
  Future<void> registerWithPassword({
    required String email,
    required String password,
    required AccountProfile profile,
  });
  Future<EmailChallenge> requestEmailCode();
  Future<void> verifyEmailCode(EmailChallenge challenge, String code);
  Future<void> changeRegistrationEmail(String email, String password);
  Future<void> refreshUser();
  Future<void> sendPasswordReset(String email);
  Future<void> signInWithGoogle({required bool registering});
  Future<void> confirmGoogleRegistration();
  Future<void> saveProfile(AccountProfile profile);
  Future<void> signOut();
}
