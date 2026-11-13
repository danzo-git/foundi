import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/auth_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/safety_repository.dart';

String safetyError(Object e) => e is AuthFailure
    ? e.message
    : 'Action indisponible. Vérifie ta connexion et réessaie.';

class SafetyScope extends InheritedWidget {
  const SafetyScope({
    super.key,
    required this.repository,
    required this.uid,
    required this.onAuthenticate,
    required this.revision,
    required super.child,
  });
  final SafetyRepository repository;
  final String? Function() uid;
  final VoidCallback onAuthenticate;
  final ValueNotifier<int> revision;
  static SafetyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SafetyScope>();
  @override
  bool updateShouldNotify(SafetyScope old) =>
      old.repository != repository || old.revision != revision;
}

class ReportDialog extends StatefulWidget {
  const ReportDialog({
    super.key,
    required this.repository,
    required this.target,
  });
  final SafetyRepository repository;
  final SafetyTarget target;
  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _form = GlobalKey<FormState>();
  final _comment = TextEditingController();
  String? _reason, _error;
  bool _busy = false;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.report(
        widget.target,
        _reason!,
        _comment.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = safetyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Signaler ${widget.target.label}'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ton identité reste confidentielle vis-à-vis de la personne signalée. N’ajoute pas de données sensibles.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                key: const ValueKey('safetyReason'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Motif obligatoire',
                ),
                items: [
                  for (final r in safetyReasons.entries)
                    DropdownMenuItem(
                      value: r.key,
                      child: Text(r.value, softWrap: true),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _reason = v),
                validator: (v) => v == null ? 'Choisis un motif.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('safetyComment'),
                controller: _comment,
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Complément facultatif',
                ),
                validator: (v) =>
                    (v?.length ?? 0) > 500 ? '500 caractères maximum.' : null,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Envoi…' : 'Envoyer le signalement'),
        ),
      ],
    ),
  );
}

Future<void> showSafetyReport(BuildContext context, SafetyTarget target) async {
  final scope = SafetyScope.maybeOf(context);
  if (scope == null) return;
  if (scope.uid() == null) {
    scope.onAuthenticate();
    return;
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => ReportDialog(repository: scope.repository, target: target),
  );
  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signalement envoyé. L’équipe Foundi pourra l’examiner.'),
      ),
    );
  }
}

class SafetyActionMenu extends StatefulWidget {
  const SafetyActionMenu({
    super.key,
    required this.target,
    this.allowBlock = false,
  });
  final SafetyTarget target;
  final bool allowBlock;
  @override
  State<SafetyActionMenu> createState() => _SafetyActionMenuState();
}

class _SafetyActionMenuState extends State<SafetyActionMenu> {
  Future<void> _action(String action) async {
    final scope = SafetyScope.maybeOf(context)!;
    if (scope.uid() == null) {
      scope.onAuthenticate();
      return;
    }
    if (action == 'report') {
      await showSafetyReport(context, widget.target);
      return;
    }
    final unblock = action == 'unblock';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          unblock ? 'Débloquer cet utilisateur ?' : 'Bloquer cet utilisateur ?',
        ),
        content: Text(
          unblock
              ? 'Les nouveaux contacts seront à nouveau possibles si les autres autorisations le permettent.'
              : 'Aucun nouveau message, proposition ou demande directe ne pourra être échangé dans les deux sens. L’historique sera conservé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(unblock ? 'Débloquer' : 'Bloquer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (unblock) {
        await scope.repository.unblockTarget(widget.target);
      } else {
        await scope.repository.block(widget.target);
      }
      scope.revision.value++;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safetyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = SafetyScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return SafetyContactGate(
      target: widget.target,
      builder: (context, state) => state?.own == true
          ? const SizedBox.shrink()
          : PopupMenuButton<String>(
              tooltip: 'Signaler ou bloquer',
              onSelected: _action,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text('Signaler ${widget.target.label}'),
                ),
                if (widget.allowBlock)
                  PopupMenuItem(
                    value: state?.blocked == true ? 'unblock' : 'block',
                    child: Text(
                      state?.blocked == true
                          ? 'Débloquer cet utilisateur'
                          : 'Bloquer cet utilisateur',
                    ),
                  ),
              ],
            ),
    );
  }
}

