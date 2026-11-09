import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/proposal_repository.dart';

class ProposalAction extends StatefulWidget {
  const ProposalAction({
    super.key,
    required this.repository,
    required this.request,
    required this.approved,
    required this.onCompose,
    required this.onOpen,
    this.onProfile,
  });
  final ProposalRepository repository;
  final FoundiRequest request;
  final bool approved;
  final VoidCallback onCompose;
  final ValueChanged<String> onOpen;
  final VoidCallback? onProfile;
  @override
  State<ProposalAction> createState() => _ProposalActionState();
}

class _ProposalActionState extends State<ProposalAction> {
  late Future<ProposalAccess>? _access = widget.approved
      ? widget.repository.proposalAccess(widget.request.id)
      : null;
  @override
  void didUpdateWidget(ProposalAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.approved != widget.approved ||
        oldWidget.request.id != widget.request.id) {
      _access = widget.approved
          ? widget.repository.proposalAccess(widget.request.id)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.approved) {
      return Column(
        children: [
          const RequestNotice(
            'Accès professionnel requis',
            'Seul un dossier professionnel approuvé permet de faire une proposition. Le changement d’espace ne suffit pas.',
          ),
          if (widget.onProfile != null)
            TextButton(
              onPressed: widget.onProfile,
              child: const Text('Consulter mon profil'),
            ),
        ],
      );
    }
    if (widget.request.status != 'published') {
      return const RequestNotice(
        'Demande indisponible',
        'Cette demande ne reçoit plus de propositions.',
      );
    }
    return FutureBuilder<ProposalAccess>(
      future: _access,
      builder: (context, s) {
        if (s.hasError) {
          return Column(
            children: [
              AuthNotice(
                s.error is AuthFailure
                    ? (s.error as AuthFailure).message
                    : 'Impossible de vérifier le droit d’envoi.',
              ),
              TextButton(
                onPressed: () => setState(
                  () => _access = widget.repository.proposalAccess(
                    widget.request.id,
                  ),
                ),
                child: const Text('Revérifier l’accès'),
              ),
            ],
          );
        }
        if (!s.hasData) {
          return const LinearProgressIndicator();
        }
        if (s.requireData.proposalId != null) {
          return OutlinedButton(
            onPressed: () => widget.onOpen(s.requireData.proposalId!),
            child: const Text('Voir ma proposition envoyée'),
          );
        }
        return FilledButton(
          onPressed: s.requireData.canSend ? widget.onCompose : null,
          child: const Text('Faire une proposition'),
        );
      },
    );
  }
}

class ProposalComposer extends StatefulWidget {
  const ProposalComposer({
    super.key,
    required this.repository,
    required this.request,
    required this.onBack,
    required this.onSent,
  });
  final ProposalRepository repository;
  final FoundiRequest request;
  final VoidCallback onBack, onSent;
  @override
  State<ProposalComposer> createState() => _ProposalComposerState();
}

