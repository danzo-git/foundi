import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../domain/request_repository.dart';
import 'request_views.dart';

class RequestComposer extends StatefulWidget {
  const RequestComposer({
    super.key,
    required this.repository,
    required this.catalog,
    required this.onExit,
    required this.onMine,
    required this.onOpen,
    this.active = true,
    this.onPublished,
    this.initial,
  });
  final FoundiRequest? initial;
  final RequestRepository repository;
  final ProfessionalRepository catalog;
  final VoidCallback onExit, onMine;
  final ValueChanged<FoundiRequest> onOpen;
  final bool active;
  final VoidCallback? onPublished;
  @override
  State<RequestComposer> createState() => _RequestComposerState();
}

class _RequestComposerState extends AuthActionState<RequestComposer> {
  final _essentials = GlobalKey<FormState>(), _details = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _description = TextEditingController(),
      _budget = TextEditingController();
  String? _categoryId, _specialtyId, _zoneId;
  int _step = 0;
  late final String _id = widget.initial?.id ?? widget.repository.newId();
  late Stream<ProfessionalCatalog> _catalog = widget.catalog.watchCatalog();
  FoundiRequest? _published;
  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r != null) {
      _title.text = r.title;
      _description.text = r.description;
      _budget.text = r.budget?.toString() ?? '';
      _categoryId = r.categoryId;
      _specialtyId = r.specialtyId.isEmpty ? null : r.specialtyId;
      _zoneId = r.zoneId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _budget.dispose();
    super.dispose();
  }

  RequestDraft get _draft => RequestDraft(
    categoryId: _categoryId ?? '',
    specialtyId: _specialtyId ?? '',
    zoneId: _zoneId ?? '',
    title: _title.text,
    description: _description.text,
    budget: RequestDraft.parseBudget(_budget.text),
  );
  void _back() {
    if (busy) return;
    if (_step == 0 || _step == 3) {
      widget.onExit();
    } else {
      setState(() {
        _step--;
        error = null;
      });
    }
  }

  bool _referencesValid(ProfessionalCatalog catalog) {
    final category = catalog.categories
        .where((c) => c.id == _categoryId)
        .firstOrNull;
    return catalog.enabled &&
        category != null &&
        catalog.zones.any((z) => z.id == _zoneId) &&
        (category.specialties.isEmpty
            ? _specialtyId == null
            : category.specialties.any((s) => s.id == _specialtyId));
  }

  Future<void> _publish(ProfessionalCatalog catalog) async {
    if (!_referencesValid(catalog)) {
      setState(
        () => error =
            'Une sélection n’est plus disponible. Modifie les informations de ta demande.',
      );
      return;
    }
    final ok = await perform(() async {
      _published = widget.initial == null
          ? await widget.repository.publish(_id, _draft)
          : await (widget.repository as RequestManagementRepository).manage(
              _id,
              'edit',
              draft: _draft,
              expectedRevision: widget.initial!.revision,
            );
    });
    if (ok && mounted) {
      if (widget.initial != null) {
        widget.onMine();
        return;
      }
      setState(() => _step = 3);
      widget.onPublished?.call();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.active) {
        _back();
      }
    },
    child: StreamBuilder<ProfessionalCatalog>(
      stream: _catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        final ready =
            catalog != null &&
            catalog.enabled &&
            catalog.categories.isNotEmpty &&
            catalog.zones.isNotEmpty;
        final category = catalog?.categories
            .where((c) => c.id == _categoryId)
            .firstOrNull;
        final specialty = category?.specialties
            .where((c) => c.id == _specialtyId)
            .firstOrNull;
        final zone = catalog?.zones.where((c) => c.id == _zoneId).firstOrNull;
        FoundiRequest? preview;
        if (_step == 2 && catalog != null) {
          preview = FoundiRequest(
            id: _id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            categoryLabel: category?.label ?? 'Catégorie indisponible',
            specialtyLabel: specialty?.label ?? '',
            zoneLabel: zone?.label ?? 'Zone indisponible',
            status: 'published',
            createdAt: null,
            budget: _draft.budget,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: RequestHeading(
                _step < 2
                    ? (widget.initial == null
                          ? 'Nouvelle demande'
                          : 'Modifier ma demande')
                    : _step == 2
                    ? 'Prévisualisation'
                    : 'Demande publiée',
                onBack: busy ? null : _back,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  if (_step < 2) ...[
                    Text(
                      'ÉTAPE ${_step + 1} SUR 2',
                      style: const TextStyle(
                        fontSize: 11,
                        color: FoundiUi.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (_step + 1) / 2,
                      color: FoundiUi.green,
                      backgroundColor: FoundiUi.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_step == 0) ...[
                    if (widget.initial != null &&
                        !_referencesValid(
                          catalog ?? const ProfessionalCatalog(),
                        ))
                      const AuthNotice(
                        'Une ancienne sélection est indisponible. Choisis une référence active pour enregistrer.',
                      ),
                    const RequestHeading(
                      'Parlons de ton besoin',
                      subtitle: 'Où et que recherches-tu ?',
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator()),
                    if (snapshot.hasError || (!ready && catalog != null)) ...[
                      const AuthNotice(
                        'Catégories et zones indisponibles. Tes saisies sont conservées.',
                      ),
                      OutlinedButton(
                        onPressed: () => setState(
                          () => _catalog = widget.catalog.watchCatalog(),
                        ),
                        child: const Text('Actualiser les références'),
                      ),
                    ],
                    Form(
                      key: _essentials,
                      child: Column(
                        children: [
                          _choice(
                            'Catégorie *',
                            'requestCategory',
                            catalog?.categories ?? [],
                            _categoryId,
                            (id) => setState(() {
                              _categoryId = id;
                              _specialtyId = null;
                            }),
                          ),
                          if (category != null &&
                              category.specialties.isNotEmpty)
                            _choice(
                              'Spécialité *',
                              'requestSpecialty',
                              category.specialties,
                              _specialtyId,
                              (id) => setState(() => _specialtyId = id),
                            ),
                          _choice(
                            'Zone de recherche *',
                            'requestZone',
                            catalog?.zones ?? [],
                            _zoneId,
                            (id) => setState(() => _zoneId = id),
                          ),
                          TextFormField(
                            key: const ValueKey('requestTitle'),
                            controller: _title,
                            enabled: !busy,
                            maxLength: 120,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Titre de la demande *',
                              hintText: 'Décris ton besoin en quelques mots',
                            ),
                            validator: (s) => (s?.trim().length ?? 0) < 3
                                ? 'Renseigne un titre (3 caractères minimum).'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Catégories et zones fournies par Foundi Admin.',
                      style: TextStyle(fontSize: 11, color: FoundiUi.muted),
                    ),
                  ] else if (_step == 1) ...[
                    const RequestHeading(
                      'Ajoute les détails',
                      subtitle: 'Explique clairement ce que tu attends.',
                    ),
                    Form(
                      key: _details,
                      child: Column(
                        children: [
                          TextFormField(
                            key: const ValueKey('requestDescription'),
                            controller: _description,
                            minLines: 5,
                            maxLines: 9,
                            enabled: !busy,
                            maxLength: 3000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Description *',
                              alignLabelWithHint: true,
                            ),
                            validator: (s) => (s?.trim().length ?? 0) < 10
                                ? 'Décris ton besoin (10 caractères minimum).'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const ValueKey('requestBudget'),
                            controller: _budget,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Budget souhaité (facultatif)',
                              suffixText: 'FCFA',
                              hintText: 'Budget à discuter',
                            ),
                            validator: (s) {
                              try {
                                RequestDraft.parseBudget(s ?? '');
                                return null;
                              } on FormatException {
                                return 'Montant entier de 0 à 999 999 999 999 FCFA.';
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const RequestNotice(
                      'Attention à ta vie privée',
                      requestPrivacy,
                      icon: Icons.lock_outline,
                    ),
                  ] else if (_step == 2 && preview != null) ...[
                    RequestHeading(
                      widget.initial == null
                          ? 'Vérifie avant publication'
                          : 'Vérifie tes modifications',
                      subtitle: 'Voici ce que les autres verront sur Foundi.',
                    ),
                    const RequestNotice('Visible même sans compte Foundi', ''),
                    const SizedBox(height: 20),
                    RequestPreview(preview),
                    const SizedBox(height: 20),
                    const Text(
                      requestPrivacy,
                      style: TextStyle(
                        fontSize: 11,
                        color: FoundiUi.muted,
                        height: 1.5,
                      ),
                    ),
                  ] else if (_published != null) ...[
                    const SizedBox(height: 30),
                    const CircleAvatar(
                      radius: 65,
                      backgroundColor: FoundiUi.tint,
                      child: CircleAvatar(
                        radius: 43,
                        backgroundColor: FoundiUi.green,
                        child: Icon(Icons.check, size: 50, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'C’est publié !',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        color: FoundiUi.ink,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ta demande est désormais visible dans le fil public Foundi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FoundiUi.muted, height: 1.6),
                    ),
                    const SizedBox(height: 35),
                    RequestCard(_published!),
                  ],
                  const SizedBox(height: 16),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthNotice(error),
                  if (_step == 0)
                    FilledButton(
                      onPressed: !ready || busy
                          ? null
                          : () {
                              if (_essentials.currentState!.validate() &&
                                  _referencesValid(catalog)) {
                                setState(() {
                                  _step = 1;
                                  error = null;
                                });
                              }
                            },
                      child: const Text('Continuer'),
                    ),
                  if (_step == 1)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (_details.currentState!.validate()) {
                                FocusScope.of(context).unfocus();
                                setState(() {
                                  _step = 2;
                                  error = null;
                                });
                              }
                            },
                      child: const Text('Prévisualiser ma demande'),
                    ),
                  if (_step == 2)
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    _step = 0;
                                    error = null;
                                  }),
                            child: const Text('Modifier'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: FilledButton(
                            key: const ValueKey('publishRequest'),
                            onPressed: busy || catalog == null
                                ? null
                                : () => _publish(catalog),
                            child: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    widget.initial == null
                                        ? 'Publier ma demande'
                                        : 'Enregistrer les modifications',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  if (_step == 3) ...[
                    FilledButton(
                      onPressed: () => widget.onOpen(_published!),
                      child: const Text('Voir ma demande'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: widget.onMine,
                      child: const Text('Accéder à Mes demandes'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget _choice(
    String label,
    String key,
    List<ReferenceChoice> values,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key-$selected-${values.map((v) => v.id).join(',')}'),
      initialValue: values.any((v) => v.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (v) => DropdownMenuItem(
              value: v.id,
              child: Text(v.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: busy ? null : onChanged,
      validator: (id) => id == null || !values.any((v) => v.id == id)
          ? 'Choisis une option active.'
          : null,
    ),
  );
}
