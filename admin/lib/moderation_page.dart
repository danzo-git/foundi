import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'moderation_repository.dart';
import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';

String _error(Object e) => e is ModerationFailure
    ? e.message
    : 'Chargement impossible. Vérifie ta connexion et réessaie.';
String _date(dynamic value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ).toLocal().toString().substring(0, 16)
    : 'Date inconnue';

class ModerationPage extends StatefulWidget {
  const ModerationPage({super.key, this.repository});
  final ModerationRepository? repository;
  @override
  State<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<ModerationPage> {
  late final _repository = widget.repository ?? FirebaseModerationRepository();
  String _status = 'new', _reason = '', _type = '';
  String? _failure;
  Map<String, dynamic>? _cursor;
  final _items = <Map<String, dynamic>>[];
  bool _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failure = null;
      if (reset) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      final page = await _repository.list({
        'status': _status,
        if (_reason.isNotEmpty) 'reason': _reason,
        if (_type.isNotEmpty) 'targetType': _type,
        if (!reset && _cursor != null) 'cursor': _cursor,
      });
      if (mounted && generation == _generation) {
        setState(() {
          _items.addAll([
            for (final v in page['items'] as List)
              Map<String, dynamic>.from(v as Map),
          ]);
          _cursor = page['cursor'] == null
              ? null
              : Map<String, dynamic>.from(page['cursor'] as Map);
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _failure = _error(e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Widget _filter(
    String title,
    Map<String, String> options,
    String selected,
    ValueChanged<String> change,
  ) => SizedBox(
    width: 240,
    child: DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text('Tous les ${title.toLowerCase()}'),
        ),
        for (final r in options.entries)
          DropdownMenuItem(
            value: r.key,
            child: Text(r.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy
          ? null
          : (v) {
              change(v ?? '');
              _load(reset: true);
            },
    ),
  );
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF4F7F8),
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Signalements',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('File privée de modération · Les plus anciens en premier'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in moderationStatuses.entries)
              ChoiceChip(
                label: Text(status.value),
                selected: _status == status.key,
                onSelected: _busy
                    ? null
                    : (_) {
                        _status = status.key;
                        _load(reset: true);
                      },
              ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _filter('Motifs', moderationReasons, _reason, (v) => _reason = v),
            _filter('Types', moderationTypes, _type, (v) => _type = v),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _busy ? null : () => _load(reset: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_failure != null) ...[
          Text(_failure!, style: const TextStyle(color: Colors.red)),
          TextButton(
            onPressed: () => _load(reset: true),
            child: const Text('Réessayer'),
          ),
        ],
        if (_items.isEmpty && !_busy && _failure == null)
          const Text('Aucun signalement dans cette file.'),
        for (final item in _items)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(
                item['priority'] == 'high'
                    ? Icons.priority_high
                    : Icons.flag_outlined,
                color: item['priority'] == 'high'
                    ? Colors.deepOrange
                    : const Color(0xFF087965),
              ),
              title: Text(item['label'] as String? ?? 'Contenu signalé'),
              subtitle: Text(
                '${moderationTypes[item['targetType']]} · ${moderationReasons[item['reason']]}\n${_date(item['createdAt'])}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ModerationDetailPage(
                      repository: _repository,
                      id: item['id'] as String,
                    ),
                  ),
                );
                if (mounted) _load(reset: true);
              },
            ),
          ),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_cursor != null && !_busy)
          TextButton(
            onPressed: () => _load(),
            child: const Text('Page suivante'),
          ),
      ],
    ),
  );
}

class ModerationDetailPage extends StatefulWidget {
  const ModerationDetailPage({
    super.key,
    required this.repository,
    required this.id,
  });
  final ModerationRepository repository;
  final String id;
  @override
  State<ModerationDetailPage> createState() => _ModerationDetailPageState();
}

