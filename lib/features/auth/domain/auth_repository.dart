class AccountProfile {
  const AccountProfile({
    this.fullName = '',
    this.phone = '',
    this.profession = '',
    this.registrationConfirmed = false,
    this.registrationPath = 'client',
    this.preferredMode = 'client',
    this.termsVersion = '',
  });
  final String fullName;
  final String phone;
  final String profession;
  final bool registrationConfirmed;
  final String registrationPath, preferredMode, termsVersion;

  bool get isComplete =>
      fullName.trim().length >= 2 &&
      (phone.isEmpty || RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone));

  AccountProfile copyWith({
    String? fullName,
    String? phone,
    bool? registrationConfirmed,
    String? registrationPath,
    String? preferredMode,
    String? termsVersion,
  }) => AccountProfile(
    fullName: fullName ?? this.fullName,
    phone: phone ?? this.phone,
    profession: profession,
    registrationConfirmed: registrationConfirmed ?? this.registrationConfirmed,
    registrationPath: registrationPath ?? this.registrationPath,
    preferredMode: preferredMode ?? this.preferredMode,
    termsVersion: termsVersion ?? this.termsVersion,
  );
}

class LegalDocuments {
  const LegalDocuments({this.version = '', this.terms = '', this.privacy = ''});
  final String version, terms, privacy;
  bool get published =>
      version.isNotEmpty && terms.isNotEmpty && privacy.isNotEmpty;
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
  Future<void> signInWithGoogle({
    required bool registering,
    String registrationPath = 'client',
    String termsVersion = '',
  });
  Future<void> confirmGoogleRegistration({
    String registrationPath = 'client',
    String termsVersion = '',
  });
  Future<LegalDocuments> loadLegalDocuments();
  Future<void> acceptLegal(String version);
  Future<void> setPreferredMode(String mode);
  Future<void> saveProfile(AccountProfile profile);
  Future<void> signOut();
}
