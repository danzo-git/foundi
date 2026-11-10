import '../../conversations/domain/conversation_repository.dart';
import '../../conversations/presentation/conversation_views.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../proposals/presentation/proposal_views.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/account_screen.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../../professional/domain/professional_showcase.dart';
import '../../professional/presentation/professional_showcase_screen.dart';
import '../../professional/presentation/professional_status_label.dart';
import 'settings_view.dart';
import '../../requests/presentation/explorer_view.dart';
import 'space_widgets.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/domain/request_interaction_repository.dart';
import '../../requests/presentation/request_action_bar.dart';
import '../../requests/presentation/request_composer.dart';
import '../../requests/presentation/request_views.dart';
import '../../notifications/presentation/notification_views.dart';
import '../../notifications/domain/notification_repository.dart';

class FoundiShell extends StatefulWidget {
  const FoundiShell({
    super.key,
    required this.user,
    required this.auth,
    this.professional = const ProfessionalProfile(),
    this.professionalRepository,
    this.onDossier,
    this.active = true,
    this.requestRepository,
    this.catalogRepository,
  });
  final FoundiUser user;
  final AuthRepository auth;
  final ProfessionalProfile professional;
  final ProfessionalRepository? professionalRepository;
  final VoidCallback? onDossier;
  final bool active;
  final RequestRepository? requestRepository;
  final ProfessionalRepository? catalogRepository;
  @override
  State<FoundiShell> createState() => _FoundiShellState();
}

