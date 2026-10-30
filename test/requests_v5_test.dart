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
  bool failPublish = false, failRead = false;
  Completer<void>? pending;
  int ids = 0;
  @override
  String newId() => 'request-${++ids}';
  @override
  Future<FoundiRequest> publish(String id, RequestDraft draft) async {
    publishIds.add(id);
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
    );
    items.insert(0, request);
    changes.add(null);
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

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('V5_CAPTURE')) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('v5Capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/v5-preview')..createSync(recursive: true);
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
  final pro = fixtures.FakePro(
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
    t.platformDispatcher.clearTextScaleFactorTestValue();
  }
}

Future<void> choose(WidgetTester t, String key, String label) async {
  final dropdown = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('$key-'),
  );
  await t.scrollUntilVisible(
    dropdown,
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await Scrollable.ensureVisible(t.element(dropdown), alignment: 0);
  await t.pumpAndSettle();
  await t.tap(dropdown);
  await t.pumpAndSettle();
  await fixtures.tap(t, find.text(label).last);
}

Future<void> fill(WidgetTester t, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await t.scrollUntilVisible(
    field,
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await t.enterText(field, value);
  await t.pump();
}

Future<void> essentials(WidgetTester t) async {
  await choose(t, 'requestCategory', 'Catégorie de test');
  await choose(t, 'requestSpecialty', 'Spécialité de test');
  await choose(t, 'requestZone', 'Zone de test');
  await fill(t, 'requestTitle', 'Mon besoin de test');
}

Future<void> preview(WidgetTester t) async {
  await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
  await essentials(t);
  await capture(t, '01-informations');
  await fixtures.tap(t, find.text('Continuer'));
  await fill(
    t,
    'requestDescription',
    'Une description publique de mon besoin de test.',
  );
  await fill(t, 'requestBudget', '100 000');
  await capture(t, '02-details');
  await fixtures.tap(t, find.text('Prévisualiser ma demande'));
  await capture(t, '03-preview');
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
    testWidgets(
      'V5 publishes in ${professional ? 'professional' : 'client'} space and reaches personal list and detail',
      (t) async {
        final repository = FakeRequests();
        await runFlow(t, repository, (auth, pro) async {
          await preview(t);
          await fixtures.tap(t, find.text('Modifier'));
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const ValueKey('requestTitle')),
                )
                .controller!
                .text,
            'Mon besoin de test',
          );
          await fixtures.tap(t, find.text('Continuer'));
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const ValueKey('requestDescription')),
                )
                .controller!
                .text,
            contains('description publique'),
          );
          await fixtures.tap(t, find.text('Prévisualiser ma demande'));
          await fixtures.tap(t, find.text('Publier ma demande'));
          expect(find.text('C’est publié !'), findsOneWidget);
          expect(repository.items.length, 1);
          await capture(t, '04-confirmation');
          await fixtures.tap(t, find.text('Accéder à Mes demandes'));
          expect(find.text('Mon besoin de test'), findsOneWidget);
          expect(find.text('Publiée'), findsOneWidget);
          await capture(t, '05-mes-demandes');
          await fixtures.tap(t, find.text('Mon besoin de test'));
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
        await fixtures.tap(t, find.text('Publier ma demande'));
        expect(find.text('C’est publié !'), findsNothing);
        expect(repository.items, isEmpty);
        expect(
          find.text('Publication non confirmée. Réessaie.'),
          findsOneWidget,
        );
        repository.failPublish = false;
        repository.pending = Completer<void>();
        await t.tap(find.byKey(const ValueKey('publishRequest')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('publishRequest')));
        await t.pump();
        expect(repository.publishIds, ['request-1', 'request-1']);
        repository.pending!.complete();
        await t.pumpAndSettle();
        expect(find.text('C’est publié !'), findsOneWidget);
        expect(repository.items.length, 1);
        await fixtures.tap(t, find.byKey(const ValueKey('nav-0')));
        await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
        expect(find.text('Parlons de ton besoin'), findsOneWidget);
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('requestTitle')))
              .controller!
              .text,
          isEmpty,
        );
      });
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
        await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
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
        await fixtures.tap(t, find.byKey(const ValueKey('nav-4')));
        await fixtures.tap(t, find.text('Mes demandes'));
        expect(find.text('Aucune demande pour le moment'), findsOneWidget);
        await capture(t, '08-vide');
        await fixtures.tap(t, find.text('Publier ma première demande'));
        await fill(t, 'requestTitle', 'Saisie conservée');
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('requestTitle')))
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
        await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
        await fixtures.tap(t, find.text('Continuer'));
        expect(find.text('Choisis une option active.'), findsWidgets);
        await essentials(t);
        await fixtures.tap(t, find.text('Continuer'));
        await fill(t, 'requestDescription', 'Description de test valide.');
        await fill(t, 'requestBudget', '-100');
        await fixtures.tap(t, find.text('Prévisualiser ma demande'));
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
  testWidgets('V5 remains usable at 320px and large text', (t) async {
    await runFlow(t, FakeRequests(), (auth, pro) async {
      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.7;
      await t.pumpAndSettle();
      await fixtures.tap(t, find.byKey(const ValueKey('nav-2')));
      await essentials(t);
      await fixtures.tap(t, find.text('Continuer'));
      await fill(
        t,
        'requestDescription',
        'Description de mon besoin à publier.',
      );
      await fixtures.tap(t, find.text('Prévisualiser ma demande'));
      expect(t.takeException(), isNull);
    });
  });
}
