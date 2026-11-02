export 'proposal_negotiation.dart' show SelectionPanel;
import 'proposal_negotiation.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/conversation_repository.dart';

class ConversationListView extends StatefulWidget {
  const ConversationListView({
    super.key,
    required this.repository,
    required this.uid,
    required this.canShowClients,
    required this.onOpen,
    required this.onExplore,
    this.initialProfessional = false,
  });
  final ConversationRepository repository;
  final String uid;
  final bool canShowClients, initialProfessional;
  final ValueChanged<String> onOpen;
  final VoidCallback onExplore;
  @override
  State<ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<ConversationListView> {
  late bool _clients = widget.canShowClients && widget.initialProfessional;
  Stream<List<Conversation>> _load() => widget.repository.watchConversations(
    widget.uid,
    asProfessional: _clients,
  );
  late Stream<List<Conversation>> _stream = _load();
  @override
  void didUpdateWidget(ConversationListView old) {
    super.didUpdateWidget(old);
    if (!widget.canShowClients && _clients) {
      _clients = false;
      _stream = _load();
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const RequestHeading('Messages', subtitle: 'Vos échanges'),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Mes recherches'),
            selected: !_clients,
            onSelected: (_) => setState(() {
              _clients = false;
              _stream = _load();
            }),
          ),
          if (widget.canShowClients)
            ChoiceChip(
              label: const Text('Mes clients'),
              selected: _clients,
              onSelected: (_) => setState(() {
                _clients = true;
                _stream = _load();
              }),
            ),
        ],
      ),
      const SizedBox(height: 20),
      StreamBuilder<List<Conversation>>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError) {
            return Column(
              children: [
                const AuthNotice(
                  'Impossible de charger les conversations. Vérifie ta connexion.',
                ),
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
            return Column(
              children: [
                const SizedBox(height: 60),
                const CircleAvatar(
                  radius: 60,
                  backgroundColor: FoundiUi.tint,
                  child: Icon(
                    Icons.mail_outline,
                    size: 48,
                    color: FoundiUi.green,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Aucune conversation',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Les conversations apparaîtront ici lorsqu’un client ouvrira une discussion.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: widget.onExplore,
                  child: const Text('Explorer les demandes'),
                ),
                const SizedBox(height: 24),
                const RequestNotice(
                  'Une discussion privée par proposition',
                  'Seul le client peut ouvrir une discussion à partir d’une proposition reçue.',
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in s.requireData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FoundiPanel(
                    onTap: () => widget.onOpen(c.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.otherName(widget.uid),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(c.requestTitle),
                        const SizedBox(height: 10),
                        Text(
                          c.lastMessagePreview.isEmpty
                              ? 'Discussion prête — écrire un message'
                              : c.lastMessagePreview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: FoundiUi.muted),
                        ),
                        const SizedBox(height: 8),
                        RequestTag(
                          c.active
                              ? proposalStatusLabel(c.proposalStatus)
                              : 'Lecture seule',
                        ),
                        Text(
                          requestDate(
                            DateTime.fromMillisecondsSinceEpoch(c.updatedAt),
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: FoundiUi.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Text(
                'Les 30 conversations les plus récentes.',
                style: TextStyle(fontSize: 12, color: FoundiUi.muted),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class ConversationView extends StatefulWidget {
  const ConversationView({
    super.key,
    required this.repository,
    required this.id,
    required this.uid,
    required this.onBack,
    this.proposals,
  });
  final ConversationRepository repository;
  final ProposalRepository? proposals;
  final String id, uid;
  final VoidCallback onBack;
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends AuthActionState<ConversationView> {
  late Stream<Conversation?> _conversation = widget.repository
      .watchConversation(widget.id);
  late Stream<MessageBatch> _messages = widget.repository.watchMessages(
    widget.id,
  );
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _limit = 30;
  String? _pendingId, _pendingText;
  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy) return;
    final text = _text.text.trim();
    if (text.isEmpty || text.length > 2000) {
      setState(() => error = 'Écris un message de 1 à 2000 caractères.');
      return;
    }
    if (_pendingId == null || text != _pendingText) {
      _pendingId = widget.repository.newMessageId(widget.id);
      _pendingText = text;
    }
    final ok = await perform(
      () => widget.repository.sendConversationMessage(
        widget.id,
        _pendingId!,
        text,
      ),
    );
    if (ok && mounted) {
      _text.clear();
      _pendingId = null;
      _pendingText = null;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _request(Conversation c) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: RequestContent(c.requestSnapshot),
    ),
  );
  void _decisions(Conversation chat) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<Proposal?>(
        stream: widget.proposals!.watchProposal(chat.selectedProposalId),
        builder: (context, s) => s.hasError
            ? const AuthNotice('Proposition indisponible.')
            : !s.hasData
            ? const LinearProgressIndicator()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.data!.professionalName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  RequestTag(s.data!.statusLabel),
                  if (s.data!.status == 'rejected')
                    const Text(
                      'Proposition refusée. Discussion archivée en lecture seule.',
                    ),
                  ProposalDecisionPanel(
                    key: ValueKey(s.data!.id),
                    repository: widget.repository,
                    proposal: s.data!,
                    uid: widget.uid,
                  ),
                ],
              ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<Conversation?>(
    stream: _conversation,
    builder: (context, c) {
      if (c.hasError ||
          (c.connectionState != ConnectionState.waiting && c.data == null)) {
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            RequestHeading('Discussion privée', onBack: widget.onBack),
            const AuthNotice('Cette discussion est privée ou indisponible.'),
            TextButton(
              onPressed: () => setState(
                () => _conversation = widget.repository.watchConversation(
                  widget.id,
                ),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        );
      }
      if (!c.hasData) return const Center(child: CircularProgressIndicator());
      final chat = c.requireData!;
      return LayoutBuilder(
        builder: (context, constraints) {
          final keyboardOpen =
              MediaQuery.viewInsetsOf(context).bottom > 0 ||
              constraints.maxHeight < 480;
          return Column(
            children: [
              if (keyboardOpen)
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      tooltip: 'Retour',
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        chat.otherName(widget.uid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Voir la demande liée',
                      onPressed: () => _request(chat),
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: RequestHeading(
                    chat.otherName(widget.uid),
                    onBack: widget.onBack,
                  ),
                ),
              if (!keyboardOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: FoundiPanel(
                    onTap: () => _request(chat),
                    color: FoundiUi.tint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          chat.requestTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        RequestTag(
                          chat.active
                              ? proposalStatusLabel(chat.proposalStatus)
                              : 'Lecture seule',
                        ),
                        const Text(
                          'Voir la demande liée',
                          style: TextStyle(fontSize: 11, color: FoundiUi.green),
                        ),
                      ],
                    ),
                  ),
                ),
              if (chat.active &&
                  widget.proposals != null &&
                  widget.uid == chat.clientUid &&
                  !keyboardOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _decisions(chat),
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('Retenir ou refuser'),
                  ),
                ),
              Expanded(
                child: StreamBuilder<MessageBatch>(
                  stream: _messages,
                  builder: (context, s) {
                    if (s.hasError) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AuthNotice(
                            'Messages indisponibles. Vérifie ta connexion.',
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _messages = widget.repository.watchMessages(
                                widget.id,
                                limit: _limit,
                              ),
                            ),
                            child: const Text('Réessayer les messages'),
                          ),
                        ],
                      );
                    }
                    if (!s.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final batch = s.requireData;
                    return Column(
                      children: [
                        if (batch.fromCache)
                          const Text(
                            'Historique local — connexion en cours…',
                            style: TextStyle(
                              fontSize: 11,
                              color: FoundiUi.muted,
                            ),
                          ),
                        Expanded(
                          child: ListView(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.all(20),
                            children: [
                              for (final m in batch.messages)
                                Align(
                                  alignment: m.senderUid == widget.uid
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 14),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: m.senderUid == widget.uid
                                          ? FoundiUi.tint
                                          : Colors.white,
                                      border: Border.all(color: FoundiUi.line),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(m.text),
                                        const SizedBox(height: 6),
                                        Text(
                                          _time(m.createdAt),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: FoundiUi.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (batch.messages.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Text(
                                    chat.active
                                        ? 'La discussion est prête. Écrivez votre premier message.'
                                        : 'Aucun message dans cet historique.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (batch.messages.length >= _limit &&
                                  _limit < 100)
                                TextButton(
                                  onPressed: () => setState(() {
                                    _limit = min(100, _limit + 30);
                                    _messages = widget.repository.watchMessages(
                                      widget.id,
                                      limit: _limit,
                                    );
                                  }),
                                  child: const Text(
                                    'Charger les anciens messages',
                                  ),
                                ),
                              if (_limit == 100 && batch.messages.length == 100)
                                const Text(
                                  'Les 100 messages les plus récents sont affichés.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: FoundiUi.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (!chat.active)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: RequestNotice(
                    chat.proposalStatus == 'rejected'
                        ? 'Proposition refusée · Lecture seule'
                        : 'Discussion en lecture seule',
                    chat.proposalStatus == 'rejected'
                        ? 'Cette discussion est archivée après refus de la proposition. L’historique reste consultable.'
                        : 'La demande a été supprimée. L’historique reste consultable.',
                  ),
                ),
              if (chat.active)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      children: [
                        AuthNotice(error),
                        if (busy) const LinearProgressIndicator(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('messageText'),
                                controller: _text,
                                enabled: !busy,
                                minLines: 1,
                                maxLines: keyboardOpen ? 2 : 4,
                                maxLength: 2000,
                                decoration: const InputDecoration(
                                  hintText: 'Écrire un message…',
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              key: const ValueKey('sendMessage'),
                              tooltip: 'Envoyer le message',
                              onPressed: busy ? null : _send,
                              icon: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
  String _time(int timestamp) {
    final t = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${requestDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
