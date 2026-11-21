import 'package:flutter/material.dart';
import 'catalog_page.dart' show green, ink;
import 'information_repository.dart';

const _statuses = {
  'draft': 'Brouillon',
  'published': 'En cours',
  'expired': 'Expirée',
  'archived': 'Archivée',
};
String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _error(Object e) => e is InformationFailure
    ? e.message
    : 'Impossible de charger ou enregistrer les annonces. Réessaie.';

DateTime _defaultEnd() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 14, 23, 59, 59);
}

class InformationPage extends StatefulWidget {
  const InformationPage({super.key, this.repository});
  final InformationRepository? repository;
  @override
  State<InformationPage> createState() => _InformationPageState();
}

class _InformationPageState extends State<InformationPage> {
  late final _repository = widget.repository ?? FirebaseInformationRepository();
  final _items = <Map<String, dynamic>>[];
  Map<String, dynamic>? _cursor;
  bool _busy = false, _archives = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _repository.list(cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        for (final raw in result['items'] as List) {
          final item = Map<String, dynamic>.from(raw);
          _items.removeWhere((old) => old['id'] == item['id']);
          _items.add(item);
        }
        _cursor = result['cursor'] == null
            ? null
            : Map<String, dynamic>.from(result['cursor']);
      });
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InformationEditor(repository: _repository, initial: item),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where(
      (item) => _archives == ['archived', 'expired'].contains(item['status']),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Annonces Foundi',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Créer une annonce'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Publie une information temporaire dans l’application. La dernière annonce publiée apparaît dans Explorer. Après sa date de fin, elle reste uniquement dans les archives de l’admin.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Information permanente : l’explication du badge reste accessible dans Compte → Informations Foundi. Elle est intégrée à l’application.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('En cours et brouillons'),
                ),
                ButtonSegment(value: true, label: Text('Archives')),
              ],
              selected: {_archives},
              onSelectionChanged: (values) =>
                  setState(() => _archives = values.single),
            ),
            IconButton(
              tooltip: 'Actualiser les annonces',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message!, style: const TextStyle(color: Colors.red)),
          ),
        if (!_busy && visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aucune annonce dans cette vue parmi les éléments chargés.',
            ),
          ),
        for (final item in visible)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Chip(
                        label: Text(_statuses[item['status']] ?? ''),
                        backgroundColor: const Color(0xFFDFF4EA),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _edit(item),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Ouvrir'),
                      ),
                    ],
                  ),
                  Text(item['summary'] as String),
                  const SizedBox(height: 8),
                  Text(
                    'Fin : ${_date((item['endsAt'] as num).toInt())} · heure locale',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        if (_cursor != null)
          OutlinedButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('Charger la suite'),
          ),
      ],
    );
  }
}

class _InformationEditor extends StatefulWidget {
  const _InformationEditor({required this.repository, this.initial});
  final InformationRepository repository;
  final Map<String, dynamic>? initial;
  @override
  State<_InformationEditor> createState() => _InformationEditorState();
}

class _InformationEditorState extends State<_InformationEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.initial?['title'] as String? ?? '',
  );
  late final _summary = TextEditingController(
    text: widget.initial?['summary'] as String? ?? '',
  );
  late final _body = TextEditingController(
    text: widget.initial?['body'] as String? ?? '',
  );
  late DateTime _end = widget.initial?['endsAt'] == null
      ? _defaultEnd()
      : DateTime.fromMillisecondsSinceEpoch(
          (widget.initial!['endsAt'] as num).toInt(),
        );
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _chooseEnd() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.add(const Duration(days: 365));
    final end = DateUtils.dateOnly(_end);
    final day = await showDatePicker(
      context: context,
      initialDate: end.isBefore(today)
          ? today
          : end.isAfter(last)
          ? last
          : end,
      firstDate: today,
      lastDate: last,
      helpText: 'Date de fin de l’annonce',
    );
    if (day != null && mounted) {
      setState(() => _end = DateTime(day.year, day.month, day.day, 23, 59, 59));
    }
  }

  Future<void> _save(String status) async {
    if (_busy) return;
    if (!_form.currentState!.validate()) return;
    if (status == 'published' && !_end.isAfter(DateTime.now())) {
      setState(() => _message = 'Choisis une date de fin future pour publier.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.repository.save({
        if (widget.initial != null) 'id': widget.initial!['id'],
        'expectedVersion': widget.initial?['version'] ?? '',
        'status': status,
        'title': _title.text.trim(),
        'summary': _summary.text.trim(),
        'body': _body.text.trim(),
        'endsAt': _end.millisecondsSinceEpoch,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = _error(e);
          _busy = false;
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int max, {
    int lines = 1,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    maxLength: max,
    minLines: lines,
    maxLines: lines == 1 ? 1 : lines + 5,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) =>
        (value ?? '').trim().isEmpty ? 'Ce champ est requis.' : null,
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.initial == null ? 'Créer une annonce' : 'Modifier l’annonce',
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(_title, 'Titre', 100),
                const SizedBox(height: 14),
                _field(_summary, 'Résumé sur la carte', 240, lines: 2),
                const SizedBox(height: 14),
                _field(_body, 'Contenu de l’annonce', 12000, lines: 5),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _chooseEnd,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Fin : ${_date(_end.millisecondsSinceEpoch)}'),
                ),
                const Text(
                  'Heure locale de cet ordinateur. La date de fin est obligatoire ; choisis une date dans les 12 prochains mois.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (_message != null)
                  Text(_message!, style: const TextStyle(color: Colors.red)),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        if (widget.initial != null && widget.initial!['status'] != 'archived')
          TextButton(
            onPressed: _busy ? null : () => _save('archived'),
            child: const Text('Archiver'),
          ),
        OutlinedButton(
          onPressed: _busy ? null : () => _save('draft'),
          child: const Text('Enregistrer en brouillon'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save('published'),
          style: FilledButton.styleFrom(backgroundColor: green),
          child: const Text('Publier'),
        ),
      ],
    ),
  );
}
