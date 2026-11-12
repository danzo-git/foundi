import 'package:flutter/material.dart';

import '../../navigation/presentation/space_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../../professional/domain/professional_showcase.dart';
import '../../professional/presentation/professional_profile_widgets.dart';
import '../../professional/presentation/professional_showcase_screen.dart';
import '../../professional/presentation/professional_status_label.dart';
import '../domain/auth_repository.dart';
import 'auth_widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.professional,
    required this.professionalSpace,
    required this.onSpaces,
    required this.onDossier,
    required this.onActivity,
    required this.onPersonal,
    this.initialSection = 0,
    this.professionalRepository,
    this.showcaseRepository,
    this.onRequests,
    this.onSentProposals,
    this.onReceivedProposals,
    this.onDirectRequests,
  });
  final FoundiUser user;
  final int initialSection;
  final ProfessionalProfile professional;
  final ProfessionalRepository? professionalRepository;
  final ProfessionalShowcaseRepository? showcaseRepository;
  final bool professionalSpace;
  final VoidCallback onSpaces, onDossier, onActivity, onPersonal;
  final VoidCallback? onRequests, onSentProposals, onReceivedProposals;
  final VoidCallback? onDirectRequests;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _scroll = ScrollController();
  final _sectionKey = GlobalKey();
  late int _section = widget.initialSection;
  bool _editing = false;
  late Future<ProfessionalShowcase?> _profile = _loadProfile();
  late Stream<ProfessionalCatalog>? _catalog = _watchCatalog();

  Future<ProfessionalShowcase?> _loadProfile() => widget.professional.approved
      ? widget.showcaseRepository?.readShowcase() ?? Future.value(null)
      : Future.value(null);
  Stream<ProfessionalCatalog>? _watchCatalog() =>
      widget.professional.status == ProfessionalStatus.none
      ? null
      : widget.professionalRepository?.watchCatalog();

  @override
  void didUpdateWidget(AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection;
    }
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.showcaseRepository != widget.showcaseRepository ||
        oldWidget.professional.approved != widget.professional.approved) {
      _profile = _loadProfile();
      _section = 0;
    }
    if (oldWidget.professionalRepository != widget.professionalRepository ||
        oldWidget.professional.status != widget.professional.status) {
      _catalog = _watchCatalog();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _labels(List<String> ids, Iterable<ReferenceChoice> choices) =>
      choices
          .where((choice) => ids.contains(choice.id))
          .map((choice) => choice.label)
          .toList();

  void _showSection(int section, {bool scrollToSection = false}) {
    setState(() => _section = section);
    if (scrollToSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _sectionKey.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target, alignment: 0.05);
        }
      });
    }
  }

  Future<void> _edit(
    ProfessionalShowcase profile, {
    ShowcaseEditSection? section,
  }) async {
    final repository = widget.showcaseRepository;
    if (_editing || !widget.professional.approved || repository == null) return;
    setState(() => _editing = true);
    final saved = await editProfessionalShowcase(
      context,
      repository: repository,
      initial: profile,
      onPersonal: widget.onPersonal,
      section: section,
    );
    if (!mounted) return;
    setState(() {
      _editing = false;
      if (saved != null && widget.professional.approved) {
        _profile = Future.value(saved);
      }
    });
  }

  Widget _tabs() => ProfessionalProfileTabs(
    section: _section,
    onSelected: (section) => _showSection(section),
  );

  Widget _professionalSection(
    ProfessionalShowcase profile,
    ProfessionalCatalog? catalog,
    bool canEdit,
  ) {
    final activity = widget.professional.activity;
    final categories = _labels(activity.categoryIds, catalog?.categories ?? []);
    final specialties = _labels(
      activity.specialtyIds,
      catalog?.categories.expand((category) => category.specialties) ?? [],
    );
    final zones = _labels(activity.zoneIds, catalog?.zones ?? []);
    void editGallery() => _edit(profile, section: ShowcaseEditSection.gallery);
    return ProfessionalProfileSection(
      key: _sectionKey,
      profile: profile,
      section: _section,
      onPhoto: (index) =>
          openShowcasePhoto(context, profile.gallery[index], index),
      onSeeAll: () => _showSection(2),
      onAdd: canEdit && profile.gallery.length < ProfessionalShowcase.maxGallery
          ? editGallery
          : null,
      onManageGallery: canEdit ? editGallery : null,
      details: [
        if (_section == 1) ...[
          if (activity.businessName.isNotEmpty)
            ProfessionalProfileDetail(
              Icons.business_outlined,
              'Nom commercial',
              activity.businessName,
            ),
          ProfessionalProfileDetail(
            Icons.work_outline,
            'Statut',
            activity.type == 'company' ? 'Entreprise' : 'Indépendant',
          ),
        ],
        if (categories.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.work_outline,
            'Catégories',
            categories.join(' · '),
          ),
        if (specialties.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.sell_outlined,
            'Spécialités',
            specialties.join(' · '),
          ),
        if (specialties.isEmpty && profile.trade.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.sell_outlined,
            'Activité',
            profile.trade,
          ),
        if (zones.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.location_on_outlined,
            'Zones d’intervention',
            zones.join(' · '),
          ),
        if (zones.isEmpty && profile.area.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.location_on_outlined,
            'Zone d’intervention',
            profile.area,
          ),
        if (_section == 1 && activity.description.isNotEmpty)
          ProfessionalProfileDetail(
            Icons.description_outlined,
            'Activité',
            activity.description,
          ),
      ],
    );
  }

  Widget _identity() {
    final personal = widget.user.profile.fullName.trim().isNotEmpty
        ? widget.user.profile.fullName
        : widget.user.displayName ?? '';
    final activity = widget.professional.activity;
    final name =
        widget.professional.status != ProfessionalStatus.none &&
            activity.businessName.isNotEmpty
        ? activity.businessName
        : personal;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    return FoundiPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: FoundiUi.tint,
            child: Text(
              initials.isEmpty ? 'F' : initials,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: FoundiUi.green,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Mon compte' : name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  professionalStatusLabel(widget.professional.status),
                  style: const TextStyle(color: FoundiUi.muted, fontSize: 13),
                ),
                if (activity.description.isNotEmpty &&
                    widget.professional.status != ProfessionalStatus.none) ...[
                  const SizedBox(height: 8),
                  Text(
                    activity.description,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dossier() {
    final status = widget.professional.status;
    final resumable =
        status == ProfessionalStatus.draft ||
        status == ProfessionalStatus.needsChanges;
    final message = switch (status) {
      ProfessionalStatus.draft =>
        'Complète ton activité et les justificatifs de ton dossier.',
      ProfessionalStatus.pending => 'Ton dossier est en cours d’examen.',
      ProfessionalStatus.needsChanges =>
        'Des compléments sont nécessaires pour poursuivre la vérification.',
      ProfessionalStatus.rejected =>
        'Consulte le résultat de la vérification de ton dossier.',
      ProfessionalStatus.suspended =>
        'Consulte le suivi de ton accès professionnel.',
      _ => '',
    };
    return FoundiPanel(
      color: FoundiUi.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(height: 1.4)),
          if (widget.professional.reviewReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.professional.reviewReason,
              style: const TextStyle(height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: widget.onDossier,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              resumable ? 'Reprendre mon dossier' : 'Suivre mon dossier',
            ),
          ),
        ],
      ),
    );
  }

  Widget _space() => FoundiPanel(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: FoundiUi.soft,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Espace actuel',
              style: TextStyle(fontSize: 12, color: FoundiUi.muted),
            ),
            Text(
              widget.professionalSpace ? 'Professionnel' : 'Client',
              key: const ValueKey('currentSpace'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: FoundiUi.ink,
              ),
            ),
          ],
        ),
        if (widget.professional.approved)
          TextButton(
            onPressed: widget.onSpaces,
            child: const Text('Changer d’espace  ›'),
          ),
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, color: FoundiUi.green),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: subtitle.isEmpty
        ? null
        : Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
          ),
    trailing: const Icon(Icons.chevron_right, color: FoundiUi.muted),
    onTap: action,
  );

  Widget _management() => FoundiPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        if (widget.onDirectRequests != null) ...[
          _row(
            Icons.mark_email_unread_outlined,
            'Demandes directes reçues',
            'Les demandes privées qui me sont adressées',
            widget.onDirectRequests!,
          ),
          const Divider(height: 1, color: FoundiUi.line),
        ],
        _row(
          Icons.person_outline,
          'Informations personnelles',
          'Nom, e-mail, téléphone et sécurité',
          widget.onPersonal,
        ),
        const Divider(height: 1, color: FoundiUi.line),
        if (widget.professional.status == ProfessionalStatus.none)
          _row(
            Icons.work_outline,
            'Devenir professionnel',
            'Présenter mon activité',
            widget.onDossier,
          )
        else ...[
          _row(
            Icons.work_outline,
            'Mon activité professionnelle',
            'Catégories, spécialités et zones',
            widget.professional.approved
                ? () => _showSection(1, scrollToSection: true)
                : widget.onActivity,
          ),
          const Divider(height: 1, color: FoundiUi.line),
          _row(
            Icons.verified_user_outlined,
            'Vérification professionnelle',
            'Statut du dossier et justificatifs',
            widget.onDossier,
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<ProfessionalCatalog>(
    stream: _catalog,
    builder: (context, catalog) => FutureBuilder<ProfessionalShowcase?>(
      future: _profile,
      builder: (context, snapshot) {
        final approved = widget.professional.approved;
        final activity = widget.professional.activity;
        final references = catalog.data;
        final display =
            snapshot.data ??
            ProfessionalShowcase(
              name: activity.businessName,
              trade: _labels(
                activity.specialtyIds,
                references?.categories.expand((item) => item.specialties) ?? [],
              ).join(' · '),
              area: _labels(
                activity.zoneIds,
                references?.zones ?? [],
              ).join(' · '),
              bio: activity.description,
            );
        final canEdit =
            approved &&
            widget.showcaseRepository != null &&
            !_editing &&
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        return SingleChildScrollView(
          key: const ValueKey('unifiedAccountScroll'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Mon compte',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: FoundiUi.ink,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (approved) ...[
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Chargement du profil professionnel',
                  ),
                if (snapshot.hasError) ...[
                  const AuthNotice('Le profil professionnel est indisponible.'),
                  OutlinedButton(
                    onPressed: () {
                      final profile = _loadProfile();
                      setState(() {
                        _profile = profile;
                      });
                    },
                    child: const Text('Réessayer le profil'),
                  ),
                ],
                ProfessionalShowcaseHeader(
                  profile: display,
                  showBio: true,
                  footer: _tabs(),
                  onEdit: canEdit ? () => _edit(display) : null,
                  onCover: canEdit
                      ? () => _edit(display, section: ShowcaseEditSection.cover)
                      : null,
                  onPortrait: canEdit
                      ? () => _edit(
                          display,
                          section: ShowcaseEditSection.portrait,
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                if (catalog.hasError) ...[
                  const AuthNotice(
                    'Les catégories et zones sont indisponibles.',
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _catalog = _watchCatalog();
                      });
                    },
                    child: const Text(
                      'Actualiser les informations professionnelles',
                    ),
                  ),
                ],
                _professionalSection(display, references, canEdit),
              ] else ...[
                _identity(),
                if (widget.professional.status != ProfessionalStatus.none) ...[
                  const SizedBox(height: 14),
                  _dossier(),
                ],
              ],
              const SizedBox(height: 14),
              _management(),
              if (widget.onReceivedProposals != null ||
                  (widget.onSentProposals != null &&
                      !widget.professionalSpace) ||
                  (widget.onRequests != null && widget.professionalSpace)) ...[
                const SizedBox(height: 14),
                FoundiPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (widget.onReceivedProposals != null)
                        _row(
                          Icons.inbox_outlined,
                          'Propositions reçues',
                          '',
                          widget.onReceivedProposals!,
                        ),
                      if (widget.onSentProposals != null &&
                          !widget.professionalSpace)
                        _row(
                          Icons.send_outlined,
                          'Mes propositions',
                          '',
                          widget.onSentProposals!,
                        ),
                      if (widget.onRequests != null && widget.professionalSpace)
                        _row(
                          Icons.description_outlined,
                          'Mes demandes',
                          '',
                          widget.onRequests!,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _space(),
            ],
          ),
        );
      },
    ),
  );
}
