import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/foundi_shell.dart';
import '../domain/professional_repository.dart';
import 'professional_onboarding.dart';
import 'professional_status_label.dart';
import '../../requests/domain/request_repository.dart';

class ProfessionalGate extends StatefulWidget {
  const ProfessionalGate({
    super.key,
    required this.user,
    required this.auth,
    required this.repository,
    this.requestRepository,
  });
  final FoundiUser user;
  final AuthRepository auth;
  final ProfessionalRepository repository;
  final RequestRepository? requestRepository;
  @override
  State<ProfessionalGate> createState() => _ProfessionalGateState();
}

class _ProfessionalGateState extends AuthActionState<ProfessionalGate> {
  late Stream<ProfessionalProfile> _stream = widget.repository.watchProfile(
    widget.user.id,
  );
  String _view = 'auto';
  bool _starting = false;
  void _show(String view) => setState(() {
    _view = view;
    error = null;
  });
  Future<void> _start() async {
    final ok = await perform(widget.repository.start);
    if (ok && mounted) _show('edit');
  }

  void _openDossier(ProfessionalProfile p) {
    if (p.status == ProfessionalStatus.none) {
      _start();
    } else if (p.status == ProfessionalStatus.draft ||
        p.status == ProfessionalStatus.needsChanges) {
      _show('edit');
    } else {
      _show('dossier');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ProfessionalProfile>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _loadError();
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final profile = snapshot.requireData;
      if (profile.status == ProfessionalStatus.none &&
          widget.user.profile.registrationPath == 'professional' &&
          _view == 'auto') {
        if (!_starting) {
          _starting = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _start();
          });
        }
        return AuthLayout(
          title: 'Profil professionnel',
          children: [
            const AuthHeading(
              title: 'Préparons ton dossier',
              description: 'Ton compte client est déjà créé.',
            ),
            AuthNotice(error),
            if (busy)
              const LinearProgressIndicator()
            else
              AuthButton(label: 'Réessayer', onPressed: _start),
            TextButton(
              onPressed: () => _show('client'),
              child: const Text('Continuer comme client'),
            ),
          ],
        );
      }
      Widget? overlay;
      // The Firestore snapshot can arrive before the callable response, or
      // after a response was lost. The saved draft is the source of truth.
      final resumeRegistration =
          _view == 'auto' &&
          widget.user.profile.registrationPath == 'professional';
      if ((_view == 'edit' || resumeRegistration) &&
          (profile.status == ProfessionalStatus.draft ||
              profile.status == ProfessionalStatus.needsChanges)) {
        overlay = ProfessionalOnboarding(
          key: ValueKey(widget.user.id),
          user: widget.user,
          auth: widget.auth,
          repository: widget.repository,
          profile: profile,
          onExit: () => _show('client'),
        );
      } else if (_view == 'dossier') {
        overlay = _dossier(profile);
      }
      // Keep the UI-only space and tab mounted while reusing the existing dossier form.
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: overlay != null,
            child: FoundiShell(
              key: ValueKey('shell-${widget.user.id}'),
              user: widget.user,
              auth: widget.auth,
              professional: profile,
              professionalRepository: widget.repository,
              requestRepository: widget.requestRepository,
              catalogRepository: widget.repository,
              onDossier: () => _openDossier(profile),
              active: overlay == null,
            ),
          ),
          ?overlay,
        ],
      );
    },
  );
  Widget _dossier(ProfessionalProfile profile) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _show('auto');
    },
    child: AuthLayout(
      title: 'Statut du dossier',
      onBack: () => _show('auto'),
      footer: [
        AuthButton(label: 'Retour à l’accueil', onPressed: () => _show('auto')),
      ],
      children: [
        AuthHeading(
          title: professionalStatusLabel(profile.status),
          description: profile.status == ProfessionalStatus.pending
              ? 'Nous examinons ton profil professionnel.'
              : 'Retrouve ici le résultat de la vérification.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFDEF4EA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(
                profile.approved
                    ? Icons.verified_user_outlined
                    : Icons.schedule,
                size: 40,
                color: const Color(0xFF107865),
              ),
              const SizedBox(height: 20),
              Text(
                profile.approved
                    ? 'Compte professionnel vérifié'
                    : 'Ton compte client reste accessible.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (profile.reviewReason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(profile.reviewReason),
              ],
              const SizedBox(height: 12),
              Text(
                profile.approved
                    ? 'Les espaces Client et Professionnel sont accessibles depuis ton compte.'
                    : 'Le mode professionnel reste verrouillé tant que le dossier n’est pas approuvé.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _loadError() => AuthLayout(
    title: 'Mon compte',
    children: [
      const AuthHeading(
        title: 'Dossier indisponible',
        description: 'Vérifie ta connexion puis réessaie.',
      ),
      AuthButton(
        label: 'Réessayer',
        onPressed: () => setState(
          () => _stream = widget.repository.watchProfile(widget.user.id),
        ),
      ),
      TextButton(
        onPressed: () => perform(widget.auth.signOut),
        child: const Text('Se déconnecter'),
      ),
    ],
  );
}
