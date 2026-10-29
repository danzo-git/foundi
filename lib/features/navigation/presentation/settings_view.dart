import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/account_screen.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../auth/presentation/legal_acceptance_screen.dart';
import '../../professional/domain/professional_repository.dart';
import '../../professional/presentation/professional_status_label.dart';
import 'space_widgets.dart';

class FoundiSettings extends StatelessWidget {
  const FoundiSettings({
    super.key,
    required this.user,
    required this.professional,
    required this.professionalSpace,
    required this.onSpaces,
    required this.onDossier,
    required this.onActivity,
    required this.onSignOut,
    this.busy = false,
    this.error,
  });
  final FoundiUser user;
  final ProfessionalProfile professional;
  final bool professionalSpace, busy;
  final String? error;
  final VoidCallback onSpaces, onDossier, onActivity, onSignOut;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Compte et préférences',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: FoundiUi.ink,
          ),
        ),
        heading('MON PROFIL'),
        group([
          row(
            Icons.person_outline,
            'Informations personnelles',
            'Nom, e-mail, téléphone',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(
                  user: user,
                  repository: AuthScope.of(context),
                ),
              ),
            ),
          ),
          if (professional.status != ProfessionalStatus.none)
            row(
              Icons.work_outline,
              'Informations professionnelles',
              'Spécialités et zones',
              onActivity,
            ),
          row(
            Icons.verified_outlined,
            professional.status == ProfessionalStatus.none
                ? 'Devenir professionnel'
                : 'Statut et vérification',
            professionalStatusLabel(professional.status),
            onDossier,
          ),
        ]),
        heading('MES ESPACES'),
        group([
          row(
            Icons.swap_horiz,
            'Gérer mes espaces',
            'Actuel : ${professionalSpace ? 'Professionnel' : 'Client'}',
            onSpaces,
          ),
        ]),
        heading('PRÉFÉRENCES ET SÉCURITÉ'),
        group([
          row(
            Icons.notifications_none,
            'Notifications',
            'Préférences · Bientôt disponible',
            () => showComingSoon(context),
          ),
          row(
            Icons.shield_outlined,
            'Confidentialité et CGU',
            'Données, sécurité, conditions',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    LegalAcceptanceScreen(repository: AuthScope.of(context)),
              ),
            ),
          ),
        ]),
        AuthNotice(error),
        const SizedBox(height: 18),
        TextButton(
          key: const ValueKey('settingsSignOut'),
          onPressed: busy ? null : onSignOut,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB43B47)),
          child: Text(busy ? 'Déconnexion…' : 'Se déconnecter'),
        ),
      ],
    ),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: FoundiUi.muted,
      ),
    ),
  );
  Widget group(List<Widget> rows) => FoundiPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, widget) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: FoundiUi.line),
          widget,
        ],
      ],
    ),
  );
  Widget row(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    dense: true,
    minTileHeight: 60,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    leading: Icon(icon, size: 21, color: FoundiUi.green),
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: FoundiUi.ink,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 11, color: FoundiUi.muted),
    ),
    trailing: const Icon(Icons.chevron_right, color: FoundiUi.muted, size: 20),
    onTap: action,
  );
}

// Presentation-only dependency scope; existing repository actions are unchanged.
class AuthScope extends InheritedWidget {
  const AuthScope({super.key, required this.repository, required super.child});
  final AuthRepository repository;
  static AuthRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()!.repository;
  @override
  bool updateShouldNotify(AuthScope oldWidget) =>
      oldWidget.repository != repository;
}
