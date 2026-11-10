import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'widget_test.dart' as fixtures;

class FakeRequests implements RequestRepository {
  final items = <FoundiRequest>[];
  final changes = StreamController<void>.broadcast();
  final publishIds = <String>[];
  RequestDraft? publishedDraft;
  bool failPublish = false, failRead = false, loseResponse = false;
  Completer<void>? pending;
  int ids = 0;
  @override
  String newId() => 'request-${++ids}';
  @override
  Future<FoundiRequest> publish(String id, RequestDraft draft) async {
    publishIds.add(id);
    publishedDraft = draft;
    if (pending != null) await pending!.future;
    if (failPublish) {
      throw const AuthFailure('Publication non confirmée. Réessaie.');
    }
    final existing = items.where((r) => r.id == id).firstOrNull;
    if (existing != null) return existing;
    final request = FoundiRequest(
      id: id,
      title: draft.title,
      description: draft.description,
      categoryLabel: 'Catégorie de test',
      specialtyLabel: 'Spécialité de test',
      zoneLabel: 'Zone de test',
      status: 'published',
      createdAt: DateTime(2026, 10, 29),
      budget: draft.budget,
      photoIds: draft.photoIds,
    );
    items.insert(0, request);
    changes.add(null);
    if (loseResponse) {
      loseResponse = false;
      throw const AuthFailure('Publication non confirmée. Réessaie.');
    }
    return request;
  }

  Stream<List<FoundiRequest>> _watch() => Stream.multi((c) {
    void send() {
      if (failRead) {
        c.addError(StateError('offline'));
      } else {
        c.add(items.toList());
      }
    }

    final s = changes.stream.listen((_) => send());
    c.onCancel = s.cancel;
    send();
  });
  @override
  Stream<List<FoundiRequest>> watchPublic() => _watch();
  @override
  Stream<List<FoundiRequest>> watchMine(String uid) => _watch();
  @override
  Stream<FoundiRequest?> watchPublicDetail(String id) =>
      _watch().map((items) => items.where((r) => r.id == id).firstOrNull);
}

class LivePublicationCatalog extends fixtures.FakePro {
  final updates = StreamController<ProfessionalCatalog>.broadcast();
  bool failCatalog = false;

  @override
  Stream<ProfessionalCatalog> watchCatalog() => Stream.multi((controller) {
    if (failCatalog) {
      controller.addError(StateError('Catalogue indisponible'));
      controller.close();
      return;
    }
    controller.add(references);
    final subscription = updates.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('V5_CAPTURE')) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('v5Capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/ux-pub-preview')
      ..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> runFlow(
  WidgetTester t,
  FakeRequests requests,
  Future<void> Function(fixtures.FakeAuth, fixtures.FakePro) body, {
  bool guest = false,
  bool professional = false,
  fixtures.FakePro? catalogProvider,
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  final auth = fixtures.FakeAuth(
    user: guest
        ? null
        : fixtures.account(
            data: fixtures.profile.copyWith(
              preferredMode: professional ? 'professional' : 'client',
            ),
          ),
  );
  final pro =
      catalogProvider ??
      fixtures.FakePro(
        profile: ProfessionalProfile(
          status: professional
              ? ProfessionalStatus.approved
              : ProfessionalStatus.none,
        ),
      );
  try {
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('v5Capture'),
        child: FoundiApp(
          authRepository: auth,
          professionalRepository: pro,
          requestRepository: requests,
        ),
      ),
    );
    await t.pumpAndSettle();
    await body(auth, pro);
  } finally {
    await t.pumpWidget(const SizedBox());
    await auth.changes.close();
    await pro.changes.close();
    await pro.docChanges.close();
    await requests.changes.close();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.view.resetViewInsets();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  }
}

Future<void> choose(WidgetTester t, String key, String label) async {
  final dropdown = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('$key-'),
  );
  await Scrollable.ensureVisible(t.element(dropdown), alignment: .3);
  await t.pumpAndSettle();
  await t.tap(dropdown);
  await t.pumpAndSettle();
  await fixtures.tap(t, find.text(label).last);
}

Future<void> fill(WidgetTester t, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await Scrollable.ensureVisible(t.element(field), alignment: .25);
  await t.pumpAndSettle();
  await t.enterText(field, value);
  await t.pump();
}

