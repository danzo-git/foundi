import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'catalog_repository.dart';

const green = Color(0xFF00856F);
const ink = Color(0xFF102B35);
IconData activityIcon(String? key) => switch (key) {
  'home' => Icons.home_rounded,
  'car' => Icons.directions_car_rounded,
  'build' => Icons.build_rounded,
  'storefront' => Icons.storefront_rounded,
  'event' => Icons.event_rounded,
  'favorite' => Icons.favorite_rounded,
  'school' => Icons.school_rounded,
  _ => Icons.work_rounded,
};

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.active, this.inherited = false});
  final bool active, inherited;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFDDF7ED) : const Color(0xFFEDF1F4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      inherited
          ? 'Parent inactif'
          : active
          ? 'Active'
          : 'Inactive',
      style: TextStyle(
        color: active ? green : const Color(0xFF607181),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.section, this.repository});
  final String section;
  final CatalogRepository? repository;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final CatalogRepository repository =
      widget.repository ?? FirebaseCatalogRepository();
  late Stream<Map<String, dynamic>> stream = repository.watch();
  String search = '', status = 'all';
  String? categoryId;
  bool busy = false;
  String? error;
  Future<void> mutate(
    Map<String, dynamic> catalog,
    Map<String, dynamic> input,
  ) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository.update({
        ...input,
        'expectedVersion': catalog['version'] ?? '',
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(
          () => error = e.code == 'aborted'
              ? 'Le référentiel a changé. Vérifiez les nouvelles données puis recommencez.'
              : e.message ?? 'Enregistrement impossible.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Enregistrement impossible. Vérifiez la connexion puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool matches(Map<String, dynamic> e) =>
      (e['label'] as String).toLowerCase().contains(search.toLowerCase()) &&
      (status == 'all' || (e['active'] != false) == (status == 'active'));
  Future<void> edit(
    Map<String, dynamic> catalog,
    String kind, {
    Map<String, dynamic>? entry,
    String? parentCategory,
  }) async {
    final operation = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CatalogEditor(
        catalog: catalog,
        kind: kind,
        entry: entry,
        categoryId: parentCategory,
      ),
    );
    if (operation != null && mounted) await mutate(catalog, operation);
  }

  bool ancestorsActive(
    Map<String, dynamic> zone,
    List<Map<String, dynamic>> zones,
  ) {
    final seen = <String>{};
    var current = zone;
    while (current['parentId'] != null) {
      if (!seen.add(current['id'])) return false;
      final parent = zones
          .where((z) => z['id'] == current['parentId'])
          .firstOrNull;
      if (parent == null || parent['active'] == false) return false;
      current = parent;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>>(
    stream: stream,
    builder: (context, s) {
      if (s.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impossible de charger le référentiel.'),
              TextButton(
                onPressed: () => setState(() => stream = repository.watch()),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final catalog = s.requireData;
      final categories = catalogEntries(catalog, 'categories');
      final zones = catalogEntries(catalog, 'zones');
      final selected = categories
          .where((c) => c['id'] == categoryId)
          .firstOrNull;
      final section = widget.section;
      final title = section == 'zones'
          ? 'Zones géographiques'
          : section == 'documents'
          ? 'Justificatifs'
          : section == 'specialties'
          ? 'Spécialités'
          : selected?['label'] ?? 'Catégories';
      final kind = section == 'zones'
          ? 'zone'
          : section == 'documents'
          ? 'documentType'
          : section == 'specialties' || selected != null
          ? 'specialty'
          : 'category';
      final List<Map<String, dynamic>> entries = kind == 'category'
          ? categories
          : kind == 'zone'
          ? zones
          : kind == 'documentType'
          ? catalogEntries(catalog, 'documentTypes')
          : selected != null
          ? catalogEntries(selected, 'specialties')
          : [
              for (final c in categories)
                for (final spec in catalogEntries(c, 'specialties'))
                  {...spec, 'categoryId': c['id'], 'categoryLabel': c['label']},
            ];
      return SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: selected != null
                  ? () => setState(() => categoryId = null)
                  : null,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(
                selected != null
                    ? 'Catalogue  ›  Catégories'
                    : 'Catalogue  ›  $title',
              ),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => edit(
                          catalog,
                          kind,
                          parentCategory: selected?['id'],
                        ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    kind == 'category'
                        ? 'Ajouter une catégorie'
                        : kind == 'specialty'
                        ? 'Ajouter une spécialité'
                        : kind == 'zone'
                        ? 'Ajouter une zone'
                        : 'Ajouter un justificatif',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              section == 'zones'
                  ? 'Organisez les zones de Côte d’Ivoire : pays, districts, régions, villes et quartiers.'
                  : section == 'documents'
                  ? 'Définissez les pièces privées exigées selon chaque activité.'
                  : 'Gérez les activités partagées par les professionnels et les demandes clients.',
              style: const TextStyle(color: Color(0xFF607181)),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(active: catalog['enabled'] == true),
                    Text(
                      catalog['enabled'] == true
                          ? 'Référentiel disponible sur le mobile'
                          : 'Référentiel en préparation — soumission désactivée',
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final enable = catalog['enabled'] != true;
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    enable
                                        ? 'Activer le référentiel ?'
                                        : 'Mettre en pause ?',
                                  ),
                                  content: Text(
                                    enable
                                        ? 'Les choix actifs seront proposés aux utilisateurs. Configurez les justificatifs de chaque catégorie avant activation.'
                                        : 'Les brouillons seront conservés. Les nouvelles soumissions seront bloquées.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Annuler'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Confirmer'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                await mutate(catalog, {
                                  'operation': 'publish',
                                  'enabled': enable,
                                });
                              }
                            },
                      child: Text(
                        catalog['enabled'] == true
                            ? 'Mettre en pause'
                            : 'Activer le référentiel',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (selected != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            activityIcon(selected['icon']),
                            color: green,
                            size: 36,
                          ),
                          Text(
                            selected['label'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          StatusBadge(active: selected['active'] != false),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => edit(
                                    catalog,
                                    'category',
                                    entry: selected,
                                  ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Modifier les informations'),
                          ),
                        ],
                      ),
                      Text(selected['description'] ?? ''),
                      const SizedBox(height: 8),
                      const Text(
                        'La pièce d’identité est toujours requise. Les autres exigences sont configurées par type de professionnel.',
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Rechercher…',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                DropdownButton<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Tous les statuts'),
                    ),
                    DropdownMenuItem(value: 'active', child: Text('Actives')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Inactives'),
                    ),
                  ],
                  onChanged: (v) => setState(() => status = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (entries.where(matches).isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucun élément. Ajoutez les premières références pour préparer les inscriptions.',
                ),
              ),
            if (kind == 'zone')
              ...zoneRows(catalog, zones)
            else
              ...entries
                  .where(matches)
                  .map(
                    (entry) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5F5EF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              activityIcon(
                                kind == 'category' ? entry['icon'] : 'work',
                              ),
                              color: green,
                            ),
                          ),
                          title: Text(
                            entry['label'],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            kind == 'category'
                                ? '${catalogEntries(entry, 'specialties').length} spécialités'
                                : entry['categoryLabel'] ??
                                      entry['description'] ??
                                      '',
                          ),
                          onTap: kind == 'category'
                              ? () => setState(() => categoryId = entry['id'])
                              : () => edit(
                                  catalog,
                                  kind,
                                  entry: entry,
                                  parentCategory:
                                      selected?['id'] ?? entry['categoryId'],
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (MediaQuery.sizeOf(context).width > 650)
                                StatusBadge(active: entry['active'] != false),
                              IconButton(
                                tooltip: 'Modifier',
                                onPressed: busy
                                    ? null
                                    : () => edit(
                                        catalog,
                                        kind,
                                        entry: entry,
                                        parentCategory:
                                            selected?['id'] ??
                                            entry['categoryId'],
                                      ),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                              IconButton(
                                tooltip: entry['active'] == false
                                    ? 'Activer'
                                    : 'Désactiver',
                                onPressed: busy
                                    ? null
                                    : () => mutate(catalog, {
                                        'operation': kind,
                                        'id': entry['id'],
                                        'categoryId':
                                            selected?['id'] ??
                                            entry['categoryId'],
                                        'value': {
                                          ...entry,
                                          'active': entry['active'] == false,
                                        },
                                      }),
                                icon: Icon(
                                  entry['active'] == false
                                      ? Icons.toggle_off_outlined
                                      : Icons.toggle_on,
                                  color: green,
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            const Text(
              'Les identifiants restent stables. La désactivation conserve les profils et les historiques existants.',
              style: TextStyle(color: Color(0xFF607181), fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
  List<Widget> zoneRows(
    Map<String, dynamic> catalog,
    List<Map<String, dynamic>> zones,
  ) {
    final rows = <Widget>[];
    final visited = <String>{};
    void visit(Map<String, dynamic> zone, int depth) {
      if (!visited.add(zone['id'])) return;
      final inherited = !ancestorsActive(zone, zones);
      if (matches(zone)) {
        rows.add(
          Card(
            child: ListTile(
              contentPadding: EdgeInsets.only(
                left: 16 + (depth.clamp(0, 5) * 18).toDouble(),
                right: 8,
              ),
              leading: Icon(
                zone['type'] == 'country'
                    ? Icons.flag_outlined
                    : Icons.location_on_outlined,
                color: green,
              ),
              title: Text(
                zone['label'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${zoneLabels[zone['type']] ?? 'Zone d’intervention'}${inherited ? ' • Parent désactivé' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (MediaQuery.sizeOf(context).width > 650)
                    StatusBadge(
                      active: zone['active'] != false && !inherited,
                      inherited: inherited,
                    ),
                  IconButton(
                    tooltip: 'Modifier',
                    onPressed: busy
                        ? null
                        : () => edit(catalog, 'zone', entry: zone),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: zone['active'] == false ? 'Activer' : 'Désactiver',
                    onPressed: busy
                        ? null
                        : () => mutate(catalog, {
                            'operation': 'zone',
                            'id': zone['id'],
                            'value': {
                              ...zone,
                              'type': zone['type'] ?? 'intervention',
                              'active': zone['active'] == false,
                            },
                          }),
                    icon: Icon(
                      zone['active'] == false
                          ? Icons.toggle_off_outlined
                          : Icons.toggle_on,
                      color: green,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      for (final child in zones.where((z) => z['parentId'] == zone['id'])) {
        visit(child, depth + 1);
      }
    }

    for (final root in zones.where(
      (z) =>
          z['parentId'] == null || !zones.any((p) => p['id'] == z['parentId']),
    )) {
      visit(root, 0);
    }
    return rows;
  }
}

class CatalogEditor extends StatefulWidget {
  const CatalogEditor({
    super.key,
    required this.catalog,
    required this.kind,
    this.entry,
    this.categoryId,
  });
  final Map<String, dynamic> catalog;
  final String kind;
  final Map<String, dynamic>? entry;
  final String? categoryId;
  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.entry?['label'] ?? '');
  late final description = TextEditingController(
    text: widget.entry?['description'] ?? '',
  );
  late final id = TextEditingController(
    text:
        widget.entry?['id'] ??
        (catalogEntries(
              widget.catalog,
              'documentTypes',
            ).any((d) => d['id'] == 'identity')
            ? ''
            : 'identity'),
  );
  late bool active = widget.entry?['active'] != false;
  late String icon = widget.entry?['icon'] ?? 'work',
      type = widget.entry?['type'] ?? 'intervention';
  late String parent = widget.entry?['parentId'] ?? '',
      category = widget.categoryId ?? '';
  late final independent = Set<String>.from(
        widget.entry?['requirements']?['independent'] ?? [],
      ),
      company = Set<String>.from(
        widget.entry?['requirements']?['company'] ?? [],
      );
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final noun = kind == 'category'
        ? 'catégorie'
        : kind == 'specialty'
        ? 'spécialité'
        : kind == 'zone'
        ? 'zone'
        : 'pièce justificative';
    final categories = catalogEntries(widget.catalog, 'categories');
    final zones = catalogEntries(widget.catalog, 'zones');
    bool descendant(Map<String, dynamic> zone) {
      final seen = <String>{};
      var current = zone;
      while (true) {
        if (current['id'] == widget.entry?['id'] || !seen.add(current['id'])) {
          return true;
        }
        final next = zones
            .where((z) => z['id'] == current['parentId'])
            .firstOrNull;
        if (next == null) return false;
        current = next;
      }
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.entry == null ? 'Ajouter une' : 'Modifier la'} $noun',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Renseignez un nom.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                if (widget.entry != null)
                  Text(
                    'Identifiant : ${widget.entry!['id']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                if (kind == 'documentType' && widget.entry == null)
                  TextFormField(
                    controller: id,
                    decoration: const InputDecoration(
                      labelText: 'Identifiant permanent *',
                      helperText:
                          'identity pour la pièce d’identité ; lettres, chiffres, _ et -',
                    ),
                    validator: (v) =>
                        v == null ||
                            !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(v)
                        ? 'Identifiant invalide.'
                        : null,
                  ),
                if (kind == 'specialty') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category.isEmpty ? null : category,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie parente *',
                    ),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(c['label']),
                          ),
                        )
                        .toList(),
                    onChanged: widget.entry != null
                        ? null
                        : (v) => setState(() => category = v!),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Choisissez une catégorie.'
                        : null,
                  ),
                ],
                if (kind == 'category') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: catalogIcons.containsKey(icon)
                        ? icon
                        : 'work',
                    decoration: const InputDecoration(labelText: 'Icône'),
                    items: catalogIcons.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                Icon(activityIcon(e.key), size: 20),
                                const SizedBox(width: 8),
                                Text(e.value),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => icon = v!,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Justificatifs requis',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'La pièce identity est toujours obligatoire. Les autres pièces sont configurables par statut.',
                  ),
                  if (catalogEntries(widget.catalog, 'documentTypes').isEmpty)
                    const Text(
                      'Ajoutez les types de justificatifs dans Catalogue → Justificatifs.',
                    ),
                  for (final config in [
                    ('Indépendant', independent),
                    ('Entreprise', company),
                  ]) ...[
                    const SizedBox(height: 12),
                    Text(
                      config.$1,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final doc in catalogEntries(
                      widget.catalog,
                      'documentTypes',
                    ).where((d) => d['id'] != 'identity'))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${doc['label']}${doc['active'] == false ? ' (inactive)' : ''}',
                        ),
                        value: config.$2.contains(doc['id']),
                        onChanged: (v) => setState(() {
                          v == true
                              ? config.$2.add(doc['id'])
                              : config.$2.remove(doc['id']);
                        }),
                      ),
                  ],
                ],
                if (kind == 'zone') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Type de zone',
                    ),
                    items: zoneLabels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: parent,
                    decoration: const InputDecoration(
                      labelText: 'Zone parente',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Aucune (racine)'),
                      ),
                      ...zones
                          .where((z) => !descendant(z))
                          .map(
                            (z) => DropdownMenuItem(
                              value: z['id'] as String,
                              child: Text(
                                z['label'],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: (v) => setState(() => parent = v!),
                  ),
                ],
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, {
              'operation': kind,
              if (widget.entry != null) 'id': widget.entry!['id'],
              if (kind == 'specialty') 'categoryId': category,
              'value': {
                'label': name.text.trim(),
                'description': description.text.trim(),
                'active': active,
                if (kind == 'documentType') 'id': id.text.trim(),
                if (kind == 'category') ...{
                  'icon': icon,
                  'requirements': {
                    'independent': independent.toList(),
                    'company': company.toList(),
                  },
                },
                if (kind == 'zone') ...{
                  'type': type,
                  'parentId': parent.isEmpty ? null : parent,
                },
              },
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
