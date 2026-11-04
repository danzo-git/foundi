import '../../conversations/domain/conversation_repository.dart';
import '../../conversations/presentation/conversation_views.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../proposals/presentation/proposal_views.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/account_screen.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../../professional/presentation/professional_status_label.dart';
import 'settings_view.dart';
import '../../requests/presentation/explorer_view.dart';
import 'space_widgets.dart';
import '../../requests/domain/request_repository.dart';
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
          _receivedRequestId = target.id;
          _showRequests('receivedProposals');
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
  bool _account = false, _settings = false, _switched = false;
  BuildContext? _selectorContext;
  FoundiRequest? _editing, _proposalRequest;
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

  String? _requestPage, _requestId;
  String _requestReturn = 'explore';
  bool _hasExplorer = false, _explorerStartForMe = false;
  int _explorerEntryVersion = 0;
  bool _hasPublication = false;
  bool _publicationComplete = false;
  int _publicationVersion = 0;
  void _showRequests(String? page) => setState(() {
    if (page == 'explore' || page == 'opportunities') {
      _hasExplorer = true;
      if (page == 'opportunities') {
        _explorerStartForMe = true;
        _explorerEntryVersion++;
      }
      page = 'explore';
    }
    _requestPage = page;
    _settings = false;
    _account =
        page == 'mine' ||
        page == 'sentProposals' ||
        page == 'receivedProposals' ||
        page == 'proposal-detail';
  });
  void _openRequest(FoundiRequest request, String from) {
    _requestId = request.id;
    _requestReturn = from;
    _showRequests('detail');
  }

  void _publish() {
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
    _showRequests('publish');
  }

  Widget _requestBody(Widget home) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: _requestPage == 'publish',
        child: switch (_requestPage) {
          'explore' => const SizedBox.shrink(),
          'mine' => RequestListView(
            key: ValueKey(_requestPage),
            repository: widget.requestRepository!,
            uid: _requestPage == 'mine' ? widget.user.id : null,
            onOpen: (r) => _openRequest(r, _requestPage!),
            onPublish: _publish,
            onProposals: _proposals == null
                ? null
                : (r) {
                    _receivedRequestId = r.id;
                    _showRequests('receivedProposals');
                  },
            onConversation: _conversations == null
                ? null
                : (id) => _openConversation(id, 'mine'),
            onEdit: (r) {
              _editing = r;
              _showRequests('edit');
            },
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
            onBack: () => _showRequests('detail'),
            onSent: () => _showRequests('sentProposals'),
          ),
          'sentProposals' => ProposalListView(
            key: const ValueKey('sentProposals'),
            repository: _proposals!,
            uid: widget.user.id,
            received: false,
            onBack: () => _showRequests(null),
            onOpen: (id) => _openProposal(id, 'sentProposals'),
          ),
          'receivedProposals' => ProposalListView(
            key: ValueKey('received-$_receivedRequestId'),
            repository: _proposals!,
            uid: widget.user.id,
            received: true,
            requestId: _receivedRequestId,
            onBack: () => _showRequests('mine'),
            onOpen: (id) => _openProposal(id, 'receivedProposals'),
          ),
          'proposal-detail' => ProposalDetailView(
            key: ValueKey(_proposalId),
            repository: _proposals!,
            id: _proposalId!,
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
          'edit' => RequestComposer(
            key: ValueKey('edit-${_editing!.id}'),
            repository: widget.requestRepository!,
            catalog: widget.catalogRepository!,
            initial: _editing,
            onExit: () => _showRequests('mine'),
            onMine: () => _showRequests('mine'),
            onOpen: (r) => _openRequest(r, 'mine'),
          ),
          'detail' => RequestDetailView(
            key: ValueKey(_requestId),
            repository: widget.requestRepository!,
            id: _requestId!,
            actionsBuilder: _proposals == null
                ? null
                : (r) => ProposalAction(
                    key: ValueKey('action-${r.id}'),
                    repository: _proposals!,
                    request: r,
                    approved: widget.professional.approved,
                    onCompose: () {
                      _proposalRequest = r;
                      _showRequests('proposal-compose');
                    },
                    onOpen: (id) => _openProposal(id, 'detail'),
                    onProfile: _dossier,
                  ),
            onBack: () => _showRequests(_requestReturn),
          ),
          _ => home,
        },
      ),
      if (_hasExplorer)
        Offstage(
          key: const ValueKey('explorerHost'),
          offstage: _requestPage != 'explore',
          child: ExplorerView(
            repository: widget.requestRepository!,
            catalog: widget.catalogRepository,
            profile: widget.professional,
            professionalSpace: professionalSpace,
            initialForMe: _explorerStartForMe,
            entryVersion: _explorerEntryVersion,
            onOpen: (r) => _openRequest(r, 'explore'),
            onPublish: _publish,
            onProfile: _activity,
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
            onExit: () => _showRequests(null),
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
    setState(() {
      _switched = _switched || result != _professional;
      _professional = result;
      _account = false;
      _settings = false;
      _requestPage = null;
    });
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

  void _navigate(int index) {
    if (index == 3 && _conversations != null) {
      _showRequests('messages');
      return;
    }
    if (widget.requestRepository != null && index == 1) {
      _showRequests('explore');
      return;
    }
    if (index == 2 && widget.requestRepository != null) {
      _publish();
      return;
    }
    if (index != 0 && index != 4) {
      showComingSoon(context);
      return;
    }
    setState(() {
      _account = index == 4;
      _settings = false;
      _requestPage = null;
    });
  }

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
        canPop:
            !widget.active || (!_settings && !_account && _requestPage == null),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.active) {
            if (_requestPage == 'publish' ||
                _requestPage == 'edit' ||
                _requestPage == 'proposal-compose') {
              return;
            }
            if (_requestPage != null) {
              _showRequests(
                _requestPage == 'conversation'
                    ? _conversationReturn
                    : _requestPage == 'proposal-detail'
                    ? _proposalDetailReturn
                    : _requestPage == 'detail'
                    ? _requestReturn
                    : null,
              );
              return;
            }
            setState(() {
              if (_settings) {
                _settings = false;
              } else {
                _account = false;
              }
            });
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
                        onSettings: _account && _requestPage == null
                            ? () => setState(() => _settings = true)
                            : null,
                      ),
                    Expanded(
                      child: _requestBody(
                        _settings
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
                            : _account
                            ? AccountScreen(
                                onSentProposals:
                                    _proposals != null &&
                                        widget.professional.status !=
                                            ProfessionalStatus.none
                                    ? () => _showRequests('sentProposals')
                                    : null,
                                onReceivedProposals: _proposals == null
                                    ? null
                                    : () {
                                        _receivedRequestId = null;
                                        _showRequests('receivedProposals');
                                      },
                                user: widget.user,
                                professional: widget.professional,
                                professionalSpace: professionalSpace,
                                onSpaces: _spaces,
                                onDossier: _dossier,
                                onActivity: _activity,
                                onPublish: widget.requestRepository == null
                                    ? null
                                    : _publish,
                                onRequests: widget.requestRepository == null
                                    ? null
                                    : () => _showRequests('mine'),
                              )
                            : FoundiHome(
                                onSentProposals:
                                    professionalSpace && _proposals != null
                                    ? () => _showRequests('sentProposals')
                                    : null,
                                onOpportunities:
                                    professionalSpace &&
                                        widget.requestRepository
                                            is OpportunityRepository
                                    ? () => _showRequests('opportunities')
                                    : null,
                                user: widget.user,
                                profile: widget.professional,
                                professionalSpace: professionalSpace,
                                switched: _switched,
                                onSpaces: _spaces,
                                onDossier: _dossier,
                                onPublish: widget.requestRepository == null
                                    ? null
                                    : _publish,
                                onRequests: widget.requestRepository == null
                                    ? null
                                    : () => _showRequests('mine'),
                                onExplore: widget.requestRepository == null
                                    ? null
                                    : () => _showRequests('explore'),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: FoundiBottomBar(
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
            accountSelected: _account,
            selectedIndex:
                _requestPage == 'messages' || _requestPage == 'conversation'
                ? 3
                : _requestPage == 'publish'
                ? 2
                : _requestPage == 'proposal-compose' ||
                      _requestPage == 'explore' ||
                      (_requestPage == 'detail' && _requestReturn == 'explore')
                ? 1
                : _requestPage == 'mine' ||
                      _account ||
                      (_requestPage == 'detail' && _requestReturn == 'mine')
                ? 4
                : 0,
            onSelect: _navigate,
          ),
        ),
      ),
    ),
  );
}

