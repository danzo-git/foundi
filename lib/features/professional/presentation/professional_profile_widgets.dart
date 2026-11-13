import 'package:flutter/material.dart';

import '../../navigation/presentation/space_widgets.dart';
import '../../requests/presentation/request_views.dart';
import '../domain/professional_showcase.dart';

class ProfessionalProfileTabs extends StatelessWidget {
  const ProfessionalProfileTabs({
    super.key,
    required this.section,
    required this.onSelected,
    this.keyPrefix = 'accountSection',
  });

  static const labels = ['À propos', 'Mon activité', 'Réalisations'];
  final int section;
  final ValueChanged<int> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, label) in labels.indexed)
        Expanded(
          child: Semantics(
            selected: section == index,
            child: TextButton(
              key: ValueKey('$keyPrefix-$index'),
              onPressed: () => onSelected(index),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                foregroundColor: section == index
                    ? FoundiUi.green
                    : FoundiUi.muted,
                shape: const RoundedRectangleBorder(),
                side: BorderSide.none,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: section == index
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: section == index
                          ? FoundiUi.green
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class ProfessionalProfileDetail extends StatelessWidget {
  const ProfessionalProfileDetail(
    this.icon,
    this.label,
    this.value, {
    super.key,
  });

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: FoundiUi.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label · ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class ProfessionalProfileSection extends StatelessWidget {
  const ProfessionalProfileSection({
    super.key,
    required this.profile,
    required this.section,
    required this.onPhoto,
    required this.onSeeAll,
    this.details = const [],
    this.onAdd,
    this.onManageGallery,
  });

  final ProfessionalShowcase profile;
  final int section;
  final List<Widget> details;
  final ValueChanged<int> onPhoto;
  final VoidCallback onSeeAll;
  final VoidCallback? onAdd, onManageGallery;

  Widget _gallery({bool preview = false}) => ShowcaseGallery(
    photos: profile.gallery,
    onPhoto: onPhoto,
    preview: preview,
    onAdd: preview ? onAdd : null,
  );

  @override
  Widget build(BuildContext context) => FoundiPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ProfessionalProfileTabs.labels[section],
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: FoundiUi.ink,
          ),
        ),
        if (section == 2) ...[
          const SizedBox(height: 12),
          if (profile.gallery.isEmpty)
            const Text(
              'Aucune réalisation ajoutée.',
              style: TextStyle(color: FoundiUi.muted),
            )
          else
            _gallery(),
          if (onManageGallery != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: onManageGallery,
                icon: const Icon(Icons.collections_outlined),
                label: const Text('Gérer les réalisations'),
              ),
            ),
        ] else ...[
          ...details,
          if (section == 0) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: FoundiUi.line),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text(
                  'Photos / Réalisations',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (profile.gallery.isNotEmpty)
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text('Voir tout (${profile.gallery.length})'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (profile.gallery.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Aucune réalisation ajoutée.',
                  style: TextStyle(color: FoundiUi.muted, fontSize: 12),
                ),
              ),
            if (profile.gallery.isNotEmpty || onAdd != null)
              _gallery(preview: true),
          ],
        ],
      ],
    ),
  );
}

class ProfessionalShowcaseHeader extends StatelessWidget {
  const ProfessionalShowcaseHeader({
    super.key,
    required this.profile,
    this.onEdit,
    this.onCover,
    this.onPortrait,
    this.showBio = false,
    this.showVerified = true,
    this.footer,
    this.action,
  });
  final ProfessionalShowcase profile;
  final VoidCallback? onEdit, onCover, onPortrait;
  final bool showBio, showVerified;
  final Widget? footer, action;

