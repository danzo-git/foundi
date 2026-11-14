import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

abstract interface class DeletionsRepository {
  Future<Map<String, dynamic>> list(String? cursor);
  Future<Map<String, dynamic>> detail(String id);
  Future<void> resume(String id, String reason);
}

class FirebaseDeletionsRepository implements DeletionsRepository {
  final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> input,
  ) async => Map<String, dynamic>.from(
    (await functions.httpsCallable(name).call(input)).data as Map,
  );
  @override
  Future<Map<String, dynamic>> list(String? cursor) =>
      call('listAccountDeletions', {'cursor': ?cursor});
  @override
  Future<Map<String, dynamic>> detail(String id) =>
      call('readAccountDeletion', {'requestId': id});
  @override
  Future<void> resume(String id, String reason) async {
    await call('resumeAccountDeletion', {'requestId': id, 'reason': reason});
  }
}

String deletionLabel(String? state) => switch (state) {
  'completed' => 'Terminée',
  'needs_review' => 'Vérification requise',
  'retry' => 'Reprise prévue',
  'waiting' => 'Attente des opérations en cours',
  'processing' => 'Traitement en cours',
  _ => 'À traiter',
};

class DeletionsPage extends StatefulWidget {
  const DeletionsPage({super.key, this.repository});
  final DeletionsRepository? repository;
  @override
  State<DeletionsPage> createState() => _DeletionsPageState();
}

class _DeletionsPageState extends State<DeletionsPage> {
  late final repo = widget.repository ?? FirebaseDeletionsRepository();
  String? cursor;
  late Future<Map<String, dynamic>> future = repo.list(null);
  void load(String? next) {
    setState(() {
      cursor = next;
      future = repo.list(next);
    });
  }

  Future<void> open(String id) async {
    try {
      final value = await repo.detail(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DeletionDetail(repository: repo, value: value),
      );
      load(cursor);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dossier indisponible ou accès révoqué.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Suppressions de compte',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const Text(
        'File privée · demandes vérifiées des titulaires · aucune suppression par UID libre',
      ),
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          onPressed: () => load(cursor),
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ),
      FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, s) {
          if (s.hasError) {
            return const Text(
              'Chargement impossible. Réessaie ou vérifie tes accès.',
            );
          }
          if (!s.hasData) return const LinearProgressIndicator();
          final items = (s.requireData['items'] as List).cast<Map>();
          return Column(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Aucune demande de suppression.'),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(deletionLabel(item['state'] as String?)),
                    subtitle: Text(
                      'Référence : ${item['requestId']}\n${item['lastErrorCode'] == null ? 'Suivi disponible' : 'Contrôle technique requis'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(item['requestId'] as String),
                  ),
                ),
              if (s.requireData['cursor'] case final String next)
                TextButton(
                  onPressed: () => load(next),
                  child: const Text('Page suivante'),
                ),
              if (cursor != null)
                TextButton(
                  onPressed: () => load(null),
                  child: const Text('Première page'),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _DeletionDetail extends StatefulWidget {
  const _DeletionDetail({required this.repository, required this.value});
  final DeletionsRepository repository;
  final Map<String, dynamic> value;
  @override
  State<_DeletionDetail> createState() => _DeletionDetailState();
}

class _DeletionDetailState extends State<_DeletionDetail> {
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(deletionLabel(widget.value['state'] as String?)),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('Référence : ${widget.value['requestId']}'),
            Text('Étape technique : ${widget.value['step']}'),
            if (widget.value['subjectUid'] != null)
              SelectableText(
                'Compte en cours d’effacement : ${widget.value['subjectUid']}',
              ),
            if (widget.value['reviewReference'] != null)
              SelectableText(
                'Objet à examiner : ${widget.value['reviewReference']}',
              ),
            if (widget.value['lastErrorCode'] != null)
              Text('Diagnostic : ${widget.value['lastErrorCode']}'),
            const Text(
              'Reprendre ne modifie ni la politique de conservation adoptée ni les décisions de modération. Vérifier la cause avant toute reprise.',
            ),
            if (['needs_review', 'retry'].contains(widget.value['state']))
              TextField(
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Motif de reprise obligatoire',
                ),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
      if (['needs_review', 'retry'].contains(widget.value['state']))
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (reason.text.trim().isEmpty) {
                    setState(() => error = 'Indique le contrôle effectué.');
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await widget.repository.resume(
                      widget.value['requestId'] as String,
                      reason.text.trim(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        busy = false;
                        error = 'Reprise refusée. Actualise le dossier.';
                      });
                    }
                  }
                },
          child: const Text('Reprendre ce dossier'),
        ),
    ],
  );
}
