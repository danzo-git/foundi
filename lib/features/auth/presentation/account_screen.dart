import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';
import 'password_reset_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final FoundiUser user;
  final AuthRepository repository;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends AuthActionState<AccountScreen> {
  void _editProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          user: widget.repository.currentUser ?? widget.user,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.user.profile;
    final name = profile.fullName.isNotEmpty
        ? profile.fullName
        : widget.user.displayName;
    return AuthLayout(
      title: 'Mon compte',
      children: [
        AuthHeading(
          title: name == null || name.isEmpty
              ? 'Bienvenue !'
              : 'Bienvenue, $name !',
          description: widget.user.email,
          icon: Icons.verified_user_outlined,
        ),
        if (!profile.isComplete) ...[
          const AuthNotice(
            'Ton compte est prêt. Tu peux compléter tes informations personnelles quand tu le souhaites.',
            isError: false,
          ),
          OutlinedButton(
            onPressed: busy ? null : _editProfile,
            child: const Text('Compléter mon profil'),
          ),
          const SizedBox(height: 24),
        ],
        Text(
          'Paramètres du compte',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Informations personnelles'),
            subtitle: const Text('Nom, téléphone et profession'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : _editProfile,
          ),
        ),
        const SizedBox(height: 28),
        AuthNotice(error),
        OutlinedButton(
          onPressed: busy ? null : () => perform(widget.repository.signOut),
          child: Text(busy ? 'Déconnexion…' : 'Se déconnecter'),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.repository,
    this.onboarding = false,
  });
  final FoundiUser user;
  final AuthRepository repository;
  final bool onboarding;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends AuthActionState<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.profile.fullName);
  late final _phone = TextEditingController(text: widget.user.profile.phone);
  late final _profession = TextEditingController(
    text: widget.user.profile.profession,
  );
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _profession.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await perform(
      () => widget.repository.saveProfile(
        AccountProfile(
          fullName: _name.text.trim(),
          phone: AuthValidators.normalizePhone(_phone.text),
          profession: _profession.text.trim(),
          registrationConfirmed: true,
        ),
      ),
    );
    if (success && mounted && !widget.onboarding) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: widget.onboarding
        ? 'Compléter mon inscription'
        : 'Informations personnelles',
    actions: widget.onboarding
        ? [
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: busy ? null : () => perform(widget.repository.signOut),
            ),
          ]
        : null,
    children: [
      AuthHeading(
        title: widget.onboarding ? 'Terminons ton profil' : 'Tes informations',
        description: widget.user.hasGoogle
            ? 'Complète ou modifie ton profil à ton rythme.'
            : 'Ton nom, ton téléphone et ta profession permettent de compléter ton compte.',
      ),
      Form(
        key: _form,
        child: ProfileFields(
          name: _name,
          phone: _phone,
          profession: _profession,
          enabled: !busy,
          optional: widget.user.hasGoogle,
        ),
      ),
      AuthNotice(error),
      const SizedBox(height: 28),
      AuthButton(
        label: widget.onboarding ? 'Continuer' : 'Enregistrer',
        busy: busy,
        onPressed: _save,
      ),
    ],
  );
}

class GoogleRegistrationScreen extends StatefulWidget {
  const GoogleRegistrationScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final FoundiUser user;
  final AuthRepository repository;
  @override
  State<GoogleRegistrationScreen> createState() =>
      _GoogleRegistrationScreenState();
}

class _GoogleRegistrationScreenState
    extends AuthActionState<GoogleRegistrationScreen> {
  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Bienvenue sur Foundi',
    children: [
      AuthHeading(
        title: 'C’est ta première visite',
        description:
            'Souhaites-tu créer ton compte Foundi avec ${widget.user.email} ?',
        icon: Icons.person_add_alt_outlined,
      ),
      const Text(
        'Tu pourras renseigner ton téléphone et ta profession plus tard dans les paramètres de ton compte.',
        style: TextStyle(height: 1.5),
      ),
      AuthNotice(error),
      const SizedBox(height: 28),
      AuthButton(
        label: 'Créer mon compte',
        busy: busy,
        onPressed: () => perform(widget.repository.confirmGoogleRegistration),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        child: const Text('Revenir à la connexion'),
      ),
    ],
  );
}

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final FoundiUser user;
  final AuthRepository repository;
  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends AuthActionState<PasswordSetupScreen> {
  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Sécuriser mon compte',
    children: [
      AuthHeading(
        title: 'Retrouve ton compte',
        description:
            'Ton compte ${widget.user.email} utilise encore la connexion par code. Définis un mot de passe par e-mail pour continuer avec le même compte.',
        icon: Icons.lock_reset,
      ),
      AuthNotice(error),
      AuthButton(
        label: 'Définir mon mot de passe',
        onPressed: busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PasswordResetScreen(
                    repository: widget.repository,
                    initialEmail: widget.user.email,
                    defining: true,
                  ),
                ),
              ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        child: const Text('Revenir me connecter'),
      ),
    ],
  );
}

class AccountLoadErrorScreen extends StatefulWidget {
  const AccountLoadErrorScreen({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<AccountLoadErrorScreen> createState() => _AccountLoadErrorScreenState();
}

class _AccountLoadErrorScreenState
    extends AuthActionState<AccountLoadErrorScreen> {
  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Chargement du compte',
    children: [
      const AuthHeading(
        title: 'Le compte est indisponible',
        description:
            'Vérifie ta connexion puis réessaie de charger tes informations.',
      ),
      AuthNotice(error),
      AuthButton(
        label: 'Réessayer',
        busy: busy,
        onPressed: () => perform(widget.repository.refreshUser),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        child: const Text('Revenir à la connexion'),
      ),
    ],
  );
}
