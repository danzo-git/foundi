import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.repository,
    required this.user,
  });
  final AuthRepository repository;
  final FoundiUser user;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends AuthActionState<VerificationScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  EmailChallenge? _challenge;
  Timer? _ticker;
  bool get _expired =>
      _challenge != null && !DateTime.now().isBefore(_challenge!.expiresAt);
  int get _seconds {
    final ms =
        _challenge?.resendAt.difference(DateTime.now()).inMilliseconds ?? 0;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    await perform(() async {
      final challenge = await widget.repository.requestEmailCode();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _code.clear();
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() {});
        if (_expired && _seconds == 0) timer.cancel();
      });
    });
  }

  Future<void> _verify() async {
    if (_challenge == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await perform(
      () => widget.repository.verifyEmailCode(_challenge!, _code.text),
    );
  }

  void _correctEmail() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChangeEmailScreen(
          repository: widget.repository,
          email: widget.user.email,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Vérifier mon e-mail',
    actions: [
      IconButton(
        tooltip: 'Se déconnecter',
        onPressed: busy ? null : () => perform(widget.repository.signOut),
        icon: const Icon(Icons.logout),
      ),
    ],
    children: [
      AuthHeading(
        title: 'Une dernière étape',
        description:
            'Confirme ton adresse ${widget.user.email} avec le code à six chiffres reçu par e-mail.',
        icon: Icons.mark_email_read_outlined,
      ),
      const Text(
        'Étape 3 sur 3',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      const LinearProgressIndicator(value: 1),
      const SizedBox(height: 28),
      if (_challenge != null)
        Form(
          key: _form,
          child: TextFormField(
            key: const ValueKey('code'),
            controller: _code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              labelText: 'Code de vérification',
              hintText: '000000',
            ),
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : 'Saisis les six chiffres reçus.',
            onFieldSubmitted: (_) {
              if (!busy && !_expired) _verify();
            },
          ),
        ),
      AuthNotice(
        error ??
            (_expired ? 'Ce code a expiré. Demande un nouveau code.' : null),
      ),
      const SizedBox(height: 24),
      AuthButton(
        label: _challenge == null ? 'Recevoir mon code' : 'Valider mon e-mail',
        busy: busy,
        onPressed: _expired ? null : (_challenge == null ? _send : _verify),
      ),
      if (_challenge != null) ...[
        const SizedBox(height: 12),
        TextButton(
          onPressed: busy || _seconds > 0 ? null : _send,
          child: Text(
            _seconds > 0
                ? 'Renvoyer un code dans ${_seconds}s'
                : 'Renvoyer un code',
          ),
        ),
      ],
      const SizedBox(height: 12),
      const Text(
        'Le code est valable 10 minutes. Pense à vérifier les courriers indésirables.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF647D75), height: 1.5),
      ),
      TextButton(
        onPressed: busy ? null : _correctEmail,
        child: const Text('Corriger mon adresse e-mail'),
      ),
      TextButton(
        onPressed: busy ? null : () => perform(widget.repository.refreshUser),
        child: const Text('Actualiser la vérification'),
      ),
    ],
  );
}

class _ChangeEmailScreen extends StatefulWidget {
  const _ChangeEmailScreen({required this.repository, required this.email});
  final AuthRepository repository;
  final String email;
  @override
  State<_ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends AuthActionState<_ChangeEmailScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final success = await perform(
      () => widget.repository.changeRegistrationEmail(
        _email.text,
        _password.text,
      ),
    );
    if (success && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Corriger mon adresse',
    children: [
      const AuthHeading(
        title: 'La bonne adresse',
        description:
            'Confirme ton mot de passe pour recevoir le code sur ta nouvelle adresse.',
      ),
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const ValueKey('newEmail'),
              controller: _email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 18),
            PasswordField(
              fieldKey: 'currentPassword',
              controller: _password,
              enabled: !busy,
              validator: AuthValidators.loginPassword,
            ),
          ],
        ),
      ),
      AuthNotice(error),
      const SizedBox(height: 24),
      AuthButton(label: 'Modifier mon adresse', busy: busy, onPressed: _save),
    ],
  );
}
