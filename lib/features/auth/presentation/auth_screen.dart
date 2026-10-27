import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';
import 'password_reset_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends AuthActionState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _profession = TextEditingController();
  bool _registering = false;
  int _step = 0;

  @override
  void dispose() {
    for (final controller in [
      _email,
      _password,
      _confirmation,
      _name,
      _phone,
      _profession,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _switchMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      _registering = !_registering;
      _step = 0;
      error = null;
      _password.clear();
      _confirmation.clear();
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_registering && _step == 0) {
      setState(() {
        _step = 1;
        error = null;
      });
      return;
    }
    final success = await perform(
      () => _registering
          ? widget.repository.registerWithPassword(
              email: _email.text,
              password: _password.text,
              profile: AccountProfile(
                fullName: _name.text.trim(),
                phone: AuthValidators.normalizePhone(_phone.text),
                profession: _profession.text.trim(),
                registrationConfirmed: true,
              ),
            )
          : widget.repository.signInWithPassword(_email.text, _password.text),
    );
    if (success && mounted) {
      _password.clear();
      _confirmation.clear();
    }
  }

  void _resetPassword(bool defining) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordResetScreen(
          repository: widget.repository,
          initialEmail: _email.text,
          defining: defining,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_registering,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) {
        if (_step == 1) {
          setState(() {
            _step = 0;
            error = null;
          });
        } else {
          _switchMode();
        }
      }
    },
    child: AuthLayout(
      title: _registering ? 'Créer un compte' : 'Se connecter',
      onBack: _registering && !busy
          ? () {
              if (_step == 1) {
                setState(() {
                  _step = 0;
                  error = null;
                });
              } else {
                _switchMode();
              }
            }
          : null,
      children: [
        AuthHeading(
          title: _registering
              ? (_step == 0 ? 'Faisons connaissance' : 'Sécurise ton compte')
              : 'Heureux de te retrouver',
          description: _registering
              ? (_step == 0
                    ? 'Renseigne tes informations pour créer ton compte Foundi.'
                    : 'Choisis tes identifiants. Nous vérifierons ensuite ton adresse e-mail.')
              : 'Connecte-toi pour retrouver tes recherches et tes échanges.',
          icon: _registering ? Icons.person_add_alt_outlined : Icons.login,
        ),
        if (_registering) ...[
          Text(
            'Étape ${_step + 1} sur 3',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: (_step + 1) / 3),
          const SizedBox(height: 24),
        ],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              key: ValueKey('$_registering-$_step'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_registering && _step == 0)
                  ProfileFields(
                    name: _name,
                    phone: _phone,
                    profession: _profession,
                    enabled: !busy,
                  )
                else ...[
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
                      hintText: 'toi@exemple.com',
                    ),
                    validator: AuthValidators.email,
                  ),
                  const SizedBox(height: 18),
                  PasswordField(
                    fieldKey: 'password',
                    controller: _password,
                    enabled: !busy,
                    newPassword: _registering,
                    validator: _registering
                        ? AuthValidators.password
                        : AuthValidators.loginPassword,
                  ),
                  if (_registering) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Au moins 12 caractères.',
                        style: TextStyle(color: Color(0xFF647D75)),
                      ),
                    ),
                    PasswordField(
                      fieldKey: 'passwordConfirmation',
                      controller: _confirmation,
                      label: 'Confirmer le mot de passe',
                      newPassword: true,
                      enabled: !busy,
                      validator: (value) => value == _password.text
                          ? null
                          : 'Les mots de passe ne correspondent pas.',
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : () => _resetPassword(false),
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        AuthNotice(error),
        const SizedBox(height: 24),
        AuthButton(
          key: const ValueKey('submitAuth'),
          label: _registering
              ? (_step == 0 ? 'Continuer' : 'Créer mon compte')
              : 'Se connecter',
          busy: busy,
          onPressed: _submit,
        ),
        if (!_registering || _step == 0) ...[
          const SizedBox(height: 24),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('ou'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const ValueKey('googleAuth'),
            onPressed: busy
                ? null
                : () => perform(
                    () => widget.repository.signInWithGoogle(
                      registering: _registering,
                    ),
                  ),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(
              _registering
                  ? 'S’inscrire avec Google'
                  : 'Se connecter avec Google',
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          _registering ? 'Tu as déjà un compte ?' : 'Tu découvres Foundi ?',
          textAlign: TextAlign.center,
        ),
        TextButton(
          key: const ValueKey('switchAuthMode'),
          onPressed: busy ? null : _switchMode,
          child: Text(_registering ? 'Se connecter' : 'Créer un compte'),
        ),
        if (!_registering)
          TextButton(
            key: const ValueKey('setupPassword'),
            onPressed: busy ? null : () => _resetPassword(true),
            child: const Text(
              'Compte créé avec un code ? Définir mon mot de passe',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
}
