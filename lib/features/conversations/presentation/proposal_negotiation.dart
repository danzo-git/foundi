import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/conversation_repository.dart';

class SelectionPanel extends StatefulWidget {
  const SelectionPanel({
    super.key,
    required this.repository,
    required this.proposals,
    required this.proposal,
    required this.uid,
    required this.onOpen,
    required this.onMine,
  });
  final ConversationRepository repository;
  final ProposalRepository proposals;
  final Proposal proposal;
  final String uid;
  final ValueChanged<String> onOpen;
  final VoidCallback onMine;
  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends AuthActionState<SelectionPanel> {
  late final _own = widget.repository.watchOwnSelection(
    widget.uid,
    widget.proposal.requestId,
  );
  Future<void> _discuss() async {
    if (busy) return;
    String? id;
    final ok = await perform(() async {
      id = (await widget.repository.selectProposal(
        widget.proposal.requestId,
        widget.proposal.id,
      )).conversationId;
    });
    if (ok && mounted) widget.onOpen(id!);
  }

  Widget _open() => FilledButton(
    onPressed: busy
        ? null
        : () => widget.onOpen(widget.proposal.conversationId!),
    child: Text(
      widget.proposal.status == 'rejected'
          ? 'Consulter l’historique'
          : 'Ouvrir la discussion',
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.uid != widget.proposal.clientUid) {
      return widget.proposal.conversationId != null
          ? _open()
          : const RequestNotice(
              'Proposition envoyée',
              'Le client peut ouvrir une discussion privée avec vous.',
            );
    }
    return StreamBuilder<FoundiRequest?>(
      stream: _own,
      builder: (context, s) {
        if (s.hasError) {
          return const AuthNotice('Impossible de vérifier la demande.');
        }
        if (!s.hasData) return const LinearProgressIndicator();
        final request = s.requireData!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RequestNotice(
              'Discuter, comparer, décider',
              'Ouvrir une discussion ne vous engage pas. La demande reste ouverte aux nouvelles propositions jusqu’à sa clôture.',
            ),
            const SizedBox(height: 16),
            AuthNotice(error),
            if (busy) const LinearProgressIndicator(),
            if (widget.proposal.conversationId != null)
              _open()
            else if (request.status == 'published' &&
                widget.proposal.status != 'rejected')
              FilledButton(
                onPressed: busy ? null : _discuss,
                child: const Text('Discuter avec ce professionnel'),
              ),
            if (widget.proposal.status == 'rejected')
              const RequestNotice(
                'Proposition refusée',
                'L’historique reste consultable. Cette proposition ne peut pas être retenue à nouveau.',
              ),
            const SizedBox(height: 12),
            ProposalDecisionPanel(
              repository: widget.repository,
              proposal: widget.proposal,
              uid: widget.uid,
            ),
          ],
        );
      },
    );
  }
}

class ProposalDecisionPanel extends StatefulWidget {
  const ProposalDecisionPanel({
    super.key,
    required this.repository,
    required this.proposal,
    required this.uid,
  });
  final ConversationRepository repository;
  final Proposal proposal;
  final String uid;
  @override
  State<ProposalDecisionPanel> createState() => _ProposalDecisionPanelState();
}

class _ProposalDecisionPanelState
    extends AuthActionState<ProposalDecisionPanel> {
  late final _own = widget.repository.watchOwnSelection(
    widget.uid,
    widget.proposal.requestId,
  );
  bool _confirming = false;
  String? _decisionId, _signature, _success;
  Future<void> _decide(String action, FoundiRequest request) async {
    if (busy || _confirming) return;
    _confirming = true;
    final replacing =
        action == 'retain' &&
        request.retainedProposalId != null &&
        request.retainedProposalId != widget.proposal.id;
    var reason = '';
    final expected = request.retainedProposalId;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              action == 'reject'
                  ? 'Refuser cette proposition ?'
                  : replacing
                  ? 'Remplacer la proposition retenue ?'
                  : 'Retenir cette proposition ?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              action == 'reject'
                  ? 'Seule cette proposition sera refusée. Sa discussion sera archivée en lecture seule et son historique conservé.'
                  : replacing
                  ? 'La proposition de ${request.retainedProfessionalName ?? 'l’autre professionnel'} ne sera plus retenue. Vous retiendrez celle de ${widget.proposal.professionalName}. Les autres discussions seront conservées.'
                  : 'Vous retenez la proposition de ${widget.proposal.professionalName}. Ce choix n’est ni un contrat signé, ni un paiement, ni une prestation terminée.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Cette décision ne clôture pas la demande et n’arrête pas les nouvelles propositions.',
            ),
            if (action == 'reject') ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('rejectionReason'),
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motif facultatif',
                ),
                onChanged: (v) => reason = v.trim(),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                action == 'reject'
                    ? 'Confirmer le refus'
                    : replacing
                    ? 'Confirmer le remplacement'
                    : 'Confirmer la retenue',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
    _confirming = false;
    if (!mounted || confirmed != true) return;
    final signature = '$action|$expected|$reason';
    if (_signature != signature) {
      _signature = signature;
      _decisionId = widget.repository.newDecisionId(widget.proposal.requestId);
    }
    final ok = await perform(
      () => widget.repository.decideProposal(
        widget.proposal.requestId,
        widget.proposal.id,
        action,
        decisionId: _decisionId!,
        expectedRetainedProposalId: expected,
        reason: reason,
      ),
    );
    if (ok && mounted) {
      setState(
        () => _success = action == 'reject'
            ? 'Proposition refusée'
            : 'Proposition retenue',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid != widget.proposal.clientUid) return const SizedBox.shrink();
    return StreamBuilder<FoundiRequest?>(
      stream: _own,
      builder: (context, s) {
        if (s.hasError) {
          return const AuthNotice(
            'Décisions indisponibles. Réessaie après actualisation.',
          );
        }
        if (!s.hasData) return const LinearProgressIndicator();
        if (!['published', 'closed'].contains(s.data!.status)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthNotice(error),
            if (_success != null)
              Text(
                _success!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (busy) const LinearProgressIndicator(),
            if (widget.proposal.status != 'rejected') ...[
              OutlinedButton(
                onPressed: busy || widget.proposal.status == 'retained'
                    ? null
                    : () => _decide('retain', s.data!),
                child: Text(
                  widget.proposal.status == 'retained'
                      ? 'Proposition retenue'
                      : 'Retenir cette proposition',
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _decide('reject', s.data!),
                child: const Text('Refuser cette proposition'),
              ),
            ],
          ],
        );
      },
    );
  }
}
