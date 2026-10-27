import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_validators.dart';

abstract class AuthActionState<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;

  Future<bool> perform(Future<void> Function() operation) async {
    if (busy) return false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      return true;
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Une erreur est survenue. Vérifie ta connexion puis réessaie.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    return false;
  }
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.children,
    this.onBack,
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      backgroundColor: Colors.transparent,
      leading: onBack == null
          ? null
          : IconButton(
              tooltip: 'Retour',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
      actions: actions,
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthHeading extends StatelessWidget {
  const AuthHeading({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.person_outline,
  });
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 30,
        backgroundColor: const Color(0xFFDEF4EA),
        child: Icon(icon, color: const Color(0xFF107865), size: 30),
      ),
      const SizedBox(height: 24),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      Text(
        description,
        style: const TextStyle(height: 1.5, color: Color(0xFF647D75)),
      ),
      const SizedBox(height: 28),
    ],
  );
}

class AuthNotice extends StatelessWidget {
  const AuthNotice(this.message, {super.key, this.isError = true});
  final String? message;
  final bool isError;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFFFECE7)
                    : const Color(0xFFDEF4EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message!,
                style: TextStyle(
                  color: isError
                      ? const Color(0xFF9E3025)
                      : const Color(0xFF153F38),
                  height: 1.5,
                ),
              ),
            ),
          ),
        );
}

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label),
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.fieldKey,
    this.label = 'Mot de passe',
    this.newPassword = false,
    this.enabled = true,
    this.validator,
  });
  final TextEditingController controller;
  final String fieldKey;
  final String label;
  final bool newPassword;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(widget.fieldKey),
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: TextInputAction.done,
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: _hidden
            ? 'Afficher le mot de passe'
            : 'Masquer le mot de passe',
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}

class ProfileFields extends StatelessWidget {
  const ProfileFields({
    super.key,
    required this.name,
    required this.phone,
    required this.profession,
    this.enabled = true,
    this.optional = false,
  });
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController profession;
  final bool enabled;
  final bool optional;

  String? _validate(String? value, FormFieldValidator<String> validator) =>
      optional && (value?.trim().isEmpty ?? true) ? null : validator(value);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        key: const ValueKey('fullName'),
        controller: name,
        enabled: enabled,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Nom complet'),
        validator: (value) => _validate(value, AuthValidators.fullName),
      ),
      const SizedBox(height: 18),
      TextFormField(
        key: const ValueKey('phone'),
        controller: phone,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Numéro de téléphone',
          hintText: '+2250700000000',
          helperText: 'Avec l’indicatif du pays. Aucun SMS ne sera envoyé.',
          helperMaxLines: 2,
        ),
        validator: (value) => _validate(value, AuthValidators.phone),
      ),
      const SizedBox(height: 18),
      TextFormField(
        key: const ValueKey('profession'),
        controller: profession,
        enabled: enabled,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Profession / activité',
          hintText: 'Ex. : étudiant, commerçant, plombier',
        ),
        validator: (value) => _validate(value, AuthValidators.profession),
      ),
    ],
  );
}
