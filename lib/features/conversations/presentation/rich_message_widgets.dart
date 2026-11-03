import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/conversation_repository.dart';
import '../domain/rich_conversation_repository.dart';
import 'media_actions.dart';

class ConversationExtrasButton extends StatelessWidget {
  const ConversationExtrasButton({
    super.key,
    required this.repository,
    required this.id,
    required this.uid,
    required this.phone,
    required this.actions,
  });
  final ConversationRepository repository;
  final String id, uid, phone;
  final ConversationMediaActions actions;
  RichConversationRepository get rich =>
      repository as RichConversationRepository;
  Future<void> _file(
    BuildContext context, {
    bool pdf = false,
    bool camera = false,
  }) async {
    try {
      final draft = pdf
          ? await actions.pickPdf()
          : await actions.pickImage(camera: camera);
      if (draft == null || !context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        builder: (_) => AttachmentUploadSheet(
          repository: rich,
          id: id,
          messageId: repository.newMessageId(id),
          draft: draft,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is AuthFailure
                  ? e.message
                  : 'Sélection du fichier impossible. Réessaie.',
            ),
          ),
        );
      }
    }
  }

  void _menu(BuildContext context) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ajouter à la conversation',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              subtitle: const Text('JPEG, PNG, WebP · 10 Mio maximum'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_file(context));
              },
            ),
            if (actions.supportsCamera)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(_file(context, camera: true));
                },
              ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Document PDF'),
              subtitle: const Text('15 Mio maximum'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_file(context, pdf: true));
              },
            ),
            ListTile(
              leading: const Icon(Icons.contact_phone_outlined),
              title: const Text('Partager mon numéro'),
              subtitle: const Text('Avec confirmation explicite'),
              onTap: () {
                Navigator.pop(sheet);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => ContactShareSheet(
                    repository: rich,
                    id: id,
                    messageId: repository.newMessageId(id),
                    initialPhone: phone,
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheet),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('chatExtras'),
    tooltip: 'Ajouter photo, PDF ou contact',
    onPressed: () => _menu(context),
    icon: const Icon(Icons.add_circle_outline),
  );
}

class AttachmentUploadSheet extends StatefulWidget {
  const AttachmentUploadSheet({
    super.key,
    required this.repository,
    required this.id,
    required this.messageId,
    required this.draft,
  });
  final RichConversationRepository repository;
  final String id, messageId;
  final AttachmentDraft draft;
  @override
  State<AttachmentUploadSheet> createState() => _AttachmentUploadSheetState();
}

