import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import 'auth_widgets.dart';
import '../../safety/presentation/safety_widgets.dart';

class LegalAcceptanceScreen extends StatefulWidget {
  const LegalAcceptanceScreen({
    super.key,
    required this.repository,
    this.readOnly = false,
    this.document,
  });
  final AuthRepository repository;
  final bool readOnly;
  final String? document;
  @override
  State<LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState
    extends AuthActionState<LegalAcceptanceScreen> {
  late Future<LegalDocuments> _future = widget.repository.loadLegalDocuments();
  bool _accepted = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<LegalDocuments>(
    future: _future,
    builder: (context, s) => AuthLayout(
      title: 'CGU et confidentialité',
      footer: [
        if (!widget.readOnly && s.data?.published == true)
          AuthButton(
            label: 'Accepter et continuer',
            busy: busy,
            onPressed: !_accepted
                ? null
                : () async {
                    final ok = await perform(
                      () =>
                          widget.repository.acceptLegal(s.requireData.version),
                    );
                    if (ok && context.mounted) Navigator.pop(context);
                  },
          ),
      ],
      children: [
        const Text(foundiConductRules),
        const SizedBox(height: 16),
        const AuthHeading(
          title: 'Tes conditions d’utilisation',
          description: 'Consulte les textes publiés par Foundi.',
        ),
        if (s.hasData && widget.readOnly) ...[
          Text('Version : ${s.requireData.version}'),
          const SizedBox(height: 12),
          if (widget.document != 'privacy') ...[
            const Text(
              'Conditions générales d’utilisation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(s.requireData.terms),
          ],
          if (widget.document != 'terms') ...[
            const SizedBox(height: 24),
            const Text(
              'Politique de confidentialité',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(s.requireData.privacy),
          ],
        ] else if (s.hasData)
          LegalConsent(
            documents: s.requireData,
            accepted: _accepted,
            onChanged: busy ? null : (v) => setState(() => _accepted = v),
          )
        else if (s.hasError)
          TextButton(
            onPressed: () => setState(
              () => _future = widget.repository.loadLegalDocuments(),
            ),
            child: const Text('Réessayer'),
          )
        else
          const LinearProgressIndicator(),
        AuthNotice(error),
      ],
    ),
  );
}