  @override
  Widget build(BuildContext context) => FoundiPanel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 19;
            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 2.7,
                      child: profile.cover == null
                          ? const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [FoundiUi.ink, FoundiUi.green],
                                ),
                              ),
                            )
                          : ShowcasePhotoView(
                              profile.cover,
                              icon: Icons.photo_outlined,
                              label: 'Couverture',
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(128, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name.isEmpty
                                ? 'Mon profil professionnel'
                                : profile.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: FoundiUi.ink,
                            ),
                          ),
                          if (profile.trade.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              profile.trade,
                              style: const TextStyle(color: FoundiUi.muted),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (showVerified)
                            const RequestTag('Professionnel vérifié'),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 14,
                  top: constraints.maxWidth / 2.7 - 58,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: SizedBox.expand(
                              child: ShowcasePhotoView(
                                profile.portrait,
                                icon: Icons.person_outline,
                                label: 'Photo du professionnel',
                              ),
                            ),
                          ),
                        ),
                        if (onPortrait != null)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filledTonal(
                              onPressed: onPortrait,
                              tooltip: 'Modifier la photo de profil',
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (onCover != null)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: compact
                        ? IconButton.filledTonal(
                            onPressed: onCover,
                            tooltip: 'Modifier la couverture',
                            icon: const Icon(Icons.camera_alt_outlined),
                          )
                        : FilledButton.icon(
                            onPressed: onCover,
                            style: FilledButton.styleFrom(
                              backgroundColor: FoundiUi.ink.withValues(
                                alpha: 0.76,
                              ),
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Modifier la couverture'),
                          ),
                  ),
              ],
            );
          },
        ),
        if (onEdit != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier le profil'),
              ),
            ),
          ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(alignment: Alignment.centerLeft, child: action!),
          ),
        if (showBio && profile.bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(profile.bio, style: const TextStyle(height: 1.45)),
          ),
        if (profile.area.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: FoundiUi.green,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    profile.area,
                    style: const TextStyle(color: FoundiUi.muted),
                  ),
                ),
              ],
            ),
          ),
        if (footer != null) ...[
          const Divider(height: 1, color: FoundiUi.line),
          footer!,
        ] else
          const SizedBox(height: 8),
      ],
    ),
  );
}

class ShowcasePhotoView extends StatelessWidget {
  const ShowcasePhotoView(
    this.photo, {
    super.key,
    required this.icon,
    this.label,
  });
  final ShowcasePhoto? photo;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: FoundiUi.tint,
      child: Center(
        child: Icon(icon, color: FoundiUi.green, semanticLabel: label),
      ),
    );
    final image = photo;
    return image == null
        ? placeholder
        : Image.memory(
            image.bytes,
            fit: BoxFit.cover,
            semanticLabel: label,
            excludeFromSemantics: label == null,
            errorBuilder: (_, _, _) => placeholder,
          );
  }
}

class ShowcaseGallery extends StatelessWidget {
  const ShowcaseGallery({
    super.key,
    required this.photos,
    this.onPhoto,
    this.onRemove,
    this.onAdd,
    this.preview = false,
  });
  final List<ShowcasePhoto> photos;
  final ValueChanged<int>? onPhoto, onRemove;
  final VoidCallback? onAdd;
  final bool preview;

  Widget _tile(int index) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ShowcasePhotoView(photos[index], icon: Icons.photo_outlined),
        if (onPhoto != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onPhoto!(index),
              child: Semantics(
                button: true,
                label: 'Voir la réalisation ${index + 1}',
              ),
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
  );

  @override
  Widget build(BuildContext context) {
    if (preview) {
      final count = photos.take(3).length;
      return SizedBox(
        height: MediaQuery.textScalerOf(context).scale(94),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count + (onAdd == null ? 0 : 1),
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => SizedBox(
            width: 104,
            child: index < count
                ? _tile(index)
                : Material(
                    color: FoundiUi.soft,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(12),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: FoundiUi.green),
                          SizedBox(height: 4),
                          Text(
                            'Ajouter',
                            style: TextStyle(color: FoundiUi.green),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 135,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (_, index) => _tile(index),
    );
  }
}