class _AttachmentUploadSheetState extends State<AttachmentUploadSheet> {
  AttachmentCancellation? _cancellation;
  bool _busy = false,
      _attempted = false,
      _cancelling = false,
      _delivered = false;
  double _progress = 0;
  String? _error;
  Future<void> _send() async {
    if (_busy || _cancelling) return;
    final signal = AttachmentCancellation();
    _cancellation = signal;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
      _progress = 0;
    });
    try {
      final state = await widget.repository.sendAttachment(
        widget.id,
        widget.messageId,
        widget.draft,
        cancellation: signal,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v.clamp(0, 1));
        },
      );
      if (!mounted) return;
      if (state == 'ready') {
        _delivered = true;
        Navigator.pop(context);
      } else if (state == 'cancelled') {
        Navigator.pop(context);
      } else {
        setState(
          () => _error = state == 'awaiting_scan'
              ? 'Analyse de sécurité indisponible. Le fichier reste privé en attente : aucun message n’a été envoyé. Réessaie lorsque la vérification est disponible.'
              : 'Vérification en cours. Réessaie pour retrouver le résultat de cet envoi.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : 'Envoi non confirmé. Vérifie ta connexion et réessaie.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    if (!_attempted) {
      Navigator.pop(context);
      return;
    }
    setState(() => _cancelling = true);
    _cancellation?.cancel();
    try {
      final state = await widget.repository.cancelAttachment(
        widget.id,
        widget.messageId,
      );
      if (!mounted) return;
      if (state == 'ready') {
        _delivered = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le fichier a déjà été envoyé.')),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Annulation non confirmée. Réessaie avant de quitter cet envoi.',
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  void dispose() {
    unawaited(MemoryImage(widget.draft.bytes).evict());
    if (_attempted && !_delivered) {
      _cancellation?.cancel();
      unawaited(
        widget.repository
            .cancelAttachment(widget.id, widget.messageId)
            .catchError((_) => 'unconfirmed'),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_attempted || _delivered,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.draft.type == 'image'
                ? 'Prévisualiser la photo'
                : 'Vérifier le PDF',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (widget.draft.type == 'image')
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Image.memory(
                widget.draft.bytes,
                fit: BoxFit.contain,
                semanticLabel: 'Photo sélectionnée',
                errorBuilder: (_, _, _) => const Text(
                  'Aperçu impossible. Le serveur vérifiera le fichier avant diffusion.',
                ),
              ),
            )
          else
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 65,
              color: FoundiUi.green,
            ),
          const SizedBox(height: 12),
          Text(widget.draft.originalName),
          Text(fileSize(widget.draft.bytes.length)),
          const SizedBox(height: 16),
          const Text(
            'Le fichier sera partagé seulement après une vérification de sécurité réussie.',
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress < 1 ? _progress : null),
            Text(
              _progress < 1
                  ? 'Envoi ${(_progress * 100).round()} %'
                  : 'Vérification de sécurité…',
            ),
          ],
          AuthNotice(_error),
          FilledButton(
            onPressed: _busy || _cancelling ? null : _send,
            child: Text(
              _attempted
                  ? 'Réessayer l’envoi'
                  : 'Envoyer ${widget.draft.type == 'image' ? 'la photo' : 'le PDF'}',
            ),
          ),
          TextButton(
            onPressed: _cancelling ? null : _cancel,
            child: Text(_cancelling ? 'Annulation…' : 'Annuler'),
          ),
          if (_error != null || _cancellation?.requested == true)
            TextButton(
              onPressed: () async {
                final close = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Fermer cet envoi ?'),
                    content: const Text(
                      'La fermeture ne confirme pas l’annulation. Si l’envoi aboutit, tu le retrouveras dans la conversation. Les fichiers non validés restent privés.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Rester'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Fermer cet envoi'),
                      ),
                    ],
                  ),
                );
                if (close == true && context.mounted) Navigator.pop(context);
              },
              child: const Text('Fermer sans confirmation'),
            ),
        ],
      ),
    ),
  );
}

class ContactShareSheet extends StatefulWidget {
  const ContactShareSheet({
    super.key,
    required this.repository,
    required this.id,
    required this.messageId,
    required this.initialPhone,
  });
  final RichConversationRepository repository;
  final String id, messageId, initialPhone;
  @override
  State<ContactShareSheet> createState() => _ContactShareSheetState();
}

class _ContactShareSheetState extends AuthActionState<ContactShareSheet> {
  late final _phone = TextEditingController(text: widget.initialPhone);
  String get _number => _phone.text.trim().replaceAll(RegExp(r'[\s().-]'), '');
  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (busy) return;
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_number)) {
      setState(
        () => error =
            'Saisis un numéro international valide, par exemple +2250700000000.',
      );
      return;
    }
    final ok = await perform(
      () =>
          widget.repository.shareContact(widget.id, widget.messageId, _number),
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      4,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Partager mon numéro',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Le destinataire pourra consulter, copier et conserver ce numéro. Un numéro déjà vu ou copié ne peut pas être repris.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('contactNumber'),
          controller: _phone,
          enabled: !busy,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Mon numéro international',
            hintText: '+225…',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Numéro à partager : ${_number.isEmpty ? 'à renseigner' : _number}',
        ),
        const Text(
          'Cet envoi ne modifie pas le numéro enregistré sur ton profil.',
        ),
        AuthNotice(error),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy ? null : _share,
          child: const Text('Je confirme le partage'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}

