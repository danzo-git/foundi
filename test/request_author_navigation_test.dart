import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/requests/domain/request_author_repository.dart';
import 'package:foundi/features/requests/domain/request_location_repository.dart';
import 'package:foundi/features/requests/presentation/explorer_view.dart';
import 'package:foundi/features/requests/presentation/request_zone_picker.dart';
import 'requests_v5_test.dart' as requests;
import 'sprint25_test.dart' as sprint;
import 'widget_test.dart' as fixtures;

class AuthorsFake extends requests.FakeRequests
    implements RequestAuthorRepository {
  RequestAuthorProfile profile = const RequestAuthorProfile(
    name: 'Awa Kouassi',
  );
  bool unavailable = false;
  final authorReads = <String>[];
  @override
  Future<RequestAuthorProfile> readRequestAuthor(String id) async {
    authorReads.add(id);
    if (unavailable) {
      throw const RequestAuthorUnavailable();
    }
    return profile;
  }
}

class LocationFake implements RequestLocationRepository {
  List<ReferenceChoice> suggestions = const [
    ReferenceChoice('cocody', 'Cocody'),
  ];
  RequestLocationFailure? failure;
  Completer<void>? waiting;
  int reads = 0;
  @override
  Future<List<ReferenceChoice>> suggest(List<ReferenceChoice> choices) async {
    reads++;
    if (waiting != null) await waiting!.future;
    if (failure != null) throw failure!;
    return suggestions;
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  setUpAll(() async {
    if (!sprint.captureEnabled) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$name').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
  });
  for (final professional in [false, true]) {
    testWidgets(
      'Explorer author tap opens ${professional ? 'professional activity' : 'client identity'} instead of the request',
      (t) async {
        final repo = AuthorsFake()..items.add(sprint.request);
        if (professional) {
          repo.profile = const RequestAuthorProfile(
            name: 'Awa Kouassi',
            professional: ProfessionalShowcase(
              name: 'Atelier Awa',
              trade: 'Menuiserie',
              area: 'Cocody',
              bio: 'Meubles sur mesure',
              professionalId: 'public-pro',
            ),
          );
        }
        int requestsOpened = 0;
        await sprint.page(
          t,
          ExplorerView(
            repository: repo,
            onOpen: (_) => requestsOpened++,
            onPublish: () {},
          ),
        );
        await sprint.capture(t, 'explorer-auteur-cliquable');
        await fixtures.tap(
          t,
          find.byKey(ValueKey('requestAuthor-${sprint.request.id}')),
        );
        expect(requestsOpened, 0);
        expect(repo.authorReads, everyElement(sprint.request.id));
        expect(repo.authorReads, hasLength(1));
        if (professional) {
          expect(find.text('Profil professionnel'), findsOneWidget);
          expect(find.text('Atelier Awa'), findsOneWidget);
          expect(find.text('Modifier le profil'), findsNothing);
          await fixtures.tap(
            t,
            find.byKey(const ValueKey('publicProfileSection-1')),
          );
          await t.scrollUntilVisible(
            find.textContaining('Activité ·'),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.textContaining('Activité ·'), findsOneWidget);
          await sprint.capture(t, 'profil-auteur-activite-professionnelle');
          repo.unavailable = true;
          await t.pump(const Duration(seconds: 31));
          await t.pumpAndSettle();
          expect(find.text('Atelier Awa'), findsNothing);
          expect(
            find.text('Ce professionnel n’est plus disponible.'),
            findsOneWidget,
          );
        } else {
          expect(find.text('Profil du demandeur'), findsOneWidget);
          expect(find.text('Awa Kouassi'), findsOneWidget);
          expect(find.text('Professionnel vérifié'), findsNothing);
          await sprint.capture(t, 'profil-auteur-client');
          repo.unavailable = true;
          await t.pump(const Duration(seconds: 31));
          await t.pumpAndSettle();
          expect(find.text('Awa Kouassi'), findsNothing);
          expect(
            find.text('Le profil de cet auteur n’est plus disponible.'),
            findsOneWidget,
          );
        }
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text(sprint.request.title), findsOneWidget);
        await fixtures.tap(t, find.text(sprint.request.title));
        expect(requestsOpened, 1);
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
      },
    );
  }
  testWidgets(
    'Rennes GPS confirmation adds only the French catalogue identifier',
    (t) async {
      const rennes = ReferenceChoice(
        'fr_commune_35238',
        'Rennes',
        countryCode: 'FR',
        zoneType: 'commune',
      );
      final location = LocationFake()..suggestions = const [rennes];
      var selected = <String>[];
      await sprint.page(
        t,
        StatefulBuilder(
          builder: (context, update) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              RequestZonePicker(
                choices: const [rennes],
                selected: selected,
                locationRepository: location,
                onChanged: (v) => update(() => selected = v),
              ),
            ],
          ),
        ),
      );
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      expect(selected, isEmpty);
      expect(find.text('Rennes'), findsOneWidget);
      await sprint.capture(t, 'rennes-position-zone-a-confirmer');
      await fixtures.tap(t, find.text('Utiliser cette zone'));
      expect(selected, ['fr_commune_35238']);
      await fixtures.tap(t, find.text('Choisir les zones'));
      expect(find.text('Rennes'), findsNWidgets(2));
      await fixtures.tap(t, find.text('Annuler'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'GPS confirms before adding, preserves existing zones, rejects duplicates and respects three-zone cap',
    (t) async {
      final location = LocationFake();
      var selected = <String>['plateau'];
      await sprint.page(
        t,
        StatefulBuilder(
          builder: (context, update) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              RequestZonePicker(
                choices: sprint.catalog.zones,
                selected: selected,
                onChanged: (v) => update(() => selected = v),
                locationRepository: location,
              ),
            ],
          ),
        ),
      );
      expect(location.reads, 0);
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      expect(selected, ['plateau']);
      expect(find.text('Confirme ta zone'), findsOneWidget);
      await sprint.capture(t, 'position-zone-a-confirmer');
      await fixtures.tap(t, find.text('Utiliser cette zone'));
      expect(selected, ['plateau', 'cocody']);
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      await fixtures.tap(t, find.text('Utiliser cette zone'));
      expect(selected, ['plateau', 'cocody']);
      selected = ['plateau', 'cocody', 'yop'];
      await t.pumpWidget(const SizedBox());
      location.suggestions = const [
        ReferenceChoice('bingerville', 'Bingerville'),
      ];
      await sprint.page(
        t,
        ListView(
          children: [
            RequestZonePicker(
              choices: sprint.catalog.zones,
              selected: selected,
              onChanged: (v) => selected = v,
              locationRepository: location,
            ),
          ],
        ),
      );
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Utiliser cette zone'),
            )
            .onPressed,
        isNull,
      );
      await fixtures.tap(t, find.text('Annuler'));
      expect(selected, ['plateau', 'cocody', 'yop']);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'GPS ambiguity requires a choice and failures keep the form intact at 320px with large text',
    (t) async {
      final location = LocationFake()
        ..suggestions = sprint.catalog.zones.take(2).toList();
      var selected = <String>['yop'];
      await sprint.page(
        t,
        ListView(
          children: [
            RequestZonePicker(
              choices: sprint.catalog.zones,
              selected: selected,
              onChanged: (v) => selected = v,
              locationRepository: location,
            ),
          ],
        ),
        width: 320,
        scale: 1.7,
      );
      await requests.tapForm(t, find.text('Utiliser ma position actuelle'));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Utiliser cette zone'),
            )
            .onPressed,
        isNull,
      );
      await requests.tapForm(t, find.text('Annuler'));
      expect(selected, ['yop']);
      location.failure = const RequestLocationFailure(
        'Localisation non autorisée. Choisis ta zone manuellement.',
      );
      await requests.tapForm(t, find.text('Utiliser ma position actuelle'));
      await sprint.capture(t, 'position-refusee-selection-conservee');
      await requests.tapForm(t, find.text('Continuer'));
      expect(selected, ['yop']);
      expect(t.takeException(), isNull);
    },
  );
}
