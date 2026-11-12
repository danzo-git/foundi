import 'package:flutter/material.dart';

import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/presentation/professional_showcase_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listRequestRespondents(
        widget.requestId,
        offset: _page?.nextOffset ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _items.addAll(page.items);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AuthFailure
              ? error.message
              : 'Impossible de charger les réponses.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (repository is! RequestRespondentProfileRepository || id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalShowcaseScreen.recommended(
          professionalId: id,
          loadRecommended: () =>
              (repository as RequestRespondentProfileRepository)
                  .readRequestRespondentProfile(widget.requestId, id),
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
