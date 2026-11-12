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
  authorPublicName: 'Ancien alias de demande',
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
  testWidgets(
    'editing a public request uses the account name without a per-request name field',
    (t) async {
      final repository = ManagedRequests()..items.add(sample);
      await runFlow(t, repository, (_, _) async {
        final menu = find.byType(PopupMenuButton<String>);
        await t.scrollUntilVisible(menu, 140);
        await t.pumpAndSettle();
        await fixtures.tap(t, menu);
        await fixtures.tap(t, find.text('Modifier'));

        final name = find.byKey(const ValueKey('requestAuthorName'));
        expect(name, findsNothing);
        expect(find.text('Nom d’affichage public'), findsNothing);
        expect(find.text('Utiliser « Awa K. »'), findsNothing);
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Auteur affiché · Awa Kouassi'), findsOneWidget);
        await tapForm(t, find.text('Enregistrer les modifications'));

        expect(repository.actions, ['edit']);
        expect(repository.lastId, sample.id);
        expect(
          repository.lastDraft!.toMap().containsKey('authorPublicName'),
          isFalse,
        );
        expect(repository.publishIds, isEmpty);
      });
    },
  );
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
    expect(find.text(sample.description), findsOneWidget);
    expect(find.text('15000'), findsOneWidget);
    await tapForm(t, find.text('Vérifier ma demande'));
    r.fail = true;
    await tapForm(t, find.text('Enregistrer les modifications'));
    expect(saved, false);
    r.fail = false;
    await tapForm(t, find.text('Enregistrer les modifications'));
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
  testWidgets(
    'edition keeps the draft across tabs and confirms a destructive exit',
    (t) async {
      final repository = ManagedRequests()..items.add(sample);
      await runFlow(t, repository, (auth, pro) async {
        Future<void> openEditor() async {
          final menu = find.byType(PopupMenuButton<String>);
          await t.scrollUntilVisible(menu, 140);
          await t.pumpAndSettle();
          await fixtures.tap(t, menu);
          await fixtures.tap(t, find.text('Modifier'));
        }

        await openEditor();
        const description = 'Une modification en cours de saisie.';
        await fill(t, 'requestDescription', description);
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        await fixtures.tap(t, find.byKey(const ValueKey('nav-0')));
        await openEditor();
        expect(find.text(description), findsOneWidget);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Quitter la modification ?'), findsOneWidget);
        await fixtures.tap(t, find.text('Continuer la saisie'));
        expect(find.text(description), findsOneWidget);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await fixtures.tap(t, find.text('Quitter'));
        expect(find.byKey(const ValueKey('requestDescription')), findsNothing);
        await openEditor();
        expect(find.text(sample.description), findsOneWidget);
        expect(repository.actions, isEmpty);
        expect(repository.publishIds, isEmpty);
      });
    },
  );
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