class FoundiHome extends StatelessWidget {
  const FoundiHome({
    super.key,
    this.onOpportunities,
    this.onSentProposals,
    required this.user,
    required this.profile,
    required this.professionalSpace,
    required this.onSpaces,
    required this.onDossier,
    this.switched = false,
    this.onPublish,
    this.onRequests,
    this.onExplore,
  });
  final VoidCallback? onOpportunities, onSentProposals;
  final FoundiUser user;
  final ProfessionalProfile profile;
  final bool professionalSpace, switched;
  final VoidCallback onSpaces, onDossier;
  final VoidCallback? onPublish, onRequests, onExplore;
  @override
  Widget build(BuildContext context) {
    final personal = user.profile.fullName.isNotEmpty
        ? user.profile.fullName
        : user.displayName ?? '';
    final name = professionalSpace && profile.activity.businessName.isNotEmpty
        ? profile.activity.businessName
        : personal.trim().split(RegExp(r'\s+')).first;
    return SingleChildScrollView(
      key: ValueKey(professionalSpace ? 'professionalHome' : 'clientHome'),
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profile.approved)
            Material(
              color: const Color(0xFFE7F0EC),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('homeSpaceSelector'),
                onTap: onSpaces,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (final pro in [false, true])
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: professionalSpace == pro
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              pro ? 'Professionnel' : 'Client',
                              style: TextStyle(
                                fontSize: 13,
                                color: professionalSpace == pro
                                    ? FoundiUi.ink
                                    : FoundiUi.muted,
                                fontWeight: professionalSpace == pro
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: FoundiUi.tint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'ESPACE CLIENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FoundiUi.green,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            !professionalSpace && profile.approved && switched
                ? 'Bienvenue côté client'
                : name.isEmpty
                ? 'Bonjour !'
                : 'Bonjour, $name${professionalSpace ? '' : ' 👋'}',
            style: TextStyle(
              height: 1.2,
              fontSize: professionalSpace || profile.approved ? 23 : 26,
              fontFamilyFallback: const ['Noto Color Emoji'],
              fontWeight: FontWeight.bold,
              color: FoundiUi.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            professionalSpace
                ? 'Ton espace professionnel prend forme.'
                : 'Que recherches-tu aujourd’hui ?',
            style: const TextStyle(fontSize: 13, color: FoundiUi.muted),
          ),
          const SizedBox(height: 30),
          if (professionalSpace) ...[
            if (onSentProposals != null) ...[
              FoundiPanel(
                onTap: onSentProposals,
                child: const Text('Mes propositions  ›'),
              ),
              const SizedBox(height: 16),
            ],
            const FutureOverview(professional: true),
            const SizedBox(height: 32),
            const Text(
              'Modules professionnels',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FoundiUi.ink,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: [
                for (final label in ['Pour moi', 'Groupes'])
                  ActionChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: label == 'Pour moi'
                            ? Colors.white
                            : FoundiUi.ink,
                      ),
                    ),
                    backgroundColor: label == 'Pour moi'
                        ? FoundiUi.green
                        : const Color(0xFFE7F0EC),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    onPressed: label == 'Pour moi' && onOpportunities != null
                        ? onOpportunities
                        : () => showComingSoon(context),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (onOpportunities != null)
              FoundiPanel(
                onTap: onOpportunities,
                child: const Text('Opportunités pour moi  ›'),
              )
            else
              const ComingSoonCard(title: 'Opportunités à venir'),
            const SizedBox(height: 12),
            const ComingSoonCard(title: 'Demandes groupées à venir'),
          ] else if (profile.approved && switched) ...[
            FoundiPanel(
              color: FoundiUi.soft,
              onTap: onPublish ?? () => showComingSoon(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Une idée en tête ?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: FoundiUi.ink,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    onPublish == null
                        ? 'Exprime ton besoin. La publication sera bientôt disponible.'
                        : 'Exprime ton besoin et publie-le sur Foundi.',
                    style: TextStyle(
                      fontSize: 13,
                      color: FoundiUi.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              onRequests == null ? 'Mes demandes (à venir)' : 'Mes demandes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FoundiUi.ink,
              ),
            ),
            const SizedBox(height: 20),
            if (onRequests == null)
              const ComingSoonCard(title: 'Suivi des demandes')
            else
              FoundiPanel(
                onTap: onRequests,
                child: const Text('Consulter mes demandes  ›'),
              ),
          ] else ...[
            FoundiPanel(
              color: FoundiUi.soft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
              onTap: () => showComingSoon(context),
              child: const Row(
                children: [
                  Icon(Icons.search, size: 18, color: FoundiUi.muted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rechercher un service ou un produit',
                      style: TextStyle(fontSize: 13, color: FoundiUi.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Découvrir Foundi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FoundiUi.ink,
              ),
            ),
            const SizedBox(height: 20),
            if (onExplore == null)
              const ComingSoonCard(title: 'Explorer les demandes')
            else
              FoundiPanel(
                onTap: onExplore,
                child: const Text('Explorer les demandes  ›'),
              ),
            const SizedBox(height: 12),
            if (onRequests == null)
              const ComingSoonCard(title: 'Mes demandes')
            else
              FoundiPanel(
                onTap: onRequests,
                child: const Text('Mes demandes  ›'),
              ),
          ],
          if (profile.status != ProfessionalStatus.none &&
              !profile.approved) ...[
            const SizedBox(height: 20),
            FoundiPanel(
              color: const Color(0xFFFFF0D8),
              onTap: onDossier,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    professionalStatusLabel(profile.status),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: FoundiUi.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (profile.reviewReason.isNotEmpty)
                    Text(
                      profile.reviewReason,
                      style: const TextStyle(
                        fontSize: 13,
                        color: FoundiUi.muted,
                      ),
                    ),
                  Text(
                    profile.status == ProfessionalStatus.draft ||
                            profile.status == ProfessionalStatus.needsChanges
                        ? 'Reprendre mon dossier'
                        : 'Suivre mon dossier  ›',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FoundiUi.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
          if (!professionalSpace)
            const Text(
              'Retrouve ton compte et ton activité depuis Compte.',
              style: TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
        ],
      ),
    );
  }
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