// Fail closed while resolving or offline. Existing history remains visible.
class SafetyContactGate extends StatefulWidget {
  const SafetyContactGate({
    super.key,
    required this.target,
    required this.builder,
  });
  final SafetyTarget target;
  final Widget Function(BuildContext, SafetyContext?) builder;
  @override
  State<SafetyContactGate> createState() => _SafetyContactGateState();
}

class _SafetyContactGateState extends State<SafetyContactGate>
    with WidgetsBindingObserver {
  SafetyScope? _scope;
  SafetyContext? _state;
  Timer? _timer;
  bool _loading = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SafetyScope.maybeOf(context);
    if (s != _scope) {
      _generation++;
      _state = null;
      _scope?.revision.removeListener(_changed);
      _scope = s;
      s?.revision.addListener(_changed);
      _timer?.cancel();
      if (s != null) {
        _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
      }
      _refresh();
    }
  }

  @override
  void didUpdateWidget(SafetyContactGate old) {
    super.didUpdateWidget(old);
    if (old.target.key != widget.target.key) {
      _generation++;
      _state = null;
      _refresh();
    }
  }

  void _changed() {
    _generation++;
    _state = null;
    _refresh();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
  }

  Future<void> _refresh() async {
    final scope = _scope;
    if (scope == null || scope.uid() == null || _loading) return;
    final generation = _generation;
    _loading = true;
    try {
      final next = await scope.repository.context(widget.target);
      if (mounted && generation == _generation) setState(() => _state = next);
    } catch (_) {
      if (mounted) setState(() => _state = null);
    } finally {
      _loading = false;
      if (mounted && generation != _generation) {
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scope?.revision.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _scope == null || _scope!.uid() == null ? const SafetyContext() : _state,
  );
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({
    super.key,
    required this.repository,
    this.onChanged,
  });
  final SafetyRepository repository;
  final VoidCallback? onChanged;
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _items = <BlockedUser>[];
  String? _cursor, _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.repository.blocked(cursor: reset ? null : _cursor);
      if (mounted) {
        setState(() {
          if (reset) _items.clear();
          _items.addAll(p.items);
          _cursor = p.cursor;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = safetyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Débloquer cet utilisateur ?'),
        content: const Text(
          'Les nouveaux contacts seront à nouveau possibles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repository.unblock(user.uid);
      widget.onChanged?.call();
      await _load(reset: true);
    } catch (e) {
      if (mounted) setState(() => _error = safetyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Comptes bloqués')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Le blocage empêche les nouveaux contacts dans les deux sens. Il conserve les conversations et les propositions existantes.',
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : () => _load(reset: true),
            child: const Text('Réessayer'),
          ),
        ],
        if (_items.isEmpty && !_busy && _error == null)
          const Text('Aucun compte bloqué.'),
        for (final u in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FoundiPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    u.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text('Utilisateur bloqué'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => _unblock(u),
                      child: const Text('Débloquer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_cursor != null && !_busy)
          TextButton(onPressed: () => _load(), child: const Text('Voir plus')),
      ],
    ),
  );
}

const foundiConductRules =
    'Foundi interdit les arnaques, l’usurpation d’identité, le harcèlement, les menaces, les contenus illégaux ou inappropriés et le spam. Respecte les autres membres et ne publie pas de données privées. Utilise les menus de signalement et de blocage. Une modération humaine peut retirer un contenu, avertir ou suspendre un compte ; une contestation est possible auprès de l’assistance.';

class SafetyHelpScreen extends StatelessWidget {
  const SafetyHelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const contact = String.fromEnvironment(
      'FOUNDI_SUPPORT_URL',
      defaultValue: 'mailto:kouamedenzel09@gmail.com',
    );
    final uri = Uri.tryParse(contact);
    final available =
        uri != null &&
        ((uri.scheme == 'https' && uri.host.isNotEmpty) ||
            (uri.scheme == 'mailto' && uri.path.contains('@')));
    return Scaffold(
      appBar: AppBar(title: const Text('Aide / Signaler un problème')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'Règles d’utilisation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(foundiConductRules),
          const SizedBox(height: 24),
          const Text(
            'Pour signaler un contenu précis, utilise son menu ⋮. Pour un problème technique ou une contestation, contacte l’assistance sans transmettre de mot de passe ni de pièce sensible.',
          ),
          const SizedBox(height: 16),
          if (available) ...[
            SelectableText(contact),
            FilledButton.icon(
              onPressed: () async {
                final opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ouverture impossible. Copie les coordonnées affichées.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.support_agent),
              label: const Text('Contacter Foundi'),
            ),
          ] else
            const Text(
              'Les coordonnées d’assistance Foundi ne sont pas encore publiées dans cette version. Leur validation est nécessaire avant distribution.',
            ),
          const SizedBox(height: 24),
          const Text(
            'En cas de danger immédiat, contacte les services d’urgence locaux. Foundi n’est pas un service d’urgence.',
          ),
        ],
      ),
    );
  }
}

// Remains available when suspension prevents the normal account/profile load.
// This uses only the authenticated, recipient-scoped notices API.
class SafetyAppealButton extends StatelessWidget {
  const SafetyAppealButton({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = SafetyScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SafetyNoticesScreen(repository: scope.repository),
        ),
      ),
      icon: const Icon(Icons.support_agent),
      label: const Text('Avis de modération et aide'),
    );
  }
}

