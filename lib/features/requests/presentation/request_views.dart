import '../../professional/domain/professional_repository.dart';
import 'explorer_view.dart';
import 'package:flutter/material.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../domain/request_repository.dart';

const requestPrivacy =
    'Le texte est visible publiquement. Évite les numéros de téléphone, e-mails et adresses exactes.';

class RequestHeading extends StatelessWidget {
  const RequestHeading(this.title, {super.key, this.subtitle, this.onBack});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
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
  });
  final FoundiRequest request;
  final VoidCallback? onTap;
  final bool showStatus;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => FoundiPanel(
    onTap: onTap,
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ?actions,
            RequestTag(request.categoryLabel),
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
    ),
  );
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
    this.uid,
    this.onEdit,
  });
  final RequestRepository repository;
  final String? uid;
  final ValueChanged<FoundiRequest>? onEdit;
  final ValueChanged<FoundiRequest> onOpen;
  final VoidCallback onPublish;
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
      builder: (context) => Padding(
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
                  : 'Elle disparaîtra du fil public et des opportunités. Tu garderas accès à ton historique.',
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        RequestHeading(
          personal ? 'Mes demandes' : 'Explorer les demandes',
          subtitle: personal
              ? 'Retrouve les besoins que tu as publiés.'
              : 'Les besoins publiés par la communauté.',
        ),
        if (personal) ...[
          if (_busy) const LinearProgressIndicator(),
          AuthNotice(_error),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                '': 'Toutes',
                'published': 'Publiées',
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
                      (!personal || _status.isEmpty || r.status == _status),
                )
                .toList();
            if (requests.isEmpty) {
              return Column(
                children: [
                  const SizedBox(height: 55),
                  const CircleAvatar(
                    radius: 70,
                    backgroundColor: FoundiUi.tint,
                    child: Icon(
                      Icons.description_outlined,
                      size: 60,
                      color: FoundiUi.green,
                    ),
                  ),
                  const SizedBox(height: 35),
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
                        ? 'Ta première demande apparaîtra ici dès sa publication.'
                        : 'Les prochains besoins publiés apparaîtront ici.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FoundiUi.muted, height: 1.5),
                  ),
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
                              if (request.status == 'published')
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
                              child: RequestContent(request),
                            ),
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
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
        const SizedBox(height: 10),
        Text(
          request.budgetLabel,
          style: const TextStyle(
            fontSize: 20,
            color: FoundiUi.green,
            fontWeight: FontWeight.bold,
          ),
        ),
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
          RequestTag(request.category),
          if (showStatus) RequestTag(request.statusLabel),
        ],
      ),
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
  });
  final RequestRepository repository;
  final String id;
  final VoidCallback onBack;
  @override
  State<RequestDetailView> createState() => _RequestDetailViewState();
}

class _RequestDetailViewState extends State<RequestDetailView> {
  late Stream<FoundiRequest?> _stream = widget.repository.watchPublicDetail(
    widget.id,
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    children: [
      RequestHeading('Détail de la demande', onBack: widget.onBack),
      StreamBuilder<FoundiRequest?>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError ||
              (s.connectionState != ConnectionState.waiting &&
                  s.data == null)) {
            return Column(
              children: [
                const AuthNotice(
                  'Cette demande est indisponible ou n’est plus publique.',
                ),
                OutlinedButton(
                  onPressed: () => setState(
                    () => _stream = widget.repository.watchPublicDetail(
                      widget.id,
                    ),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestContent(s.requireData!),
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
  String? _detail;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _detail == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _detail = null);
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
                          repository: widget.repository,
                          catalog: widget.catalog,
                          onOpen: (r) => setState(() => _detail = r.id),
                          onPublish: widget.onAuthenticate,
                        ),
                      ),
                      if (_detail != null)
                        RequestDetailView(
                          key: ValueKey(_detail),
                          repository: widget.repository,
                          id: _detail!,
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
        accountSelected: false,
        selectedIndex: 1,
        onSelect: (i) {
          if (i == 0 || i == 1) {
            setState(() => _detail = null);
          } else if (i == 3) {
            showComingSoon(context);
          } else {
            widget.onAuthenticate();
          }
        },
      ),
    ),
  );
}
