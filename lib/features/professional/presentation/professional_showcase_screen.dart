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

class ProfessionalShowcaseScreen extends StatefulWidget {
  const ProfessionalShowcaseScreen({
    super.key,
    required this.repository,
    this.proposalId,
    this.businessName = '',
    this.onPersonal,
  });

  final ProfessionalShowcaseRepository repository;
  final String? proposalId;
  final String businessName;
  final VoidCallback? onPersonal;

  @override
  State<ProfessionalShowcaseScreen> createState() =>
      _ProfessionalShowcaseScreenState();
}

class _ProfessionalShowcaseScreenState
    extends State<ProfessionalShowcaseScreen> {
  bool get _own => widget.proposalId == null;
  late Future<ProfessionalShowcase?> _profile = _load();

  Future<ProfessionalShowcase?> _load() =>
      widget.repository.readShowcase(proposalId: widget.proposalId);

  Future<void> _edit(ProfessionalShowcase? profile) async {
    final saved = await Navigator.of(context).push<ProfessionalShowcase>(
      MaterialPageRoute(
        builder: (_) => _ShowcaseEditor(
          repository: widget.repository,
          initial: profile ?? ProfessionalShowcase(name: widget.businessName),
          onPersonal: widget.onPersonal,
        ),
      ),
    );
    if (!mounted || saved == null) return;
    setState(() {
      _profile = Future.value(saved);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil professionnel enregistré.')),
    );
  }

  void _openPhoto(ShowcasePhoto photo, int index) {
    showDialog<void>(
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

  @override
  Widget build(BuildContext context) => _ShowcasePage(
    title: 'Profil professionnel',
    child: FutureBuilder<ProfessionalShowcase?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final failure = snapshot.error;
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
                    _profile = profile;
                  });
                },
                child: const Text('Réessayer'),
              ),
            ],
          );
        }
        final profile = snapshot.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
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
              _ShowcaseIdentity(profile: profile),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _SectionTitle('À propos'),
                const SizedBox(height: 6),
                Text(profile.bio, style: const TextStyle(height: 1.5)),
              ],
              const SizedBox(height: 22),
              const _SectionTitle('Réalisations'),
              const SizedBox(height: 8),
              if (profile.gallery.isEmpty)
                const Text(
                  'Aucune réalisation ajoutée.',
                  style: TextStyle(color: FoundiUi.muted),
                )
              else
                _PhotoGrid(
                  photos: profile.gallery,
                  onPhoto: (index) => _openPhoto(profile.gallery[index], index),
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
  });

  final ProfessionalShowcaseRepository repository;
  final ProfessionalShowcase initial;
  final VoidCallback? onPersonal;

  @override
  State<_ShowcaseEditor> createState() => _ShowcaseEditorState();
}

class _ShowcaseEditorState extends AuthActionState<_ShowcaseEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _trade = TextEditingController(text: widget.initial.trade);
  late final _area = TextEditingController(text: widget.initial.area);
  late final _bio = TextEditingController(text: widget.initial.bio);
  late ShowcasePhoto? _portrait = widget.initial.portrait;
  late ShowcasePhoto? _cover = widget.initial.cover;
  late final _gallery = widget.initial.gallery.toList();

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
    ValueChanged<ShowcasePhoto?> update,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: SizedBox(
      height: 44,
      width: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: _Photo(photo, icon: Icons.photo_outlined),
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
                'Ce profil est accessible aux clients qui reçoivent tes propositions.',
                style: TextStyle(color: FoundiUi.muted),
              ),
              const SizedBox(height: 12),
              _photoRow(
                'Photo de profil',
                _portrait,
                (photo) => _portrait = photo,
              ),
              _photoRow('Couverture', _cover, (photo) => _cover = photo),
              const SizedBox(height: 12),
              _field('Nom affiché', _name, 65, required: true),
              const SizedBox(height: 6),
              _field('Métier', _trade, 85, required: true),
              const SizedBox(height: 6),
              _field('Zones d’intervention', _area, 100),
              const SizedBox(height: 6),
              _field('Présentation', _bio, 500, lines: 4),
              const SizedBox(height: 12),
              const _SectionTitle('Réalisations'),
              const SizedBox(height: 8),
              if (_gallery.isNotEmpty)
                _PhotoGrid(
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
  const _SectionTitle(this.text);
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

class _ShowcaseIdentity extends StatelessWidget {
  const _ShowcaseIdentity({required this.profile});
  final ProfessionalShowcase profile;

  @override
  Widget build(BuildContext context) => FoundiPanel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 145,
              width: double.infinity,
              child: profile.cover == null
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [FoundiUi.ink, FoundiUi.green],
                        ),
                      ),
                    )
                  : _Photo(
                      profile.cover,
                      icon: Icons.photo_outlined,
                      label: 'Couverture',
                    ),
            ),
            Positioned(
              left: 14,
              bottom: -24,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: _Photo(
                    profile.portrait,
                    icon: Icons.person_outline,
                    label: 'Photo du professionnel',
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 32, 15, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RequestTag('Professionnel vérifié'),
              const SizedBox(height: 8),
              _SectionTitle(profile.name),
              const SizedBox(height: 4),
              Text(profile.trade),
              if (profile.area.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: FoundiUi.green,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        profile.area,
                        style: const TextStyle(color: FoundiUi.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Photo extends StatelessWidget {
  const _Photo(this.photo, {required this.icon, this.label});
  final ShowcasePhoto? photo;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: FoundiUi.tint,
      child: Center(child: Icon(icon, color: FoundiUi.green)),
    );
    final image = photo;
    return image == null
        ? placeholder
        : Image.memory(
            image.bytes,
            fit: BoxFit.cover,
            semanticLabel: label,
            excludeFromSemantics: label == null,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos, this.onPhoto, this.onRemove});
  final List<ShowcasePhoto> photos;
  final ValueChanged<int>? onPhoto, onRemove;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    primary: false,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 135,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: photos.length,
    itemBuilder: (context, index) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Photo(photos[index], icon: Icons.photo_outlined),
          if (onPhoto != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onPhoto!(index),
                child: Semantics(label: 'Voir la réalisation ${index + 1}'),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                tooltip: 'Retirer la réalisation ${index + 1}',
                onPressed: () => onRemove!(index),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    ),
  );
}
