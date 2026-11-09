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
  RequestComposerState createState() => RequestComposerState();
}

enum _Stage { input, review, success }

class RequestComposerState extends AuthActionState<RequestComposer> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _budget = TextEditingController();
  String? _categoryId, _specialtyId, _zoneId;
  bool _manualTitle = false;
  bool _confirmingExit = false;
  _Stage _stage = _Stage.input;
  late final String _id = widget.initial?.id ?? widget.repository.newId();
  late Stream<ProfessionalCatalog> _catalog = widget.catalog.watchCatalog();
  late RequestDraft _reviewedDraft;
  late FoundiRequest _preview;
  FoundiRequest? _published;

  @override
  void initState() {
    super.initState();
    final request = widget.initial;
    if (request == null) return;
    _manualTitle = true;
    _title.text = request.title;
    _description.text = request.description;
    _budget.text = request.budget?.toString() ?? '';
    _categoryId = request.categoryId;
    _specialtyId = request.specialtyId.isEmpty ? null : request.specialtyId;
    _zoneId = request.zoneId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _budget.dispose();
    super.dispose();
  }

  String? get _suggestedTitle {
    final description = _description.text.trim();
    if (description.length < 10) return null;
    final firstLine = description.split(RegExp(r'[\r\n]')).first;
    final sentence = firstLine
        .split(RegExp(r'[.!?](?:\s|$)'))
        .first
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sentence.length < 3 ||
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(sentence)) {
      return null;
    }
    const limit = 72;
    if (sentence.length <= limit) return sentence;

    final prefix = StringBuffer();
    for (final character in sentence.characters) {
      if (prefix.length + character.length >= limit) break;
      prefix.write(character);
    }
    final text = prefix.toString();
    final lastSpace = text.lastIndexOf(' ');
    final excerpt = (lastSpace >= 3 ? text.substring(0, lastSpace) : text)
        .trimRight();
    return excerpt.length >= 3 ? '$excerpt…' : null;
  }

  bool get _changed {
    final initial = widget.initial;
    return initial != null &&
        (_title.text.trim() != initial.title ||
            _description.text.trim() != initial.description ||
            _budget.text.trim() != (initial.budget?.toString() ?? '') ||
            _categoryId != initial.categoryId ||
            (_specialtyId ?? '') != initial.specialtyId ||
            _zoneId != initial.zoneId);
  }

  /// Creation stays mounted in the shell. Only replacing or closing an edit
  /// can actually discard typed values.
  Future<bool> confirmDiscard() async {
    if (busy || _confirmingExit) return false;
    if (!_changed) return true;
    _confirmingExit = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Quitter la modification ?'),
              content: const Text(
                'Les modifications saisies seront perdues si tu quittes.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Continuer la saisie'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Quitter'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _back() async {
    if (busy) return;
    if (_stage == _Stage.review) {
      _returnToInput();
    } else if (await confirmDiscard() && mounted && widget.active) {
      widget.onExit();
    }
  }

  void _returnToInput() => setState(() {
    _stage = _Stage.input;
    error = null;
  });

  ProfessionalCategory? _category(ProfessionalCatalog catalog, String? id) =>
      catalog.categories.where((item) => item.id == id).firstOrNull;

  bool _referencesValid(ProfessionalCatalog catalog, RequestDraft draft) {
    final category = _category(catalog, draft.categoryId);
    return catalog.enabled &&
        category != null &&
        catalog.zones.any((zone) => zone.id == draft.zoneId) &&
        (category.specialties.isEmpty
            ? draft.specialtyId.isEmpty
            : category.specialties.any((item) => item.id == draft.specialtyId));
  }

  void _verify(ProfessionalCatalog catalog) {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final category = _category(catalog, _categoryId);
    final draft = RequestDraft(
      categoryId: _categoryId ?? '',
      specialtyId: category?.specialties.isNotEmpty == true
          ? _specialtyId ?? ''
          : '',
      zoneId: _zoneId ?? '',
      title: (_manualTitle ? _title.text : _suggestedTitle ?? _title.text)
          .trim(),
      description: _description.text.trim(),
      budget: RequestDraft.parseBudget(_budget.text),
    );
    if (!_referencesValid(catalog, draft)) return;
    final specialty = category!.specialties
        .where((item) => item.id == draft.specialtyId)
        .firstOrNull;
    _reviewedDraft = draft;
    _preview = FoundiRequest(
      id: _id,
      title: draft.title,
      description: draft.description,
      categoryLabel: category.label,
      specialtyLabel: specialty?.label ?? '',
      zoneLabel: catalog.zones
          .firstWhere((zone) => zone.id == draft.zoneId)
          .label,
      status: 'published',
      createdAt: null,
      budget: draft.budget,
    );
    setState(() {
      _stage = _Stage.review;
      error = null;
    });
  }

  Future<void> _publish() async {
    final ok = await perform(() async {
      _published = widget.initial == null
          ? await widget.repository.publish(_id, _reviewedDraft)
          : await (widget.repository as RequestManagementRepository).manage(
              _id,
              'edit',
              draft: _reviewedDraft,
              expectedRevision: widget.initial!.revision,
            );
    });
    if (!ok || !mounted) return;
    if (widget.initial != null) {
      widget.onMine();
      return;
    }
    setState(() => _stage = _Stage.success);
    widget.onPublished?.call();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.active) _back();
    },
    child: StreamBuilder<ProfessionalCatalog>(
      stream: _catalog,
      builder: (context, snapshot) {
        final value = snapshot.data;
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        final catalog =
            !waiting &&
                !snapshot.hasError &&
                value != null &&
                value.enabled &&
                value.categories.isNotEmpty &&
                value.zones.isNotEmpty
            ? value
            : null;
        final references = _catalogStatus(waiting, catalog);
        return SingleChildScrollView(
          key: ValueKey(_stage),
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestHeading(
                switch (_stage) {
                  _Stage.input =>
                    widget.initial == null
                        ? 'Nouvelle demande'
                        : 'Modifier ma demande',
                  _Stage.review => 'Vérification',
                  _Stage.success => 'Demande publiée',
                },
                onBack: _back,
                bottomSpacing: 10,
              ),
              switch (_stage) {
                _Stage.input => _input(catalog, references),
                _Stage.review => _review(catalog, references),
                _Stage.success => _success(),
              },
            ],
          ),
        );
      },
    ),
  );

  Widget _catalogStatus(bool waiting, ProfessionalCatalog? catalog) {
    if (waiting) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Chargement des catégories et des zones',
      );
    }
    if (catalog != null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthNotice(
          'Catégories et zones indisponibles. Tes saisies sont conservées.',
        ),
        OutlinedButton(
          onPressed: () => setState(() {
            _catalog = widget.catalog.watchCatalog();
          }),
          child: const Text('Actualiser les références'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _input(ProfessionalCatalog? catalog, Widget references) {
    final category = catalog == null ? null : _category(catalog, _categoryId);
    final suggestion = _suggestedTitle;
    final showTitle =
        _manualTitle ||
        (_description.text.trim().length >= 10 && suggestion == null);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RequestHeading(
            'De quoi as-tu besoin ?',
            subtitle: 'Décris simplement ce que tu recherches.',
            bottomSpacing: 12,
          ),
          TextFormField(
            key: const ValueKey('requestDescription'),
            controller: _description,
            minLines: 3,
            maxLines: 6,
            maxLength: 3000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description du besoin *',
              hintText: 'Ex. Installer un climatiseur dans une chambre',
              alignLabelWithHint: true,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final length = value?.trim().length ?? 0;
              return length < 10 || length > 3000
                  ? 'Décris ton besoin en 10 à 3 000 caractères.'
                  : null;
            },
          ),
          const SizedBox(height: 8),
          references,
          if (catalog != null) ...[
            if ((_categoryId != null && category == null) ||
                (_zoneId != null &&
                    !catalog.zones.any((item) => item.id == _zoneId)) ||
                (_specialtyId != null &&
                    category?.specialties.isNotEmpty == true &&
                    !category!.specialties.any(
                      (item) => item.id == _specialtyId,
                    )))
              const AuthNotice(
                'Une sélection n’est plus disponible. Choisis une référence active.',
              ),
            _choice(
              'Catégorie *',
              'requestCategory',
              catalog.categories,
              _categoryId,
              (id) => setState(() {
                _categoryId = id;
                _specialtyId = null;
              }),
            ),
            if (category != null && category.specialties.isNotEmpty)
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
              catalog.zones,
              _zoneId,
              (id) => setState(() => _zoneId = id),
            ),
          ],
          TextFormField(
            key: const ValueKey('requestBudget'),
            controller: _budget,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Budget (facultatif)',
              suffixText: 'FCFA',
              hintText: 'Budget à discuter',
            ),
            validator: (value) {
              try {
                RequestDraft.parseBudget(value ?? '');
                return null;
              } on FormatException {
                return 'Montant entier de 0 à 999 999 999 999 FCFA.';
              }
            },
          ),
          const SizedBox(height: 12),
          if (showTitle)
            TextFormField(
              key: const ValueKey('requestTitle'),
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Titre de la demande *',
              ),
              onChanged: (_) {
                if (!_manualTitle) setState(() => _manualTitle = true);
              },
              validator: (value) {
                final length = value?.trim().length ?? 0;
                return length < 3 || length > 120
                    ? 'Renseigne un titre de 3 à 120 caractères.'
                    : null;
              },
            )
          else if (suggestion != null)
            FoundiPanel(
              color: FoundiUi.soft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Titre proposé',
                          style: TextStyle(color: FoundiUi.muted),
                        ),
                        Text(
                          suggestion,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    flex: 2,
                    child: TextButton(
                      onPressed: () => setState(() {
                        _title.text = suggestion;
                        _manualTitle = true;
                      }),
                      child: const Text(
                        'Modifier le titre',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            requestPrivacy,
            style: TextStyle(color: FoundiUi.muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('verifyRequest'),
            onPressed: catalog == null ? null : () => _verify(catalog),
            child: const Text('Vérifier ma demande'),
          ),
        ],
      ),
    );
  }

  Widget _review(ProfessionalCatalog? catalog, Widget references) {
    final valid = catalog != null && _referencesValid(catalog, _reviewedDraft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestHeading(
          widget.initial == null
              ? 'Vérifie avant publication'
              : 'Vérifie tes modifications',
          subtitle: 'Voici ce qui sera visible, même sans compte Foundi.',
          bottomSpacing: 16,
        ),
        RequestPreview(_preview),
        const SizedBox(height: 12),
        const Text(
          requestPrivacy,
          style: TextStyle(color: FoundiUi.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 12),
        references,
        if (catalog != null && !valid)
          const AuthNotice(
            'Une sélection n’est plus disponible. Modifie ta demande avant de continuer.',
          ),
        AuthNotice(error),
        FilledButton(
          key: const ValueKey('publishRequest'),
          onPressed: busy || !valid ? null : _publish,
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  widget.initial == null
                      ? 'Publier ma demande'
                      : 'Enregistrer les modifications',
                ),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: busy ? null : _returnToInput,
          child: const Text('Modifier'),
        ),
      ],
    );
  }

  Widget _success() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CircleAvatar(
        radius: 52,
        backgroundColor: FoundiUi.tint,
        child: CircleAvatar(
          radius: 35,
          backgroundColor: FoundiUi.green,
          child: Icon(Icons.check, size: 42, color: Colors.white),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        'C’est publié !',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 28,
          color: FoundiUi.ink,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Ta demande est désormais visible dans le fil public Foundi.',
        textAlign: TextAlign.center,
        style: TextStyle(color: FoundiUi.muted, height: 1.6),
      ),
      const SizedBox(height: 24),
      RequestCard(_published!),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => widget.onOpen(_published!),
        child: const Text('Voir ma demande'),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: widget.onMine,
        child: const Text('Accéder à Mes demandes'),
      ),
    ],
  );

  Widget _choice(
    String label,
    String key,
    List<ReferenceChoice> values,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key-$selected-${values.map((v) => v.id).join(',')}'),
      initialValue: values.any((v) => v.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (value) => DropdownMenuItem(
              value: value.id,
              child: Text(value.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (id) => id == null || !values.any((value) => value.id == id)
          ? 'Choisis une option active.'
          : null,
    ),
  );
}