Future<void> tapForm(WidgetTester t, Finder target) async {
  await Scrollable.ensureVisible(t.element(target), alignment: .65);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> chooseReferences(WidgetTester t) async {
  await choose(t, 'requestCategory', 'Catégorie de test');
  await choose(t, 'requestSpecialty', 'Spécialité de test');
  await choose(t, 'requestZone', 'Zone de test');
}

Future<void> confirmSpace(WidgetTester t, String label) async {
  await fixtures.tap(t, find.text(label));
  await fixtures.tap(t, find.byKey(const ValueKey('confirmSpace')));
}

Future<void> preview(WidgetTester t) async {
  final action = find.byKey(const ValueKey('openPublication'));
  expect(
    find.descendant(of: action, matching: find.text('Publier une demande')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: action, matching: find.byIcon(Icons.add)),
    findsOneWidget,
  );
  await fixtures.tap(t, action);
  expect(find.text('De quoi as-tu besoin ?'), findsOneWidget);
  expect(
    t.widget<TextFormField>(find.byType(TextFormField).first).key,
    const ValueKey('requestDescription'),
  );
  expect(find.text('Continuer'), findsNothing);
  await capture(t, '01-formulaire-vide');
  await fill(
    t,
    'requestDescription',
    'Une description publique de mon besoin de test.',
  );
  await chooseReferences(t);
  await fill(t, 'requestBudget', '100 000');
  expect(
    find.text('Une description publique de mon besoin de test'),
    findsOneWidget,
  );
  if (const bool.fromEnvironment('V5_CAPTURE')) {
    FocusManager.instance.primaryFocus?.unfocus();
    Scrollable.of(t.element(find.text('Nouvelle demande'))).position.jumpTo(0);
    await capture(t, '02-formulaire-rempli');
  }
  await tapForm(t, find.text('Modifier le titre'));
  await fill(t, 'requestTitle', 'Mon besoin de test');
  await tapForm(t, find.text('Vérifier ma demande'));
  await capture(t, '03-verification');
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('V5_CAPTURE')) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$name').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  test(
    'FCFA budget accepts empty, zero and grouped integers and rejects negatives or decimals',
    () {
      expect(RequestDraft.parseBudget(''), isNull);
      expect(RequestDraft.parseBudget('0'), 0);
      expect(RequestDraft.parseBudget('100 000'), 100000);
      expect(formatFcfa(1500000), '1 500 000');
      for (final value in ['-1', '1.5', 'abc', '1000000000000', '1e3']) {
        expect(() => RequestDraft.parseBudget(value), throwsFormatException);
      }
    },
  );
  for (final professional in [false, true]) {
    final accountType = professional ? 'approved professional' : 'client';
    testWidgets(
      'V5 $accountType publishes in Client space and reaches personal list and detail',
      (t) async {
        final repository = FakeRequests();
        await runFlow(t, repository, (auth, pro) async {
          if (professional) {
            await fixtures.tap(t, find.byKey(const ValueKey('spaceSelector')));
            await confirmSpace(t, 'Espace client');
          }
          await preview(t);
          await tapForm(t, find.text('Modifier'));
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const ValueKey('requestTitle')),
                )
                .controller!
                .text,
            'Mon besoin de test',
          );
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const ValueKey('requestDescription')),
                )
                .controller!
                .text,
            contains('description publique'),
          );
          await tapForm(t, find.text('Vérifier ma demande'));
          await tapForm(t, find.text('Publier ma demande'));
          expect(find.text('C’est publié !'), findsOneWidget);
          expect(repository.items.length, 1);
          await capture(t, '05-succes');
          await tapForm(t, find.text('Accéder à Mes demandes'));
          expect(find.text('Mon besoin de test'), findsOneWidget);
          expect(find.text('Ouverte'), findsOneWidget);
          final published = find.text('Mon besoin de test');
          await t.scrollUntilVisible(published, 180);
          await t.pumpAndSettle();
          await fixtures.tap(t, published);
          expect(find.text('Détail de la demande'), findsOneWidget);
          expect(auth.modeWrites, 0);
          expect(pro.accessChecks, 0);
        }, professional: professional);
      },
    );
  }
  testWidgets(
    'V5 failed publication has no success; retry and double tap reuse a single ID',
    (t) async {
      final repository = FakeRequests()..failPublish = true;
      await runFlow(t, repository, (auth, pro) async {
        await preview(t);
        await tapForm(t, find.text('Publier ma demande'));
        expect(find.text('C’est publié !'), findsNothing);
        expect(repository.items, isEmpty);
        expect(
          find.text('Publication non confirmée. Réessaie.'),
          findsOneWidget,
        );
        await capture(t, '04-erreur');
        repository.failPublish = false;
        repository.pending = Completer<void>();
        final publish = find.byKey(const ValueKey('publishRequest'));
        await Scrollable.ensureVisible(t.element(publish), alignment: .6);
        await t.pumpAndSettle();
        await t.tap(publish);
        await t.pump();
        await t.tap(publish);
        await t.pump();
        expect(repository.publishIds, ['request-1', 'request-1']);
        repository.pending!.complete();
        await t.pumpAndSettle();
        expect(find.text('C’est publié !'), findsOneWidget);
        expect(repository.items.length, 1);
        await fixtures.tap(t, find.byKey(const ValueKey('nav-0')));
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        expect(find.text('De quoi as-tu besoin ?'), findsOneWidget);
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('requestDescription')),
              )
              .controller!
              .text,
          isEmpty,
        );
      });
    },
  );
  testWidgets(
    'an automatically suggested title can be published with no budget',
    (t) async {
      final repository = FakeRequests()..loseResponse = true;
      await runFlow(t, repository, (auth, pro) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        const title = 'Installer un climatiseur dans la chambre';
        const description = '$title. Il faut retirer l’ancien appareil.';
        await fill(t, 'requestDescription', description);
        await chooseReferences(t);
        expect(find.text(title), findsOneWidget);
        expect(find.byKey(const ValueKey('requestTitle')), findsNothing);
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text(title), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(find.text('BUDGET SOUHAITÉ'), findsNothing);
        expect(repository.publishIds, isEmpty);
        await tapForm(t, find.text('Publier ma demande'));
        expect(repository.items.single.title, title);
        expect(repository.items.single.budget, isNull);
        expect(find.text('C’est publié !'), findsNothing);
        await tapForm(t, find.text('Publier ma demande'));
        expect(find.text('C’est publié !'), findsOneWidget);
        expect(repository.items, hasLength(1));
        expect(repository.publishIds, ['request-1', 'request-1']);
      });
    },
  );

  testWidgets(
    'custom title survives description and category changes, including a category with no specialty',
    (t) async {
      final repository = FakeRequests();
      final pro = fixtures.FakePro()
        ..references = ProfessionalCatalog(
          enabled: true,
          categories: [
            ...fixtures.catalog.categories,
            const ProfessionalCategory('other', 'Autre catégorie', [], {}),
          ],
          zones: fixtures.catalog.zones,
        );
      await runFlow(t, repository, (auth, _) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        await fill(
          t,
          'requestDescription',
          'Installer un climatiseur dans la chambre.',
        );
        await chooseReferences(t);
        await tapForm(t, find.text('Modifier le titre'));
        await fill(t, 'requestTitle', 'Titre personnalisé');
        await fill(
          t,
          'requestDescription',
          'Réparer le climatiseur dans la chambre.',
        );
        await choose(t, 'requestCategory', 'Autre catégorie');
        expect(find.text('Spécialité *'), findsNothing);
        await choose(t, 'requestCategory', 'Catégorie de test');
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Choisis une option active.'), findsOneWidget);
        await choose(t, 'requestCategory', 'Autre catégorie');
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Titre personnalisé'), findsOneWidget);
        expect(find.text('Autre catégorie'), findsOneWidget);
        await tapForm(t, find.text('Publier ma demande'));
        expect(repository.items, hasLength(1));
        expect(repository.items.single.title, 'Titre personnalisé');
        expect(repository.publishedDraft?.specialtyId, isEmpty);
      }, catalogProvider: pro);
    },
  );

  testWidgets('invalid title suggestion reveals a required editable title', (
    t,
  ) async {
    await runFlow(t, FakeRequests(), (auth, pro) async {
      await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
      await fill(
        t,
        'requestDescription',
        'OK\nJe cherche une aide pour déplacer un meuble.',
      );
      await chooseReferences(t);
      expect(find.byKey(const ValueKey('requestTitle')), findsOneWidget);
      await tapForm(t, find.text('Vérifier ma demande'));
      expect(
        find.text('Renseigne un titre de 3 à 120 caractères.'),
        findsOneWidget,
      );
      await fill(t, 'requestTitle', 'Aide pour déplacer un meuble');
      await tapForm(t, find.text('Vérifier ma demande'));
      expect(find.text('Aide pour déplacer un meuble'), findsOneWidget);
    });
  });

  testWidgets(
    'catalogue failure keeps the description and a retired zone blocks the reviewed draft',
    (t) async {
      final repository = FakeRequests();
      final pro = LivePublicationCatalog()..failCatalog = true;
      addTearDown(pro.updates.close);
      await runFlow(t, repository, (auth, _) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        const description = 'Installer un climatiseur dans la chambre.';
        await fill(t, 'requestDescription', description);
        expect(
          t
              .widget<FilledButton>(find.byKey(const ValueKey('verifyRequest')))
              .onPressed,
          isNull,
        );
        pro.failCatalog = false;
        await tapForm(t, find.text('Actualiser les références'));
        expect(find.text(description), findsOneWidget);
        await chooseReferences(t);
        await tapForm(t, find.text('Vérifier ma demande'));
        pro.updates.add(
          ProfessionalCatalog(
            enabled: true,
            categories: fixtures.catalog.categories,
            zones: const [ReferenceChoice('other_zone', 'Nouvelle zone')],
          ),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const ValueKey('publishRequest')),
              )
              .onPressed,
          isNull,
        );
        expect(repository.publishIds, isEmpty);
        await tapForm(t, find.text('Modifier'));
        expect(find.text(description), findsOneWidget);
        await choose(t, 'requestZone', 'Nouvelle zone');
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Nouvelle zone'), findsOneWidget);
      }, catalogProvider: pro);
    },
  );
  testWidgets(
    'V5 guest explores public detail and reuses existing authentication to publish',
    (t) async {
      final repository = FakeRequests();
      await repository.publish(
        'public',
        const RequestDraft(
          categoryId: 'test_sector',
          specialtyId: 'test_specialty',
          zoneId: 'test_zone',
          title: 'Besoin public',
          description: 'Une description publique sans contact.',
        ),
      );
      await runFlow(t, repository, (auth, pro) async {
        expect(find.text('Explorer les demandes'), findsOneWidget);
        await capture(t, '06-explorer');
        await fixtures.tap(t, find.text('Besoin public'));
        expect(
          find.text('Une description publique sans contact.'),
          findsOneWidget,
        );
        await capture(t, '07-detail');
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        expect(find.byKey(const ValueKey('submitAuth')), findsOneWidget);
        await fixtures.tap(t, find.text('Explorer sans compte'));
        expect(find.text('Explorer les demandes'), findsOneWidget);
        expect(auth.user, isNull);
      }, guest: true);
    },
  );
  testWidgets(
    'V5 personal empty state starts publication and internal tabs preserve input',
    (t) async {
      await runFlow(t, FakeRequests(), (auth, pro) async {
        expect(find.text('Aucune demande pour le moment'), findsOneWidget);
        expect(find.text('Publier ma première demande'), findsNothing);
        await capture(t, '08-vide');
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        await fill(t, 'requestDescription', 'Saisie conservée');
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        await fixtures.tap(t, find.byKey(const ValueKey('nav-0')));
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('requestDescription')),
              )
              .controller!
              .text,
          'Saisie conservée',
        );
      });
    },
  );
  testWidgets(
    'V5 validates required inputs and budget and handles list error with retry',
    (t) async {
      final repository = FakeRequests();
      await runFlow(t, repository, (auth, pro) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Choisis une option active.'), findsWidgets);
        expect(
          find.text('Décris ton besoin en 10 à 3 000 caractères.'),
          findsOneWidget,
        );
        await fill(t, 'requestDescription', 'Description de test valide.');
        await chooseReferences(t);
        await fill(t, 'requestBudget', '-100');
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.textContaining('Montant entier'), findsOneWidget);
        expect(repository.publishIds, isEmpty);
        repository.failRead = true;
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        expect(
          find.textContaining('Impossible de charger les demandes.'),
          findsOneWidget,
        );
        repository.failRead = false;
        await fixtures.tap(t, find.text('Réessayer'));
        expect(find.textContaining('Aucune demande publiée'), findsOneWidget);
      });
    },
  );
  testWidgets('An approved professional publishes only from Client space', (
    t,
  ) async {
    final repository = FakeRequests();
    await runFlow(t, repository, (auth, pro) async {
      final publish = find.byKey(const ValueKey('openPublication'));
      final selector = find.byKey(const ValueKey('spaceSelector'));
      final firstTab = find.byKey(const ValueKey('nav-0'));
      final description = find.byKey(const ValueKey('requestDescription'));

      expect(find.text('Explorer les demandes'), findsOneWidget);
      expect(publish, findsNothing);
      expect(find.text('Publier une demande'), findsNothing);
      await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
      await fixtures.tap(t, find.text('Mes demandes'));
      expect(find.text('Aucune demande pour le moment'), findsOneWidget);
      expect(publish, findsNothing);
      await fixtures.tap(t, firstTab);

      await fixtures.tap(t, selector);
      expect(find.text('Choisir mon espace'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Choisir mon espace'), findsNothing);
      expect(find.text('Explorer les demandes'), findsOneWidget);

      await fixtures.tap(t, selector);
      await confirmSpace(t, 'Espace client');
      expect(find.text('Espace Client'), findsOneWidget);
      expect(description, findsNothing);
      expect(repository.publishIds, isEmpty);
      await fixtures.tap(t, publish);
      await fill(t, 'requestDescription', 'Brouillon conservé');

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Aucune demande pour le moment'), findsOneWidget);
      await fixtures.tap(t, selector);
      await confirmSpace(t, 'Espace professionnel');
      expect(find.text('Explorer les demandes'), findsOneWidget);
      expect(publish, findsNothing);
      await fixtures.tap(t, selector);
      await confirmSpace(t, 'Espace client');
      await fixtures.tap(t, publish);
      expect(
        t.widget<TextFormField>(description).controller!.text,
        'Brouillon conservé',
      );
      await fixtures.tap(t, firstTab);
      await preview(t);
      await tapForm(t, find.text('Publier ma demande'));
      expect(repository.publishIds, hasLength(1));

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Mon besoin de test'), findsOneWidget);
      await fixtures.tap(t, selector);
      await confirmSpace(t, 'Espace professionnel');
      await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
      await fixtures.tap(t, find.text('Mes demandes'));
      expect(find.text('Mon besoin de test'), findsOneWidget);
      await fixtures.tap(t, firstTab);
      pro.emit(const ProfessionalProfile(status: ProfessionalStatus.suspended));
      await t.pumpAndSettle();
      expect(find.text('Espace Client'), findsOneWidget);
      expect(publish, findsOneWidget);
      expect(auth.signOuts, 0);
      expect(auth.modeWrites, 0);
    }, professional: true);
  });

  testWidgets('Space selector remains usable at 320px and large text', (
    t,
  ) async {
    await runFlow(t, FakeRequests(), (auth, pro) async {
      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      await t.pumpAndSettle();
      await fixtures.tap(t, find.byKey(const ValueKey('spaceSelector')));
      await confirmSpace(t, 'Espace client');
      expect(find.text('Espace Client'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, professional: true);
  });

  testWidgets('V5 remains usable at 320px and large text', (t) async {
    await runFlow(t, FakeRequests(), (auth, pro) async {
      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.7;
      await t.pumpAndSettle();
      final publication = find.byKey(const ValueKey('openPublication'));
      await t.scrollUntilVisible(publication, 120);
      await t.pumpAndSettle();
      await fixtures.tap(t, publication);
      final semantics = t.ensureSemantics();
      try {
        await fill(
          t,
          'requestDescription',
          'Description de mon besoin à publier.',
        );
        await chooseReferences(t);
        await fill(t, 'requestBudget', '20 000');
        expect(t.testTextInput.isVisible, isTrue);
        t.view.viewInsets = const FakeViewPadding(bottom: 220);
        await t.pumpAndSettle();
        await tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Vérifie avant publication'), findsOneWidget);
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  });
}
