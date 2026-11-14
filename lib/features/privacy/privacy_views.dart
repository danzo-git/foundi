import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/domain/auth_repository.dart';
import 'privacy_repository.dart';

class PrivacyScope extends InheritedWidget {
  const PrivacyScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final PrivacyRepository repository;
  static PrivacyRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrivacyScope>()?.repository;
  @override
  bool updateShouldNotify(PrivacyScope oldWidget) =>
      oldWidget.repository != repository;
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.repository});
  final PrivacyRepository repository;
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _confirmed = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> submit(bool google) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.request(password: _password.text, google: google);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Impossible de confirmer la demande. Réessaie.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
    if (mounted && widget.repository.pending) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Supprimer mon compte')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Cette action est définitive',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Le compte sera fermé dès l’acceptation de la demande. Tes demandes, ton profil professionnel, tes photos, tes justificatifs et tes messages seront retirés puis effacés par étapes. Les messages écrits par les autres membres restent dans leur historique, avec une mention « Compte supprimé ».',
        ),
        const SizedBox(height: 16),
        const Text(
          'Des preuves et traces de modération peuvent être conservées temporairement selon la politique validée. Supprimer le compte ne lève aucune mesure visant un autre membre. Le stockage du fournisseur peut garder des copies techniques pendant son délai de récupération.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Le suivi reste sur cet appareil après la déconnexion. Ne désinstalle pas Foundi et n’efface pas ses données avant la fin du traitement. Une panne ne sera jamais affichée comme une suppression terminée.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _confirmed,
          onChanged: _busy
              ? null
              : (v) => setState(() => _confirmed = v ?? false),
          title: const Text(
            'Je comprends les conséquences et demande la suppression définitive de mon compte et de mes données associées.',
          ),
        ),
        if (widget.repository.hasPassword) ...[
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Confirmer mon mot de passe',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _confirmed && !_busy ? () => submit(false) : null,
            child: Text(_busy ? 'Vérification…' : 'Confirmer la suppression'),
          ),
        ],
        if (widget.repository.hasGoogle)
          OutlinedButton(
            onPressed: _confirmed && !_busy ? () => submit(true) : null,
            child: const Text('Vérifier avec Google et supprimer'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        const SelectableText('Assistance : kouamedenzel09@gmail.com'),
      ],
    ),
  );
}

class DeletionStatusScreen extends StatefulWidget {
  const DeletionStatusScreen({super.key, required this.repository});
  final PrivacyRepository repository;
  @override
  State<DeletionStatusScreen> createState() => _DeletionStatusScreenState();
}

class _DeletionStatusScreenState extends State<DeletionStatusScreen> {
  late Future<DeletionStatus> _future = widget.repository.status();
  String? _error;
  void refresh() {
    if (!mounted) return;
    final next = widget.repository.status();
    // The previous frame may still be mounted when an immediate network error
    // completes. Observe it now; FutureBuilder will still display its failure.
    next.ignore();
    setState(() {
      _future = next;
    });
  }

  String label(DeletionStatus s) => switch (s.state) {
    'completed' => 'Suppression terminée',
    'needs_review' => 'Une vérification est nécessaire',
    'retry' => 'Traitement interrompu, reprise prévue',
    _ => 'Suppression en cours',
  };
  Future<void> action(Future<void> Function() action) async {
    try {
      await action();
      refresh();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suivi de suppression')),
    body: FutureBuilder<DeletionStatus>(
      future: _future,
      builder: (context, s) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (s.hasData) ...[
            Text(
              label(s.requireData),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              s.requireData.state == 'completed'
                  ? 'Le compte et les données actives associées ont été supprimés. Les éventuelles conservations temporaires sont indiquées ci-dessous.'
                  : 'Ton suivi est conservé sur cet appareil. Le traitement peut nécessiter plusieurs étapes. Une interruption laisse le dossier ouvert et vérifiable.',
            ),
            if (s.requireData.retainedUntil case final until?)
              Text(
                'Conservation temporaire de preuves ou de traces de modération au plus tard jusqu’au ${until.toLocal()}.',
              ),
            if (s.requireData.providerRetentionUntil case final until?)
              Text(
                'Copies de récupération du stockage : échéance technique estimée au ${until.toLocal()}. Les délais propres aux autres fournisseurs restent décrits dans la politique.',
              ),
            if (s.requireData.canRetry)
              OutlinedButton(
                onPressed: () => action(widget.repository.retry),
                child: const Text('Demander une reprise'),
              ),
            if (s.requireData.state == 'completed')
              FilledButton(
                onPressed: () =>
                    action(widget.repository.closeCompletedReceipt),
                child: const Text('Fermer le suivi sur cet appareil'),
              ),
          ] else if (s.hasError)
            Text(
              s.error is AuthFailure
                  ? (s.error as AuthFailure).message
                  : 'Suivi indisponible. Réessaie.',
            )
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: refresh,
            child: const Text('Actualiser le suivi'),
          ),
          if (s.hasError &&
              (widget.repository.hasPassword || widget.repository.hasGoogle))
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DeleteAccountScreen(repository: widget.repository),
                ),
              ),
              child: const Text('Vérifier un envoi non confirmé'),
            ),
          if (widget.repository.receiptExport case final receipt?) ...[
            const Text(
              'Le code de suivi donne accès à ton état de traitement. Garde-le privé ; tu peux le conserver pour retrouver ce suivi depuis le site Foundi.',
            ),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: receipt)),
              child: const Text('Copier mon code de suivi'),
            ),
          ],
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (s.hasError)
            TextButton(
              onPressed: () async {
                final leave = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Quitter le suivi local ?'),
                    content: const Text(
                      'Garde une copie de ton code de suivi. Fermer ce suivi sur cet appareil n’annule pas une demande acceptée et ne prouve pas que la suppression est terminée. Tu pourras retrouver le dossier avec ton code ou contacter l’assistance.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Rester'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Quitter ce suivi'),
                      ),
                    ],
                  ),
                );
                if (leave == true) {
                  await action(widget.repository.forgetLocalReceipt);
                }
              },
              child: const Text('Quitter le suivi sur cet appareil'),
            ),
          const SelectableText('Assistance : kouamedenzel09@gmail.com'),
          TextButton(
            onPressed: () => Clipboard.setData(
              const ClipboardData(text: 'kouamedenzel09@gmail.com'),
            ),
            child: const Text('Copier le contact d’assistance'),
          ),
        ],
      ),
    ),
  );
}

class PrivacySessionGate extends StatelessWidget {
  const PrivacySessionGate({
    super.key,
    required this.repository,
    required this.child,
  });
  final PrivacyRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (_, _) => repository.pending
        ? DeletionStatusScreen(repository: repository)
        : child,
  );
}
