import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/presentation/foundi_logo.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/professional_showcase.dart';
import 'professional_profile_widgets.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/presentation/direct_requests.dart';

enum ShowcaseEditSection { portrait, cover, gallery }

Future<ProfessionalShowcase?> editProfessionalShowcase(
  BuildContext context, {
  required ProfessionalShowcaseRepository repository,
  required ProfessionalShowcase initial,
  VoidCallback? onPersonal,
  ShowcaseEditSection? section,
}) => Navigator.of(context).push<ProfessionalShowcase>(
  MaterialPageRoute(
    builder: (_) => _ShowcaseEditor(
      repository: repository,
      initial: initial,
      onPersonal: onPersonal,
      section: section,
    ),
  ),
);

Future<void> openShowcasePhoto(
  BuildContext context,
  ShowcasePhoto photo,
  int index,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Image.memory(
                photo.bytes,
                fit: BoxFit.contain,
                semanticLabel: 'Réalisation ${index + 1}',
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Image indisponible.'),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProfessionalShowcaseScreen extends StatefulWidget {
  const ProfessionalShowcaseScreen({
    super.key,
    required ProfessionalShowcaseRepository this.repository,
    this.proposalId,
    this.businessName = '',
    this.onPersonal,
    this.professionalId,
  }) : loadRecommended = null,
       checkAvailability = null,
       onUnavailable = null;

  const ProfessionalShowcaseScreen.recommended({
    super.key,
    required Future<ProfessionalShowcase> Function() this.loadRecommended,
    this.professionalId,
    this.checkAvailability,
    this.onUnavailable,
  }) : repository = null,
       proposalId = null,
       businessName = '',
       onPersonal = null;

  final ProfessionalShowcaseRepository? repository;
  final Future<ProfessionalShowcase> Function()? loadRecommended;
  final String? proposalId;
  final String businessName;
  final VoidCallback? onPersonal;
  final String? professionalId;
  final Future<bool> Function()? checkAvailability;
  final VoidCallback? onUnavailable;

  @override
  State<ProfessionalShowcaseScreen> createState() =>
      _ProfessionalShowcaseScreenState();
}

class _ProfessionalShowcaseScreenState extends State<ProfessionalShowcaseScreen>
    with WidgetsBindingObserver {
  bool get _own => widget.proposalId == null && widget.loadRecommended == null;
  late Future<ProfessionalShowcase?> _profile = _load();
  int _section = 0;
  Timer? _lease;
  Object? _failure;
  bool _verified = true,
      _checking = false,
      _requesting = false,
      _photoOpen = false;
  @override
  void initState() {
    super.initState();
    if (widget.checkAvailability != null) {
      WidgetsBinding.instance.addObserver(this);
      _lease = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    }
  }

  @override
  void dispose() {
    _lease?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.checkAvailability == null) return;
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (mounted) {
      setState(() => _verified = false);
    }
  }

  Future<void> _check() async {
    if (_checking ||
        !mounted ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _checking = true;
    setState(() => _verified = false);
    try {
      final available = await widget.checkAvailability!();
      if (!mounted) return;
      if (!available) {
        widget.onUnavailable?.call();
        if (_photoOpen) Navigator.of(context).pop();
        setState(
          () => _failure = const AuthFailure(
            'Ce professionnel n’est plus disponible.',
          ),
        );
      } else {
        setState(() => _verified = true);
      }
    } catch (_) {
      /* A failed lease never leaves a verified badge or an enabled request action. */
    } finally {
      _checking = false;
    }
  }

  Future<void> _request(ProfessionalShowcase profile, String id) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final current = widget.checkAvailability == null
          ? profile
          : await _load();
      if (!mounted || current == null) return;
      if (widget.checkAvailability != null) {
        setState(() {
          _profile = Future.value(current);
          _verified = true;
        });
      }
      DirectRequestsScope.maybeOf(context)?.onRequest?.call(
        DirectProfessionalTarget(
          id,
          current.name,
          activity: current.requestActivity,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<ProfessionalShowcase?> _load() async {
    final profile =
        await (widget.loadRecommended?.call() ??
            widget.repository!.readShowcase(proposalId: widget.proposalId));
    if (mounted && widget.checkAvailability != null) {
      setState(() => _verified = true);
    }
    return profile;
  }

  Future<void> _edit(ProfessionalShowcase? profile) async {
    final saved = await editProfessionalShowcase(
      context,
      repository: widget.repository!,
      initial: profile ?? ProfessionalShowcase(name: widget.businessName),
      onPersonal: widget.onPersonal,
    );
    if (!mounted || saved == null) return;
    setState(() {
      _profile = Future.value(saved);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil professionnel enregistré.')),
    );
  }

  Future<void> _openPhoto(ShowcasePhoto photo, int index) async {
    _photoOpen = true;
    await openShowcasePhoto(context, photo, index);
    _photoOpen = false;
  }

  @override
  Widget build(BuildContext context) => _ShowcasePage(
    title: 'Profil professionnel',
    child: FutureBuilder<ProfessionalShowcase?>(
      future: _profile,
      builder: (context, snapshot) {
        if (_failure == null &&
            snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_failure != null || snapshot.hasError) {
          final failure = _failure ?? snapshot.error;
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              AuthNotice(
                failure is AuthFailure
                    ? failure.message
                    : 'Impossible de charger le profil.',
              ),
              OutlinedButton(
                onPressed: () {
                  final profile = _load();
                  setState(() {
                    _failure = null;
                    _profile = profile;
                  });
                },
                child: const Text('Réessayer'),
              ),
            ],
          );
        }
        final profile = snapshot.data;
        final professionalId = widget.professionalId ?? profile?.professionalId;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            if (_own) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    'Aperçu client',
                    style: TextStyle(color: FoundiUi.muted),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => _edit(profile),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      profile == null
                          ? 'Créer mon profil'
                          : 'Modifier le profil',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (profile == null)
              RequestNotice(
                _own ? 'Présente ton activité' : 'Profil indisponible',
                _own
                    ? 'Ajoute une présentation et des photos pour les clients qui reçoivent tes propositions.'
                    : 'Le profil et les réalisations ne sont pas disponibles pour cette proposition.',
              )
            else ...[
              ProfessionalShowcaseHeader(
                profile: profile,
                showVerified: _verified,
                showBio: true,
                action:
                    !_own &&
                        professionalId != null &&
                        DirectRequestsScope.maybeOf(context)?.onRequest !=
                            null &&
                        DirectRequestsScope.maybeOf(
                              context,
                            )?.auth.currentUser?.id !=
                            professionalId
                    ? OutlinedButton.icon(
                        key: const ValueKey('requestProfessionalDirectly'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          backgroundColor: FoundiUi.soft,
                          foregroundColor: FoundiUi.green,
                          side: const BorderSide(color: FoundiUi.green),
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: !_verified || _requesting
                            ? null
                            : () => _request(profile, professionalId),
                        icon: const Icon(Icons.send_outlined, size: 17),
                        label: const Text('Faire une demande'),
                      )
                    : null,
                footer: ProfessionalProfileTabs(
                  section: _section,
                  keyPrefix: 'publicProfileSection',
                  onSelected: (section) => setState(() => _section = section),
                ),
              ),
              const SizedBox(height: 14),
              if (!_verified && widget.checkAvailability != null)
                TextButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Revérifier la disponibilité'),
                ),
              ProfessionalProfileSection(
                profile: profile,
                section: _section,
                onPhoto: (index) => _openPhoto(profile.gallery[index], index),
                onSeeAll: () => setState(() => _section = 2),
                details: [
                  if (_section == 1 && profile.name.isNotEmpty)
                    ProfessionalProfileDetail(
                      Icons.business_outlined,
                      'Nom professionnel',
                      profile.name,
                    ),
                  if (profile.trade.isNotEmpty)
                    ProfessionalProfileDetail(
                      Icons.sell_outlined,
                      'Activité',
                      profile.trade,
                    ),
                  if (profile.area.isNotEmpty)
                    ProfessionalProfileDetail(
                      Icons.location_on_outlined,
                      'Zone d’intervention',
                      profile.area,
                    ),
                  if (_section == 1 && profile.bio.isNotEmpty)
                    ProfessionalProfileDetail(
                      Icons.description_outlined,
                      'Présentation',
                      profile.bio,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _ShowcaseEditor extends StatefulWidget {
  const _ShowcaseEditor({
    required this.repository,
    required this.initial,
    this.onPersonal,
    this.section,
  });

  final ProfessionalShowcaseRepository repository;
  final ProfessionalShowcase initial;
  final VoidCallback? onPersonal;
  final ShowcaseEditSection? section;

  @override
  State<_ShowcaseEditor> createState() => _ShowcaseEditorState();
}

class _ShowcaseEditorState extends AuthActionState<_ShowcaseEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _portraitSection = GlobalKey();
  final _coverSection = GlobalKey();
  final _gallerySection = GlobalKey();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _trade = TextEditingController(text: widget.initial.trade);
  late final _area = TextEditingController(text: widget.initial.area);
  late final _bio = TextEditingController(text: widget.initial.bio);
  late ShowcasePhoto? _portrait = widget.initial.portrait;
  late ShowcasePhoto? _cover = widget.initial.cover;
  late final _gallery = widget.initial.gallery.toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = switch (widget.section) {
        ShowcaseEditSection.portrait => _portraitSection.currentContext,
        ShowcaseEditSection.cover => _coverSection.currentContext,
        ShowcaseEditSection.gallery => _gallerySection.currentContext,
        null => null,
      };
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.15);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    _trade.dispose();
    _area.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<Uint8List?> _pickPhoto() async {
    final mobile =
        !kIsWeb &&
        const [
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform);
    if (mobile) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 84,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      _checkPhotoSize(await file.length());
      return file.readAsBytes();
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    _checkPhotoSize(file.lengthSync() ?? await file.length());
    return file.readAsBytes();
  }

  void _checkPhotoSize(int? length) {
    if (length == null ||
        length == 0 ||
        length > ProfessionalShowcase.maxInputBytes) {
      throw const AuthFailure(
        'Choisis une photo JPEG, PNG ou WebP de 2 Mio maximum.',
      );
    }
  }

  Future<void> _pick(ValueChanged<ShowcasePhoto> update) async {
    final success = await perform(() async {
      final bytes = await _pickPhoto();
      if (!mounted || bytes == null) return;
      setState(() => update(ShowcasePhoto(bytes)));
    });
    final message = error;
    if (!success && mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    if (busy) return;
    if (!_form.currentState!.validate()) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    late ProfessionalShowcase saved;
    final success = await perform(() async {
      saved = await widget.repository.saveShowcase(
        ProfessionalShowcase(
          revision: widget.initial.revision,
          name: _name.text.trim(),
          trade: _trade.text.trim(),
          area: _area.text.trim(),
          bio: _bio.text.trim(),
          portrait: _portrait,
          cover: _cover,
          gallery: List.unmodifiable(_gallery),
        ),
      );
    });
    if (success && mounted) Navigator.pop(context, saved);
  }

  Widget _field(
    String label,
    TextEditingController controller,
    int limit, {
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    controller: controller,
    enabled: !busy,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: lines > 1,
    ),
    maxLength: limit,
    minLines: lines,
    maxLines: lines,
    validator: required
        ? (value) =>
              (value?.trim().length ?? 0) < 2 ? 'Renseigne ce champ.' : null
        : null,
  );

  Widget _photoRow(
    String title,
    ShowcasePhoto? photo,
    ValueChanged<ShowcasePhoto?> update, {
    Key? key,
  }) => ListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    leading: SizedBox(
      height: 44,
      width: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ShowcasePhotoView(photo, icon: Icons.photo_outlined),
      ),
    ),
    title: Text(title),
    subtitle: Text(photo == null ? 'Ajouter' : 'Remplacer'),
    enabled: !busy,
    onTap: () => _pick(update),
    trailing: photo == null
        ? null
        : IconButton(
            tooltip: 'Retirer $title',
            onPressed: busy ? null : () => setState(() => update(null)),
            icon: const Icon(Icons.delete_outline),
          ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: _ShowcasePage(
      title: 'Modifier mon profil',
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Profil visible par les clients'),
              const SizedBox(height: 6),
              const Text(
                'Ces informations et photos sont visibles sur ton profil professionnel public.',
                style: TextStyle(color: FoundiUi.muted),
              ),
              const SizedBox(height: 12),
              _photoRow(
                'Photo de profil',
                _portrait,
                (photo) => _portrait = photo,
                key: _portraitSection,
              ),
              _photoRow(
                'Couverture',
                _cover,
                (photo) => _cover = photo,
                key: _coverSection,
              ),
              const SizedBox(height: 12),
              _field('Nom affiché', _name, 65, required: true),
              const SizedBox(height: 6),
              _field('Métier', _trade, 85, required: true),
              const SizedBox(height: 6),
              _field('Zones d’intervention', _area, 100),
              const SizedBox(height: 6),
              _field('Présentation', _bio, 500, lines: 4),
              const SizedBox(height: 12),
              _SectionTitle('Réalisations', key: _gallerySection),
              const SizedBox(height: 8),
              if (_gallery.isNotEmpty)
                ShowcaseGallery(
                  photos: _gallery,
                  onRemove: busy
                      ? null
                      : (index) => setState(() => _gallery.removeAt(index)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    busy || _gallery.length >= ProfessionalShowcase.maxGallery
                    ? null
                    : () => _pick(_gallery.add),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Ajouter une réalisation'),
              ),
              const Text(
                'Jusqu’à 6 réalisations. Publie des photos de ton travail avec l’accord des personnes reconnaissables.',
                style: TextStyle(color: FoundiUi.muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (widget.onPersonal != null)
                FoundiPanel(
                  color: FoundiUi.soft,
                  onTap: busy ? null : widget.onPersonal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline, color: FoundiUi.green),
                    title: Text('Informations personnelles'),
                    subtitle: Text(
                      'Nom complet et coordonnées du compte, en privé.',
                    ),
                    trailing: Icon(Icons.chevron_right),
                  ),
                ),
              AuthNotice(error),
              const SizedBox(height: 16),
              AuthButton(label: 'Enregistrer', busy: busy, onPressed: _save),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ShowcasePage extends StatelessWidget {
  const _ShowcasePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FoundiUi.background,
    appBar: AppBar(
      backgroundColor: FoundiUi.background,
      title: Text(title),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: FoundiLogo(size: 28, decorative: true),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(
        color: FoundiUi.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
