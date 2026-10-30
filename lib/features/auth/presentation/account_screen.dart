import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';
import 'password_reset_screen.dart';

import '../../professional/domain/professional_repository.dart';
import '../../professional/presentation/professional_status_label.dart';
import '../../navigation/presentation/space_widgets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.professional,
    required this.professionalSpace,
    required this.onSpaces,
    required this.onDossier,
    required this.onActivity,
    this.onPublish,
    this.onRequests,
  });
  final FoundiUser user;
  final ProfessionalProfile professional;
  final bool professionalSpace;
  final VoidCallback onSpaces, onDossier, onActivity;
  final VoidCallback? onPublish, onRequests;
  @override
  Widget build(BuildContext context) {
    final personalName = user.profile.fullName.isNotEmpty
        ? user.profile.fullName
        : user.displayName ?? '';
    final name = professional.activity.businessName.isNotEmpty
        ? professional.activity.businessName
        : personalName;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final hasDossier = professional.status != ProfessionalStatus.none;
    final approved = professional.approved;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Mon compte',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: FoundiUi.ink,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: FoundiUi.tint,
                child: Text(
                  initials.isEmpty ? 'F' : initials,
                  style: const TextStyle(
                    color: FoundiUi.green,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Mon compte' : name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: FoundiUi.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: const TextStyle(
                        fontSize: 11,
                        color: FoundiUi.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (approved || !hasDossier)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: FoundiUi.tint,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (approved) ...[
                              const Icon(
                                Icons.check,
                                size: 13,
                                color: FoundiUi.green,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                approved
                                    ? 'Professionnel vérifié'
                                    : 'Compte client',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: FoundiUi.green,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        professional.status == ProfessionalStatus.rejected ||
                                professional.status ==
                                    ProfessionalStatus.suspended
                            ? professionalStatusLabel(professional.status)
                            : 'Dossier professionnel en cours',
                        style: const TextStyle(
                          fontSize: 12,
                          color: FoundiUi.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (hasDossier && !approved) ...[
            FoundiPanel(
              color: const Color(0xFFFFF0D8),
              onTap: onDossier,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    professionalStatusLabel(professional.status),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: FoundiUi.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ton espace client reste disponible. L’espace professionnel nécessite une approbation.',
                    style: TextStyle(
                      fontSize: 13,
                      color: FoundiUi.muted,
                      height: 1.4,
                    ),
                  ),
                  if (professional.reviewReason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      professional.reviewReason,
                      style: const TextStyle(fontSize: 13, color: FoundiUi.ink),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Suivre mon dossier  ›',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FoundiUi.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (approved || !hasDossier)
            FoundiPanel(
              color: FoundiUi.soft,
              onTap: approved ? onSpaces : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mon espace actuel',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: FoundiUi.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    professionalSpace ? 'Professionnel' : 'Client',
                    key: const ValueKey('currentSpace'),
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                      color: FoundiUi.ink,
                    ),
                  ),
                  if (approved) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Changer d’espace  ›',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: FoundiUi.green,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  const Text(
                    'Mon espace actuel : ',
                    style: TextStyle(fontSize: 12, color: FoundiUi.muted),
                  ),
                  const Text(
                    'Client',
                    key: ValueKey('currentSpace'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FoundiUi.green,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          if (onRequests != null) ...[
            FoundiPanel(
              onTap: onRequests,
              padding: EdgeInsets.zero,
              child: const ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: FoundiUi.green,
                ),
                title: Text('Mes demandes'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (approved || !hasDossier) ...[
            const Text(
              'Vue d’ensemble',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: FoundiUi.ink,
              ),
            ),
            const SizedBox(height: 18),
            const FutureOverview(),
            const SizedBox(height: 32),
          ] else ...[
            const Text(
              'Mes fonctionnalités',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: FoundiUi.ink,
              ),
            ),
            const SizedBox(height: 18),
            FoundiPanel(
              onTap: onPublish ?? () => showComingSoon(context),
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.add, color: FoundiUi.green),
                title: Text(
                  'Publier',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  onPublish == null
                      ? 'Bientôt disponible'
                      : 'Exprimer un besoin',
                  style: TextStyle(fontSize: 12, color: FoundiUi.muted),
                ),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Les propositions restent bloquées jusqu’à validation.',
              style: TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
          ],
          if (approved)
            FoundiPanel(
              onTap: onActivity,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Votre activité',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: FoundiUi.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          professional.activity.businessName.isEmpty
                              ? 'Informations professionnelles'
                              : professional.activity.businessName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: FoundiUi.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: FoundiUi.muted),
                ],
              ),
            )
          else if (!hasDossier)
            FoundiPanel(
              onTap: onDossier,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.work_outline, color: FoundiUi.green),
                title: Text(
                  'Devenir professionnel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FoundiUi.ink,
                  ),
                ),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
          const SizedBox(height: 28),
          const Text(
            'Les réglages sont accessibles via l’engrenage.',
            style: TextStyle(fontSize: 11, color: FoundiUi.muted),
          ),
        ],
      ),
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
      TextButton(
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        child: const Text('Revenir à la connexion'),
      ),
    ],
  );
}