class SafetyNoticesScreen extends StatelessWidget {
  const SafetyNoticesScreen({super.key, required this.repository});
  final SafetyRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Décisions de modération')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'Tes derniers avis restent consultables ici, y compris après leur fermeture dans le profil.',
        ),
        const SizedBox(height: 16),
        SafetyNoticesPanel(repository: repository, showAcknowledged: true),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SafetyHelpScreen()),
          ),
          icon: const Icon(Icons.support_agent),
          label: const Text('Aide et contestation'),
        ),
      ],
    ),
  );
}

class SafetyNoticesPanel extends StatefulWidget {
  const SafetyNoticesPanel({
    super.key,
    required this.repository,
    this.showAcknowledged = false,
    this.showHistoryLink = false,
  });
  final SafetyRepository repository;
  final bool showAcknowledged, showHistoryLink;
  @override
  State<SafetyNoticesPanel> createState() => _SafetyNoticesPanelState();
}

class _SafetyNoticesPanelState extends State<SafetyNoticesPanel> {
  List<SafetyNotice> _items = [];
  final _closing = <String>{}, _errors = <String, String>{};
  bool _loading = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SafetyNoticesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _items = [];
      _closing.clear();
      _errors.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.notices();
      if (mounted && generation == _generation) {
        setState(() => _items = items);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = safetyError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _acknowledge(SafetyNotice notice) async {
    if (_closing.contains(notice.id)) return;
    final generation = _generation;
    setState(() {
      _closing.add(notice.id);
      _errors.remove(notice.id);
    });
    try {
      await widget.repository.acknowledgeNotice(notice.id);
      if (mounted && generation == _generation) {
        setState(
          () => _items = [
            for (final n in _items)
              n.id == notice.id
                  ? SafetyNotice(
                      id: n.id,
                      text: n.text,
                      acknowledgedAt: DateTime.now(),
                    )
                  : n,
          ],
        );
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _errors[notice.id] = safetyError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _closing.remove(notice.id));
      }
    }
  }

  Future<void> _history() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SafetyNoticesScreen(repository: widget.repository),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_loading) const CircularProgressIndicator(),
      if (_error != null) ...[
        Text(_error!),
        TextButton(
          onPressed: _loading || _closing.isNotEmpty ? null : _load,
          child: const Text('Réessayer'),
        ),
      ],
      if (!_loading &&
          _error == null &&
          _items.isEmpty &&
          widget.showAcknowledged)
        const Text('Aucun avis de modération.'),
      for (final notice in _items.where(
        (n) => widget.showAcknowledged || !n.acknowledged,
      ))
        Padding(
          key: ValueKey('safetyNotice_${notice.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: FoundiPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(notice.text),
                if (notice.acknowledged) ...[
                  const SizedBox(height: 12),
                  const Text('Lecture confirmée'),
                ] else ...[
                  if (_errors[notice.id] != null) Text(_errors[notice.id]!),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: ValueKey('acknowledge_${notice.id}'),
                      onPressed: _closing.contains(notice.id) || _loading
                          ? null
                          : () => _acknowledge(notice),
                      icon: _closing.contains(notice.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _closing.contains(notice.id)
                            ? 'Fermeture…'
                            : 'J’ai compris',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (widget.showHistoryLink)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _closing.isNotEmpty ? null : _history,
            icon: const Icon(Icons.history),
            label: const Text('Historique des avis'),
          ),
        ),
    ],
  );
}