class _FoundiShellState extends AuthActionState<FoundiShell> {
  NotificationScope? _notifications;
  bool _openingNotification = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = NotificationScope.maybeOf(context);
    if (_notifications?.intent != scope?.intent) {
      _notifications?.intent.removeListener(_notificationIntentChanged);
      _notifications = scope;
      scope?.intent.addListener(_notificationIntentChanged);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _notificationIntentChanged(),
      );
    }
  }

  @override
  void dispose() {
    _notifications?.intent.removeListener(_notificationIntentChanged);
    super.dispose();
  }

  void _notificationIntentChanged() {
    if (!mounted || !widget.active || _openingNotification) return;
    final intent = _notifications?.intent.value;
    if (intent == null) return;
    _notifications!.intent.value = null;
    if (intent.uid != widget.user.id) {
      _notificationUnavailable();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _openNotification(intent.id, push: true);
  }

  void _notificationUnavailable() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Ce contenu n’est plus disponible ou cet accès n’est plus autorisé.',
      ),
    ),
  );
  Future<void> _openNotification(String id, {bool push = false}) async {
    final scope = _notifications;
    if (scope == null || _openingNotification) return;
    _openingNotification = true;
    try {
      final target = await scope.repository.resolve(id);
      if (!mounted || widget.auth.currentUser?.id != widget.user.id) return;
      if (push) await scope.repository.markRead(widget.user.id, id);
      if (!mounted) return;
      switch (target.type) {
        case 'professional':
          _dossier();
        case 'conversation':
          if (_conversations == null) {
            _notificationUnavailable();
            return;
          }
          _openConversation(target.id, 'messages');
        case 'proposal':
          if (_proposals == null) {
            _notificationUnavailable();
            return;
          }
          _openProposal(target.id, 'sentProposals');
        case 'requestProposals':
          _receivedReturn = 'mine';
          _receivedRequestId = target.id;
          _showRequests('receivedProposals');
        case 'recommendation':
          final repository = widget.requestRepository?.interactionRepository;
          if (repository == null) {
            _notificationUnavailable();
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfessionalShowcaseScreen.recommended(
                loadRecommended: () =>
                    repository.readRequestRecommendation(target.id),
              ),
            ),
          );
        case 'opportunity':
          if (!widget.professional.approved ||
              widget.requestRepository == null) {
            _notificationUnavailable();
            return;
          }
          setState(() => _professional = true);
          _requestId = target.id;
          _requestReturn = 'explore';
          _showRequests('detail');
        default:
          _notificationUnavailable();
      }
    } catch (_) {
      if (mounted) {
        _notificationUnavailable();
      }
    } finally {
      _openingNotification = false;
      if (mounted && _notifications?.intent.value != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _notificationIntentChanged(),
        );
      }
    }
  }

  void _inbox() {
    final scope = _notifications;
    if (scope == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (inboxContext) => NotificationInbox(
          repository: scope.repository,
          uid: widget.user.id,
          permission: scope.permission,
          onOpen: (id) async {
            final target = await scope.repository.resolve(id);
            if (!mounted || !inboxContext.mounted) return;
            // Resolve before dismissing, then revalidate again in the shell during navigation.
            if (target.id.isEmpty) return;
            Navigator.pop(inboxContext);
            await _openNotification(id);
          },
        ),
      ),
    );
  }

  void _notificationSettings() {
    final scope = _notifications;
    if (scope != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NotificationSettings(
            repository: scope.repository,
            uid: widget.user.id,
            permission: scope.permission,
          ),
        ),
      );
    }
  }

  late bool _professional =
      widget.professional.approved &&
      widget.user.profile.preferredMode == 'professional';
  bool _settings = false;
  BuildContext? _selectorContext;
  FoundiRequest? _editing, _proposalRequest;
  GlobalKey<RequestComposerState>? _editKey;
  String? _proposalId, _receivedRequestId, _conversationId;
  String _conversationReturn = 'messages';
  ConversationRepository? get _conversations =>
      widget.requestRepository is ConversationRepository
      ? widget.requestRepository as ConversationRepository
      : null;
  void _openConversation(String id, String from) {
    _conversationId = id;
    _conversationReturn = from;
    _showRequests('conversation');
  }

  String _proposalDetailReturn = 'sentProposals';
  ProposalRepository? get _proposals =>
      widget.requestRepository is ProposalRepository
      ? widget.requestRepository as ProposalRepository
      : null;
  void _openProposal(String id, String from) {
    _proposalId = id;
    _proposalDetailReturn = from;
    _showRequests('proposal-detail');
  }

  String? _page, _requestId;
  String get _landing => professionalSpace ? 'explore' : 'mine';
  String get _requestPage => _page ?? _landing;
  String _requestReturn = 'explore';
  String _composeReturn = 'detail';
  String _receivedReturn = 'mine';
  String _publicationReturn = 'mine';
  bool _hasExplorer = false;
  bool _hasPublication = false;
  bool _publicationComplete = false;
  int _publicationVersion = 0;

  String? get _backPage => switch (_requestPage) {
    'conversation' => _conversationReturn,
    'proposal-detail' => _proposalDetailReturn,
    'detail' => _requestReturn,
    'receivedProposals' => _receivedReturn,
    'sentProposals' when !professionalSpace => 'account',
    _ => null,
  };

  int _tabFor(String page) => switch (page) {
    'explore' => professionalSpace ? 0 : 1,
    'sentProposals' => professionalSpace ? 1 : 3,
    'messages' || 'conversation' => 2,
    'account' => 3,
    'mine' || 'edit' => professionalSpace ? 3 : 0,
    'detail' || 'proposal-compose' => _tabFor(_requestReturn),
    'receivedProposals' => _tabFor(_receivedReturn),
    'proposal-detail' => _tabFor(_proposalDetailReturn),
    'publish' => _tabFor(_publicationReturn),
    _ => 0,
  };

  void _showRequests(String? page) => setState(() {
    _hasExplorer = _hasExplorer || _requestPage == 'explore';
    _page = page;
    _settings = false;
  });
  void _openRequest(FoundiRequest request, String from) {
    _requestId = request.id;
    _requestReturn = from;
    _showRequests('detail');
  }

  Widget? _proposalAction(
    FoundiRequest request,
    String from, {
    bool compact = false,
  }) {
    final repository = _proposals;
    if (repository == null) return null;
    return ProposalAction(
      key: ValueKey('action-${request.id}'),
      repository: repository,
      request: request,
      approved: widget.professional.approved,
      compact: compact,
      ownRequest:
          from == 'mine' || (from == 'detail' && _requestReturn == 'mine'),
      emphasized: professionalSpace,
      onCompose: () {
        if (!widget.active || _requestPage != from) return;
        if (from != 'detail') {
          _requestId = request.id;
          _requestReturn = from;
        }
        _proposalRequest = request;
        _composeReturn = from;
        _showRequests('proposal-compose');
      },
      onOpen: (id) {
        if (widget.active && _requestPage == from) _openProposal(id, from);
      },
      onProfile:
          widget.professional.status == ProfessionalStatus.none && compact
          ? null
          : _dossier,
    );
  }

  Widget _requestActions(FoundiRequest request, String from) =>
      RequestActionBar(
        request: request,
        uid: widget.user.id,
        repository: widget.requestRepository!.interactionRepository!,
        reply: _proposalAction(request, from, compact: true),
      );

  void _publish() {
    if (professionalSpace) {
      _spaces();
      return;
    }
    final repository = widget.requestRepository;
    final catalog = widget.catalogRepository;
    if (repository == null || catalog == null) {
      showComingSoon(context);
      return;
    }
    if (_publicationComplete) {
      _publicationVersion++;
      _publicationComplete = false;
    }
    _hasPublication = true;
    _publicationReturn = _requestPage;
    _showRequests('publish');
  }

  Future<void> _startEdit(FoundiRequest request) async {
    if (_editing?.id != request.id) {
      final previous = _editKey?.currentState;
      if (previous != null && !await previous.confirmDiscard()) return;
      if (!mounted || _requestPage != 'mine') return;
      _editing = request;
      _editKey = GlobalKey<RequestComposerState>();
    }
    _showRequests('edit');
  }

  void _finishEdit() {
    setState(() {
      _editing = null;
      _editKey = null;
      if (_requestPage == 'edit') _page = 'mine';
    });
  }

  Widget _requestBody() => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: _requestPage == 'publish',
        child: switch (_requestPage) {
          'explore' when widget.requestRepository != null =>
            const SizedBox.shrink(),
          'mine' when widget.requestRepository != null => RequestListView(
            repository: widget.requestRepository!,
            uid: widget.user.id,
            onOpen: (r) => _openRequest(r, 'mine'),
            footerBuilder:
                widget.requestRepository?.interactionRepository == null
                ? null
                : (r) => _requestActions(r, 'mine'),
            onPublish: professionalSpace ? null : _publish,
            showPublicationBanner: true,
            onProposals: _proposals == null
                ? null
                : (r) {
                    _receivedReturn = 'mine';
                    _receivedRequestId = r.id;
                    _showRequests('receivedProposals');
                  },
            onConversation: _conversations == null
                ? null
                : (id) => _openConversation(id, 'mine'),
            onEdit: widget.catalogRepository == null ? null : _startEdit,
          ),
          'messages' => ConversationListView(
            repository: _conversations!,
            uid: widget.user.id,
            canShowClients:
                widget.professional.status != ProfessionalStatus.none,
            initialProfessional: professionalSpace,
            onOpen: (id) => _openConversation(id, 'messages'),
            onExplore: () => _showRequests('explore'),
          ),
          'conversation' => ConversationView(
            key: ValueKey('${widget.user.id}:$_conversationId'),
            repository: _conversations!,
            proposals: _proposals,
            ownPhone: widget.user.profile.phone,
            active: widget.active,
            uid: widget.user.id,
            id: _conversationId!,
            onBack: () => _showRequests(_conversationReturn),
          ),
          'proposal-compose' => ProposalComposer(
            repository: _proposals!,
            request: _proposalRequest!,
            onBack: () => _showRequests(_composeReturn),
            onSent: () => _showRequests('sentProposals'),
          ),
          'sentProposals' => ProposalListView(
            key: const ValueKey('sentProposals'),
            repository: _proposals!,
            uid: widget.user.id,
            received: false,
            onBack: () => _showRequests(professionalSpace ? null : 'account'),
            onOpen: (id) => _openProposal(id, 'sentProposals'),
          ),
          'receivedProposals' => ProposalListView(
            key: ValueKey('received-$_receivedRequestId'),
            repository: _proposals!,
            uid: widget.user.id,
            received: true,
            requestId: _receivedRequestId,
            onBack: () => _showRequests(_receivedReturn),
            onOpen: (id) => _openProposal(id, 'receivedProposals'),
          ),
          'proposal-detail' => ProposalDetailView(
            key: ValueKey(_proposalId),
            repository: _proposals!,
            id: _proposalId!,
            professionalProfileAction: _showcaseRepository == null
                ? null
                : (proposal) => proposal.clientUid == widget.user.id
                      ? () => _openShowcase(proposalId: proposal.id)
                      : null,
            actionsBuilder: _conversations == null
                ? null
                : (p) => SelectionPanel(
                    key: ValueKey('select-${p.id}'),
                    repository: _conversations!,
                    proposals: _proposals!,
                    proposal: p,
                    uid: widget.user.id,
                    onOpen: (id) => _openConversation(id, 'proposal-detail'),
                    onMine: () => _showRequests('mine'),
                  ),
            onBack: () => _showRequests(_proposalDetailReturn),
          ),
          'edit' => const SizedBox.shrink(),
          'detail' => RequestDetailView(
            key: ValueKey(_requestId),
            repository: widget.requestRepository!,
            id: _requestId!,
            actionsBuilder:
                widget.requestRepository?.interactionRepository != null
                ? (r) => _requestActions(r, 'detail')
                : _proposals == null
                ? null
                : (r) => _proposalAction(r, 'detail')!,
            onBack: () => _showRequests(_requestReturn),
          ),
          'account' => _accountBody(),
          'publish' => const SizedBox.shrink(),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            children: [
              RequestHeading(
                _requestPage == 'mine'
                    ? 'Mes demandes'
                    : 'Explorer les demandes',
              ),
              const RequestNotice(
                'Demandes indisponibles',
                'Le service de demandes est indisponible.',
              ),
            ],
          ),
        },
      ),
      if (widget.requestRepository != null &&
          (_hasExplorer || _requestPage == 'explore'))
        Offstage(
          key: const ValueKey('explorerHost'),
          offstage: _requestPage != 'explore',
          child: ExplorerView(
            repository: widget.requestRepository!,
            catalog: widget.catalogRepository,
            profile: widget.professional,
            professionalSpace: professionalSpace,
            initialForMe: professionalSpace,
            onOpen: (r) => _openRequest(r, 'explore'),
            onPublish: _publish,
            onProfile: _activity,
            footerBuilder:
                widget.requestRepository?.interactionRepository == null
                ? null
                : (r) => _requestActions(r, 'explore'),
          ),
        ),
      if (_editing != null)
        Offstage(
          key: const ValueKey('editionHost'),
          offstage: _requestPage != 'edit',
          child: RequestComposer(
            key: _editKey,
            repository: widget.requestRepository!,
            catalog: widget.catalogRepository!,
            initial: _editing,
            active: _requestPage == 'edit' && widget.active,
            onExit: _finishEdit,
            onMine: _finishEdit,
            onOpen: (r) => _openRequest(r, 'mine'),
          ),
        ),
      if (_hasPublication)
        Offstage(
          key: const ValueKey('publicationHost'),
          offstage: _requestPage != 'publish',
          child: RequestComposer(
            key: ValueKey('requestComposer-$_publicationVersion'),
            repository: widget.requestRepository!,
            catalog: widget.catalogRepository!,
            active: _requestPage == 'publish' && widget.active,
            onPublished: () => _publicationComplete = true,
            onExit: () => _showRequests(
              _publicationComplete ? 'mine' : _publicationReturn,
            ),
            onMine: () {
              _hasPublication = false;
              _showRequests('mine');
            },
            onOpen: (r) {
              _hasPublication = false;
              _openRequest(r, 'mine');
            },
          ),
        ),
    ],
  );
  bool get professionalSpace => widget.professional.approved && _professional;
  @override
  void didUpdateWidget(FoundiShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _notificationIntentChanged(),
      );
    }
    if (!widget.professional.approved) {
      if (_professional) {
        _page = null;
        _settings = false;
      }
      _professional = false;
      if (oldWidget.professional.approved && _selectorContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final sheet = _selectorContext;
          if (mounted &&
              sheet != null &&
              sheet.mounted &&
              ModalRoute.of(sheet)?.isCurrent == true) {
            Navigator.pop(sheet);
          }
        });
      }
    }
  }

  void _dossier() {
    if (widget.onDossier != null) {
      widget.onDossier!();
    } else {
      showComingSoon(context);
    }
  }

  Future<void> _spaces() async {
    if (!widget.professional.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ton espace client reste actif. Le mode professionnel nécessite une approbation.',
          ),
        ),
      );
      return;
    }
    bool selected = professionalSpace;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x7A092D26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (context) {
        _selectorContext = context;
        return StatefulBuilder(
          builder: (context, update) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(23, 8, 23, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choisir mon espace',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: FoundiUi.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Un seul compte, deux façons d’utiliser Foundi.',
                    style: TextStyle(fontSize: 12, color: FoundiUi.muted),
                  ),
                  const SizedBox(height: 26),
                  SpaceChoice(
                    professional: false,
                    selected: !selected,
                    onTap: () => update(() => selected = false),
                  ),
                  const SizedBox(height: 10),
                  SpaceChoice(
                    professional: true,
                    selected: selected,
                    onTap: () => update(() => selected = true),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const ValueKey('confirmSpace'),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Continuer'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _selectorContext = null;
    if (!mounted || result == null) return;
    if (result && !widget.professional.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le profil professionnel n’est plus approuvé. Ton espace client reste disponible.',
          ),
        ),
      );
      return;
    }
    if (result != professionalSpace) {
      _hasExplorer = _hasExplorer || _requestPage == 'explore';
      _professional = result;
      _showRequests(null);
    }
  }

  void _activity() {
    if (widget.professional.status == ProfessionalStatus.draft ||
        widget.professional.status == ProfessionalStatus.needsChanges) {
      _dossier();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalActivityView(
          profile: widget.professional,
          repository: widget.professionalRepository,
        ),
      ),
    );
  }

  ProfessionalShowcaseRepository? get _showcaseRepository {
    final repository = widget.professionalRepository;
    return repository is ProfessionalShowcaseRepository
        ? repository as ProfessionalShowcaseRepository
        : null;
  }

  void _openShowcase({String? proposalId}) {
    final repository = _showcaseRepository;
    if (repository == null ||
        (proposalId == null && !widget.professional.approved)) {
      return;
    }
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalShowcaseScreen(
          repository: repository,
          proposalId: proposalId,
          businessName: widget.professional.activity.businessName,
          onPersonal: proposalId != null
              ? null
              : () {
                  if (!mounted) return;
                  final user = widget.auth.currentUser;
                  if (user?.id != widget.user.id) return;
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProfileScreen(user: user!, repository: widget.auth),
                    ),
                  );
                },
        ),
      ),
    );
  }

  void _navigate(int index) {
    final page = switch (index) {
      0 => _landing,
      1 => professionalSpace ? 'sentProposals' : 'explore',
      2 => 'messages',
      3 => 'account',
      _ => throw ArgumentError.value(index),
    };
    if ((page == 'messages' && _conversations == null) ||
        (page == 'sentProposals' && _proposals == null)) {
      showComingSoon(context);
      return;
    }
    _showRequests(page);
  }

  Widget _accountBody() => _settings
      ? FoundiSettings(
          user: widget.auth.currentUser ?? widget.user,
          professional: widget.professional,
          professionalSpace: professionalSpace,
          onSpaces: _spaces,
          onDossier: _dossier,
          onActivity: _activity,
          onNotifications: _notifications == null
              ? null
              : _notificationSettings,
          onSignOut: () => perform(widget.auth.signOut),
          busy: busy,
          error: error,
        )
      : AccountScreen(
          onSentProposals:
              _proposals != null &&
                  widget.professional.status != ProfessionalStatus.none
              ? () => _showRequests('sentProposals')
              : null,
          onReceivedProposals: _proposals == null
              ? null
              : () {
                  _receivedReturn = 'account';
                  _receivedRequestId = null;
                  _showRequests('receivedProposals');
                },
          user: widget.user,
          professional: widget.professional,
          professionalSpace: professionalSpace,
          onSpaces: _spaces,
          onDossier: _dossier,
          onActivity: _activity,
          onPublish: widget.requestRepository == null ? null : _publish,
          onShowcase: _showcaseRepository == null
              ? null
              : () => _openShowcase(),
          onRequests: widget.requestRepository == null
              ? null
              : () => _showRequests('mine'),
        );

  @override
  Widget build(BuildContext context) => AuthScope(
    repository: widget.auth,
    child: Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: FoundiUi.background,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: FoundiUi.green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      child: PopScope(
        canPop: !widget.active || _requestPage == _landing,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !widget.active || _requestPage == _landing) return;
          // The active form handles its own steps and in-flight submissions.
          if (const {
            'publish',
            'edit',
            'proposal-compose',
          }.contains(_requestPage)) {
            return;
          }
          if (_settings) {
            setState(() => _settings = false);
          } else {
            _showRequests(_backPage);
          }
        },
        child: Scaffold(
          backgroundColor: FoundiUi.background,
          body: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    if (_settings)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 22, 12),
                        child: Row(
                          children: [
                            IconButton(
                              key: const ValueKey('settingsBack'),
                              tooltip: 'Retour au compte',
                              onPressed: () =>
                                  setState(() => _settings = false),
                              icon: const Icon(
                                Icons.chevron_left,
                                color: FoundiUi.ink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Paramètres',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: FoundiUi.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_requestPage != 'publish' &&
                        _requestPage != 'edit' &&
                        _requestPage != 'conversation' &&
                        _requestPage != 'detail')
                      FoundiBrand(
                        notificationBell: _notifications == null
                            ? null
                            : NotificationBell(
                                repository: _notifications!.repository,
                                uid: widget.user.id,
                                onOpen: _inbox,
                              ),
                        onSettings: _requestPage == 'account'
                            ? () => setState(() => _settings = true)
                            : null,
                      ),
                    if (_requestPage == _landing)
                      FoundiSpaceLabel(
                        professional: professionalSpace,
                        onSelect: widget.professional.approved ? _spaces : null,
                      ),
                    Expanded(child: _requestBody()),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: FoundiBottomBar(
            professionalSpace: professionalSpace,
            messagesIcon: _notifications?.repository is MessageReadRepository
                ? MessageUnreadIcon(
                    repository:
                        _notifications!.repository as MessageReadRepository,
                    uid: widget.user.id,
                    selected:
                        _requestPage == 'messages' ||
                        _requestPage == 'conversation',
                  )
                : null,
            selectedIndex: _tabFor(_requestPage),
            onSelect: _navigate,
          ),
        ),
      ),
    ),
  );
}

