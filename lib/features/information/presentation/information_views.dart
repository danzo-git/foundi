import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/presentation/professional_badge.dart';
import '../domain/information_repository.dart';

// Long announcements also work on web, where individual timers have a limited range.
// Each wake-up only schedules the remaining delay; it performs no network request.
class _ExpiryAlarm {
  _ExpiryAlarm(Duration remaining, VoidCallback onEnd) {
    _schedule(remaining, onEnd);
  }
  Timer? _timer;
  void _schedule(Duration remaining, VoidCallback onEnd) {
    const maximum = Duration(days: 1);
    final step = remaining > maximum ? maximum : remaining;
    _timer = Timer(step, () {
      if (remaining > step) {
        _schedule(remaining - step, onEnd);
      } else {
        onEnd();
      }
    });
  }

  void cancel() => _timer?.cancel();
}

void openFoundiInformation(
  BuildContext context,
  InformationRepository? repository,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => InformationScreen(repository: repository),
  ),
);

const _badgeSummary =
    'Les particuliers comme les professionnels peuvent répondre à une demande.';
const _badgeBody =
    '$badgeExplanation : le dossier de ce compte a été approuvé.\n\n'
    'Sans badge : particulier ou professionnel dont le dossier n’est pas approuvé.\n\n'
    '$badgeDisclaimer\n\n'
    'Échange sur ton besoin et les conditions de la prestation avant de choisir.';

class WarmInformationCard extends StatelessWidget {
  const WarmInformationCard({
    super.key,
    required this.title,
    required this.summary,
    this.body = '',
    this.footer,
    this.onDismiss,
    this.badge = false,
  });
  final String title, summary, body;
  final Widget? footer;
  final VoidCallback? onDismiss;
  final bool badge;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD8F5DF), Color(0xFFDCF5EF), Color(0xFFF7FAE9)],
      ),
      border: Border.all(color: const Color(0xFFB3DBC5)),
      boxShadow: [
        BoxShadow(
          color: FoundiUi.green.withValues(alpha: .07),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFEDAD),
                shape: BoxShape.circle,
              ),
              child: Icon(
                badge ? Icons.verified_user_outlined : Icons.campaign_outlined,
                color: FoundiUi.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                badge ? 'À connaître' : 'Du nouveau sur Foundi',
                style: const TextStyle(
                  color: FoundiUi.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Fermer l’annonce',
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 20, color: FoundiUi.ink),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: FoundiUi.ink,
            fontSize: 23,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(summary, style: const TextStyle(color: FoundiUi.ink, height: 1.5)),
        if (body.trim().isNotEmpty && body.trim() != summary.trim()) ...[
          const SizedBox(height: 14),
          Text(body, style: const TextStyle(color: FoundiUi.ink, height: 1.5)),
        ],
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    ),
  );
}

/// One summary request per visit (at most once a minute), no Firestore listener.
/// Dismissal is local; it never removes the announcement from the information hub.
class ExplorerInformation extends StatefulWidget {
  const ExplorerInformation({
    super.key,
    this.repository,
    this.accountId = 'guest',
    this.active = true,
  });
  final InformationRepository? repository;
  final String accountId;
  final bool active;
  @override
  State<ExplorerInformation> createState() => _ExplorerInformationState();
}

