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
    this.footer,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final List<Widget>? footer;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF087F70),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Text(
              'F',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Foundi',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
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
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...children,
                    if (footer != null) ...[
                      const SizedBox(height: 28),
                      ...footer!,
                    ],
                  ],
              ),
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
    this.enabled = true,
    this.optional = false,
  });
  final TextEditingController name;
  final TextEditingController phone;
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
          labelText: 'Téléphone (facultatif)',
          hintText: '+2250700000000',
          helperText: 'Avec l’indicatif du pays. Aucun SMS ne sera envoyé.',
          helperMaxLines: 2,
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? null
            : AuthValidators.phone(value),
      ),
    ],
  );
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress(this.step, {super.key});
  final int step;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Étape $step sur 3',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Row(
        children: List.generate(
          3,
          (index) => Expanded(
            child: Container(
              height: 5,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
              decoration: BoxDecoration(
                color: index < step
                    ? const Color(0xFF087F70)
                    : const Color(0xFFD7E6E0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ],
  );
}

class PathChoice extends StatelessWidget {
  const PathChoice({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String title, description;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFFDEF4EA) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? const Color(0xFF43A891) : const Color(0xFFDCE7E2),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : const Color(0xFFDEF4EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF107865)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xFF647D75),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (badge != null)
                  Text(
                    badge!,
                    style: const TextStyle(
                      color: Color(0xFF107865),
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected
                        ? const Color(0xFF107865)
                        : const Color(0xFFDCE7E2),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class LegalConsent extends StatelessWidget {
  const LegalConsent({
    super.key,
    required this.documents,
    required this.accepted,
    required this.onChanged,
  });
  final LegalDocuments documents;
  final bool accepted;
  final ValueChanged<bool>? onChanged;
  void _show(BuildContext context, String title, String text) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => !documents.published
      ? const AuthNotice(
          'Les CGU et la politique de confidentialité sont en préparation. Leur acceptation sera demandée après publication, avant la soumission professionnelle.',
          isError: false,
        )
      : Column(
          children: [
            CheckboxListTile(
              key: const ValueKey('acceptTerms'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: accepted,
              onChanged: onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
              title: const Text(
                'J’accepte les CGU et la politique de confidentialité',
                style: TextStyle(fontSize: 13),
              ),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => _show(context, 'CGU', documents.terms),
                  child: const Text('Lire les CGU'),
                ),
                TextButton(
                  onPressed: () => _show(
                    context,
                    'Politique de confidentialité',
                    documents.privacy,
                  ),
                  child: const Text('Confidentialité'),
                ),
              ],
            ),
          ],
        );
}
