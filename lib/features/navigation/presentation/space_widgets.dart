import 'package:flutter/material.dart';

abstract final class FoundiUi {
  static const green = Color(0xFF087D68);
  static const ink = Color(0xFF103D35);
  static const muted = Color(0xFF65817B);
  static const background = Color(0xFFF7FAF8);
  static const tint = Color(0xFFDFF4EA);
  static const soft = Color(0xFFEFF9F3);
  static const line = Color(0xFFDDE8E3);
}

void showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Bientôt disponible'),
        duration: Duration(seconds: 2),
      ),
    );
}

class FoundiBrand extends StatelessWidget {
  const FoundiBrand({super.key, this.onSettings});
  final VoidCallback? onSettings;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      onSettings == null ? 24 : 20,
      22,
      onSettings == null ? 18 : 6,
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FoundiUi.green,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Text(
            'F',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Foundi',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: FoundiUi.ink,
            ),
          ),
        ),
        if (onSettings != null)
          IconButton.filledTonal(
            key: const ValueKey('openSettings'),
            tooltip: 'Paramètres',
            onPressed: onSettings,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFE7F0EC),
            ),
            icon: const Icon(
              Icons.settings_outlined,
              color: FoundiUi.ink,
              size: 22,
            ),
          ),
      ],
    ),
  );
}

class FoundiBottomBar extends StatelessWidget {
  const FoundiBottomBar({
    super.key,
    required this.accountSelected,
    required this.onSelect,
  });
  final bool accountSelected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: FoundiUi.line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            item('Accueil', Icons.home_outlined, 0, !accountSelected),
            item('Explorer', Icons.search, 1, false),
            item('Publier', Icons.add, 2, false),
            item('Messages', Icons.chat_bubble_outline, 3, false),
            item('Compte', Icons.account_circle_outlined, 4, accountSelected),
          ],
        ),
      ),
    ),
  );
  Widget item(String label, IconData icon, int index, bool selected) =>
      Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: InkWell(
            key: ValueKey('nav-$index'),
            onTap: () => onSelect(index),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index == 2)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: FoundiUi.green,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    )
                  else
                    SizedBox(
                      height: 40,
                      child: Icon(
                        icon,
                        color: selected ? FoundiUi.green : FoundiUi.muted,
                        size: 23,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected || index == 2
                          ? FoundiUi.green
                          : FoundiUi.muted,
                      fontWeight: selected || index == 2
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class FoundiPanel extends StatelessWidget {
  const FoundiPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: color == Colors.white ? FoundiUi.line : Colors.transparent,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({
    super.key,
    required this.title,
    this.subtitle = 'Bientôt disponible',
  });
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => FoundiPanel(
    onTap: () => showComingSoon(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: FoundiUi.ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: FoundiUi.muted,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class FutureOverview extends StatelessWidget {
  const FutureOverview({super.key, this.professional = false});
  final bool professional;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, label)
          in (professional
                  ? ['À venir', 'Mes propositions']
                  : ['Offres (à venir)', 'Demandes (à venir)'])
              .indexed) ...[
        if (index > 0) const SizedBox(width: 12),
        Expanded(
          child: FoundiPanel(
            color: professional && index == 0 ? FoundiUi.tint : Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: professional ? 16 : 20,
            ),
            onTap: () => showComingSoon(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '—',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: FoundiUi.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: FoundiUi.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class SpaceChoice extends StatelessWidget {
  const SpaceChoice({
    super.key,
    required this.professional,
    required this.selected,
    required this.onTap,
  });
  final bool professional, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FoundiPanel(
    color: selected ? FoundiUi.tint : Colors.white,
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          professional ? Icons.work_outline : Icons.person_outline,
          color: FoundiUi.green,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                professional ? 'Espace professionnel' : 'Espace client',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: FoundiUi.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                professional
                    ? 'Mes outils professionnels'
                    : 'Mes recherches et mes besoins',
                style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
              ),
            ],
          ),
        ),
        if (selected) const Icon(Icons.check, color: FoundiUi.green, size: 20),
      ],
    ),
  );
}
