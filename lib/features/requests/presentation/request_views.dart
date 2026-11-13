import '../../professional/domain/professional_repository.dart';
import 'explorer_view.dart';
import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/request_repository.dart';
import '../domain/request_photo_repository.dart';
import 'request_photos.dart';
import 'request_respondents.dart';
import '../domain/request_interaction_repository.dart';
import 'request_action_bar.dart';
import '../../safety/domain/safety_repository.dart';
import '../../safety/presentation/safety_widgets.dart';

const requestPrivacy =
    'Le texte est visible publiquement. Évite les numéros de téléphone, e-mails et adresses exactes.';

class RequestHeading extends StatelessWidget {
  const RequestHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.onBack,
    this.bottomSpacing = 22,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final double bottomSpacing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Retour',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: FoundiUi.line),
        ] else
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: FoundiUi.ink,
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: const TextStyle(color: FoundiUi.muted, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

class FoundiActionBanner extends StatelessWidget {
  const FoundiActionBanner.client({super.key, required this.onPublish});

  const FoundiActionBanner.professional({super.key}) : onPublish = null;

  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final publish = onPublish;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [Color(0xFF065746), FoundiUi.green, Color(0xFF109468)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -36,
              bottom: -88,
              child: Container(
                width: 200,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: FoundiUi.tint.withValues(alpha: .12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showArt =
                      constraints.maxWidth >= 230 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 22;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        publish != null
                            ? 'Un besoin ?'
                            : 'Opportunités pour vous',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              publish != null
                                  ? 'Publiez votre demande et recevez des propositions de professionnels vérifiés.'
                                  : 'Découvrez des demandes qui correspondent à vos compétences et à vos zones d’intervention.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (showArt) ...[
                            const SizedBox(width: 8),
                            ExcludeSemantics(
                              child: _BannerIllustration(
                                checklist: publish != null,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (publish != null) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const ValueKey('openPublication'),
                          onPressed: publish,
                          style: FilledButton.styleFrom(
                            foregroundColor: FoundiUi.green,
                            backgroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          child: const Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Icon(Icons.add, size: 21),
                              Text(
                                'Publier une demande',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerIllustration extends StatelessWidget {
  const _BannerIllustration({required this.checklist});

  final bool checklist;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    height: 72,
    child: checklist
        ? Transform.rotate(
            angle: -.18,
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.assignment, color: Color(0xFF4DE1A6), size: 74),
                Positioned(
                  top: 18,
                  child: Icon(
                    Icons.checklist_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ],
            ),
          )
        : Stack(
            alignment: Alignment.center,
            children: [
              for (final (size, color) in const [
                (58.0, Color(0xFFFF8733)),
                (46.0, Color(0xFFFFF2DB)),
                (34.0, Color(0xFFFF8733)),
                (24.0, Color(0xFFFFF2DB)),
                (13.0, Color(0xFFFF8733)),
              ])
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              Positioned(
                top: 3,
                right: 5,
                child: Transform.rotate(
                  angle: -.8,
                  child: const Icon(
                    Icons.arrow_right_alt,
                    color: Color(0xFFFFD35A),
                    size: 40,
                  ),
                ),
              ),
            ],
          ),
  );
}

class RequestNotice extends StatelessWidget {
  const RequestNotice(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.info_outline,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => FoundiPanel(
    color: FoundiUi.tint,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: FoundiUi.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: FoundiUi.ink,
                ),
              ),
            ),
          ],
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: FoundiUi.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

class RequestTag extends StatelessWidget {
  const RequestTag(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: FoundiUi.tint,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        color: FoundiUi.green,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class RequestCard extends StatelessWidget {
  const RequestCard(
    this.request, {
    super.key,
    this.onTap,
    this.showStatus = false,
    this.actions,
    this.footer,
    this.showDescription = false,
    this.photos,
  });
  final FoundiRequest request;
  final VoidCallback? onTap;
  final bool showStatus;
  final Widget? actions;
  final Widget? footer;
  final bool showDescription;
  final Widget? photos;
  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.all(17);
    final actionBar = footer;
    if (actionBar == null) {
      return FoundiPanel(
        onTap: onTap,
        padding: padding,
        child: _content(context),
      );
    }
    return FoundiPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: padding.copyWith(bottom: 8),
              child: _content(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: actionBar,
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!showDescription && !request.isDirect)
        Align(
          alignment: Alignment.centerRight,
          child: SafetyActionMenu(target: SafetyTarget('request', request.id)),
        ),
      if (showDescription || request.isDirect) ...[
        Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: FoundiUi.tint,
              child: Icon(
                Icons.person_outline,
                size: 18,
                color: FoundiUi.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                request.authorDisplayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: FoundiUi.ink,
                ),
              ),
            ),
            if (!request.isDirect)
              SafetyActionMenu(target: SafetyTarget('request', request.id)),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ?actions,
          RequestTag(request.categoryLabel),
          if (request.isDirect) const RequestTag('Privée'),
          if (showStatus) RequestTag(request.statusLabel),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        request.title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: FoundiUi.ink,
        ),
      ),
      if (showDescription && request.description.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        _ExplorerRequestDescription(request.description),
      ],
      if (photos != null) ...[const SizedBox(height: 12), photos!],
      const SizedBox(height: 10),
      Text(
        request.budget == null
            ? request.budgetLabel
            : 'Budget : ${request.budgetLabel}',
        style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 17,
            color: FoundiUi.green,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              request.zoneLabel,
              style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 18, color: FoundiUi.muted),
        ],
      ),
      if (request.createdAt != null) ...[
        const SizedBox(height: 10),
        Text(
          requestDate(request.createdAt!),
          style: const TextStyle(fontSize: 11, color: FoundiUi.muted),
        ),
      ],
    ],
  );
}

class _ExplorerRequestDescription extends StatefulWidget {
  const _ExplorerRequestDescription(this.description);
  final String description;

  @override
  State<_ExplorerRequestDescription> createState() =>
      _ExplorerRequestDescriptionState();
}

class _ExplorerRequestDescriptionState
    extends State<_ExplorerRequestDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: FoundiUi.ink);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.description, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 4,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description,
              style: style,
              maxLines: _expanded ? null : 4,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Voir moins' : 'Voir plus'),
              ),
          ],
        );
      },
    );
  }
}

String requestDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class RequestListView extends StatefulWidget {
  const RequestListView({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onPublish,
    this.showPublicationBanner = false,
    this.uid,
    this.onEdit,
    this.onProposals,
    this.onConversation,
    this.footerBuilder,
  });
  final RequestRepository repository;
  final String? uid;
  final ValueChanged<FoundiRequest>? onEdit;
  final ValueChanged<FoundiRequest>? onProposals;
  final ValueChanged<String>? onConversation;
  final ValueChanged<FoundiRequest> onOpen;
  final VoidCallback? onPublish;
  final bool showPublicationBanner;
  final Widget Function(FoundiRequest)? footerBuilder;
  @override
  State<RequestListView> createState() => _RequestListViewState();
}

class _RequestListViewState extends State<RequestListView> {
  bool _busy = false;
  String? _error;
  String _status = '';
  Future<void> _action(FoundiRequest request, String action) async {
    if (_busy) return;
    if (action == 'edit') {
      widget.onEdit?.call(request);
      return;
    }
    final deleting = action == 'delete';
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              deleting ? 'Supprimer la demande ?' : 'Clôturer cette demande ?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              deleting
                  ? 'Elle disparaîtra des listes visibles. Cette action ne peut pas être annulée ici.'
                  : 'Elle disparaîtra du fil public et des opportunités et ne recevra plus de nouvelles propositions. Les discussions non refusées pourront continuer et les historiques resteront accessibles.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: deleting
                  ? FilledButton.styleFrom(backgroundColor: Colors.red)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                deleting ? 'Supprimer ma demande' : 'Confirmer la clôture',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.repository as RequestManagementRepository).manage(
        request.id,
        action,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Action non confirmée. Réessaie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  late Stream<List<FoundiRequest>> _stream = _load();
  Stream<List<FoundiRequest>> _load() => widget.uid == null
      ? widget.repository.watchPublic()
      : widget.repository.watchMine(widget.uid!);
  @override
  Widget build(BuildContext context) {
    final personal = widget.uid != null;
    final publish = widget.onPublish;
    final showBanner =
        personal && widget.showPublicationBanner && publish != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        RequestHeading(
          personal ? 'Mes demandes' : 'Explorer les demandes',
          subtitle: personal
              ? 'Suivez vos demandes et les propositions des professionnels.'
              : 'Les besoins publiés par la communauté.',
        ),
        if (showBanner) ...[
          FoundiActionBanner.client(onPublish: publish),
          const SizedBox(height: 14),
        ],
        if (personal) ...[
          if (_busy) const LinearProgressIndicator(),
          AuthNotice(_error),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                '': 'Toutes',
                'published': 'Ouvertes',
                'closed': 'Clôturées',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _status == entry.key,
                  onSelected: (_) => setState(() => _status = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (!personal) ...[
          const RequestNotice(
            'Accès libre',
            'Lis les demandes sans créer de compte.',
          ),
          const SizedBox(height: 20),
        ],
        StreamBuilder<List<FoundiRequest>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const AuthNotice(
                    'Impossible de charger les demandes. Vérifie ta connexion puis réessaie.',
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _stream = _load()),
                    child: const Text('Réessayer'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final requests = snapshot.requireData
                .where(
                  (r) =>
                      r.status != 'deleted' &&
                      (!personal ||
                          _status.isEmpty ||
                          r.status == _status ||
                          (_status == 'published' &&
                              r.status == 'in_discussion')),
                )
                .toList();
            if (requests.isEmpty) {
              return Column(
                children: [
                  const SizedBox(height: 16),
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: FoundiUi.tint,
                    child: Icon(
                      Icons.description_outlined,
                      size: 30,
                      color: FoundiUi.green,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    personal
                        ? 'Aucune demande pour le moment'
                        : 'Aucune demande publiée pour le moment',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    personal
                        ? (showBanner
                              ? 'Utilise la bannière pour publier ta première demande.'
                              : 'Ta première demande apparaîtra ici dès sa publication.')
                        : 'Les prochains besoins publiés apparaîtront ici.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FoundiUi.muted, height: 1.5),
                  ),
                  if (!showBanner && publish != null) ...[
                    const SizedBox(height: 45),
                    FilledButton(
                      onPressed: widget.onPublish,
                      child: Text(
                        personal
                            ? 'Publier ma première demande'
                            : 'Publier une demande',
                      ),
                    ),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (personal) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      RequestTag(
                        '${requests.length} demande${requests.length > 1 ? 's' : ''}',
                      ),
                      const RequestTag('Publications'),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                for (final request in requests) ...[
                  RequestCard(
                    request,
                    key: ValueKey(request.id),
                    footer: widget.footerBuilder?.call(request),
                    showStatus: personal,
                    actions:
                        personal &&
                            widget.repository is RequestManagementRepository
                        ? PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (a) => _action(request, a),
                            itemBuilder: (_) => [
                              if (request.status == 'published' &&
                                  widget.onEdit != null)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Modifier'),
                                ),
                              if (request.status == 'published' ||
                                  request.status == 'in_discussion')
                                const PopupMenuItem(
                                  value: 'close',
                                  child: Text('Clôturer'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Supprimer',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          )
                        : null,
                    onTap: request.status == 'published'
                        ? () => widget.onOpen(request)
                        : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  RequestContent(request),
                                  if (request.conversationId != null &&
                                      widget.onConversation != null)
                                    FilledButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        widget.onConversation!(
                                          request.conversationId!,
                                        );
                                      },
                                      child: const Text('Ouvrir la discussion'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  if (personal &&
                      request.conversationId != null &&
                      widget.onConversation != null)
                    FilledButton(
                      onPressed: () =>
                          widget.onConversation!(request.conversationId!),
                      child: const Text('Ouvrir la discussion'),
                    ),
                  if (personal && widget.onProposals != null)
                    TextButton(
                      onPressed: () => widget.onProposals!(request),
                      child: Text(
                        'Voir les propositions reçues (${request.proposalCount})',
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
                Text(
                  personal
                      ? 'Tes ${requests.length} dernières publications.'
                      : 'Les 30 demandes les plus récentes. D’autres demandes apparaîtront ici.',
                  style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class RequestPreview extends StatelessWidget {
  const RequestPreview(this.request, {super.key});
  final FoundiRequest request;
  @override
  Widget build(BuildContext context) => FoundiPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            RequestTag(request.category),
            if (request.isDirect) const RequestTag('Privée'),
            RequestTag(request.zoneLabel),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          request.title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: FoundiUi.ink,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(color: FoundiUi.line),
        ),
        const Text(
          'DESCRIPTION',
          style: TextStyle(
            fontSize: 11,
            color: FoundiUi.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          request.description,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        if (request.budget != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: FoundiUi.line),
          ),
          const Text(
            'BUDGET SOUHAITÉ',
            style: TextStyle(
              fontSize: 11,
              color: FoundiUi.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            request.budgetLabel,
            style: const TextStyle(
              fontSize: 20,
              color: FoundiUi.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    ),
  );
}

class RequestContent extends StatelessWidget {
  const RequestContent(this.request, {super.key, this.showStatus = true});
  final FoundiRequest request;
  final bool showStatus;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (!request.isDirect)
            SafetyActionMenu(target: SafetyTarget('request', request.id)),
          RequestTag(request.category),
          if (request.isDirect) const RequestTag('Privée'),
          if (showStatus) RequestTag(request.statusLabel),
        ],
      ),
      if (request.isDirect &&
          request.directProfessionalName?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        Text(
          'Pour ${request.directProfessionalName}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: FoundiUi.green,
          ),
        ),
      ],
      if (request.isDirect) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.person_outline, size: 19, color: FoundiUi.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Demande de ${request.authorDisplayName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: FoundiUi.ink,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      Text(
        request.title,
        style: const TextStyle(
          fontSize: 24,
          color: FoundiUi.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: FoundiUi.green,
            size: 20,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              request.zoneLabel,
              style: const TextStyle(color: FoundiUi.muted),
            ),
          ),
        ],
      ),
      if (request.createdAt != null) ...[
        const SizedBox(height: 10),
        Text(
          requestDate(request.createdAt!),
          style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
        ),
      ],
      const SizedBox(height: 24),
      FoundiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Budget souhaité',
              style: TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
            const SizedBox(height: 8),
            Text(
              request.budgetLabel,
              style: const TextStyle(
                fontSize: 23,
                color: FoundiUi.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: FoundiUi.line),
            ),
            const Text(
              'Catégorie',
              style: TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
            const SizedBox(height: 10),
            Text(
              request.category,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      FoundiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Description',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 18),
            Text(
              request.description,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );
}

class RequestDetailView extends StatefulWidget {
  const RequestDetailView({
    super.key,
    required this.repository,
    required this.id,
    required this.onBack,
    this.actionsBuilder,
    this.canReadPhotos = true,
    this.showRespondents = false,
    this.onViewProposals,
    this.load,
    this.privateRequest = false,
  });
  final Widget Function(FoundiRequest)? actionsBuilder;
  final RequestRepository repository;
  final String id;
  final VoidCallback onBack;
  final bool canReadPhotos;
  final bool showRespondents;
  final ValueChanged<String>? onViewProposals;
  final Stream<FoundiRequest?> Function()? load;
  final bool privateRequest;
  @override
  State<RequestDetailView> createState() => _RequestDetailViewState();
}

class _RequestDetailViewState extends State<RequestDetailView> {
  Stream<FoundiRequest?> _load() =>
      widget.load?.call() ?? widget.repository.watchPublicDetail(widget.id);
  late Stream<FoundiRequest?> _stream = _load();
  RequestRespondentsRepository? get _respondents {
    final repository = widget.repository;
    return widget.showRespondents && repository is RequestRespondentsRepository
        ? repository as RequestRespondentsRepository
        : null;
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    children: [
      RequestHeading(
        widget.privateRequest
            ? 'Demande privée'
            : _respondents == null
            ? 'Détail de la demande'
            : 'Réponses à la demande',
        onBack: widget.onBack,
      ),
      StreamBuilder<FoundiRequest?>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError ||
              (s.connectionState != ConnectionState.waiting &&
                  s.data == null)) {
            return Column(
              children: [
                AuthNotice(
                  widget.privateRequest
                      ? 'Cette demande privée est indisponible ou cet accès n’est plus autorisé.'
                      : 'Cette demande est indisponible ou n’est plus publique.',
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _stream = _load()),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final request = s.requireData!;
          final repository = widget.repository;
          final respondents = _respondents;
          if (respondents != null) {
            if (request.status != 'published') {
              return const AuthNotice('Cette demande n’est plus publique.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FoundiPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RequestTag(request.statusLabel),
                      const SizedBox(height: 8),
                      Text(
                        request.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.zoneLabel,
                        style: const TextStyle(color: FoundiUi.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                RequestRespondents(
                  key: ValueKey(request.id),
                  repository: respondents,
                  requestId: request.id,
                  onViewProposals: widget.onViewProposals == null
                      ? null
                      : () => widget.onViewProposals!(request.id),
                ),
                if (widget.actionsBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: widget.actionsBuilder!(request),
                  ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestContent(request),
              if (request.photoIds.isNotEmpty) ...[
                const SizedBox(height: 20),
                PublishedRequestPhotos(
                  requestId: request.id,
                  photoIds: request.photoIds,
                  readPhoto:
                      request.photosPublic &&
                          repository is PublicRequestPhotoRepository
                      ? (repository as PublicRequestPhotoRepository)
                            .readPublicRequestPhoto
                      : widget.canReadPhotos &&
                            repository is RequestPhotoRepository
                      ? (repository as RequestPhotoRepository).readRequestPhoto
                      : null,
                ),
              ],
              if (widget.actionsBuilder != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: widget.actionsBuilder!(request),
                ),
              const SizedBox(height: 24),
              const RequestNotice(
                'Coordonnées personnelles non affichées',
                '',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: widget.onBack,
                child: const Text('Retour aux demandes'),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class GuestRequests extends StatefulWidget {
  const GuestRequests({
    super.key,
    required this.repository,
    this.catalog,
    required this.onAuthenticate,
  });
  final ProfessionalRepository? catalog;
  final RequestRepository repository;
  final VoidCallback onAuthenticate;
  @override
  State<GuestRequests> createState() => _GuestRequestsState();
}

class _GuestRequestsState extends State<GuestRequests> {
  final _explorerKey = GlobalKey<ExplorerViewState>();
  String? _detail;
  Widget _actions(FoundiRequest request) => RequestActionBar(
    request: request,
    repository: widget.repository.interactionRepository!,
    onAuthenticate: widget.onAuthenticate,
    onViewRespondents: () => setState(() => _detail = request.id),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _detail == null &&
        _explorerKey.currentState?.showingProfessionals != true,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        if (_detail == null &&
            _explorerKey.currentState?.handleBack() == true) {
          return;
        }
        setState(() => _detail = null);
      }
    },
    child: Scaffold(
      backgroundColor: FoundiUi.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                if (_detail == null) const FoundiBrand(),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Offstage(
                        offstage: _detail != null,
                        child: ExplorerView(
                          key: _explorerKey,
                          active: _detail == null,
                          onSectionChanged: () => setState(() {}),
                          repository: widget.repository,
                          catalog: widget.catalog,
                          onOpen: (r) => setState(() => _detail = r.id),
                          onPublish: widget.onAuthenticate,
                          footerBuilder:
                              widget.repository.interactionRepository == null
                              ? null
                              : _actions,
                        ),
                      ),
                      if (_detail != null)
                        RequestDetailView(
                          key: ValueKey(_detail),
                          repository: widget.repository,
                          id: _detail!,
                          showRespondents: true,
                          canReadPhotos: false,
                          actionsBuilder:
                              widget.repository.interactionRepository == null
                              ? null
                              : _actions,
                          onBack: () => setState(() => _detail = null),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FoundiBottomBar(
        guest: true,
        selectedIndex: 0,
        onSelect: (i) {
          if (i == 0) {
            setState(() => _detail = null);
          } else if (i == 2) {
            showComingSoon(context);
          } else {
            widget.onAuthenticate();
          }
        },
      ),
    ),
  );
}
