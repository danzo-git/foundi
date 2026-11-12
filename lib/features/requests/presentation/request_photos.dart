import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../auth/domain/auth_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/request_photo_repository.dart';

typedef RequestPhotoPicker = Future<List<RequestPhotoSelection>> Function();

class RequestPhotoSelection {
  const RequestPhotoSelection(this.size, this.read);
  final int? size;
  final Future<Uint8List> Function() read;
}

Future<List<RequestPhotoSelection>> pickRequestPhotos() async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  return [
    for (final file in files)
      RequestPhotoSelection(
        file.lengthSync() ?? await file.length(),
        file.readAsBytes,
      ),
  ];
}

bool _matches(Uint8List data, List<int> signature, [int offset = 0]) {
  if (data.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (data[offset + i] != signature[i]) return false;
  }
  return true;
}

Future<LocalRequestPhoto> validateRequestPhoto(
  RequestPhotoSelection selection,
) async {
  const sizeError = AuthFailure('Choisis une photo de 5 Mio maximum.');
  final size = selection.size;
  if (size == null || size > maxRequestPhotoBytes) throw sizeError;
  final bytes = await selection.read();
  if (bytes.length > maxRequestPhotoBytes) throw sizeError;
  final String type;
  if (_matches(bytes, const [255, 216, 255])) {
    type = 'image/jpeg';
  } else if (_matches(bytes, const [137, 80, 78, 71, 13, 10, 26, 10])) {
    type = 'image/png';
  } else if (_matches(bytes, const [82, 73, 70, 70]) &&
      _matches(bytes, const [87, 69, 66, 80], 8)) {
    type = 'image/webp';
  } else {
    throw const AuthFailure(
      'Choisis une photo JPEG, PNG ou WebP. Convertis les fichiers HEIC ou HEIF avant de les ajouter.',
    );
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 20000000) {
      throw const AuthFailure(
        'Cette photo dépasse 20 mégapixels. Choisis une image plus petite.',
      );
    }
    final landscape = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: landscape ? min(192, descriptor.width) : null,
      targetHeight: landscape ? null : min(192, descriptor.height),
    );
    if (codec.frameCount != 1) {
      throw const AuthFailure('Choisis une photo fixe.');
    }
    (await codec.getNextFrame()).image.dispose();
  } on AuthFailure {
    rethrow;
  } catch (_) {
    throw const AuthFailure(
      'Cette photo est illisible. Choisis une autre image.',
    );
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
  final random = Random.secure();
  final id = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return LocalRequestPhoto(id: id, bytes: bytes, contentType: type);
}

class LocalRequestPhotos extends StatelessWidget {
  const LocalRequestPhotos({
    super.key,
    required this.photos,
    this.onRemove,
    this.numberOffset = 0,
  });

  final List<LocalRequestPhoto> photos;
  final ValueChanged<LocalRequestPhoto>? onRemove;
  final int numberOffset;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (index, photo) in photos.indexed)
        _PhotoTile(
          key: ValueKey(photo.id),
          bytes: photo.bytes,
          number: index + 1 + numberOffset,
          onRemove: onRemove == null ? null : () => onRemove!(photo),
        ),
    ],
  );
}

class PublishedRequestPhotos extends StatelessWidget {
  const PublishedRequestPhotos({
    super.key,
    required this.requestId,
    required this.photoIds,
    this.readPhoto,
    this.inFeed = false,
    this.onRemove,
  });
  final String requestId;
  final List<String> photoIds;
  final RequestPhotoReader? readPhoto;
  final bool inFeed;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final source = readPhoto;
    if (inFeed && source != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          for (final (index, id) in photoIds.indexed)
            Expanded(child: _photo(source, id, index)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photos de la demande',
          style: TextStyle(fontWeight: FontWeight.w700, color: FoundiUi.ink),
        ),
        const SizedBox(height: 8),
        if (source == null)
          const Text(
            'Photos réservées à l’auteur et aux professionnels approuvés.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, id) in photoIds.indexed)
                _photo(source, id, index),
            ],
          ),
      ],
    );
  }

  Widget _photo(RequestPhotoReader source, String id, int index) =>
      _PublishedPhoto(
        key: ValueKey((requestId, id, source)),
        readPhoto: source,
        requestId: requestId,
        photoId: id,
        number: index + 1,
        inFeed: inFeed,
        onRemove: onRemove == null ? null : () => onRemove!(id),
      );
}

class _PublishedPhoto extends StatefulWidget {
  const _PublishedPhoto({
    super.key,
    required this.readPhoto,
    required this.requestId,
    required this.photoId,
    required this.number,
    required this.inFeed,
    this.onRemove,
  });

  final RequestPhotoReader readPhoto;
  final String requestId, photoId;
  final int number;
  final bool inFeed;
  final VoidCallback? onRemove;

  @override
  State<_PublishedPhoto> createState() => _PublishedPhotoState();
}

class _PublishedPhotoState extends State<_PublishedPhoto> {
  late Future<Uint8List> _photo = _load();
  Future<Uint8List> _load() =>
      widget.readPhoto(widget.requestId, widget.photoId);

  void _retry() => setState(() {
    _photo = _load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _photo,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return _PhotoTile(
          bytes: snapshot.requireData,
          number: widget.number,
          inFeed: widget.inFeed,
          onRemove: widget.onRemove,
        );
      }
      if (snapshot.hasError) {
        if (widget.inFeed) {
          return SizedBox(
            height: 132,
            child: Center(
              child: IconButton(
                tooltip:
                    'Photo indisponible. Réessayer la photo ${widget.number}',
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }
        final error = snapshot.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error is AuthFailure ? error.message : 'Photo indisponible.'),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Réessayer la photo ${widget.number}'),
            ),
            if (widget.onRemove != null)
              TextButton(
                onPressed: widget.onRemove,
                child: Text('Retirer la photo ${widget.number}'),
              ),
          ],
        );
      }
      return SizedBox(
        width: widget.inFeed ? double.infinity : 78,
        height: widget.inFeed ? 132 : 78,
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Chargement de la photo ${widget.number}',
          ),
        ),
      );
    },
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.bytes,
    required this.number,
    this.onRemove,
    this.inFeed = false,
  });

  final Uint8List bytes;
  final int number;
  final VoidCallback? onRemove;
  final bool inFeed;

  Widget _image({required BoxFit fit, int? width}) => Image.memory(
    bytes,
    fit: fit,
    cacheWidth: width,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) =>
        const Center(child: Icon(Icons.broken_image_outlined)),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: inFeed ? double.infinity : 78,
    height: inFeed ? 132 : 78,
    child: Material(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      color: FoundiUi.tint,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _image(fit: BoxFit.cover, width: inFeed ? 720 : 180),
          Semantics(
            button: true,
            label: 'Agrandir la photo $number',
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text('Photo $number'),
                  content: _image(fit: BoxFit.contain),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: IconButton.filledTonal(
                tooltip: 'Retirer la photo $number',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
        ],
      ),
    ),
  );
}