class _ExplorerInformationState extends State<ExplorerInformation>
    with WidgetsBindingObserver {
  FoundiInformation? _item;
  Set<String> _dismissed = {};
  bool _ready = false;
  DateTime? _loaded;
  _ExpiryAlarm? _expiry;
  int _generation = 0;
  String get _key => 'foundi.information.dismissed.${widget.accountId}';
  String get _version => _item?.dismissalKey ?? 'badge-v1';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(ExplorerInformation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.repository != widget.repository) {
      _generation++;
      _expiry?.cancel();
      _dismissed = {};
      _loaded = null;
      _ready = false;
      _item = null;
      if (widget.active) _load();
    } else if (widget.active && !oldWidget.active) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    if (!force &&
        _loaded != null &&
        DateTime.now().difference(_loaded!) < const Duration(minutes: 1)) {
      return;
    }
    _loaded = DateTime.now();
    final generation = ++_generation;
    Set<String> dismissed = {};
    try {
      dismissed =
          (await SharedPreferences.getInstance())
              .getStringList(_key)
              ?.toSet() ??
          {};
    } catch (_) {
      /* Local preferences can be unavailable. */
    }
    List<FoundiInformation> items = [];
    try {
      items =
          await widget.repository?.listInformation(featuredOnly: true) ?? [];
    } catch (_) {
      /* Explorer remains available. */
    }
    if (!mounted || generation != _generation) return;
    _expiry?.cancel();
    setState(() {
      _item = items
          .where((item) => item.validUntil.isAfter(DateTime.now()))
          .firstOrNull;
      _dismissed = {...dismissed, ..._dismissed};
      _ready = true;
    });
    final item = _item;
    if (item != null) {
      _expiry = _ExpiryAlarm(item.validUntil.difference(DateTime.now()), () {
        if (mounted) {
          setState(() {
            _item = null;
          });
        }
      });
    }
  }

  Future<void> _dismiss() async {
    final version = _version, key = _key;
    // Keep only small identifiers locally, including dismissals of an older
    // announcement that may become featured again when a newer one expires.
    final dismissed = [..._dismissed, version];
    final bounded = dismissed.length > 40
        ? dismissed.sublist(dismissed.length - 40)
        : dismissed;
    setState(() => _dismissed = bounded.toSet());
    try {
      await (await SharedPreferences.getInstance()).setStringList(key, bounded);
    } catch (_) {
      /* Session dismissal still works. */
    }
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _dismissed.contains(_version)) {
      return const SizedBox.shrink();
    }
    final item = _item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: item == null
          ? WarmInformationCard(
              title: 'Un repère pour choisir en confiance.',
              summary: _badgeSummary,
              body: _badgeBody,
              badge: true,
              onDismiss: _dismiss,
            )
          : AnnouncementInformationCard(
              key: ValueKey(item.dismissalKey),
              repository: widget.repository!,
              announcement: item,
              onDismiss: _dismiss,
              active: widget.active,
            ),
    );
  }
}

class InformationScreen extends StatefulWidget {
  const InformationScreen({super.key, this.repository});
  final InformationRepository? repository;
  @override
  State<InformationScreen> createState() => _InformationScreenState();
}

