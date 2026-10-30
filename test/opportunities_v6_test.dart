import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/explorer_view.dart';
import 'requests_v5_test.dart' show FakeRequests;
import 'widget_test.dart' as fixtures;

const catalogData = ProfessionalCatalog(
  enabled: true,
  categories: [
    ProfessionalCategory('auto', 'Automobile', [
      ReferenceChoice('repair', 'Mécanique'),
    ], {}),
    ProfessionalCategory('home', 'Immobilier', [
      ReferenceChoice('rent', 'Location'),
    ], {}),
  ],
  zones: [
    ReferenceChoice('cocody', 'Abidjan › Cocody'),
    ReferenceChoice('bingerville', 'Abidjan › Bingerville'),
  ],
);
const approved = ProfessionalProfile(
  status: ProfessionalStatus.approved,
  activity: ProfessionalActivity(
    categoryIds: ['auto'],
    specialtyIds: ['repair'],
    zoneIds: ['cocody', 'bingerville'],
  ),
);

class Catalog extends fixtures.FakePro {
  Catalog({super.profile});
  @override
  Future<ProfessionalCatalog> loadCatalog() async => catalogData;
}

FoundiRequest row(
  String id, {
  String category = 'auto',
  String specialty = 'repair',
  String zone = 'cocody',
  String status = 'published',
}) => FoundiRequest(
  id: id,
  title: 'Demande $id',
  description: 'Description publique de la demande.',
  categoryLabel: category == 'auto' ? 'Automobile' : 'Immobilier',
  specialtyLabel: specialty,
  zoneLabel: zone,
  categoryId: category,
  specialtyId: specialty,
  zoneId: zone,
  status: status,
  createdAt: DateTime(2026),
);

class ExplorerRequests extends FakeRequests
    implements ExplorerRepository, OpportunityRepository {
  ExplorerFilters? lastFilters;
  List<String>? lastZones, lastCategories, lastSpecialties;
  int personalizedCalls = 0;
  bool fail = false;
  @override
  Stream<List<FoundiRequest>> watchExplore({
    ExplorerFilters filters = const ExplorerFilters(),
  }) {
    lastFilters = filters;
    if (fail) return Stream.error(StateError('offline'));
    return watchPublic().map((rows) => rows.where(filters.matches).toList());
  }

  @override
  Future<OpportunityPage> opportunities({
    List<String>? categoryIds,
    List<String>? specialtyIds,
    List<String>? zoneIds,
    Map<String, dynamic>? cursor,
  }) async {
    personalizedCalls++;
    lastZones = zoneIds;
    lastCategories = categoryIds;
    lastSpecialties = specialtyIds;
    if (fail) throw StateError('offline');
    return OpportunityPage(
      items
          .where(
            (r) =>
                r.status == 'published' &&
                r.id != 'own' &&
                (categoryIds ?? ['auto']).contains(r.categoryId) &&
                (specialtyIds ?? ['repair']).contains(r.specialtyId) &&
                (zoneIds ?? ['cocody', 'bingerville']).contains(r.zoneId),
          )
          .toList(),
      null,
    );
  }
}

