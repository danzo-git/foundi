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
  late bool _professional =
      widget.professional.approved &&
      widget.user.profile.preferredMode == 'professional';
  bool _account = false, _settings = false, _switched = false;
  BuildContext? _selectorContext;
  FoundiRequest? _editing;
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
    _account = page == 'mine';
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
            onEdit: (r) {
              _editing = r;
              _showRequests('edit');
            },
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
            if (_requestPage == 'publish' || _requestPage == 'edit') return;
            if (_requestPage != null) {
              _showRequests(_requestPage == 'detail' ? _requestReturn : null);
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
                        _requestPage != 'detail')
                      FoundiBrand(
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
                                onSignOut: () => perform(widget.auth.signOut),
                                busy: busy,
                                error: error,
                              )
                            : _account
                            ? AccountScreen(
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
            accountSelected: _account,
            selectedIndex: _requestPage == 'publish'
                ? 2
                : _requestPage == 'explore' ||
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
  final VoidCallback? onOpportunities;
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