class _ProposalComposerState extends AuthActionState<ProposalComposer> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController(),
      _amount = TextEditingController(),
      _delay = TextEditingController();
  bool _preview = false;
  Proposal? _sent;
  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _delay.dispose();
    super.dispose();
  }

  ProposalDraft get _draft => ProposalDraft(
    description: _description.text,
    amount: RequestDraft.parseBudget(_amount.text),
    delay: _delay.text,
  );
  Future<void> _send() async {
    if (busy) return;
    final ok = await perform(() async {
      _sent = await widget.repository.sendProposal(widget.request.id, _draft);
    });
    if (ok && mounted) setState(() {});
  }

  void _back() {
    if (busy) return;
    if (_preview && _sent == null) {
      setState(() => _preview = false);
    } else {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        RequestHeading(
          _sent != null
              ? 'Proposition envoyée'
              : _preview
              ? 'Vérifier ma proposition'
              : 'Faire une proposition',
          onBack: busy ? null : _back,
        ),
        Text(
          widget.request.title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        if (_sent != null) ...[
          const CircleAvatar(
            radius: 45,
            backgroundColor: FoundiUi.tint,
            child: Icon(Icons.check, size: 40, color: FoundiUi.green),
          ),
          const SizedBox(height: 20),
          const RequestNotice(
            'C’est envoyé !',
            'Ta proposition privée est enregistrée. Le client peut la consulter.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.onSent,
            child: const Text('Voir mes propositions'),
          ),
        ] else if (!_preview) ...[
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  key: const ValueKey('proposalDescription'),
                  controller: _description,
                  enabled: !busy,
                  minLines: 5,
                  maxLines: 9,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'Ta proposition *',
                    alignLabelWithHint: true,
                  ),
                  validator: (s) => (s?.trim().length ?? 0) < 10
                      ? 'Décris ta solution (10 caractères minimum).'
                      : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('proposalAmount'),
                  controller: _amount,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Montant (facultatif)',
                    suffixText: 'FCFA',
                  ),
                  validator: (s) {
                    try {
                      final value = RequestDraft.parseBudget(s ?? '');
                      if (value != null && value <= 0) {
                        return 'Le montant doit être strictement positif.';
                      }
                      return null;
                    } on FormatException {
                      return 'Montant entier positif, 12 chiffres maximum.';
                    }
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('proposalDelay'),
                  controller: _delay,
                  enabled: !busy,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Délai (facultatif)',
                  ),
                  validator: (s) => (s?.trim().length ?? 0) > 120
                      ? '120 caractères maximum.'
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const RequestNotice(
            'Proposition privée',
            'Présente ta solution, le montant et le délai si tu les connais. Aucune coordonnée personnelle ni pièce jointe n’est requise.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    if (_form.currentState!.validate()) {
                      FocusScope.of(context).unfocus();
                      setState(() => _preview = true);
                    }
                  },
            child: const Text('Prévisualiser ma proposition'),
          ),
        ] else ...[
          FoundiPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RequestTag('Proposition privée'),
                const SizedBox(height: 16),
                Text(_draft.description),
                const SizedBox(height: 16),
                Text(
                  _draft.amount == null
                      ? 'Montant à discuter'
                      : '${formatFcfa(_draft.amount!)} FCFA',
                ),
                if (_draft.delay.isNotEmpty) Text('Délai : ${_draft.delay}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Confirme cet envoi au client. Une seule proposition est autorisée pour cette demande ; aucune modification ni retrait n’est prévu dans ce sprint.',
          ),
          const SizedBox(height: 20),
          AuthNotice(error),
          if (busy) const LinearProgressIndicator(),
          FilledButton(
            key: const ValueKey('sendProposal'),
            onPressed: busy ? null : _send,
            child: const Text('Confirmer et envoyer'),
          ),
          TextButton(
            onPressed: busy ? null : () => setState(() => _preview = false),
            child: const Text('Modifier ma proposition'),
          ),
        ],
      ],
    ),
  );
}

class ProposalListView extends StatefulWidget {
  const ProposalListView({
    super.key,
    required this.repository,
    required this.uid,
    required this.received,
    required this.onOpen,
    required this.onBack,
    this.requestId,
  });
  final ProposalRepository repository;
  final String uid;
  final bool received;
  final String? requestId;
  final ValueChanged<String> onOpen;
  final VoidCallback onBack;
  @override
  State<ProposalListView> createState() => _ProposalListViewState();
}

