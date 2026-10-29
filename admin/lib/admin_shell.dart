import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'catalog_page.dart';
import 'applications_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  String section = 'dashboard';
  final scaffold = GlobalKey<ScaffoldState>();
  void select(String value) {
    setState(() => section = value);
    if (scaffold.currentState?.isDrawerOpen == true) Navigator.pop(context);
  }

  Widget navigation() => Container(
    width: 244,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF073B36), Color(0xFF022C29)],
      ),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: green,
                  child: Text(
                    'F',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Foundi Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                nav('dashboard', 'Tableau de bord', Icons.dashboard_outlined),
                nav(
                  'applications',
                  'Candidatures pro',
                  Icons.description_outlined,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Catalogue',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                nav(
                  'categories',
                  'Catégories',
                  Icons.category_outlined,
                  indent: true,
                ),
                nav(
                  'specialties',
                  'Spécialités',
                  Icons.handyman_outlined,
                  indent: true,
                ),
                nav(
                  'zones',
                  'Zones géographiques',
                  Icons.location_on_outlined,
                  indent: true,
                ),
                nav(
                  'documents',
                  'Justificatifs',
                  Icons.folder_shared_outlined,
                  indent: true,
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFC8F5E1),
                  child: Text('A', style: TextStyle(color: Color(0xFF073B36))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Administrateur',
                        style: TextStyle(color: Colors.white),
                      ),
                      Text(
                        FirebaseAuth.instance.currentUser?.email ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget nav(String key, String label, IconData icon, {bool indent = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: ListTile(
          contentPadding: EdgeInsets.only(left: indent ? 28 : 12, right: 8),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          selected: section == key,
          selectedTileColor: const Color(0xFF0C6154),
          selectedColor: Colors.white,
          textColor: Colors.white70,
          iconColor: Colors.white70,
          leading: Icon(icon, size: 19),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: section == key ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap: () => select(key),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    final content = section == 'dashboard' || section == 'applications'
        ? Dashboard(
            key: ValueKey(section),
            embedded: true,
            initialStatus: section == 'dashboard' ? '' : 'pending',
          )
        : CatalogPage(key: ValueKey(section), section: section);
    return Scaffold(
      key: scaffold,
      drawer: desktop ? null : Drawer(child: navigation()),
      body: Row(
        children: [
          if (desktop) navigation(),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE5ECEB)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Menu',
                        onPressed: desktop
                            ? null
                            : () => scaffold.currentState!.openDrawer(),
                        icon: const Icon(Icons.menu, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          section == 'dashboard'
                              ? 'Vue d’ensemble'
                              : section == 'applications'
                              ? 'Vérification professionnelle'
                              : 'Gestion du catalogue',
                          style: const TextStyle(color: Color(0xFF607181)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Se déconnecter',
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        icon: const Icon(Icons.logout, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