Future<void> select(WidgetTester t, String field, String label) async {
  final dropdown = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('$field-'),
  );
  await t.ensureVisible(dropdown);
  await t.tap(dropdown);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  for (final type in ['visiteur', 'client', 'professionnel']) {
    testWidgets('Explorer commun : $type, filtres et détail public', (t) async {
      t.view.physicalSize = const Size(430, 1050);
      t.view.devicePixelRatio = 1;
      final pro = type == 'professionnel';
      final auth = fixtures.FakeAuth(
        user: type == 'visiteur'
            ? null
            : fixtures.account(
                data: fixtures.profile.copyWith(
                  preferredMode: pro ? 'professional' : 'client',
                ),
              ),
      );
      final c = Catalog(profile: pro ? approved : const ProfessionalProfile());
      final r = ExplorerRequests()
        ..items.addAll([
          row('car'),
          row('house', category: 'home', specialty: 'rent'),
          row('closed', status: 'closed'),
          row('deleted', status: 'deleted'),
        ]);
      await t.pumpWidget(
        FoundiApp(
          authRepository: auth,
          professionalRepository: c,
          requestRepository: r,
        ),
      );
      await t.pumpAndSettle();
      if (type != 'visiteur') {
        await t.tap(find.text('Explorer').last);
        await t.pumpAndSettle();
      }
      expect(find.text('Explorer les demandes'), findsOneWidget);
      expect(find.text('Pour moi'), pro ? findsOneWidget : findsNothing);
      expect(find.text('Demande closed'), findsNothing);
      expect(find.text('Demande deleted'), findsNothing);
      await t.tap(find.text('Filtres'));
      await t.pumpAndSettle();
      await select(t, 'Catégorie', 'Automobile');
      await select(t, 'Spécialité', 'Mécanique');
      await select(t, 'Catégorie', 'Immobilier');
      expect(find.text('Mécanique'), findsNothing);
      await select(t, 'Spécialité', 'Location');
      await select(t, 'Zone géographique', 'Abidjan › Cocody');
      await t.ensureVisible(find.text('Voir les résultats'));
      await t.tap(find.text('Voir les résultats'));
      await t.pumpAndSettle();
      expect(r.lastFilters?.categoryId, 'home');
      expect(r.lastFilters?.specialtyId, 'rent');
      expect(r.lastFilters?.zoneId, 'cocody');
      expect(find.text('Demande car'), findsNothing);
      expect(find.text('Demande house'), findsOneWidget);
      await t.tap(find.text('Demande house'));
      await t.pumpAndSettle();
      expect(find.text('Détail de la demande'), findsOneWidget);
      await t.tap(find.byTooltip('Retour'));
      await t.pumpAndSettle();
      expect(find.text('Demande house'), findsOneWidget);
      expect(find.text('Demande car'), findsNothing);
      await t.tap(find.text('Effacer les filtres').first);
      await t.pumpAndSettle();
      expect(find.text('Demande car'), findsOneWidget);
      r.items.removeWhere((item) => item.id == 'car');
      r.items.add(row('car', status: 'closed'));
      r.changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('Demande car'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await r.changes.close();
      await c.changes.close();
      await c.docChanges.close();
      await auth.changes.close();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }
  testWidgets(
    'Pour moi intersection, effacer, vide, erreur et retour au public libre',
    (t) async {
      t.view.physicalSize = const Size(430, 1100);
      t.view.devicePixelRatio = 1;
      final r = ExplorerRequests()
        ..items.addAll([
          row('own'),
          row('car'),
          row('other-zone', zone: 'bingerville'),
          row('house', category: 'home', specialty: 'rent'),
        ]);
      final c = Catalog();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerView(
              repository: r,
              catalog: c,
              profile: approved,
              professionalSpace: true,
              initialForMe: true,
              onOpen: (_) {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(r.personalizedCalls, 1);
      expect(find.text('Demande own'), findsNothing);
      expect(find.text('Demande house'), findsNothing);
      expect(find.text('Demande other-zone'), findsOneWidget);
      await t.tap(find.text('Filtres'));
      await t.pumpAndSettle();
      await select(t, 'Catégorie', 'Automobile');
      await select(t, 'Spécialité', 'Mécanique');
      await select(t, 'Zone géographique', 'Abidjan › Cocody');
      await t.ensureVisible(find.text('Voir les résultats'));
      await t.tap(find.text('Voir les résultats'));
      await t.pumpAndSettle();
      expect(r.lastZones, ['cocody']);
      expect(r.lastCategories, ['auto']);
      expect(r.lastSpecialties, ['repair']);
      expect(find.text('Demande other-zone'), findsNothing);
      await t.tap(find.text('Effacer les filtres').first);
      await t.pumpAndSettle();
      expect(r.lastZones, null);
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pour moi'))
            .selected,
        true,
      );
      r.fail = true;
      await t.tap(find.text('Actualiser'));
      await t.pumpAndSettle();
      expect(find.text('Réessayer'), findsOneWidget);
      r.fail = false;
      r.items.clear();
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Aucune demande trouvée'), findsOneWidget);
      r.items.add(row('house', category: 'home', specialty: 'rent'));
      await t.tap(find.text('Voir toutes les demandes'));
      await t.pumpAndSettle();
      expect(find.text('Demande house'), findsOneWidget);
      await t.tap(find.text('Filtres'));
      await t.pumpAndSettle();
      await select(t, 'Catégorie', 'Immobilier');
      await t.ensureVisible(find.text('Voir les résultats'));
      await t.tap(find.text('Voir les résultats'));
      await t.pumpAndSettle();
      expect(r.lastFilters?.categoryId, 'home');
      await t.pumpWidget(const SizedBox());
      await r.changes.close();
      await c.changes.close();
      await c.docChanges.close();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  for (final status in [
    ProfessionalStatus.pending,
    ProfessionalStatus.draft,
    ProfessionalStatus.needsChanges,
    ProfessionalStatus.rejected,
    ProfessionalStatus.suspended,
    ProfessionalStatus.none,
    ProfessionalStatus.approved,
  ]) {
    testWidgets('Pas de Pour moi pour ${status.name}', (t) async {
      final r = ExplorerRequests();
      final c = Catalog();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerView(
              repository: r,
              catalog: c,
              profile: ProfessionalProfile(status: status),
              professionalSpace: status != ProfessionalStatus.approved,
              initialForMe: true,
              onOpen: (_) {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Pour moi'), findsNothing);
      expect(r.personalizedCalls, 0);
      await t.pumpWidget(const SizedBox());
      await r.changes.close();
      await c.changes.close();
      await c.docChanges.close();
    });
  }
  testWidgets(
    'Profil approuvé inexploitable : état explicatif et accès profil',
    (t) async {
      final r = ExplorerRequests();
      final c = Catalog();
      var opened = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerView(
              repository: r,
              catalog: c,
              profile: const ProfessionalProfile(
                status: ProfessionalStatus.approved,
              ),
              professionalSpace: true,
              initialForMe: true,
              onOpen: (_) {},
              onPublish: () {},
              onProfile: () => opened = true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Profil à compléter'), findsOneWidget);
      expect(r.personalizedCalls, 0);
      await t.tap(find.text('Voir mon profil professionnel'));
      expect(opened, true);
      await t.pumpWidget(const SizedBox());
      await r.changes.close();
      await c.changes.close();
      await c.docChanges.close();
    },
  );
}
