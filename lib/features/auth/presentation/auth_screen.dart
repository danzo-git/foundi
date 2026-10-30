import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';
import 'password_reset_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.repository, this.onExplore});
  final AuthRepository repository;
  final VoidCallback? onExplore;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends AuthActionState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  final _name = TextEditingController(), _phone = TextEditingController();
  // 0: common login, 1: choice of path, 2: account creation.
  int _page = 0;
  String? _path;
  bool _accepted = false;
  LegalDocuments? _legal;
  bool _loadingLegal = false;
  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    setState(() {
      _page = page;
      error = null;
      _password.clear();
    });
    if (page == 2 && _legal == null) _loadLegal();
  }

  Future<void> _loadLegal() async {
    setState(() => _loadingLegal = true);
    await perform(() async {
      final documents = await widget.repository.loadLegalDocuments();
      if (mounted) setState(() => _legal = documents);
    });
    if (mounted) setState(() => _loadingLegal = false);
  }

  bool _consentReady() {
    if (_legal == null) {
      setState(() => error = 'Charge les conditions avant de continuer.');
      return false;
    }
    if (_legal!.published && !_accepted) {
      setState(
        () => error = 'Accepte les CGU et la politique de confidentialité.',
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_page == 2 && !_consentReady()) return;
    await perform(
      () => _page == 2
          ? widget.repository.registerWithPassword(
              email: _email.text,
              password: _password.text,
              profile: AccountProfile(
                fullName: _name.text.trim(),
                phone: AuthValidators.normalizePhone(_phone.text),
                registrationConfirmed: true,
                registrationPath: _path ?? 'client',
                termsVersion: _legal!.published ? _legal!.version : '',
              ),
            )
          : widget.repository.signInWithPassword(_email.text, _password.text),
    );
  }

  Future<void> _google() async {
    if (_page == 2 && !_consentReady()) return;
    await perform(
      () => widget.repository.signInWithGoogle(
        registering: _page == 2,
        registrationPath: _path ?? 'client',
        termsVersion: _page == 2 && _legal!.published ? _legal!.version : '',
      ),
    );
  }

  void _reset(bool defining) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PasswordResetScreen(
        repository: widget.repository,
        initialEmail: _email.text,
        defining: defining,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _page == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) _go(_page - 1);
    },
    child: _page == 1 ? _choice() : _credentials(),
  );
  Widget _choice() => AuthLayout(
    title: 'Créer un compte',
    onBack: () => _go(0),
    footer: [
      const AuthNotice(
        'Tu pourras utiliser les deux espaces avec un seul compte.',
        isError: false,
      ),
      AuthButton(
        key: const ValueKey('continuePath'),
        label: 'Continuer',
        onPressed: _path == null ? null : () => _go(2),
      ),
    ],
    children: [
      const AuthHeading(
        title: 'Créer un compte',
        description: 'Comment souhaites-tu utiliser Foundi ?',
      ),
      PathChoice(
        key: const ValueKey('clientPath'),
        title: 'Je cherche un service',
        description: 'Publier mes besoins et recevoir des offres',
        icon: Icons.search,
        selected: _path == 'client',
        onTap: () => setState(() => _path = 'client'),
      ),
      PathChoice(
        key: const ValueKey('professionalPath'),
        title: 'Je suis professionnel',
        description: 'Répondre aux demandes de clients',
        icon: Icons.work_outline,
        selected: _path == 'professional',
        onTap: () => setState(() => _path = 'professional'),
      ),
      TextButton(
        onPressed: () => _go(0),
        child: const Text('Déjà inscrit ? Se connecter'),
      ),
    ],
  );
  Widget _credentials() {
    final registering = _page == 2;
    return AuthLayout(
      title: registering ? 'Créer un compte' : 'Se connecter',
      onBack: registering && !busy ? () => _go(1) : null,
      footer: [
        AuthButton(
          key: const ValueKey('submitAuth'),
          label: registering ? 'Continuer' : 'Se connecter',
          busy: busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text('ou'),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('googleAuth'),
          onPressed: busy ? null : _google,
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(
            registering ? 'Continuer avec Google' : 'Se connecter avec Google',
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          key: const ValueKey('switchAuthMode'),
          onPressed: busy ? null : () => _go(registering ? 0 : 1),
          child: Text(
            registering
                ? 'Déjà inscrit ? Se connecter'
                : 'Tu découvres Foundi ? Créer un compte',
          ),
        ),
        if (!registering) ...[
          if (widget.onExplore != null)
            TextButton(
              onPressed: busy ? null : widget.onExplore,
              child: const Text('Explorer sans compte'),
            ),
          const Text(
            'Même connexion pour clients et professionnels.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF647D75)),
          ),
          TextButton(
            key: const ValueKey('setupPassword'),
            onPressed: busy ? null : () => _reset(true),
            child: const Text(
              'Compte créé avec un code ? Définir mon mot de passe',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
      children: [
        AuthHeading(
          title: registering
              ? 'Faisons connaissance'
              : 'Heureux de te retrouver',
          description: registering
              ? 'Créons ton compte Foundi.'
              : 'Connecte-toi pour retrouver tes échanges.',
        ),
        if (registering && _path == 'professional') const OnboardingProgress(1),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (registering) ...[
                  TextFormField(
                    key: const ValueKey('fullName'),
                    controller: _name,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Nom complet ou nom affiché',
                      hintText: 'Ton nom',
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: AuthValidators.fullName,
                  ),
                  const SizedBox(height: 18),
                ],
                TextFormField(
                  key: const ValueKey('email'),
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    hintText: 'nom@exemple.com',
                  ),
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: 18),
                PasswordField(
                  fieldKey: 'password',
                  controller: _password,
                  enabled: !busy,
                  newPassword: registering,
                  validator: registering
                      ? AuthValidators.password
                      : AuthValidators.loginPassword,
                ),
                if (registering) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Au moins 12 caractères.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF647D75)),
                    ),
                  ),
                  TextFormField(
                    key: const ValueKey('phone'),
                    controller: _phone,
                    enabled: !busy,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Téléphone (+225) · facultatif',
                      hintText: '+2250700000000',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? null
                        : AuthValidators.phone(v),
                  ),
                  const SizedBox(height: 12),
                  if (_legal != null)
                    LegalConsent(
                      documents: _legal!,
                      accepted: _accepted,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _accepted = v),
                    )
                  else if (_loadingLegal)
                    const LinearProgressIndicator()
                  else
                    TextButton(
                      onPressed: _loadLegal,
                      child: const Text('Réessayer de charger les conditions'),
                    ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : () => _reset(false),
                      child: const Text('Mot de passe oublié ?'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AuthNotice(error),
      ],
    );
  }
}