class _ModerationDetailPageState extends State<ModerationDetailPage> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _pending;
  String? _failure;
  bool _busy = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showFailure(Object error) {
    if (!mounted) return;
    setState(() => _failure = _error(error));
    // Decisions may be below the fold on a narrow screen. Bring the error into view.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final value = await widget.repository.detail(widget.id);
      if (mounted) {
        setState(() {
          _report = value;
          _failure = null;
          _pending = null;
        });
      }
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String action) async {
    var justification = '';
    var publicMessage = '';
    final notifying = [
      'warn',
      'hide',
      'suspend',
      'restore_content',
      'restore_account',
    ].contains(action);
    final form = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(moderationActions[action]!),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cette décision sera enregistrée dans le journal privé. Ne mentionne pas le signalant dans une communication au compte concerné.',
                ),
                const SizedBox(height: 12),
                Text(
                  action == 'take'
                      ? 'Le dossier passera en cours d’examen et te sera attribué pour le suivi. Cette étape n’applique aucune sanction et n’envoie aucune notification.'
                      : action == 'reopen'
                      ? 'Le dossier repassera en cours d’examen. Les décisions précédentes restent dans l’historique et les mesures actives restent appliquées. Aucun avis ne sera envoyé pour cette réouverture.'
                      : [
                          'warn',
                          'hide',
                          'suspend',
                          'restore_content',
                          'restore_account',
                        ].contains(action)
                      ? 'L’avis indiquera le contenu concerné et le message à l’utilisateur ci-dessous. La justification interne reste privée. Le push dépend des préférences de son appareil.'
                      : 'Le classement sans suite n’applique aucune sanction et n’envoie aucune notification au compte signalé.',
                ),
                const SizedBox(height: 16),
                if (notifying) ...[
                  TextFormField(
                    key: const ValueKey('moderationPublicMessage'),
                    onChanged: (value) => publicMessage = value,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Message à l’utilisateur',
                      helperText:
                          'Explique la décision sans identifier le signalant ni copier de preuve privée.',
                      helperMaxLines: 3,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Explique la décision à l’utilisateur.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const ValueKey('moderationPrivateReason'),
                  onChanged: (value) => justification = value,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Justification interne obligatoire',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Justifie cette décision.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(c, justification.trim());
              }
            },
            child: const Text('Confirmer la décision'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    final same =
        _pending?['action'] == action &&
        _pending?['reason'] == reason &&
        _pending?['publicMessage'] ==
            (notifying ? publicMessage.trim() : null) &&
        _pending?['expectedRevision'] == _report!['revision'];
    final input = same
        ? _pending!
        : {
            'reportId': widget.id,
            'action': action,
            'reason': reason,
            if (notifying) 'publicMessage': publicMessage.trim(),
            'expectedRevision': _report!['revision'],
            'decisionId':
                'decision_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}',
          };
    _pending = input;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.repository.decide(input);
      await _load();
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachment() async {
    setState(() => _busy = true);
    try {
      final file = await widget.repository.readAttachment(widget.id);
      saveDocument(file.bytes, file.contentType, 'preuve-signalement');
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final open = r != null && ['new', 'in_progress'].contains(r['status']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossier de modération'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_failure != null) ...[
            Text(_failure!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _load,
              child: const Text('Actualiser le dossier'),
            ),
          ],
          if (r != null) ...[
            Text(
              r['label'] as String? ?? 'Signalement',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '${moderationStatuses[r['status']]} · ${moderationTypes[r['targetType']]} · ${moderationReasons[r['reason']]}',
            ),
            Text(
              'Créé le ${_date(r['createdAt'])} · Révision ${r['revision']}',
            ),
            if (r['status'] == 'new')
              const Text(
                'Commencer l’examen permet de suivre le dossier avant de décider. Aucune sanction n’est appliquée à cette étape.',
              ),
            if (r['status'] == 'in_progress') ...[
              const Text(
                'Examen en cours : une décision reste à prendre. Ce statut seul n’applique aucune sanction.',
              ),
              if (r['assignedAdminUid'] != null)
                SelectableText(
                  'Administrateur chargé du suivi : ${r['assignedAdminUid']}',
                ),
            ],
            if (['resolved', 'dismissed'].contains(r['status']))
              const Text(
                'Dossier traité. Réexamine-le pour compléter ou modifier la décision. Une réouverture ne lève aucune mesure active.',
              ),
            const SizedBox(height: 20),
            const Text(
              'Informations réservées à la modération',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(
              'Signalé : ${r['reportedUid']}\nSignalant : ${r['reporterUid']}\nCible : ${r['targetId']}',
            ),
            const SizedBox(height: 12),
            Text(r['comment'] as String? ?? ''),
            const SizedBox(height: 20),
            const Text(
              'Preuves minimales privées',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert({
                ...Map<String, dynamic>.from(r['evidence'] as Map),
                'images': 'Miniatures privées ci-dessous',
              }),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final img
                    in (r['evidence'] as Map)['images'] as List? ?? [])
                  Image.memory(
                    base64Decode(img['base64'] as String),
                    width: 240,
                    height: 200,
                    fit: BoxFit.contain,
                    semanticLabel: 'Preuve visuelle privée',
                    errorBuilder: (_, _, _) =>
                        const Text('Image de preuve indisponible.'),
                  ),
              ],
            ),
            if ((r['evidence'] as Map)['mediaUnavailable'] != null)
              const Text(
                'Certaines images étaient indisponibles lors du signalement. Les références sont conservées pour examen.',
              ),
            if ([
              'image',
              'pdf',
            ].contains((r['evidence'] as Map)['message']?['type']))
              TextButton.icon(
                onPressed: _busy ? null : _attachment,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Consulter la pièce jointe signalée'),
              ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in moderationActions.entries)
                  if (r['availableActions'] is List
                      ? (r['availableActions'] as List).contains(action.key)
                      : (['resolved', 'dismissed'].contains(r['status']) &&
                                action.key == 'reopen') ||
                            (open &&
                                action.key != 'reopen' &&
                                !action.key.startsWith('restore_') &&
                                (action.key != 'take' ||
                                    r['status'] == 'new') &&
                                (action.key != 'hide' ||
                                    [
                                      'request',
                                      'professional',
                                    ].contains(r['targetType']))) ||
                            (action.key == 'restore_content' &&
                                r['contentHidden'] == true) ||
                            (action.key == 'restore_account' &&
                                r['accountSuspended'] == true))
                    OutlinedButton(
                      onPressed: _busy ? null : () => _decide(action.key),
                      child: Text(action.value),
                    ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Journal d’audit',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            for (final a in r['audit'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${moderationActions[a['action']]} · ${_date(a['createdAt'])}',
                ),
                subtitle: Text(
                  '${a['adminUid']}\nInterne : ${a['reason']}${a['publicMessage'] == null ? '' : '\nÀ l’utilisateur : ${a['publicMessage']}'}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
