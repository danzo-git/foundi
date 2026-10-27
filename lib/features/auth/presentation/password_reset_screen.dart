import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.repository,
    this.initialEmail = '',
    this.defining = false,
  });
  final AuthRepository repository;
  final String initialEmail;
  final bool defining;
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends AuthActionState<PasswordResetScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sent = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (await perform(() => widget.repository.sendPasswordReset(_email.text)) &&
        mounted) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: widget.defining ? 'Définir mon mot de passe' : 'Mot de passe oublié',
    children: [
      AuthHeading(
        title: widget.defining ? 'Conserve ton compte' : 'Retrouve ton compte',
        description: widget.defining
            ? 'Reçois un lien pour définir ton mot de passe et retrouver le même compte Foundi.'
            : 'Reçois un lien par e-mail pour choisir un nouveau mot de passe.',
        icon: Icons.lock_reset,
      ),
      Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('resetEmail'),
          controller: _email,
          enabled: !busy && !_sent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Adresse e-mail'),
          validator: AuthValidators.email,
        ),
      ),
      AuthNotice(error),
      if (_sent)
        const AuthNotice(
          'Si cette adresse correspond à un compte, un lien a été envoyé. Vérifie aussi les courriers indésirables, puis reviens te connecter avec ton mot de passe.',
          isError: false,
        ),
      const SizedBox(height: 24),
      if (!_sent)
        AuthButton(label: 'Envoyer le lien', busy: busy, onPressed: _send)
      else
        AuthButton(
          label: 'Retour à la connexion',
          onPressed: () => Navigator.of(context).pop(),
        ),
    ],
  );
}
