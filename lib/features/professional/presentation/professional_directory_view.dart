import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/professional_directory.dart';
import '../domain/professional_repository.dart';
import 'professional_showcase_screen.dart';

class ProfessionalDirectoryView extends StatefulWidget {
  const ProfessionalDirectoryView({
    super.key,
    required this.repository,
    required this.catalog,
    required this.heading,
    this.active = true,
  });
  final ProfessionalDirectoryRepository? repository;
  final ProfessionalRepository? catalog;
  final Widget heading;
  final bool active;
  @override
  State<ProfessionalDirectoryView> createState() =>
      _ProfessionalDirectoryViewState();
}

class _ProfessionalDirectoryViewState extends State<ProfessionalDirectoryView>
    with WidgetsBindingObserver {
  final _query = TextEditingController(), _scroll = ScrollController();
  final _items = <ProfessionalListing>[];
  final _valid = <String>{};
  final _visibleIds = <String>{};
  ProfessionalDirectoryFilters _filters = const ProfessionalDirectoryFilters();
  ProfessionalCatalog? _catalog;
  Timer? _debounce, _lease;
  String? _cursor, _error;
  int _generation = 0;
  bool _busy = false, _opening = false, _checking = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lease = Timer.periodic(const Duration(seconds: 30), (_) => _validate());
    _load(reset: true);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _lease?.cancel();
    _query.dispose();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProfessionalDirectoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _validate();
    if (!widget.active) _valid.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _validate();
    } else if (mounted) {
      setState(_valid.clear);
    }
  }

  void _revoke(String id) {
    widget.repository?.clearDirectoryMedia(id);
    if (mounted) {
      setState(() {
        _valid.remove(id);
        _items.removeWhere((p) => p.professionalId == id);
      });
    }
  }

  Future<void> _validate() async {
    if (!mounted ||
        !widget.active ||
        _opening ||
        _checking ||
        _items.isEmpty ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _checking = true;
    setState(_valid.clear);
    final generation = _generation, ids = _visibleIds.take(24).toList();
    try {
      final available = <String>{};
      for (var start = 0; start < ids.length; start += 24) {
        available.addAll(
          await widget.repository!.checkDirectoryProfessionals(
            ids.sublist(start, (start + 24).clamp(0, ids.length)),
          ),
        );
      }
      if (!mounted || generation != _generation) return;
      for (final id in ids.where((id) => !available.contains(id))) {
        widget.repository!.clearDirectoryMedia(id);
      }
      setState(() {
        _valid.addAll(available);
        _items.removeWhere(
          (p) =>
              ids.contains(p.professionalId) &&
              !available.contains(p.professionalId),
        );
      });
    } catch (_) {
      /* Keep text visible, with no stale badge or media, until the next successful check. */
    } finally {
      _checking = false;
    }
  }

  Future<void> _load({bool reset = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _valid.clear();
        _cursor = null;
      }
    });
    try {
      final repository = widget.repository;
      if (repository == null || widget.catalog == null) {
        throw const AuthFailure('L’annuaire est temporairement indisponible.');
      }
      final catalog = await widget.catalog!.loadCatalog();
      if (!mounted || generation != _generation) return;
      if (!catalog.enabled) {
        throw const AuthFailure('L’annuaire est temporairement indisponible.');
      }
      _catalog = catalog;
      ProfessionalDirectoryPage page;
      var cursor = _cursor, emptyPages = 0;
      do {
        page = await repository.searchProfessionals(_filters, cursor: cursor);
        if (!mounted || generation != _generation) return;
        cursor = page.cursor;
        emptyPages++;
      } while (page.items.isEmpty && cursor != null && emptyPages < 3);
      setState(() {
        final ids = _items.map((p) => p.professionalId).toSet();
        _items.addAll(page.items.where((p) => ids.add(p.professionalId)));
        _valid.addAll(page.items.map((p) => p.professionalId));
        _cursor = page.cursor;
        _busy = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e is AuthFailure
              ? e.message
              : 'Impossible de charger les professionnels. Vérifie ta connexion puis réessaie.';
          _busy = false;
        });
      }
    }
  }

  void _change(ProfessionalDirectoryFilters filters, {bool debounce = false}) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _filters = filters;
      _items.clear();
      _valid.clear();
      _cursor = null;
      _busy = true;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (debounce) {
      _debounce = Timer(
        const Duration(milliseconds: 400),
        () => _load(reset: true),
      );
    } else {
      _load(reset: true);
    }
  }

  void _reset() {
    _query.clear();
    _change(const ProfessionalDirectoryFilters());
  }

  Future<void> _open(ProfessionalListing item) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ProfessionalShowcaseScreen.recommended(
            professionalId: item.professionalId,
            loadRecommended: () => widget.repository!.readDirectoryProfessional(
              item.professionalId,
            ),
            checkAvailability: () async =>
                (await widget.repository!.checkDirectoryProfessionals([
                  item.professionalId,
                ])).contains(item.professionalId),
            onUnavailable: () => _revoke(item.professionalId),
          ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted) _validate();
    }
  }

  Future<void> _showFilters() async {
    final catalog = _catalog;
    if (catalog == null) return;
    var category = _filters.categoryId,
        specialty = _filters.specialtyId,
        zone = _filters.zoneId;
    final selected = await showModalBottomSheet<ProfessionalDirectoryFilters>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final specialties = catalog.categories
              .where((c) => c.id == category)
              .expand((c) => c.specialties)
              .toList();
          Widget choice(
            String label,
            List<ReferenceChoice> values,
            String? value,
            ValueChanged<String?>? change,
          ) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'directory-$label-$value-${values.map((v) => v.id).join(',')}',
              ),
              initialValue: values.any((v) => v.id == value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
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
              onChanged: change,
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
                const Text(
                  'Filtrer les professionnels',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 22),
                choice(
                  'Catégorie',
                  catalog.categories,
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
                  'Zone d’intervention',
                  catalog.zones,
                  zone,
                  (id) => update(() => zone = id),
                ),
                const Text(
                  'Rechercher dans les zones déclarées par les professionnels.',
                ),
                const SizedBox(height: 16),
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
                    ProfessionalDirectoryFilters(
                      query: _query.text,
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
    if (selected != null && mounted) _change(selected);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _catalog?.categories ?? [];
    final header = <Widget>[
      widget.heading,
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('professionalSearch'),
        controller: _query,
        maxLength: 80,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          counterText: '',
          prefixIcon: Icon(Icons.search),
          hintText: 'Un métier, un service, un nom…',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        onChanged: (query) => _change(
          ProfessionalDirectoryFilters(
            query: query,
            categoryId: _filters.categoryId,
            specialtyId: _filters.specialtyId,
            zoneId: _filters.zoneId,
          ),
          debounce: true,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('Tous'),
                selected: _filters.categoryId == null,
                onSelected: (_) => _change(
                  ProfessionalDirectoryFilters(
                    query: _query.text,
                    zoneId: _filters.zoneId,
                  ),
                ),
              ),
            ),
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.label),
                  selected: _filters.categoryId == c.id,
                  onSelected: (_) => _change(
                    ProfessionalDirectoryFilters(
                      query: _query.text,
                      categoryId: c.id,
                      zoneId: _filters.zoneId,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('professionalFilters'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: _catalog == null ? null : _showFilters,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Filtres'),
          ),
          if (_filters.specialtyId != null || _filters.zoneId != null)
            const RequestTag('Filtres actifs'),
          IconButton(
            tooltip: 'Actualiser les professionnels',
            onPressed: _busy ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 20, color: FoundiUi.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Des professionnels vérifiés, à votre rencontre.',
                style: TextStyle(color: FoundiUi.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        RequestNotice('Chargement indisponible', _error!),
        TextButton(
          onPressed: () => _load(reset: _items.isEmpty),
          child: const Text('Réessayer'),
        ),
      ],
      if (_busy) const LinearProgressIndicator(),
      if (!_busy && _error == null && _items.isEmpty && _cursor == null) ...[
        const SizedBox(height: 24),
        const Icon(
          Icons.person_search_outlined,
          size: 48,
          color: FoundiUi.green,
        ),
        const SizedBox(height: 16),
        const Text(
          'Aucun professionnel trouvé',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Essaie un autre métier ou élargis les filtres.',
          textAlign: TextAlign.center,
        ),
        TextButton(
          onPressed: _reset,
          child: const Text('Réinitialiser la recherche'),
        ),
      ],
    ];
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      itemCount: 1 + _items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: header,
          );
        }
        if (index <= _items.length) {
          final item = _items[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ProfessionalCard(
              key: ValueKey(item.professionalId),
              item: item,
              repository: widget.repository!,
              verified: _valid.contains(item.professionalId),
              onVisibility: (visible) {
                if (visible) {
                  _visibleIds.add(item.professionalId);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_valid.contains(item.professionalId)) {
                      _validate();
                    }
                  });
                } else {
                  _visibleIds.remove(item.professionalId);
                }
              },
              onTap: () => _open(item),
            ),
          );
        }
        if (_cursor != null && !_busy) {
          return OutlinedButton(
            onPressed: _load,
            child: Text(
              _items.isEmpty ? 'Continuer la recherche' : 'Charger la suite',
            ),
          );
        }
        return const SizedBox(height: 12);
      },
    );
  }
}

