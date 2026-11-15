import 'dart:async';
import '../domain/account_photo_changes.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/auth_repository.dart';
import '../domain/personal_avatar_repository.dart';
import '../../navigation/presentation/space_widgets.dart';

class PersonalAvatarEndpointScope extends InheritedWidget {
  const PersonalAvatarEndpointScope({
    super.key,
    required this.endpointBase,
    required super.child,
  });
  final String? endpointBase;
  static String? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PersonalAvatarEndpointScope>()
      ?.endpointBase;
  @override
  bool updateShouldNotify(PersonalAvatarEndpointScope oldWidget) =>
      endpointBase != oldWidget.endpointBase;
}

class PersonalAvatar extends StatefulWidget {
  const PersonalAvatar({
    super.key,
    this.publicId,
    this.versionStream,
    this.loadImage,
    this.size = 32,
    this.fallback,
  });
  final String? publicId;
  final Stream<String?>? versionStream;
  final Future<Uint8List?> Function(String version)? loadImage;
  final double size;
  final Widget? fallback;
  @override
  State<PersonalAvatar> createState() => _PersonalAvatarState();
}

class _PersonalAvatarState extends State<PersonalAvatar> {
  Stream<String?>? _versions;
  String? _version;
  Future<Uint8List?>? _image;
  Uint8List? _bytes;
  void _bind() {
    _version = null;
    _image = null;
    _evict();
    _versions =
        widget.versionStream ??
        (widget.publicId != null && Firebase.apps.isNotEmpty
            ? FirebaseFirestore.instance
                  .doc('publicPersonalAvatars/${widget.publicId}')
                  .snapshots(includeMetadataChanges: true)
                  .map(
                    (s) => s.metadata.isFromCache
                        ? null
                        : s.data()?['version'] as String?,
                  )
            : null);
  }

  void _evict() {
    if (_bytes != null) {
      MemoryImage(_bytes!).evict();
      _bytes = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(PersonalAvatar old) {
    super.didUpdateWidget(old);
    if (old.publicId != widget.publicId ||
        old.versionStream != widget.versionStream) {
      _bind();
    }
  }

  @override
  void dispose() {
    _evict();
    super.dispose();
  }

  Future<Uint8List?> _load(String version) async {
    if (widget.loadImage != null) return widget.loadImage!(version);
    final base =
        PersonalAvatarEndpointScope.maybeOf(context) ??
        'https://europe-west1-${Firebase.app().options.projectId}.cloudfunctions.net';
    final response =
        await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ).get<List<int>>(
          '$base/readPublicPersonalAvatar',
          queryParameters: {'id': widget.publicId, 'version': version},
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Cache-Control': 'no-cache'},
          ),
        );
    return Uint8List.fromList(response.data!);
  }

  Widget get _fallback =>
      widget.fallback ??
      CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: FoundiUi.tint,
        child: const Icon(
          Icons.person_outline,
          size: 18,
          color: FoundiUi.green,
        ),
      );
  @override
  Widget build(BuildContext context) => _versions == null
      ? _fallback
      : StreamBuilder<String?>(
          stream: _versions,
          builder: (context, snapshot) {
            final version = snapshot.data;
            if (snapshot.hasError || version == null) {
              _evict();
              _version = null;
              _image = null;
              return _fallback;
            }
            if (_version != version) {
              _evict();
              _version = version;
              _image = _load(version);
            }
            return FutureBuilder<Uint8List?>(
              key: ValueKey(version),
              future: _image,
              builder: (context, image) {
                if (image.hasError || image.data == null) return _fallback;
                _bytes = image.data;
                return ClipOval(
                  child: Image.memory(
                    image.data!,
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.cover,
                    frameBuilder: (_, child, frame, _) =>
                        frame == null ? _fallback : child,
                    errorBuilder: (_, _, _) => _fallback,
                    semanticLabel: 'Photo personnelle publique',
                  ),
                );
              },
            );
          },
        );
}

class AccountPhotoSelection {
  const AccountPhotoSelection(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

typedef AccountPhotoPicker = Future<AccountPhotoSelection?> Function();
Future<AccountPhotoSelection?> pickAccountPhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 5 * 1024 * 1024) {
    throw const AuthFailure('Choisis une photo de 5 Mio maximum.');
  }
  final type =
      file.mimeType ??
      (file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : file.name.toLowerCase().endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg');
  return AccountPhotoSelection(bytes, type);
}

Future<bool> editAccountPhoto(
  BuildContext context,
  PersonalAvatarRepository repository, {
  AccountPhotoPicker picker = pickAccountPhoto,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            20,
            22,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: PersonalAvatarEditor(
            repository: repository,
            picker: picker,
            onSaved: () => Navigator.pop(context, true),
            onClose: () => Navigator.pop(context, false),
          ),
        ),
      ),
    ) ??
    false;

