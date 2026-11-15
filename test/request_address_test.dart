import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/requests/domain/request_location_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';
import 'package:foundi/features/requests/presentation/request_zone_picker.dart';
import 'requests_v5_test.dart' as requests;
import 'sprint25_test.dart' as sprint;
import 'widget_test.dart' as fixtures;

const rennes = ReferenceChoice(
  'fr_commune_35238',
  'Rennes',
  countryCode: 'FR',
  zoneType: 'commune',
);
const address = RequestInterventionAddress(
  line: '10 rue des Ateliers, 35000 Rennes, France',
  countryCode: 'FR',
);

class AddressLocationFake
    implements RequestLocationRepository, RequestAddressLocationRepository {
  RequestLocationFailure? failure;
  RequestDetectedLocation result = const RequestDetectedLocation(
    addressLine: '10 rue des Ateliers, 35000 Rennes, France',
    countryCode: 'FR',
    accuracyMeters: 12,
    hasStreet: true,
    hasNumber: true,
    zones: [rennes],
  );
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<ReferenceChoice>> suggest(List<ReferenceChoice> choices) async =>
      result.zones;
  @override
  Future<RequestDetectedLocation> locateAddress(
    List<ReferenceChoice> choices,
  ) async {
    if (failure != null) throw failure!;
    return result;
  }
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
  test(
    'draft only replaces an address explicitly, and public model reads confirmed projection',
    () {
      const draft = RequestDraft(
        categoryId: 'c',
        specialtyId: 's',
        zoneId: 'z',
        title: 'Titre',
        description: 'Description',
        interventionAddress: address,
      );
      expect(draft.toMap().containsKey('interventionAddress'), false);
      const confirmed = RequestDraft(
        categoryId: 'c',
        specialtyId: 's',
        zoneId: 'z',
        title: 'Titre',
        description: 'Description',
        interventionAddress: address,
        replaceInterventionAddress: true,
      );
      expect(confirmed.toMap()['interventionAddress'], address.toMap());
      const removed = RequestDraft(
        categoryId: 'c',
        specialtyId: 's',
        zoneId: 'z',
        title: 'Titre',
        description: 'Description',
        replaceInterventionAddress: true,
      );
      expect(removed.toMap().containsKey('interventionAddress'), true);
      expect(removed.toMap()['interventionAddress'], null);
    },
  );
  testWidgets(
    'GPS address requires explicit confirmation, permits correction, cancel preserves previous choices',
    (t) async {
      var selected = <String>[];
      RequestInterventionAddress? chosen;
      await sprint.page(
        t,
        StatefulBuilder(
          builder: (context, update) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const RequestHeading('Lieu de la demande'),
              RequestZonePicker(
                choices: const [rennes],
                selected: selected,
                interventionAddress: chosen,
                onChanged: (v) => update(() => selected = v),
                onAddressChanged: (v) => update(() => chosen = v),
                locationRepository: AddressLocationFake(),
              ),
            ],
          ),
        ),
      );
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      expect(chosen, null);
      expect(selected, isEmpty);
      expect(
        find.textContaining('cartes publiques et le détail'),
        findsOneWidget,
      );
      expect(find.textContaining('±12 m'), findsOneWidget);
      await sprint.capture(t, 'adresse-gps-confirmation');
      await fixtures.tap(t, find.text('Annuler'));
      expect(chosen, null);
      expect(selected, isEmpty);
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      await requests.fill(
        t,
        'requestInterventionAddressLine',
        '12 rue des Ateliers, 35000 Rennes, France',
      );
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('confirmRequestInterventionAddress')),
      );
      expect(chosen?.line, '12 rue des Ateliers, 35000 Rennes, France');
      expect(selected, [rennes.id]);
      expect(
        find.text('Visible sur les cartes publiques de ta demande.'),
        findsOneWidget,
      );
      await fixtures.tap(t, find.text('Retirer cette adresse'));
      expect(chosen, null);
      expect(selected, [rennes.id]);
      expect(t.takeException(), null);
    },
  );
  testWidgets(
    'manual address works after GPS refusal and direct address copy stays private',
    (t) async {
      RequestInterventionAddress? chosen;
      final location = AddressLocationFake()
        ..failure = const RequestLocationFailure('Localisation refusée.');
      await sprint.page(
        t,
        ListView(
          children: [
            RequestZonePicker(
              choices: const [rennes],
              selected: const [],
              onChanged: (_) {},
              onAddressChanged: (v) => chosen = v,
              locationRepository: location,
              publicAddress: false,
            ),
          ],
        ),
      );
      await fixtures.tap(t, find.text('Utiliser ma position actuelle'));
      await fixtures.tap(t, find.text('Saisir une adresse'));
      expect(
        find.textContaining('professionnel destinataire de ta demande privée'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cartes publiques et le détail'),
        findsNothing,
      );
      await requests.fill(
        t,
        'requestInterventionAddressLine',
        'Point de rendez-vous près de la mairie, Rennes',
      );
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('requestInterventionAddressCountry')),
      );
      await fixtures.tap(t, find.text('France').last);
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('confirmRequestInterventionAddress')),
      );
      expect(chosen?.countryCode, 'FR');
      expect(chosen?.line, contains('mairie'));
    },
  );
  testWidgets(
    'public card, preview and detail all display full chosen address, legacy card has none',
    (t) async {
      final r = FoundiRequest.fromMap('PublicAddressRequest01', {
        'title': 'Réparer une fuite dans la cuisine',
        'description':
            'Je cherche un plombier pour intervenir et vérifier les raccords.',
        'categoryLabel': 'Services à domicile',
        'specialtyLabel': 'Plomberie',
        'zoneLabel': 'Rennes',
        'status': 'published',
        'createdAt': DateTime(2026, 11, 15, 14, 30).millisecondsSinceEpoch,
        'authorPublicName': 'Awa Kouassi',
        'interventionAddress': {
          'line': address.line,
          'countryCode': address.countryCode,
        },
      });
      for (final view in [
        RequestCard(r, showDescription: true),
        RequestPreview(r),
        RequestContent(r),
      ]) {
        await sprint.page(
          t,
          ListView(
            padding: const EdgeInsets.all(20),
            children: [const RequestHeading('Explorer les demandes'), view],
          ),
        );
        expect(
          find.text('Adresse d’intervention : ${address.line}'),
          findsOneWidget,
        );
        if (view is RequestCard) {
          await sprint.capture(t, 'adresse-carte-publique');
        }
        if (view is RequestContent) {
          await sprint.capture(t, 'adresse-detail-demande');
        }
        expect(t.takeException(), null);
      }
      await sprint.page(t, RequestCard(sprint.request));
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    },
  );
  testWidgets(
    'composer publishes the corrected address only after public review',
    (t) async {
      final repo = requests.FakeRequests(),
          pro = fixtures.FakePro()..references = sprint.catalog;
      final location = AddressLocationFake()
        ..result = const RequestDetectedLocation(
          addressLine: 'Rue des Jardins, Cocody, Abidjan, Côte d’Ivoire',
          countryCode: 'CI',
          accuracyMeters: 30,
          hasStreet: true,
          zones: [ReferenceChoice('cocody', 'Cocody')],
        );
      await sprint.page(
        t,
        RequestComposer(
          repository: repo,
          catalog: pro,
          locationRepository: location,
          onExit: () {},
          onMine: () {},
          onOpen: (_) {},
        ),
      );
      await requests.fill(
        t,
        'requestDescription',
        'Une fuite sous mon évier nécessite une réparation.',
      );
      await requests.choose(t, 'requestCategory', 'Services à domicile');
      await requests.choose(t, 'requestSpecialty', 'Plomberie');
      await requests.tapForm(t, find.text('Utiliser ma position actuelle'));
      expect(
        find.textContaining('numéro ou la rue n’a pas pu être identifié'),
        findsOneWidget,
      );
      await requests.fill(
        t,
        'requestInterventionAddressLine',
        '10 rue des Jardins, Cocody, Abidjan, Côte d’Ivoire',
      );
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('confirmRequestInterventionAddress')),
      );
      expect(repo.publishedDraft, null);
      await requests.tapForm(t, find.text('Vérifier ma demande'));
      expect(
        find.text(
          'Adresse d’intervention : 10 rue des Jardins, Cocody, Abidjan, Côte d’Ivoire',
        ),
        findsOneWidget,
      );
      await sprint.capture(t, 'adresse-apercu-publication');
      await requests.tapForm(t, find.text('Publier ma demande'));
      expect(
        repo.publishedDraft?.interventionAddress?.line,
        '10 rue des Jardins, Cocody, Abidjan, Côte d’Ivoire',
      );
      expect(repo.publishedDraft?.replaceInterventionAddress, true);
      expect(
        repo.publishedDraft?.toMap()['interventionAddress']['confirmed'],
        true,
      );
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
    },
  );
}