class _ProfessionalCard extends StatefulWidget {
  const _ProfessionalCard({
    super.key,
    required this.item,
    required this.repository,
    required this.verified,
    required this.onTap,
    required this.onVisibility,
  });
  final ProfessionalListing item;
  final ProfessionalDirectoryRepository repository;
  final bool verified;
  final VoidCallback onTap;
  final ValueChanged<bool> onVisibility;
  @override
  State<_ProfessionalCard> createState() => _ProfessionalCardState();
}

class _ProfessionalCardState extends State<_ProfessionalCard> {
  @override
  void initState() {
    super.initState();
    widget.onVisibility(true);
  }

  @override
  void dispose() {
    widget.onVisibility(false);
    super.dispose();
  }

  late Future<ProfessionalMediaManifest> _media = widget.repository
      .directoryMediaManifest(widget.item.professionalId);
  @override
  void didUpdateWidget(_ProfessionalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.verified && widget.verified) {
      _media = widget.repository.directoryMediaManifest(
        widget.item.professionalId,
      );
    }
  }

  Widget _photo(String id, {bool portrait = false}) => FutureBuilder<Uint8List>(
    future: widget.repository.readDirectoryThumbnail(
      widget.item.professionalId,
      id,
    ),
    builder: (_, snapshot) => snapshot.hasData
        ? Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => const Icon(
              Icons.image_not_supported_outlined,
              color: FoundiUi.muted,
            ),
          )
        : ColoredBox(
            color: FoundiUi.soft,
            child: Center(
              child: Icon(
                portrait ? Icons.person_outline : Icons.image_outlined,
                color: FoundiUi.muted,
              ),
            ),
          ),
  );
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Voir le profil de ${widget.item.name}',
    child: FoundiPanel(
      onTap: widget.onTap,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<ProfessionalMediaManifest>(
        future: _media,
        builder: (context, snapshot) {
          final media = widget.verified ? snapshot.data : null,
              item = widget.item;
          final words = item.name
              .trim()
              .split(RegExp(r'\s+'))
              .where((s) => s.isNotEmpty)
              .take(2);
          final initials = words
              .map((s) => s.characters.first.toUpperCase())
              .join();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 58,
                      height: 58,
                      child: media?.portraitId != null
                          ? _photo(media!.portraitId!, portrait: true)
                          : ColoredBox(
                              color: FoundiUi.tint,
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: FoundiUi.green,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: FoundiUi.ink,
                          ),
                        ),
                        if (widget.verified)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 15,
                                  color: FoundiUi.green,
                                ),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Professionnel vérifié',
                                    style: TextStyle(
                                      color: FoundiUi.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(item.trade, style: const TextStyle(fontSize: 13)),
                        if ({
                              ...item.categories,
                              ...item.specialties,
                            }.join(' · ') !=
                            item.trade)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              {
                                ...item.categories,
                                ...item.specialties,
                              }.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: FoundiUi.muted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 5),
                        if (item.zones.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: FoundiUi.muted,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  item.zones.join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: FoundiUi.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: FoundiUi.muted,
                  ),
                ],
              ),
              if (media?.galleryIds.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 86,
                  child: Row(
                    children: [
                      for (final id in media!.galleryIds)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _photo(id),
                            ),
                          ),
                        ),
                      if (media.galleryIds.length < 3)
                        Spacer(flex: 3 - media.galleryIds.length),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