class _InformationScreenState extends State<InformationScreen>
    with WidgetsBindingObserver {
  late Future<List<FoundiInformation>> _items = _load();
  _ExpiryAlarm? _expiry;
  int _generation = 0;
  Future<List<FoundiInformation>> _load() async {
    final generation = ++_generation;
    final items =
        await widget.repository?.listInformation() ?? <FoundiInformation>[];
    if (mounted && generation == _generation) {
      _expiry?.cancel();
      final future =
          items
              .where((item) => item.validUntil.isAfter(DateTime.now()))
              .map((item) => item.validUntil)
              .toList()
            ..sort();
      if (future.isNotEmpty) {
        _expiry = _ExpiryAlarm(future.first.difference(DateTime.now()), () {
          if (mounted) _reload();
        });
      }
    }
    return items;
  }

  void _reload() {
    final next = _load();
    // The FutureBuilder subscribes on the next frame; handle fast failures too.
    next.ignore();
    setState(() {
      _items = next;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FoundiUi.background,
    appBar: AppBar(title: const Text('Informations Foundi')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: RefreshIndicator(
          onRefresh: () async {
            final next = _load();
            setState(() {
              _items = next;
            });
            try {
              await next;
            } catch (_) {
              /* The inline error offers a retry. */
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nouveautés et conseils, à portée de main.',
                        style: TextStyle(color: FoundiUi.muted, height: 1.5),
                      ),
                      SizedBox(height: 20),
                      WarmInformationCard(
                        title: 'Comprendre le badge Foundi',
                        summary: _badgeSummary,
                        body: _badgeBody,
                        badge: true,
                      ),
                      SizedBox(height: 28),
                      Text(
                        'Les dernières infos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: FoundiUi.ink,
                        ),
                      ),
                      SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              FutureBuilder<List<FoundiInformation>>(
                future: _items,
                builder: (context, snapshot) {
                  Widget? notice;
                  if (snapshot.connectionState != ConnectionState.done) {
                    notice = const LinearProgressIndicator();
                  } else if (snapshot.hasError) {
                    notice = Column(
                      children: [
                        const Text(
                          'Les annonces sont momentanément indisponibles.',
                        ),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    );
                  }
                  final items = (snapshot.data ?? [])
                      .where((item) => item.validUntil.isAfter(DateTime.now()))
                      .toList();
                  if (notice == null && items.isEmpty) {
                    notice = const Text(
                      'Tu es à jour. Les prochaines nouveautés apparaîtront ici.',
                      style: TextStyle(color: FoundiUi.muted, height: 1.5),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    sliver: notice != null
                        ? SliverToBoxAdapter(child: notice)
                        : SliverList.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: AnnouncementInformationCard(
                                  key: ValueKey(item.dismissalKey),
                                  repository: widget.repository!,
                                  announcement: item,
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Fetches the full text automatically as the card enters the visible list.
/// It never pushes a detail route, and expiry still removes the entire card.
class AnnouncementInformationCard extends StatefulWidget {
  const AnnouncementInformationCard({
    super.key,
    required this.repository,
    required this.announcement,
    this.onDismiss,
    this.active = true,
  });
  final InformationRepository repository;
  final FoundiInformation announcement;
  final VoidCallback? onDismiss;
  final bool active;
  @override
  State<AnnouncementInformationCard> createState() =>
      _AnnouncementInformationCardState();
}

class _AnnouncementInformationCardState
    extends State<AnnouncementInformationCard>
    with WidgetsBindingObserver {
  late Future<FoundiInformation> _information = _load();
  _ExpiryAlarm? _expiry;
  bool _expired = false;
  int _generation = 0;
  Future<FoundiInformation> _load() async {
    final generation = ++_generation;
    final item = await widget.repository.readInformation(
      widget.announcement.id,
    );
    if (mounted && generation == _generation) {
      _expiry?.cancel();
      _expired = !item.validUntil.isAfter(DateTime.now());
      if (!_expired) {
        _expiry = _ExpiryAlarm(item.validUntil.difference(DateTime.now()), () {
          if (mounted) setState(() => _expired = true);
        });
      }
    }
    return item;
  }

  void _reload() {
    final next = _load();
    next.ignore();
    setState(() {
      _information = next;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(AnnouncementInformationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.announcement.dismissalKey !=
            widget.announcement.dismissalKey ||
        (widget.active && !oldWidget.active)) {
      _expired = false;
      _information = _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        ModalRoute.of(context)?.isCurrent != false) {
      _reload();
    }
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FoundiInformation>(
    future: _information,
    builder: (context, snapshot) {
      if (_expired || snapshot.error is InformationUnavailable) {
        return const SizedBox.shrink();
      }
      final loading = snapshot.connectionState != ConnectionState.done;
      final item = !loading && !snapshot.hasError
          ? snapshot.data!
          : widget.announcement;
      return WarmInformationCard(
        title: item.title,
        summary: item.summary,
        body: loading || snapshot.hasError ? '' : item.body,
        onDismiss: widget.onDismiss,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading)
              const LinearProgressIndicator(
                semanticsLabel: 'Chargement de l’information',
              ),
            if (!loading && snapshot.hasError) ...[
              const Text(
                'Le texte complet est momentanément indisponible.',
                style: TextStyle(color: FoundiUi.muted),
              ),
              TextButton(onPressed: _reload, child: const Text('Réessayer')),
            ],
            const SizedBox(height: 8),
            Text(
              'Jusqu’au ${_date(item.endsAt)}',
              style: const TextStyle(color: FoundiUi.muted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}
