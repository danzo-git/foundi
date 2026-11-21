import 'conversation_card.dart';
import 'dart:async';
import '../../proposals/presentation/proposal_certifications.dart';
import '../../../core/initial_event_timeout.dart';
import '../../auth/domain/account_photo_changes.dart';
import '../../auth/domain/auth_repository.dart';
import '../../safety/domain/safety_repository.dart';
import '../../safety/presentation/safety_widgets.dart';
export 'proposal_negotiation.dart' show SelectionPanel;
import 'proposal_negotiation.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../requests/presentation/request_views.dart';
import '../../requests/domain/request_repository.dart' show formatFcfa;
import '../domain/conversation_repository.dart';
import '../domain/rich_conversation_repository.dart';
import '../../proposals/presentation/proposal_views.dart';
import 'rich_message_widgets.dart';
import 'media_actions.dart';
import 'message_send_trace.dart';
import 'text_message_outbox.dart';
import '../../notifications/presentation/conversation_read_tracker.dart';

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
  Stream<List<Conversation>> _load() => withInitialEventTimeout(
    widget.repository.watchConversations(widget.uid, asProfessional: _clients),
  );
  late Stream<List<Conversation>> _stream = _load();
  @override
  void didUpdateWidget(ConversationListView old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository || old.uid != widget.uid) {
      _clients = widget.canShowClients && widget.initialProfessional;
      _stream = _load();
    } else if (!widget.canShowClients && _clients) {
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
              label: const Text('Mes réponses'),
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
        key: ValueKey('${widget.uid}:$_clients'),
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
              _ConversationCards(
                repository: widget.repository,
                uid: widget.uid,
                conversations: s.requireData,
                onOpen: widget.onOpen,
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

class _ConversationCards extends StatefulWidget {
  const _ConversationCards({
    required this.repository,
    required this.uid,
    required this.conversations,
    required this.onOpen,
  });
  final ConversationRepository repository;
  final String uid;
  final List<Conversation> conversations;
  final ValueChanged<String> onOpen;
  @override
  State<_ConversationCards> createState() => _ConversationCardsState();
}

class _ConversationCardsState extends State<_ConversationCards>
    with WidgetsBindingObserver {
  final _deleting = <String>{};
  bool _optionsOpen = false;
  Future<void> _options(Conversation conversation) async {
    final repository = widget.repository, uid = widget.uid;
    if (_optionsOpen ||
        _deleting.contains(conversation.id) ||
        repository is! ConversationDeletionRepository) {
      return;
    }
    _optionsOpen = true;
    try {
      final remove = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheet) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    conversation.otherName(uid),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: FoundiUi.ink,
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey('deleteConversationAction'),
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Supprimer la conversation',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(sheet, true),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, false),
                  child: const Text('Annuler'),
                ),
              ],
            ),
          ),
        ),
      );
      if (remove != true ||
          !mounted ||
          widget.uid != uid ||
          widget.repository != repository) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Supprimer la conversation ?'),
          content: Text(
            'Elle sera retirée de ta messagerie sur tous tes appareils. L’autre personne conserve son historique. Les nouveaux messages ne la feront pas réapparaître.${conversation.proposalStatus == 'retained' ? ' La proposition reste retenue.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              key: const ValueKey('confirmDeleteConversation'),
              onPressed: () => Navigator.pop(dialog, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          widget.uid != uid ||
          widget.repository != repository) {
        return;
      }
      setState(() => _deleting.add(conversation.id));
      try {
        await (repository as ConversationDeletionRepository).deleteConversation(
          conversation.id,
          viewerUid: uid,
        );
        if (mounted && widget.uid == uid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversation supprimée de ta messagerie.'),
            ),
          );
        }
      } catch (e) {
        if (mounted && widget.uid == uid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is AuthFailure
                    ? e.message
                    : 'Suppression non confirmée. Réessaie.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _deleting.remove(conversation.id));
      }
    } finally {
      _optionsOpen = false;
    }
  }

  late Future<Map<String, String>> _avatars = _load();
  late final StreamSubscription<void> _changes;
  String _identity(_ConversationCards value) =>
      '${value.uid}:${value.conversations.map((c) => '${c.id}/${c.clientUid}/${c.responderUid}').join(',')}';
  Future<Map<String, String>> _load() async {
    final repository = widget.repository;
    if (repository is! ConversationAvatarRepository) return {};
    try {
      return await (repository as ConversationAvatarRepository)
          .resolveConversationAvatars(
            widget.conversations.map((c) => c.id).take(30).toList(),
          );
    } catch (_) {
      return {};
    }
  }

  void _refresh() {
    if (mounted) setState(() => _avatars = _load());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = AccountPhotoChanges.stream.listen((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void didUpdateWidget(_ConversationCards old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository ||
        _identity(old) != _identity(widget) ||
        old.conversations.map((c) => '${c.updatedAt}:${c.status}').join(',') !=
            widget.conversations
                .map((c) => '${c.updatedAt}:${c.status}')
                .join(',')) {
      _avatars = _load();
    }
  }

  @override
  void dispose() {
    _changes.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
    key: ValueKey(_identity(widget)),
    future: _avatars,
    builder: (context, s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in widget.conversations)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ConversationCard(
              key: ValueKey('conversation-${c.id}'),
              conversation: c,
              viewerUid: widget.uid,
              onOpen: () => widget.onOpen(c.id),
              avatarKey: s.data?[c.id],
              onLongPress: widget.repository is ConversationDeletionRepository
                  ? () => _options(c)
                  : null,
              deleting: _deleting.contains(c.id),
            ),
          ),
      ],
    ),
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
    this.ownPhone = '',
    this.active = true,
    this.mediaActions = const PlatformConversationMediaActions(),
  });
  final ConversationRepository repository;
  final ProposalRepository? proposals;
  final String ownPhone;
  final bool active;
  final ConversationMediaActions mediaActions;
  final String id, uid;
  final VoidCallback onBack;
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  Stream<Conversation?> _watchConversation() =>
      withInitialEventTimeout(widget.repository.watchConversation(widget.id));
  late Stream<Conversation?> _conversation = _watchConversation();
  late TextMessageOutbox _outbox;
  late Stream<MessageBatch> _messages;
  String? error;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _limit = 30;
  Stream<MessageBatch> _watchMessages() {
    final outbox = _outbox;
    return withInitialEventTimeout(
      widget.repository.watchMessages(widget.id, limit: _limit).map((batch) {
        outbox.observe(batch);
        return batch;
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _bindOutbox();
  }

  void _bindOutbox() {
    _outbox = TextMessageOutbox.forConversation(
      widget.repository,
      widget.uid,
      widget.id,
    );
    _outbox.addListener(_outboxChanged);
    _messages = _watchMessages();
  }

  void _outboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.uid != widget.uid ||
        oldWidget.repository != widget.repository) {
      _outbox.removeListener(_outboxChanged);
      _limit = 30;
      _text.clear();
      error = null;
      _conversation = _watchConversation();
      _linkedId = null;
      _linkedProposal = null;
      _bindOutbox();
    } else if (oldWidget.proposals != widget.proposals) {
      _linkedId = null;
      _linkedProposal = null;
    }
  }

  Stream<Proposal?>? _linkedProposal;
  String? _linkedId;
  Stream<Proposal?> _proposalStream(String id) {
    if (_linkedId != id) {
      _linkedId = id;
      _linkedProposal = withInitialEventTimeout(
        widget.proposals!.watchProposal(id),
      );
    }
    return _linkedProposal!;
  }

  void _offer(Conversation chat) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SizedBox(
        height: min(
          MediaQuery.sizeOf(sheet).height * .85,
          max(
            0,
            MediaQuery.sizeOf(sheet).height -
                MediaQuery.viewInsetsOf(sheet).bottom -
                64,
          ),
        ),
        child: ProposalDetailView(
          repository: widget.proposals!,
          id: chat.selectedProposalId,
          onBack: () => Navigator.pop(sheet),
          actionsBuilder: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProposalDecisionPanel(
                repository: widget.repository,
                proposal: p,
                uid: widget.uid,
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Retour à la conversation'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _offerHeader(Conversation chat) => StreamBuilder<Proposal?>(
    stream: _proposalStream(chat.selectedProposalId),
    builder: (context, s) {
      if (s.hasError) {
        return TextButton(
          onPressed: () => _offer(chat),
          child: const Text('Réessayer de voir la proposition'),
        );
      }
      if (!s.hasData) {
        return s.connectionState == ConnectionState.waiting
            ? const SizedBox(height: 4, child: LinearProgressIndicator())
            : TextButton(
                onPressed: () => _offer(chat),
                child: const Text('Proposition liée indisponible'),
              );
      }
      final p = s.data!;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: FoundiPanel(
          onTap: () => _offer(chat),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Proposition liée',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${p.amount == null ? 'Montant à discuter' : '${formatFcfa(p.amount!)} FCFA'}${p.delay.isEmpty ? '' : ' · ${p.delay}'}',
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RequestTag(p.statusLabel),
                  TextButton(
                    onPressed: () => _offer(chat),
                    child: const Text('Voir la proposition'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  @override
  void dispose() {
    _outbox.removeListener(_outboxChanged);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(Conversation chat) {
    final clock = Stopwatch()..start();
    if (!chat.active ||
        ![chat.clientUid, chat.responderUid].contains(widget.uid)) {
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty || text.length > 2000) {
      setState(() => error = 'Écris un message de 1 à 2000 caractères.');
      return;
    }
    error = null;
    // Clear synchronously: a second tap cannot resubmit the same composer draft.
    _text.clear();
    _outbox.send(text, clock);
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
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
  void _decisions(Conversation chat) {
    final stream = withInitialEventTimeout(
      widget.proposals!.watchProposal(chat.selectedProposalId),
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder<Proposal?>(
          stream: stream,
          builder: (context, s) =>
              (s.hasError ||
                  (s.connectionState != ConnectionState.waiting &&
                      s.data == null))
              ? const AuthNotice('Proposition indisponible.')
              : !s.hasData
              ? const LinearProgressIndicator()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.data!.responderName,
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
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Conversation?>(
    key: ValueKey((widget.uid, widget.id, widget.repository)),
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
              onPressed: () =>
                  setState(() => _conversation = _watchConversation()),
              child: const Text('Réessayer'),
            ),
          ],
        );
      }
      if (!c.hasData) return const Center(child: CircularProgressIndicator());
      final chat = c.requireData!;
      return SafetyContactGate(
        target: SafetyTarget('conversation', widget.id),
        builder: (context, safety) {
          final canSend =
              chat.active &&
              safety?.contactAllowed == true &&
              [chat.clientUid, chat.responderUid].contains(widget.uid);
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
                        if (widget.proposals != null)
                          IconButton(
                            tooltip: 'Voir la proposition',
                            onPressed: () => _offer(chat),
                            icon: const Icon(Icons.description_outlined),
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
                  if (widget.proposals != null && widget.uid == chat.clientUid)
                    LiveProposalCertifications(
                      repository: widget.proposals!,
                      ids: [chat.selectedProposalId],
                      builder: (context, values) => Align(
                        alignment: Alignment.centerLeft,
                        child: proposalBadge(values, chat.selectedProposalId),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SafetyActionMenu(
                      target: SafetyTarget('conversation', widget.id),
                      allowBlock: true,
                    ),
                  ),
                  if (safety?.contactAllowed != true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        safety?.blocked == true
                            ? 'Utilisateur bloqué · Historique conservé'
                            : 'Contact indisponible · Vérification ou restriction en cours',
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RequestTag(
                              chat.active
                                  ? proposalStatusLabel(chat.proposalStatus)
                                  : 'Lecture seule',
                            ),
                            const Text(
                              'Voir la demande liée',
                              style: TextStyle(
                                fontSize: 11,
                                color: FoundiUi.green,
                              ),
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
                  if (!keyboardOpen && widget.proposals != null)
                    _offerHeader(chat),
                  Expanded(
                    child: StreamBuilder<MessageBatch>(
                      key: ValueKey((widget.uid, widget.id, widget.repository)),
                      stream: _messages,
                      builder: (context, s) {
                        if (!s.hasError &&
                            !s.hasData &&
                            _outbox.items.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final batch = s.hasError
                            ? const MessageBatch([])
                            : s.data ?? const MessageBatch([]);
                        final messages = _outbox.merge(batch);
                        return ConversationReadTracker(
                          conversationId: widget.id,
                          uid: widget.uid,
                          batch: batch,
                          scroll: _scroll,
                          active: widget.active && !s.hasError,
                          child: Column(
                            children: [
                              if (s.hasError) ...[
                                const AuthNotice(
                                  'Messages indisponibles. Vérifie ta connexion.',
                                ),
                                TextButton(
                                  onPressed: () => setState(
                                    () => _messages = _watchMessages(),
                                  ),
                                  child: const Text('Réessayer les messages'),
                                ),
                              ],
                              if (batch.fromCache)
                                const Text(
                                  'Historique local — connexion en cours…',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: FoundiUi.muted,
                                  ),
                                ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _scroll,
                                  reverse: true,
                                  padding: const EdgeInsets.all(20),
                                  itemCount: messages.length + 1,
                                  findChildIndexCallback: (key) {
                                    if (key ==
                                        const ValueKey('history-footer')) {
                                      return messages.length;
                                    }
                                    final index = messages.indexWhere(
                                      (m) =>
                                          key ==
                                          ValueKey('${widget.uid}:${m.id}'),
                                    );
                                    return index < 0 ? null : index;
                                  },
                                  itemBuilder: (context, index) {
                                    if (index < messages.length) {
                                      final m = messages[index];
                                      final outgoing = _outbox.item(m.id);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              MessageSendTrace.bubbleFrame(
                                                m.id,
                                              );
                                            }
                                          });
                                      return Align(
                                        key: ValueKey('${widget.uid}:${m.id}'),
                                        alignment: m.senderUid == widget.uid
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            maxWidth: 320,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: m.senderUid == widget.uid
                                                ? FoundiUi.tint
                                                : Colors.white,
                                            border: Border.all(
                                              color: FoundiUi.line,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              if (m.senderUid != widget.uid)
                                                SafetyActionMenu(
                                                  target: SafetyTarget(
                                                    'message',
                                                    m.id,
                                                    conversationId: widget.id,
                                                  ),
                                                ),
                                              RichMessageBody(
                                                key: ValueKey(
                                                  '${widget.uid}:${m.id}',
                                                ),
                                                message: m,
                                                id: widget.id,
                                                uid: widget.uid,
                                                repository:
                                                    widget.repository
                                                        is RichConversationRepository
                                                    ? widget.repository
                                                          as RichConversationRepository
                                                    : null,
                                                actions: widget.mediaActions,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _time(m.createdAt),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: FoundiUi.muted,
                                                ),
                                              ),
                                              if (m.senderUid == widget.uid &&
                                                  m.type == 'text') ...[
                                                Text(
                                                  switch (outgoing?.delivery) {
                                                    TextDelivery.sending =>
                                                      'Envoi en cours',
                                                    TextDelivery.failed =>
                                                      'Échec de l’envoi',
                                                    _ => 'Envoyé',
                                                  },
                                                  key: ValueKey(
                                                    'delivery-${m.id}',
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: FoundiUi.muted,
                                                  ),
                                                ),
                                                if (outgoing?.delivery ==
                                                    TextDelivery.failed) ...[
                                                  Text(
                                                    outgoing!.error!,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  if (canSend)
                                                    TextButton(
                                                      key: ValueKey(
                                                        'retry-${m.id}',
                                                      ),
                                                      onPressed: () =>
                                                          _outbox.retry(m.id),
                                                      child: const Text(
                                                        'Réessayer',
                                                      ),
                                                    ),
                                                ],
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return Column(
                                      key: const ValueKey('history-footer'),
                                      children: [
                                        if (messages.isEmpty && !s.hasError)
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
                                              _messages = _watchMessages();
                                            }),
                                            child: const Text(
                                              'Charger les anciens messages',
                                            ),
                                          ),
                                        if (_limit == 100 &&
                                            batch.messages.length == 100)
                                          const Text(
                                            'Les 100 messages les plus récents sont affichés.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: FoundiUi.muted,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
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
                  if (canSend)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Column(
                          children: [
                            AuthNotice(error),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (widget.repository
                                    is RichConversationRepository)
                                  ConversationExtrasButton(
                                    repository: widget.repository,
                                    id: widget.id,
                                    uid: widget.uid,
                                    phone: widget.ownPhone,
                                    actions: widget.mediaActions,
                                  ),
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey('messageText'),
                                    controller: _text,
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
                                  onPressed: () => _send(chat),
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
    },
  );
  String _time(int timestamp) {
    final t = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${requestDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
