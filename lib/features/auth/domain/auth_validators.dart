class AuthValidators {
  static String? email(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Saisis une adresse e-mail valide.';

  static String? fullName(String? value) {
    final text = value?.trim() ?? '';
    return text.length >= 2 && text.length <= 100
        ? null
        : 'Saisis ton nom complet (2 à 100 caractères).';
  }

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[\s().-]'), '');

  static String? phone(String? value) =>
      RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalizePhone(value ?? ''))
      ? null
      : 'Ajoute l’indicatif, par exemple +2250700000000.';

  static String? profession(String? value) {
    final text = value?.trim() ?? '';
    return text.isNotEmpty && text.length <= 100
        ? null
        : 'Renseigne ta profession ou ton activité.';
  }

  static String? password(String? value) =>
      (value?.length ?? 0) >= 12 ? null : 'Utilise au moins 12 caractères.';

  static String? loginPassword(String? value) =>
      value?.isNotEmpty == true ? null : 'Saisis ton mot de passe.';
}
