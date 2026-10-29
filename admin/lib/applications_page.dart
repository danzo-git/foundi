import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
import 'admin_services.dart';

String date(dynamic value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ).toLocal().toString().substring(0, 16)
    : '—';

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    this.embedded = false,
    this.initialStatus = 'pending',
  });
  final bool embedded;
  final String initialStatus;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late String status = widget.initialStatus;
  String search = '', category = '', zone = '';
  DateTimeRange? dates;
  int page = 0;
  Map<String, dynamic> catalog = {};
  late Future<void> catalogLoad;
  @override
  void initState() {
    super.initState();
    catalogLoad = db
        .doc('referenceData/professionalOnboarding')
        .get()
        .then((s) {
          if (mounted) setState(() => catalog = s.data() ?? {});
        })
        .catchError((Object _) {
          if (mounted) setState(() => catalog = {});
        });
  }

  String names(dynamic ids, String key) {
    final entries = <dynamic>[...?catalog[key]];
    if (key == 'specialties') {
      for (final c in (catalog['categories'] as List? ?? [])) {
        entries.addAll(c['specialties'] as List? ?? []);
      }
    }
    return (ids as List? ?? [])
        .map(
          (id) =>
              entries.where((e) => e['id'] == id).firstOrNull?['label'] ?? id,
        )
        .join(', ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(
            title: const Text('Foundi Admin'),
            actions: [
              IconButton(
                tooltip: 'Actualiser',
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Déconnexion'),
              ),
            ],
          ),
    body: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialStatus.isEmpty
                      ? 'Tableau de bord'
                      : 'Candidatures professionnelles',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Text(
                  'Examinez les candidatures et accompagnez les professionnels.',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ...labels.entries
                        .where((e) => e.key != 'suspended')
                        .map(
                          (e) => SizedBox(
                            width: 185,
                            child: Card(
                              child: InkWell(
                                onTap: () => setState(() {
                                  status = e.key;
                                  page = 0;
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: FutureBuilder<AggregateQuerySnapshot>(
                                    future: db
                                        .collection('professionalProfiles')
                                        .where('status', isEqualTo: e.key)
                                        .count()
                                        .get(),
                                    builder: (context, s) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(e.value),
                                        Text(
                                          s.hasError
                                              ? 'Indisponible'
                                              : '${s.data?.count ?? '…'}',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        ,
                    SizedBox(
                      width: 185,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Catégories actives'),
                              Text(
                                (catalog['categories'] as List? ?? [])
                                    .where((c) => c['active'] != false)
                                    .length
                                    .toString(),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Nom ou identifiant (page courante)',
                        ),
                        onChanged: (v) =>
                            setState(() => search = v.toLowerCase()),
                      ),
                    ),
                    DropdownButton<String>(
                      value: status,
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Tous les statuts'),
                        ),
                        ...labels.entries.map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        status = v!;
                        page = 0;
                      }),
                    ),
                    filter(
                      'Catégorie',
                      'categories',
                      category,
                      (v) => category = v,
                    ),
                    filter('Zone', 'zones', zone, (v) => zone = v),
                    OutlinedButton(
                      onPressed: () async {
                        final v = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (v != null) {
                          setState(() {
                            dates = v;
                            page = 0;
                          });
                        }
                      },
                      child: Text(
                        dates == null
                            ? 'Date de soumission'
                            : '${dates!.start.toString().substring(0, 10)} — ${dates!.end.toString().substring(0, 10)}',
                      ),
                    ),
                    if (dates != null)
                      IconButton(
                        onPressed: () => setState(() {
                          dates = null;
                          page = 0;
                        }),
                        icon: const Icon(Icons.clear),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                list(),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> open(String uid) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Dossier(uid: uid, names: names),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget filter(
    String label,
    String key,
    String value,
    void Function(String) change,
  ) => DropdownButton<String>(
    value: value,
    items: [
      DropdownMenuItem(value: '', child: Text(label)),
      ...(catalog[key] as List? ?? []).map(
        (e) => DropdownMenuItem(
          value: e['id'] as String,
          child: Text(e['label'] as String),
        ),
      ),
    ],
    onChanged: (v) => setState(() {
      change(v!);
      page = 0;
    }),
  );
  Widget list() {
    Query<Map<String, dynamic>> q = db
        .collection('professionalProfiles')
        .orderBy('submittedAt', descending: true);
    // One indexed server filter; remaining filters are explicitly applied to each fetched page.
    if (status.isNotEmpty) q = q.where('status', isEqualTo: status);
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: q.limit((page + 1) * 25 + 1).get(),
      builder: (context, s) {
        if (s.hasError) {
          return Column(
            children: [
              const Text(
                'Chargement impossible. Vérifiez la connexion et les index Firebase.',
              ),
              TextButton(
                onPressed: () => setState(() {}),
                child: const Text('Réessayer'),
              ),
            ],
          );
        }
        if (!s.hasData) return const LinearProgressIndicator();
        final all = s.data!.docs;
        final rows = all.skip(page * 25).take(25).where((d) {
          final p = d.data();
          final submitted = p['submittedAt'] as num? ?? 0;
          return ('${p['businessName']} ${d.id}'.toLowerCase().contains(
                search,
              )) &&
              (category.isEmpty ||
                  (p['categoryIds'] as List? ?? []).contains(category)) &&
              (zone.isEmpty || (p['zoneIds'] as List? ?? []).contains(zone)) &&
              (dates == null ||
                  (submitted >= dates!.start.millisecondsSinceEpoch &&
                      submitted <
                          dates!.end
                              .add(const Duration(days: 1))
                              .millisecondsSinceEpoch));
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recherche, catégorie, zone et dates : filtres sur les 25 dossiers de la page.',
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Aucun dossier sur cette page.'),
              ),
            if (MediaQuery.sizeOf(context).width > 950 && rows.isNotEmpty)
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(
                      Color(0xFFF6F9FA),
                    ),
                    columns: const [
                      DataColumn(label: Text('Nom')),
                      DataColumn(label: Text('Activité')),
                      DataColumn(label: Text('Catégories')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Statut')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((d) {
                      final p = d.data();
                      return DataRow(
                        cells: [
                          DataCell(Text(p['businessName'] ?? '')),
                          DataCell(
                            Text(
                              p['type'] == 'company'
                                  ? 'Entreprise'
                                  : 'Indépendant',
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 160,
                              child: Text(
                                names(p['categoryIds'], 'categories'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(date(p['submittedAt']))),
                          DataCell(Text(labels[p['status']] ?? p['status'])),
                          DataCell(
                            OutlinedButton(
                              onPressed: () => open(d.id),
                              child: const Text('Voir'),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              )
            else
              ...rows.map((d) {
                final p = d.data();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.work_outline),
                    ),
                    title: Text('${p['businessName']}'),
                    subtitle: Text(
                      '${p['type'] == 'company' ? 'Entreprise' : 'Indépendant'} • ${names(p['specialtyIds'], 'specialties')}\n${date(p['submittedAt'])} • ${labels[p['status']] ?? p['status']}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(d.id),
                  ),
                );
              }),
            Row(
              children: [
                TextButton(
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  child: const Text('Précédent'),
                ),
                Text('Page ${page + 1}'),
                TextButton(
                  onPressed: all.length > (page + 1) * 25
                      ? () => setState(() => page++)
                      : null,
                  child: const Text('Suivant'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class Dossier extends StatefulWidget {
  const Dossier({super.key, required this.uid, required this.names});
  final String uid;
  final String Function(dynamic, String) names;
  @override
  State<Dossier> createState() => _DossierState();
}

class _DossierState extends State<Dossier> {
  bool busy = false;
  String? error;
  Future<void> decide(Map<String, dynamic> p, String status) async {
    final reason = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmer : ${labels[status]}'),
        content: TextField(
          controller: reason,
          maxLength: 2000,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: status == 'approved'
                ? 'Commentaire facultatif'
                : 'Motif obligatoire (5 caractères minimum)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (approved != true) return;
    if (status != 'approved' && text.length < 5) {
      setState(() => error = 'Précisez le motif (5 caractères minimum).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await functions.httpsCallable('reviewProfessionalProfile').call({
        'uid': widget.uid,
        'status': status,
        'reason': text,
        'revision': p['revision'],
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Décision impossible.');
    } catch (_) {
      if (mounted) setState(() => error = 'Connexion indisponible. Réessayez.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> document(String kind) async {
    setState(() => busy = true);
    try {
      final result = await functions
          .httpsCallable('readProfessionalDocument')
          .call({'uid': widget.uid, 'kind': kind});
      final bytes = base64Decode(result.data['base64']);
      saveDocument(bytes, result.data['contentType'], kind);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Document indisponible ou accès révoqué.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Examen du dossier')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('professionalProfiles/${widget.uid}').snapshots(),
      builder: (context, s) {
        if (s.hasError) {
          return const Center(
            child: Text('Accès refusé ou connexion indisponible.'),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final p = s.data!.data();
        if (p == null) return const Center(child: Text('Dossier introuvable.'));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p['businessName']}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    '${labels[p['status']] ?? p['status']} • Soumis le ${date(p['submittedAt'])}',
                  ),
                  Text('Identifiant : ${widget.uid}'),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: db.doc('users/${widget.uid}').get(),
                    builder: (context, u) => Text(
                      u.hasError
                          ? 'Coordonnées indisponibles'
                          : '${u.data?.data()?['fullName'] ?? ''} • ${u.data?.data()?['phone'] ?? ''}',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(p['type'] == 'company' ? 'Entreprise' : 'Indépendant'),
                  Text(widget.names(p['categoryIds'], 'categories')),
                  Text(
                    'Spécialités : ${widget.names(p['specialtyIds'], 'specialties')}',
                  ),
                  Text('Zones : ${widget.names(p['zoneIds'], 'zones')}'),
                  const SizedBox(height: 16),
                  Text('${p['description']}'),
                  if (p['reviewReason'] != null)
                    Text('Dernier motif : ${p['reviewReason']}'),
                  const SizedBox(height: 24),
                  const Text(
                    'Justificatifs privés',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection(
                          'professionalProfiles/${widget.uid}/documents',
                        )
                        .snapshots(),
                    builder: (context, d) {
                      if (d.hasError) {
                        return const Text('Justificatifs indisponibles.');
                      }
                      if (!d.hasData) return const LinearProgressIndicator();
                      return Column(
                        children: d.data!.docs
                            .map(
                              (doc) => ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text('${doc.data()['name']}'),
                                subtitle: Text(
                                  widget.names([doc.id], 'documentTypes'),
                                ),
                                trailing: TextButton(
                                  onPressed:
                                      busy || doc.data()['state'] != 'ready'
                                      ? null
                                      : () => document(doc.id),
                                  child: const Text('Consulter / télécharger'),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  if (p['status'] == 'pending')
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: ['approved', 'needs_changes', 'rejected']
                          .map(
                            (status) => FilledButton(
                              onPressed: busy ? null : () => decide(p, status),
                              child: Text(
                                {
                                  'approved': 'Approuver',
                                  'needs_changes': 'Demander des corrections',
                                  'rejected': 'Refuser',
                                }[status]!,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Historique des décisions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection('professionalAudit')
                        .where('uid', isEqualTo: widget.uid)
                        .snapshots(),
                    builder: (context, a) {
                      if (a.hasError) {
                        return const Text('Historique indisponible.');
                      }
                      if (!a.hasData) return const LinearProgressIndicator();
                      final entries = a.data!.docs.toList()
                        ..sort(
                          (a, b) => (b.data()['createdAt'] as num).compareTo(
                            a.data()['createdAt'] as num,
                          ),
                        );
                      return Column(
                        children: entries.map((d) {
                          final v = d.data();
                          return ListTile(
                            title: Text(
                              '${labels[v['to']]} • ${date(v['createdAt'])}',
                            ),
                            subtitle: Text(
                              'Administrateur : ${v['adminUid']}\n${v['reason'] ?? ''}',
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
