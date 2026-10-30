import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';
import 'requests_v5_test.dart';
import 'widget_test.dart' as fixtures;

const sample = FoundiRequest(
  id: 'request',
  title: 'Mon titre existant',
  description: 'Description déjà enregistrée',
  categoryLabel: 'Catégorie',
  specialtyLabel: 'Spécialité',
  zoneLabel: 'Zone',
  status: 'published',
  createdAt: null,
  revision: 123,
  categoryId: 'test_sector',
  specialtyId: 'test_specialty',
  zoneId: 'test_zone',
  budget: 15000,
);

class ManagedRequests extends FakeRequests
    implements RequestManagementRepository {
  final actions = <String>[];
  bool fail = false;
  RequestDraft? lastDraft;
  String? lastId;
  int? lastRevision;
  @override
  Future<FoundiRequest> manage(
    String id,
    String action, {
    RequestDraft? draft,
    int? expectedRevision,
  }) async {
    if (fail) throw StateError('offline');
    actions.add(action);
    lastDraft = draft;
    lastId = id;
    lastRevision = expectedRevision;
    items.clear();
    if (action == 'close') {
      items.add(
        const FoundiRequest(
          id: 'request',
          title: 'Mon titre existant',
          description: 'Description déjà enregistrée',
          categoryLabel: 'Catégorie',
          specialtyLabel: '',
          zoneLabel: 'Zone',
          status: 'closed',
          createdAt: null,
        ),
      );
    }
    changes.add(null);
    return sample;
  }
}

void main() {
  testWidgets('edition preloads title and keeps the original identifier', (
    t,
  ) async {
    final r = ManagedRequests();
    final pro = fixtures.FakePro();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestComposer(
            repository: r,
            catalog: pro,
            initial: sample,
            onExit: () {},
            onMine: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Mon titre existant'), findsOneWidget);
    expect(r.ids, 0);
    await t.pumpWidget(const SizedBox());
    await r.changes.close();
    await pro.changes.close();
    await pro.docChanges.close();
  });
  testWidgets('prefilled edit saves on original ID and reports failures', (
    t,
  ) async {
    final r = ManagedRequests();
    final pro = fixtures.FakePro();
    var saved = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestComposer(
            repository: r,
            catalog: pro,
            initial: sample,
            onExit: () {},
            onMine: () => saved = true,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('requestTitle')),
      'Titre corrigé',
    );
    await t.tap(find.text('Continuer'));
    await t.pumpAndSettle();
    expect(find.text(sample.description), findsOneWidget);
    expect(find.text('15000'), findsOneWidget);
    await t.tap(find.text('Prévisualiser ma demande'));
    await t.pumpAndSettle();
    r.fail = true;
    await t.tap(find.text('Enregistrer les modifications'));
    await t.pumpAndSettle();
    expect(saved, false);
    r.fail = false;
    await t.tap(find.text('Enregistrer les modifications'));
    await t.pumpAndSettle();
    expect(saved, true);
    expect(r.lastId, sample.id);
    expect(r.lastRevision, 123);
    expect(r.lastDraft?.title, 'Titre corrigé');
    expect(r.publishIds, isEmpty);
    await t.pumpWidget(const SizedBox());
    await r.changes.close();
    await pro.changes.close();
    await pro.docChanges.close();
  });
  testWidgets('close and delete require confirmation and hide deleted cards', (
    t,
  ) async {
    final r = ManagedRequests()..items.add(sample);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestListView(
            repository: r,
            uid: 'owner',
            onOpen: (_) {},
            onPublish: () {},
            onEdit: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clôturer'));
    await t.pumpAndSettle();
    expect(r.actions, isEmpty);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clôturer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmer la clôture'));
    await t.pumpAndSettle();
    expect(r.actions, ['close']);
    expect(find.text('Clôturée'), findsOneWidget);
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Supprimer'));
    await t.pumpAndSettle();
    expect(r.actions, ['close']);
    await t.tap(find.text('Supprimer ma demande'));
    await t.pumpAndSettle();
    expect(r.actions, ['close', 'delete']);
    expect(find.text('Mon titre existant'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await r.changes.close();
  });
}
