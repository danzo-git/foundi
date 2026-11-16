import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/in_flight_reads.dart';

import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/presentation/professional_showcase_screen.dart';
import '../../professional/domain/professional_showcase.dart';
import '../domain/request_repository.dart';

class RequestRespondents extends StatefulWidget {
  const RequestRespondents({
    super.key,
    required this.repository,
    required this.requestId,
    this.onViewProposals,
  });

  final RequestRespondentsRepository repository;
  final String requestId;
  final VoidCallback? onViewProposals;

  @override
  State<RequestRespondents> createState() => _RequestRespondentsState();
}

class _RequestRespondentsState extends State<RequestRespondents> {
  final _items = <RequestRespondent>[];
  RequestRespondentsPage? _page;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RequestRespondents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.repository != widget.repository) {
      _generation++;
      _items.clear();
      _page = null;
      _error = null;
      _busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    final generation = ++_generation;
    final repository = widget.repository, requestId = widget.requestId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var offset = _page?.nextOffset ?? 0, emptyPages = 0;
      late RequestRespondentsPage page;
      // Continue a few empty, filtered pages without requiring repeated taps.
      // One deadline covers the whole operation, including pagination.
      await (() async {
        do {
          page = await repository.listRequestRespondents(
            requestId,
            offset: offset,
          );
          if (!mounted || generation != _generation) return;
          emptyPages++;
          final next = page.nextOffset;
          if (next != null && next <= offset) {
            throw StateError('Respondent pagination did not advance');
          }
          if (page.items.isNotEmpty || next == null || emptyPages >= 3) break;
          offset = next;
        } while (true);
      })().timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        final seen = _items
            .map((r) => r.professionalId)
            .whereType<String>()
            .toSet();
        _items.addAll(
          page.items.where(
            (r) => r.professionalId == null || seen.add(r.professionalId!),
          ),
        );
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          if (error is TimeoutException) {
            _generation++;
            _busy = false;
          }
          if (error is ReadAccessDenied || error is ReadScopeChanged) {
            // A refusal can mean the request or an account is no longer public.
            _items.clear();
            _page = null;
          }
          _error = error is TimeoutException
              ? 'Le chargement prend trop de temps. Vérifie ta connexion puis réessaie.'
              : error is ReadScopeChanged
              ? 'Le compte a changé. Rouvre cette demande.'
              : error is AuthFailure
              ? error.message
              : 'Impossible de charger les réponses.';
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _heading(int total) => switch (total) {
    0 => 'Aucune réponse pour le moment',
    1 => '1 professionnel a répondu',
    _ => '$total professionnels ont répondu',
  };

  void _openProfile(RequestRespondent respondent) {
    final repository = widget.repository;
    final id = respondent.professionalId;
    final requestId = widget.requestId;
    if (repository is! RequestRespondentProfileRepository || id == null) return;
    void unavailable() {
      if (mounted &&
          widget.repository == repository &&
          widget.requestId == requestId) {
        setState(() => _items.removeWhere((row) => row.professionalId == id));
      }
    }

    Future<ProfessionalShowcase> load() async {
      try {
        return await (repository as RequestRespondentProfileRepository)
            .readRequestRespondentProfile(requestId, id);
      } on ReadAccessDenied {
        unavailable();
        rethrow;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalShowcaseScreen.recommended(
          professionalId: id,
          loadRecommended: load,
          refreshRecommended: () async {
            try {
              return await load();
            } on ReadAccessDenied {
              return null;
            }
          },
          onUnavailable: unavailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (page != null) ...[
          Text(
            _heading(page.total),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (page.canViewProposals && widget.onViewProposals != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: widget.onViewProposals,
              child: const Text('Voir mes propositions'),
            ),
          ],
          for (final respondent in _items)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FoundiPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (respondent.professionalId != null &&
                            widget.repository
                                is RequestRespondentProfileRepository)
                          TextButton(
                            onPressed: () => _openProfile(respondent),
                            style: TextButton.styleFrom(
                              foregroundColor: FoundiUi.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Text(
                              respondent.name,
                              textAlign: TextAlign.start,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          Text(
                            respondent.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        const Icon(
                          Icons.verified,
                          color: FoundiUi.green,
                          size: 19,
                          semanticLabel: 'Professionnel vérifié',
                        ),
                      ],
                    ),
                    if (respondent.activity.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        respondent.activity.join(' · '),
                        style: const TextStyle(color: FoundiUi.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (page.total > 0 && _items.isEmpty && page.nextOffset == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Les profils des répondants sont indisponibles.'),
            ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(
              semanticsLabel: 'Chargement des réponses',
            ),
          )
        else if (_error != null) ...[
          AuthNotice(_error),
          OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
        ] else if (page?.nextOffset != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: _load,
              child: const Text('Voir plus de répondants'),
            ),
          ),
      ],
    );
  }
}
