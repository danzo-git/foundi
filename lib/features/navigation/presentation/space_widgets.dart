import 'package:flutter/material.dart';
import '../../../core/presentation/foundi_logo.dart';

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
  const FoundiBrand({super.key, this.onSettings, this.notificationBell});
  final VoidCallback? onSettings;
  final Widget? notificationBell;
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
        const FoundiLogo(size: 38, decorative: true),
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
        ?notificationBell,
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

class FoundiSpaceLabel extends StatelessWidget {
  const FoundiSpaceLabel({
    super.key,
    required this.professional,
    this.onSelect,
  });

  final bool professional;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Material(
        color: FoundiUi.tint,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: onSelect == null ? null : const ValueKey('spaceSelector'),
          onTap: onSelect,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  professional ? Icons.work_outline : Icons.person_outline,
                  size: 18,
                  color: FoundiUi.green,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    professional ? 'Espace Professionnel' : 'Espace Client',
                    style: const TextStyle(
                      color: FoundiUi.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onSelect != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 18, color: FoundiUi.ink),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FoundiBottomBar extends StatelessWidget {
  const FoundiBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.professionalSpace = false,
    this.guest = false,
    this.messagesIcon,
  });

  final bool professionalSpace, guest;
  final ValueChanged<int> onSelect;
  final int selectedIndex;
  final Widget? messagesIcon;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      if (professionalSpace) ...[
        ('Explorer', Icons.search),
        ('Mes propositions', Icons.send_outlined),
      ] else if (guest) ...[
        ('Explorer', Icons.search),
        ('Publier', Icons.add),
      ] else ...[
        ('Mes demandes', Icons.assignment_outlined),
        ('Explorer', Icons.search),
      ],
      ('Messages', Icons.chat_bubble_outline),
      ('Compte', Icons.person_outline),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: FoundiUi.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, (label, icon)) in destinations.indexed)
                _item(label, icon, index),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(String label, IconData icon, int index) {
    final selected = index == selectedIndex;
    final color = selected ? FoundiUi.green : FoundiUi.ink;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? FoundiUi.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('nav-$index'),
            onTap: () => onSelect(index),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 32,
                    child: Center(
                      child: index == 2 && messagesIcon != null
                          ? messagesIcon!
                          : Icon(icon, color: color, size: 24),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