class ProfessionalActivityView extends StatefulWidget {
  const ProfessionalActivityView({
    super.key,
    required this.profile,
    this.repository,
  });
  final ProfessionalProfile profile;
  final ProfessionalRepository? repository;
  @override
  State<ProfessionalActivityView> createState() =>
      _ProfessionalActivityViewState();
}

class _ProfessionalActivityViewState extends State<ProfessionalActivityView> {
  late final Future<ProfessionalCatalog> catalog =
      widget.repository?.loadCatalog() ??
      Future.value(const ProfessionalCatalog());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Informations professionnelles')),
    body: FutureBuilder<ProfessionalCatalog>(
      future: catalog,
      builder: (context, s) {
        final p = widget.profile;
        final a = p.activity;
        String labels(List<String> ids, List<ReferenceChoice> choices) => ids
            .map(
              (id) =>
                  choices.where((c) => c.id == id).firstOrNull?.label ??
                  'Référence indisponible',
            )
            .join(', ');
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.businessName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(professionalStatusLabel(p.status)),
              const SizedBox(height: 20),
              Text(a.type == 'company' ? 'Entreprise' : 'Indépendant'),
              const SizedBox(height: 12),
              Text(a.description),
              const SizedBox(height: 24),
              if (s.hasError)
                const Text(
                  'Les libellés des catégories et zones sont indisponibles.',
                )
              else if (!s.hasData)
                const LinearProgressIndicator()
              else ...[
                Text(
                  'Catégories : ${labels(a.categoryIds, s.requireData.categories)}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Spécialités : ${labels(a.specialtyIds, s.requireData.categories.expand((c) => c.specialties).toList())}',
                ),
                const SizedBox(height: 12),
                Text('Zones : ${labels(a.zoneIds, s.requireData.zones)}'),
              ],
            ],
          ),
        );
      },
    ),
  );
}