String fileSize(int bytes) => '${(bytes / 1048576).toStringAsFixed(2)} Mio';

class RichMessageBody extends StatefulWidget {
  const RichMessageBody({
    super.key,
    required this.message,
    required this.id,
    required this.uid,
    required this.repository,
    required this.actions,
  });
  final ConversationMessage message;
  final String id, uid;
  final RichConversationRepository? repository;
  final ConversationMediaActions actions;
  @override
  State<RichMessageBody> createState() => _RichMessageBodyState();
}

class _RichMessageBodyState extends State<RichMessageBody> {
  Future<Uint8List>? _image;
  Uint8List? _bytes;
  bool _busy = false;
  String? _error;
  Future<Uint8List> _read() async {
    if (widget.repository == null) {
      throw const AuthFailure('Fichier indisponible.');
    }
    final bytes = await widget.repository!.readAttachment(
      widget.id,
      widget.message.id,
    );
    if (mounted) _bytes = bytes;
    return bytes;
  }

  @override
  void dispose() {
    if (_bytes != null) unawaited(MemoryImage(_bytes!).evict());
    super.dispose();
  }

  Future<void> _pdf() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _read();
      if (mounted) {
        await widget.actions.openPdf(
          widget.uid,
          bytes,
          widget.message.originalName ?? 'document.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : 'Ouverture du PDF impossible. Réessaie.',
        );
      }
    } finally {
      _bytes = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    if (m.type == 'text') return Text(m.text);
    if (m.type == 'contact') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact partagé',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SelectableText(m.phoneNumber ?? 'Numéro indisponible'),
          Wrap(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.call_outlined),
                label: const Text('Appeler'),
                onPressed: () async {
                  try {
                    await widget.actions.callPhone(m.phoneNumber ?? '');
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => _error = e is AuthFailure
                            ? e.message
                            : 'Action Appeler indisponible.',
                      );
                    }
                  }
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copier'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: m.phoneNumber ?? ''),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Numéro copié.')),
                    );
                  }
                },
              ),
            ],
          ),
          AuthNotice(_error),
        ],
      );
    }
    if (m.type == 'pdf') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.picture_as_pdf_outlined, color: FoundiUi.green),
          Text(
            m.originalName ?? 'Document PDF',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(fileSize(m.sizeBytes ?? 0)),
          TextButton(
            onPressed: _busy ? null : _pdf,
            child: Text(_busy ? 'Chargement…' : 'Ouvrir le PDF'),
          ),
          AuthNotice(_error),
        ],
      );
    }
    if (m.type == 'image') {
      return FutureBuilder<Uint8List>(
        future: _image ??= _read(),
        builder: (context, s) {
          if (s.hasError) {
            return Column(
              children: [
                const Text('Photo indisponible, hors ligne ou accès refusé.'),
                TextButton(
                  onPressed: () => setState(() => _image = null),
                  child: const Text('Réessayer la photo'),
                ),
              ],
            );
          }
          if (!s.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Semantics(
            button: true,
            label: 'Agrandir la photo partagée',
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => PrivateImageViewer(bytes: s.data!),
              ),
              child: Image.memory(
                s.data!,
                height: 170,
                width: 240,
                fit: BoxFit.cover,
                semanticLabel: 'Photo partagée',
                errorBuilder: (_, _, _) => const Text('Photo illisible.'),
              ),
            ),
          );
        },
      );
    }
    return const Text('Ce type de message n’est pas pris en charge.');
  }
}

class PrivateImageViewer extends StatefulWidget {
  const PrivateImageViewer({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<PrivateImageViewer> createState() => _PrivateImageViewerState();
}

class _PrivateImageViewerState extends State<PrivateImageViewer> {
  @override
  void dispose() {
    unawaited(MemoryImage(widget.bytes).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: 'Fermer la photo',
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  widget.bytes,
                  fit: BoxFit.contain,
                  semanticLabel: 'Photo en plein écran',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