class _ProposalListViewState extends State<ProposalListView> {
  Stream<List<Proposal>> _load() => widget.received
      ? widget.repository.watchReceivedProposals(
          widget.uid,
          requestId: widget.requestId,
        )
      : widget.repository.watchSentProposals(widget.uid);
  late Stream<List<Proposal>> _stream = _load();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      RequestHeading(
        widget.received ? 'Propositions reçues' : 'Mes propositions',
        onBack: widget.onBack,
      ),
      StreamBuilder<List<Proposal>>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError) {
            return Column(
              children: [
                const AuthNotice('Impossible de charger les propositions.'),
                TextButton(
                  onPressed: () => setState(() => _stream = _load()),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.requireData.isEmpty) {
            return RequestNotice(
              widget.received
                  ? 'Aucune proposition reçue'
                  : 'Aucune proposition envoyée',
              'Les propositions apparaîtront ici lorsqu’elles seront enregistrées.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in s.requireData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: FoundiPanel(
                    onTap: () => widget.onOpen(p.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RequestTag(p.statusLabel),
                        const SizedBox(height: 12),
                        Text(
                          p.requestTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        if (widget.received) Text(p.professionalName),
                        const SizedBox(height: 10),
                        Text(
                          p.amount == null
                              ? 'Montant à discuter'
                              : '${formatFcfa(p.amount!)} FCFA',
                        ),
                        if (p.delay.isNotEmpty) Text(p.delay),
                        Text(
                          requestDate(
                            DateTime.fromMillisecondsSinceEpoch(p.createdAt),
                          ),
                        ),
                        Text(
                          p.status == 'rejected'
                              ? 'Consulter l’historique  ›'
                              : p.conversationId != null
                              ? 'Reprendre la discussion  ›'
                              : 'Voir et discuter  ›',
                          style: TextStyle(color: FoundiUi.green),
                        ),
                      ],
                    ),
                  ),
                ),
              const Text(
                'Les 30 propositions les plus récentes.',
                style: TextStyle(color: FoundiUi.muted, fontSize: 12),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class ProposalDetailView extends StatefulWidget {
  const ProposalDetailView({
    super.key,
    required this.repository,
    required this.id,
    required this.onBack,
    this.actionsBuilder,
    this.professionalProfileAction,
  });
  final Widget Function(Proposal)? actionsBuilder;
  final VoidCallback? Function(Proposal)? professionalProfileAction;
  final ProposalRepository repository;
  final String id;
  final VoidCallback onBack;
  @override
  State<ProposalDetailView> createState() => _ProposalDetailViewState();
}

class _ProposalDetailViewState extends State<ProposalDetailView> {
  late Stream<Proposal?> _stream = widget.repository.watchProposal(widget.id);
  Future<bool>? _approval;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      RequestHeading('Détail de la proposition', onBack: widget.onBack),
      StreamBuilder<Proposal?>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError ||
              (s.connectionState != ConnectionState.waiting &&
                  s.data == null)) {
            return Column(
              children: [
                const AuthNotice(
                  'Cette proposition est privée ou indisponible.',
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _stream = widget.repository.watchProposal(widget.id);
                    _approval = null;
                  }),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = s.requireData!;
          final openProfile = widget.professionalProfileAction?.call(p);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestTag(p.statusLabel),
              const SizedBox(height: 18),
              Text(
                p.requestTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                p.professionalName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              FutureBuilder<bool>(
                future: _approval ??= widget.repository.proposalApproval(
                  widget.id,
                ),
                builder: (context, a) => Text(
                  a.data == true
                      ? 'Professionnel actuellement approuvé'
                      : a.hasError
                      ? 'Vérification actuelle indisponible'
                      : a.hasData
                      ? 'Vérification professionnelle non active'
                      : 'Vérification en cours…',
                  style: const TextStyle(color: FoundiUi.muted, fontSize: 12),
                ),
              ),
              if (openProfile != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: openProfile,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Voir le profil professionnel'),
                  ),
                ),
              const SizedBox(height: 20),
              FoundiPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.description),
                    const SizedBox(height: 16),
                    Text(
                      p.amount == null
                          ? 'Montant à discuter'
                          : '${formatFcfa(p.amount!)} FCFA',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: FoundiUi.green,
                      ),
                    ),
                    if (p.delay.isNotEmpty) Text('Délai : ${p.delay}'),
                    Text(
                      requestDate(
                        DateTime.fromMillisecondsSinceEpoch(p.createdAt),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (widget.actionsBuilder != null)
                widget.actionsBuilder!(p)
              else
                const RequestNotice(
                  'Consultation uniquement',
                  'Cette proposition est envoyée. Aucune acceptation ni conversation n’est ouverte ici.',
                ),
            ],
          );
        },
      ),
    ],
  );
}
