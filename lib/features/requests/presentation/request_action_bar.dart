import 'dart:async';

import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/request_interaction_repository.dart';
import '../domain/request_repository.dart';

class RequestActionButton extends StatelessWidget {
  const RequestActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected,
    this.emphasized = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool? selected;
  final bool emphasized, busy;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: emphasized || selected == true
            ? FoundiUi.green
            : FoundiUi.ink,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      ),
      onPressed: onPressed,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Chargement',
              ),
            )
          else
            Icon(icon, size: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

void requestActionMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

class RequestActionBar extends StatefulWidget {
  const RequestActionBar({
    super.key,
    required this.request,
    required this.repository,
    this.uid,
    this.onAuthenticate,
    this.reply,
    this.onViewRespondents,
  });

  final FoundiRequest request;
  final RequestInteractionRepository repository;
  final String? uid;
  final VoidCallback? onAuthenticate;
  final Widget? reply;
  final VoidCallback? onViewRespondents;

  @override
  State<RequestActionBar> createState() => _RequestActionBarState();
}

class _RequestActionBarState extends State<RequestActionBar> {
  StreamSubscription<bool>? _mine;
  Stream<RequestEngagement>? _counts;
  bool? _liked, _pending;
  int _generation = 0;

  bool get _open => widget.request.status == 'published';

  void _subscribe() {
    _generation++;
    _mine?.cancel();
    _mine = null;
    _counts = null;
    _liked = _pending = null;
    if (!_open) return;
    _counts = widget.repository.watchRequestEngagement(widget.request.id);
    final uid = widget.uid;
    if (uid != null) {
      _mine = widget.repository
          .watchMyRequestLike(widget.request.id, uid)
          .listen(
            (liked) => setState(() => _liked = liked),
            onError: (Object _) => setState(() => _liked = null),
          );
    }
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(RequestActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.uid != widget.uid ||
        oldWidget.request.id != widget.request.id ||
        oldWidget.request.status != widget.request.status) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _mine?.cancel();
    super.dispose();
  }

  Future<void> _like() async {
    if (widget.uid == null) {
      widget.onAuthenticate?.call();
      return;
    }
    final current = _liked;
    if (current == null) {
      setState(_subscribe);
      requestActionMessage(
        context,
        'Impossible de charger ton J’aime. Réessaie dans un instant.',
      );
      return;
    }
    final generation = _generation;
    final next = !current;
    setState(() => _pending = next);
    try {
      await widget.repository.setRequestLike(widget.request.id, next);
      if (mounted && generation == _generation) setState(() => _liked = next);
    } catch (error) {
      if (mounted && generation == _generation) {
        requestActionMessage(
          context,
          error is AuthFailure
              ? error.message
              : 'J’aime non confirmé. Réessaie.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _pending = null);
    }
  }

  Future<void> _recommend() async {
    if (widget.uid == null) {
      widget.onAuthenticate?.call();
      return;
    }
    final alreadyRecommended = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _RecommendationSheet(
        request: widget.request,
        repository: widget.repository,
      ),
    );
    if (mounted && alreadyRecommended != null) {
      requestActionMessage(
        context,
        alreadyRecommended
            ? 'Tu as déjà recommandé ce professionnel pour cette demande.'
            : 'Recommandation enregistrée. L’auteur et le professionnel recevront une notification Foundi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = _pending ?? _liked ?? false;
    return StreamBuilder<RequestEngagement>(
      stream: _counts,
      builder: (context, count) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_open)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                if (count.data?.recommendationCount case final int total)
                  Text(
                    '$total ${total == 1 ? 'recommandation' : 'recommandations'}',
                    style: const TextStyle(color: FoundiUi.muted, fontSize: 12),
                  ),
                if (count.data?.responseCount case final int total)
                  TextButton(
                    onPressed: widget.onViewRespondents,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      foregroundColor: FoundiUi.ink,
                      disabledForegroundColor: FoundiUi.muted,
                    ),
                    child: Text(
                      '$total ${total == 1 ? 'réponse' : 'réponses'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (count.hasError)
                  TextButton.icon(
                    onPressed: () => setState(_subscribe),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Réessayer les compteurs'),
                  ),
              ],
            ),
          const Divider(height: 12, thickness: 1, color: FoundiUi.line),
          Row(
            children: [
              Expanded(
                child: RequestActionButton(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  label: count.data == null
                      ? 'J’aime'
                      : 'J’aime · ${count.data!.likeCount}',
                  selected: liked,
                  onPressed: _open && _pending == null ? _like : null,
                ),
              ),
              const _ActionDivider(),
              Expanded(
                child: RequestActionButton(
                  icon: Icons.send_outlined,
                  label: 'Recommander',
                  onPressed: _open ? _recommend : null,
                ),
              ),
              const _ActionDivider(),
              Expanded(
                child:
                    widget.reply ??
                    RequestActionButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'Répondre',
                      onPressed: _open ? widget.onAuthenticate : null,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 20,
    child: VerticalDivider(width: 1, color: FoundiUi.line),
  );
}

class _RecommendationSheet extends StatefulWidget {
  const _RecommendationSheet({required this.request, required this.repository});
  final FoundiRequest request;
  final RequestInteractionRepository repository;

  @override
  State<_RecommendationSheet> createState() => _RecommendationSheetState();
}

class _RecommendationSheetState extends State<_RecommendationSheet> {
  final _search = TextEditingController();
  final _results = <RecommendationProfessional>[];
  RecommendationProfessional? _selected;
  String _query = '';
  String? _cursor, _error;
  bool _loading = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || _saving) return;
    setState(() {
      if (reset) {
        _query = _search.text.trim();
        _cursor = null;
        _results.clear();
        _selected = null;
      }
      _error = null;
      _loading = true;
    });
    try {
      final page = await widget.repository.searchRecommendationProfessionals(
        widget.request.id,
        _query,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(page.items);
        _cursor = page.cursor;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _message(error, 'Recherche indisponible.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final selected = _selected;
    if (selected == null || _saving || _loading) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.recommendRequestProfessional(
        widget.request.id,
        selected.id,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _message(error, 'Recommandation non confirmée. Réessaie.');
        });
      }
    }
  }

  String _message(Object error, String fallback) =>
      error is AuthFailure ? error.message : fallback;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: .85,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Recommander un professionnel',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fermer',
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _search,
                        enabled: !_saving,
                        maxLength: 80,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(reset: true),
                        decoration: InputDecoration(
                          labelText: 'Nom, spécialité ou zone',
                          counterText: '',
                          suffixIcon: IconButton(
                            tooltip: 'Rechercher',
                            onPressed: _loading || _saving
                                ? null
                                : () => _load(reset: true),
                            icon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_results.isEmpty && !_loading && _error == null)
                        const Text(
                          'Aucun professionnel trouvé sur cette page.',
                        ),
                      for (final professional in _results)
                        _candidate(professional),
                      if (_cursor != null && !_loading)
                        TextButton(
                          onPressed: _saving ? null : () => _load(reset: false),
                          child: const Text(
                            'Chercher parmi d’autres professionnels',
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _selected == null || _loading || _saving
                      ? null
                      : _confirm,
                  child: Text(
                    _saving ? 'Enregistrement…' : 'Confirmer la recommandation',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _candidate(RecommendationProfessional professional) {
    final selected = _selected?.id == professional.id;
    final activity = [...professional.categories, ...professional.specialties];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      selected: selected,
      selectedTileColor: FoundiUi.tint,
      title: Text(professional.name),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: FoundiUi.green,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Professionnel vérifié',
            style: TextStyle(color: FoundiUi.green),
          ),
          if (activity.isNotEmpty) Text(activity.join(' · ')),
          if (professional.zones.isNotEmpty)
            Text(professional.zones.join(' · ')),
        ],
      ),
      onTap: _saving ? null : () => setState(() => _selected = professional),
    );
  }
}
