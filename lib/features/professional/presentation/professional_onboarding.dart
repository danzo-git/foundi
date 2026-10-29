import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../domain/professional_repository.dart';
import '../../auth/presentation/legal_acceptance_screen.dart';

class ProfessionalOnboarding extends StatefulWidget {
  const ProfessionalOnboarding({
    super.key,
    required this.user,
    required this.auth,
    required this.repository,
    required this.profile,
    required this.onExit,
  });
  final FoundiUser user;
  final AuthRepository auth;
  final ProfessionalRepository repository;
  final ProfessionalProfile profile;
  final VoidCallback onExit;
  @override
  State<ProfessionalOnboarding> createState() => _ProfessionalOnboardingState();
}

class _ProfessionalOnboardingState
    extends AuthActionState<ProfessionalOnboarding>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _business = TextEditingController(
    text: widget.profile.activity.businessName,
  );
  late final _description = TextEditingController(
    text: widget.profile.activity.description,
  );
  late String _type = widget.profile.activity.type;
  late final _categories = widget.profile.activity.categoryIds.toSet();
  late final _specialties = widget.profile.activity.specialtyIds.toSet();
  late final _zones = widget.profile.activity.zoneIds.toSet();
  late int _step = widget.profile.step;
  late Stream<ProfessionalCatalog> _catalog = widget.repository.watchCatalog();
  late final _documents = widget.repository.watchDocuments(widget.user.id);
  Timer? _timer;
  Future<void> _saves = Future.value();
  bool _certified = false, _dirty = false;
  String? _saveError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _business.addListener(_changed);
    _description.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _business.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _step == 2 && _dirty) {
      _queueSave();
    }
  }

  ProfessionalActivity get _activity => ProfessionalActivity(
    type: _type,
    businessName: _business.text.trim(),
    description: _description.text.trim(),
    categoryIds: _categories.toList(),
    specialtyIds: _specialties.toList(),
    zoneIds: _zones.toList(),
  );
  void _changed() {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _queueSave);
  }

  void _queueSave() {
    _timer?.cancel();
    if (!_dirty) return;
    final value = _activity;
    _dirty = false;
    _saves = _saves.then((_) async {
      try {
        await widget.repository.saveActivity(value, complete: false);
        if (mounted) setState(() => _saveError = null);
      } catch (_) {
        if (mounted) {
          setState(() {
            _dirty = true;
            _saveError =
                'Brouillon non synchronisé. Vérifie ta connexion et réessaie avant de quitter.';
          });
        }
      }
    });
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _queueSave();
    await _saves;
    if (_saveError != null) throw AuthFailure(_saveError!);
  }

  Future<void> _exit() async {
    final ok = await perform(() async {
      if (_step == 2) {
        _dirty = true;
        await _flush();
      }
    });
    if (ok && mounted) widget.onExit();
  }

  Future<void> _continue(ProfessionalCatalog catalog) async {
    if (catalog.requiredFor(_activity) == null) {
      setState(
        () => error =
            'Sélectionne des catégories, spécialités et zones actives. Retire les choix devenus indisponibles.',
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    final ok = await perform(() async {
      await _flush();
      await widget.repository.saveActivity(_activity, complete: true);
    });
    if (ok && mounted) {
      setState(() {
        _step = 3;
        _certified = false;
      });
    }
  }

  Future<void> _chooseDocument(ReferenceChoice choice) async {
    await perform(() async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (file == null) return;
      final length = file.lengthSync() ?? await file.length();
      if (length == null || length > 5 * 1024 * 1024) {
        throw const AuthFailure('Choisis un PDF, JPEG ou PNG de 5 Mo maximum.');
      }
      await widget.repository.uploadDocument(
        choice.id,
        file.name,
        await file.readAsBytes(),
      );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) _exit();
    },
    child: StreamBuilder<ProfessionalCatalog>(
      stream: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AuthLayout(
            title: 'Activité professionnelle',
            children: [
              const AuthHeading(
                title: 'Références indisponibles',
                description: 'Ton dossier est conservé.',
              ),
              AuthButton(
                label: 'Réessayer',
                onPressed: () =>
                    setState(() => _catalog = widget.repository.watchCatalog()),
              ),
              TextButton(
                onPressed: _exit,
                child: const Text('Enregistrer et terminer plus tard'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _step == 2
            ? _activityScreen(snapshot.requireData)
            : _documentScreen(snapshot.requireData);
      },
    ),
  );
  Widget _activityScreen(ProfessionalCatalog catalog) => AuthLayout(
    title: 'Activité professionnelle',
    onBack: busy ? null : _exit,
    footer: [
      AuthButton(
        label: 'Continuer',
        busy: busy,
        onPressed: !catalog.enabled ? null : () => _continue(catalog),
      ),
      TextButton(
        onPressed: busy ? null : _exit,
        child: const Text('Enregistrer et terminer plus tard'),
      ),
    ],
    children: [
      const AuthHeading(
        title: 'Parlons de ton activité',
        description: 'Décris tes spécialités et ta zone de service.',
      ),
      const OnboardingProgress(2),
      if (catalog.enabled &&
          (catalog.categories.isEmpty || catalog.zones.isEmpty))
        const AuthNotice(
          'Aucune catégorie ou zone active disponible. Ton brouillon est conservé.',
        ),
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'independent', label: Text('Indépendant')),
                ButtonSegment(value: 'company', label: Text('Entreprise')),
              ],
              selected: {_type},
              onSelectionChanged: busy
                  ? null
                  : (v) {
                      setState(() => _type = v.single);
                      _changed();
                    },
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('businessName'),
              controller: _business,
              enabled: !busy,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Nom professionnel / commercial',
                hintText: 'Nom affiché aux clients',
              ),
              validator: (v) => (v?.trim().length ?? 0) < 2
                  ? 'Renseigne ton nom professionnel.'
                  : null,
            ),
            const SizedBox(height: 16),
            _selection('Catégories', catalog.categories, _categories, () {
              _specialties.removeWhere(
                (id) => !catalog.categories
                    .where((c) => _categories.contains(c.id))
                    .any((c) => c.specialties.any((s) => s.id == id)),
              );
            }),
            if (_categories.isNotEmpty)
              _selection(
                'Spécialités',
                catalog.categories
                    .where((c) => _categories.contains(c.id))
                    .expand((c) => c.specialties)
                    .toList(),
                _specialties,
              ),
            _selection('Zones d’intervention', catalog.zones, _zones),
            TextFormField(
              key: const ValueKey('activityDescription'),
              controller: _description,
              enabled: !busy,
              maxLength: 2000,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Décris tes prestations…',
              ),
              validator: (v) => (v?.trim().length ?? 0) < 20
                  ? 'Décris tes prestations en au moins 20 caractères.'
                  : null,
            ),
          ],
        ),
      ),
      if (!catalog.enabled)
        const AuthNotice(
          'Les catégories, zones et justificatifs sont en préparation. Tu peux enregistrer ton brouillon ; la suite sera disponible après leur configuration.',
          isError: false,
        ),
      AuthNotice(_saveError),
      AuthNotice(error),
    ],
  );
  Widget _selection(
    String label,
    List<ReferenceChoice> choices,
    Set<String> selected, [
    VoidCallback? after,
  ]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final id in selected.where(
          (id) => !choices.any((c) => c.id == id),
        ))
          InputChip(
            label: Text('Indisponible : $id'),
            onDeleted: busy
                ? null
                : () {
                    setState(() {
                      selected.remove(id);
                      after?.call();
                    });
                    _changed();
                  },
          ),
        const SizedBox(height: 8),
        InkWell(
          key: ValueKey('select-$label'),
          borderRadius: BorderRadius.circular(12),
          onTap: busy || choices.isEmpty
              ? null
              : () async {
                  final pending = selected
                      .where((id) => choices.any((choice) => choice.id == id))
                      .toSet();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, update) => AlertDialog(
                        title: Text(label),
                        content: SizedBox(
                          width: 360,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: choices
                                  .map(
                                    (choice) => CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(choice.label),
                                      value: pending.contains(choice.id),
                                      onChanged: (v) => update(() {
                                        v == true
                                            ? pending.add(choice.id)
                                            : pending.remove(choice.id);
                                      }),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Valider'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (confirmed == true && mounted) {
                    setState(() {
                      selected
                        ..clear()
                        ..addAll(pending);
                      after?.call();
                    });
                    _changed();
                  }
                },
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    choices.isEmpty
                        ? 'Aucune référence disponible.'
                        : selected.isEmpty
                        ? 'Sélectionner'
                        : choices
                              .where((c) => selected.contains(c.id))
                              .map((c) => c.label)
                              .join(', '),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _documentScreen(
    ProfessionalCatalog catalog,
  ) => StreamBuilder<List<ProfessionalDocument>>(
    stream: _documents,
    builder: (context, snapshot) {
      final required = catalog.requiredFor(_activity);
      final uploaded = snapshot.data ?? [];
      final ready =
          required != null &&
          required.every((r) => uploaded.any((d) => d.kind == r.id && d.ready));
      return AuthLayout(
        title: 'Justificatifs',
        onBack: busy ? null : () => setState(() => _step = 2),
        footer: [
          AuthButton(
            label: 'Soumettre mon dossier',
            busy: busy,
            onPressed: !ready || !_certified || snapshot.hasError
                ? null
                : () async {
                    final ok = await perform(
                      () => widget.repository.submit(certified: _certified),
                    );
                    if (ok && mounted) widget.onExit();
                  },
          ),
          TextButton(
            onPressed: busy ? null : _exit,
            child: const Text('Enregistrer et terminer plus tard'),
          ),
        ],
        children: [
          const AuthHeading(
            title: 'Vérifie ton profil',
            description: 'Ces documents restent confidentiels.',
          ),
          const OnboardingProgress(3),
          if (snapshot.hasError)
            const AuthNotice(
              'Impossible de charger les justificatifs. Vérifie ta connexion puis réessaie.',
            )
          else if (!snapshot.hasData)
            const LinearProgressIndicator(),
          if (required == null)
            const AuthNotice(
              'Les justificatifs requis pour cette activité ne sont pas encore configurés. Ton brouillon reste disponible.',
            )
          else
            for (final choice in required) ...[
              Card(
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(
                    choice.id == 'identity'
                        ? Icons.badge_outlined
                        : Icons.description_outlined,
                    color: const Color(0xFF107865),
                  ),
                  title: Text(
                    choice.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    uploaded
                            .where((d) => d.kind == choice.id && d.ready)
                            .firstOrNull
                            ?.name ??
                        'Ajouter un document',
                  ),
                  trailing: Icon(
                    uploaded.any((d) => d.kind == choice.id && d.ready)
                        ? Icons.check_circle
                        : Icons.add_circle_outline,
                    color: const Color(0xFF107865),
                  ),
                  onTap: busy || !snapshot.hasData || snapshot.hasError
                      ? null
                      : () => _chooseDocument(choice),
                ),
              ),
              const SizedBox(height: 8),
            ],
          const AuthNotice(
            'Les justificatifs requis varient selon l’activité et le statut du professionnel. PDF, JPEG ou PNG · 5 Mo maximum par document.',
            isError: false,
          ),
          CheckboxListTile(
            key: const ValueKey('certifyProfile'),
            value: _certified,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Je certifie l’exactitude des informations'),
            onChanged: busy
                ? null
                : (v) => setState(() => _certified = v ?? false),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LegalAcceptanceScreen(repository: widget.auth),
                    ),
                  ),
            child: const Text('Consulter et accepter les CGU'),
          ),
          AuthNotice(error),
        ],
      );
    },
  );
}
