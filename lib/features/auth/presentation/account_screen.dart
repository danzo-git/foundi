import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';
import 'password_reset_screen.dart';
import '../../safety/presentation/safety_widgets.dart';

export 'account_view.dart';

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
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await perform(
      () => widget.repository.saveProfile(
        widget.user.profile.copyWith(
          fullName: _name.text.trim(),
          phone: AuthValidators.normalizePhone(_phone.text),
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
            : 'Modifie ton nom et ton téléphone facultatif.',
      ),
      Form(
        key: _form,
        child: ProfileFields(
          name: _name,
          phone: _phone,
          enabled: !busy,
          optional: widget.user.hasGoogle,
        ),
      ),
      if (!widget.onboarding) ...[
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('accountEmail'),
          initialValue: widget.user.email,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        if (widget.user.hasPassword)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PasswordResetScreen(
                          repository: widget.repository,
                          initialEmail: widget.user.email,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.lock_reset),
              label: const Text('Réinitialiser mon mot de passe'),
            ),
          ),
      ],
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
  late Future<LegalDocuments> _legal = widget.repository.loadLegalDocuments();
  String _path = 'client';
  bool _accepted = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<LegalDocuments>(
    future: _legal,
    builder: (context, snapshot) => AuthLayout(
      title: 'Bienvenue sur Foundi',
      children: [
        AuthHeading(
          title: 'C’est ta première visite',
          description:
              'Souhaites-tu créer ton compte Foundi avec ${widget.user.email} ?',
          icon: Icons.person_add_alt_outlined,
        ),
        const Text(
          'Tu pourras compléter ton téléphone et activer un profil professionnel dans ton compte.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 20),
        PathChoice(
          title: 'Je cherche un service',
          description: 'Publier mes besoins et recevoir des offres',
          icon: Icons.search,
          selected: _path == 'client',
          onTap: busy ? null : () => setState(() => _path = 'client'),
        ),
        PathChoice(
          title: 'Je suis professionnel',
          description: 'Répondre aux demandes de clients',
          icon: Icons.work_outline,
          selected: _path == 'professional',
          onTap: busy ? null : () => setState(() => _path = 'professional'),
        ),
        if (snapshot.hasData)
          LegalConsent(
            documents: snapshot.requireData,
            accepted: _accepted,
            onChanged: busy ? null : (v) => setState(() => _accepted = v),
          )
        else if (snapshot.hasError)
          TextButton(
            onPressed: () =>
                setState(() => _legal = widget.repository.loadLegalDocuments()),
            child: const Text('Réessayer de charger les conditions'),
          )
        else
          const LinearProgressIndicator(),
        AuthNotice(error),
        const SizedBox(height: 28),
        AuthButton(
          label: 'Créer mon compte',
          busy: busy,
          onPressed:
              !snapshot.hasData ||
                  (snapshot.requireData.published && !_accepted)
              ? null
              : () => perform(
                  () => widget.repository.confirmGoogleRegistration(
                    registrationPath: _path,
                    termsVersion: snapshot.requireData.version,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: busy ? null : () => perform(widget.repository.signOut),
          child: const Text('Revenir à la connexion'),
        ),
      ],
    ),
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
      const SafetyAppealButton(),
      const SizedBox(height: 12),
      TextButton(
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        child: const Text('Revenir à la connexion'),
      ),
    ],
  );
}