class AccountIdentityAvatar extends StatefulWidget {
  const AccountIdentityAvatar({
    super.key,
    required this.repository,
    required this.initials,
    this.onChanged,
    this.picker = pickAccountPhoto,
  });
  final PersonalAvatarRepository repository;
  final String initials;
  final VoidCallback? onChanged;
  final AccountPhotoPicker picker;
  @override
  State<AccountIdentityAvatar> createState() => _AccountIdentityAvatarState();
}

class _AccountIdentityAvatarState extends State<AccountIdentityAvatar> {
  late Future<PersonalAvatarState> _state = widget.repository
      .personalAvatarState();
  late final StreamSubscription<void> _updates;
  @override
  void initState() {
    super.initState();
    _updates = AccountPhotoChanges.stream.listen((_) {
      if (mounted) {
        setState(() {
          _state = widget.repository.personalAvatarState();
        });
      }
    });
  }

  @override
  void dispose() {
    _updates.cancel();
    super.dispose();
  }

  Future<void> _edit() async {
    if (await editAccountPhoto(
          context,
          widget.repository,
          picker: widget.picker,
        ) &&
        mounted) {
      setState(() {
        _state = widget.repository.personalAvatarState();
      });
      widget.onChanged?.call();
    }
  }

  Widget get _initials => CircleAvatar(
    radius: 30,
    backgroundColor: FoundiUi.tint,
    child: Text(
      widget.initials.isEmpty ? 'F' : widget.initials,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: FoundiUi.green,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Modifier ma photo de compte',
    child: Tooltip(
      message: 'Modifier ma photo de compte',
      child: InkWell(
        key: const ValueKey('accountIdentityAvatar'),
        onTap: _edit,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            children: [
              FutureBuilder<PersonalAvatarState>(
                future: _state,
                builder: (context, snapshot) => snapshot.data?.preview == null
                    ? _initials
                    : ClipOval(
                        child: Image.memory(
                          snapshot.data!.preview!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _initials,
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: FoundiUi.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PersonalAvatarEditor extends StatefulWidget {
  const PersonalAvatarEditor({
    super.key,
    required this.repository,
    this.picker = pickAccountPhoto,
    this.onSaved,
    this.onClose,
  });
  final PersonalAvatarRepository repository;
  final AccountPhotoPicker picker;
  final VoidCallback? onSaved, onClose;
  @override
  State<PersonalAvatarEditor> createState() => _PersonalAvatarEditorState();
}

class _PersonalAvatarEditorState extends State<PersonalAvatarEditor> {
  late Future<PersonalAvatarState> _state = widget.repository
      .personalAvatarState();
  AccountPhotoSelection? _chosen;
  String? _error;
  bool _busy = false;
  Future<void> _pick() async {
    try {
      final selection = await widget.picker();
      if (selection != null && mounted) {
        setState(() {
          _chosen = selection;
          _error = null;
        });
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de lire cette photo. Réessaie.');
      }
    }
  }

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (remove) {
        await widget.repository.removePersonalAvatar();
      } else {
        await widget.repository.savePersonalAvatar(
          bytes: _chosen?.bytes,
          contentType: _chosen?.contentType,
          publish: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _chosen = null;
        _state = widget.repository.personalAvatarState();
      });
      widget.onSaved?.call();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Modification non confirmée. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: FutureBuilder<PersonalAvatarState>(
      future: _state,
      builder: (context, snapshot) {
        final current = snapshot.data,
            bytes = _chosen?.bytes ?? snapshot.data?.preview;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ma photo de compte',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: _busy ? null : widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Cette photo représente ton compte. Elle est visible avec tes demandes et sera aussi utilisée pour ton profil professionnel, si tu en crées un.',
            ),
            const SizedBox(height: 16),
            Center(
              child: bytes == null
                  ? const CircleAvatar(
                      radius: 44,
                      backgroundColor: FoundiUi.tint,
                      child: Icon(
                        Icons.person_outline,
                        size: 40,
                        color: FoundiUi.green,
                      ),
                    )
                  : ClipOval(
                      child: Image.memory(
                        bytes,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.person_outline, size: 70),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (snapshot.hasError)
              TextButton(
                onPressed: () => setState(() {
                  _state = widget.repository.personalAvatarState();
                }),
                child: const Text('Réessayer le chargement de la photo'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                current?.hasPhoto == true || _chosen != null
                    ? 'Changer ma photo'
                    : 'Choisir une photo',
              ),
            ),
            if (_chosen != null ||
                current?.hasPhoto == true && current?.published != true)
              FilledButton(
                onPressed: _busy ? null : () => _save(),
                child: const Text('Utiliser cette photo'),
              ),
            if (current?.hasPhoto == true)
              TextButton(
                onPressed: _busy ? null : () => _save(remove: true),
                child: const Text('Supprimer ma photo'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
          ],
        );
      },
    ),
  );
}
