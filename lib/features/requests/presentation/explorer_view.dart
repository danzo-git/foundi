import 'dart:async';
import 'package:flutter/material.dart';
import '../../professional/domain/professional_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/request_repository.dart';
import 'request_views.dart';

class ExplorerView extends StatefulWidget {
  const ExplorerView({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onPublish,
    this.catalog,
    this.profile = const ProfessionalProfile(),
    this.professionalSpace = false,
    this.initialForMe = false,
    this.entryVersion = 0,
    this.onProfile,
  });
  final int entryVersion;
  final RequestRepository repository;
  final ProfessionalRepository? catalog;
  final ProfessionalProfile profile;
  final bool professionalSpace, initialForMe;
  final ValueChanged<FoundiRequest> onOpen;
  final VoidCallback onPublish;
  final VoidCallback? onProfile;
  @override
  State<ExplorerView> createState() => _ExplorerViewState();
}

class _ExplorerViewState extends State<ExplorerView> {
  bool get _eligible => widget.professionalSpace && widget.profile.approved;
  late bool _forMe = _eligible && widget.initialForMe;
  ExplorerFilters _public = const ExplorerFilters(),
      _personal = const ExplorerFilters();
  ExplorerFilters get _filters => _forMe ? _personal : _public;
  ProfessionalCatalog? _catalog;
  final _items = <FoundiRequest>[];
  Map<String, dynamic>? _cursor;
  StreamSubscription<List<FoundiRequest>>? _subscription;
  int _generation = 0;
  bool _busy = true;
  String? _error;
  bool get _usableProfile {
    final a = widget.profile.activity;
    final c = _catalog;
    if (c == null) return false;
    return c.zones.any((z) => a.zoneIds.contains(z.id)) &&
        c.categories.any(
          (cat) =>
              a.categoryIds.contains(cat.id) &&
              (cat.specialties.isEmpty ||
                  cat.specialties.any((s) => a.specialtyIds.contains(s.id))),
        );
  }

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(ExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_eligible && _forMe) {
      _forMe = false;
      _load(reset: true);
    } else if (oldWidget.initialForMe != widget.initialForMe ||
        oldWidget.entryVersion != widget.entryVersion) {
      _forMe = _eligible && widget.initialForMe;
      _load(reset: true);
    } else if (oldWidget.profile != widget.profile && _forMe) {
      _personal = const ExplorerFilters();
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final generation = ++_generation;
    _subscription?.cancel();
    _subscription = null;
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      if (widget.catalog != null) {
        _catalog = await widget.catalog!.loadCatalog();
      }
      if (!mounted || generation != _generation) return;
      if (_forMe && !_usableProfile) {
        setState(() => _busy = false);
        return;
      }
      final OpportunityPage page;
      if (_forMe) {
        if (widget.repository is! OpportunityRepository) {
          throw StateError('Opportunities unavailable');
        }
        page = await (widget.repository as OpportunityRepository).opportunities(
          categoryIds: _filters.categoryId == null
              ? null
              : [_filters.categoryId!],
          specialtyIds: _filters.specialtyId == null
              ? null
              : [_filters.specialtyId!],
          zoneIds: _filters.zoneId == null ? null : [_filters.zoneId!],
          cursor: _cursor,
        );
      } else {
        final stream = widget.repository is ExplorerRepository
            ? (widget.repository as ExplorerRepository).watchExplore(
                filters: _filters,
              )
            : widget.repository.watchPublic();
        _subscription = stream.listen(
          (rows) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _items
                ..clear()
                ..addAll(rows.where(_filters.matches));
              _error = null;
              _busy = false;
            });
          },
          onError: (Object e) {
            if (mounted && generation == _generation) {
              setState(() {
                _error = 'Impossible de charger les demandes. Réessaie.';
                _busy = false;
              });
            }
          },
        );
        return;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _items.map((r) => r.id).toSet();
        _items.addAll(
          page.items.where((r) => r.status == 'published' && ids.add(r.id)),
        );
        _cursor = page.cursor;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error =
              'Impossible de charger les demandes ou leurs filtres. Vérifie ta connexion puis réessaie.';
          _busy = false;
        });
      }
    }
  }

  void _mode(bool forMe) {
    if (_busy || forMe == _forMe) return;
    setState(() => _forMe = forMe);
    _load(reset: true);
  }

  void _clear() {
    setState(() {
      if (_forMe) {
        _personal = const ExplorerFilters();
      } else {
        _public = const ExplorerFilters();
      }
    });
    _load(reset: true);
  }

  String _label(String id, Iterable<ReferenceChoice> choices) =>
      choices.where((c) => c.id == id).firstOrNull?.label ??
      'Référence indisponible';
  Future<void> _showFilters() async {
    final catalog = _catalog;
    if (catalog == null || !catalog.enabled) {
      setState(() => _error = 'Filtres indisponibles. Réessaie.');
      return;
    }
    final a = widget.profile.activity;
    final categories = catalog.categories
        .where((c) => !_forMe || a.categoryIds.contains(c.id))
        .toList();
    final zones = catalog.zones
        .where((z) => !_forMe || a.zoneIds.contains(z.id))
        .toList();
    var category = _filters.categoryId,
        specialty = _filters.specialtyId,
        zone = _filters.zoneId;
    final selected = await showModalBottomSheet<ExplorerFilters>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final specialties = categories
              .where((c) => c.id == category)
              .expand((c) => c.specialties)
              .where((s) => !_forMe || a.specialtyIds.contains(s.id))
              .toList();
          Widget choice(
            String title,
            List<ReferenceChoice> values,
            String? value,
            ValueChanged<String?>? onChanged,
          ) => Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                '$title-$value-${values.map((v) => v.id).join(',')}',
              ),
              initialValue: values.any((v) => v.id == value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: title),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Toutes'),
                ),
                for (final v in values)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text(v.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          );
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _forMe ? 'Affiner mes opportunités' : 'Filtrer les demandes',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                if (_forMe) ...[
                  const RequestNotice(
                    'Pour moi activé',
                    'Les critères de ton profil sont appliqués automatiquement. Les filtres les affinent.',
                  ),
                  const SizedBox(height: 20),
                ],
                choice(
                  'Catégorie',
                  categories,
                  category,
                  (id) => update(() {
                    category = id;
                    specialty = null;
                  }),
                ),
                choice(
                  'Spécialité',
                  specialties,
                  specialty,
                  category == null
                      ? null
                      : (id) => update(() => specialty = id),
                ),
                choice(
                  'Zone géographique',
                  zones,
                  zone,
                  (id) => update(() => zone = id),
                ),
                const Text(
                  'Les zones correspondent aux identifiants déclarés, sans extension automatique aux zones voisines.',
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => update(() {
                    category = null;
                    specialty = null;
                    zone = null;
                  }),
                  child: const Text('Effacer'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ExplorerFilters(
                      categoryId: category,
                      specialtyId: specialty,
                      zoneId: zone,
                    ),
                  ),
                  child: const Text('Voir les résultats'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        if (_forMe) {
          _personal = selected;
        } else {
          _public = selected;
        }
      });
      _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        const RequestHeading(
          'Explorer les demandes',
          subtitle: 'Les besoins publiés par la communauté.',
        ),
        if (_eligible) ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tout Explorer'),
                selected: !_forMe,
                onSelected: (_) => _mode(false),
              ),
              ChoiceChip(
                label: const Text('Pour moi'),
                selected: _forMe,
                onSelected: (_) => _mode(true),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_forMe) ...[
          const RequestNotice(
            'Pour moi activé',
            'Catégories, spécialités et zones de ton profil professionnel approuvé.',
          ),
          const SizedBox(height: 16),
        ],
        OutlinedButton.icon(
          onPressed: _busy ? null : _showFilters,
          icon: const Icon(Icons.tune),
          label: const Text('Filtres'),
        ),
        if (!_filters.isEmpty)
          Wrap(
            spacing: 8,
            children: [
              if (_filters.categoryId != null)
                RequestTag(
                  _label(_filters.categoryId!, catalog?.categories ?? []),
                ),
              if (_filters.specialtyId != null)
                RequestTag(
                  _label(
                    _filters.specialtyId!,
                    catalog?.categories.expand((c) => c.specialties) ?? [],
                  ),
                ),
              if (_filters.zoneId != null)
                RequestTag(_label(_filters.zoneId!, catalog?.zones ?? [])),
              TextButton(
                onPressed: _busy ? null : _clear,
                child: const Text('Effacer les filtres'),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: _busy ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton(
            onPressed: () => _load(reset: _items.isEmpty),
            child: const Text('Réessayer'),
          ),
        ],
        if (!_busy && _error == null && _forMe && !_usableProfile) ...[
          const RequestNotice(
            'Profil à compléter',
            'Aucune activité ou zone exploitable dans ton dossier approuvé. Consulte tes informations professionnelles.',
          ),
          if (widget.onProfile != null)
            TextButton(
              onPressed: widget.onProfile,
              child: const Text('Voir mon profil professionnel'),
            ),
        ] else if (!_busy && _error == null && _items.isEmpty) ...[
          const SizedBox(height: 36),
          const CircleAvatar(
            radius: 55,
            backgroundColor: FoundiUi.tint,
            child: Icon(Icons.search, size: 45, color: FoundiUi.green),
          ),
          const SizedBox(height: 24),
          Text(
            _filters.isEmpty && !_forMe
                ? 'Aucune demande publiée pour le moment'
                : 'Aucune demande trouvée',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Essaie d’élargir les critères ou consulte toutes les demandes.',
            textAlign: TextAlign.center,
          ),
          if (!_filters.isEmpty)
            TextButton(
              onPressed: _clear,
              child: const Text('Effacer les filtres'),
            ),
          if (_forMe)
            FilledButton(
              onPressed: () => _mode(false),
              child: const Text('Voir toutes les demandes'),
            ),
          if (!_forMe && _filters.isEmpty)
            FilledButton(
              onPressed: widget.onPublish,
              child: const Text('Publier une demande'),
            ),
        ],
        if (!_forMe && !_busy && _error == null)
          const Text(
            'Les 30 demandes les plus récentes pour ces critères.',
            style: TextStyle(fontSize: 12, color: FoundiUi.muted),
          ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('${_items.length} résultat(s) affiché(s)'),
          ),
        for (final request in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: RequestCard(request, onTap: () => widget.onOpen(request)),
          ),
        if (!_busy && _cursor != null)
          OutlinedButton(
            onPressed: _load,
            child: const Text('Charger la suite'),
          ),
      ],
    );
  }
}
