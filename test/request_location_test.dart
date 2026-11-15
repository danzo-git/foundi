import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/requests/data/device_request_location_repository.dart';
import 'package:foundi/features/requests/domain/request_location_repository.dart';

const zones = [
  ReferenceChoice('ci', 'Côte d’Ivoire', zoneType: 'country'),
  ReferenceChoice('abidjan', 'Abidjan', zoneType: 'city'),
  ReferenceChoice(
    'cocody',
    'Côte d’Ivoire › Abidjan › Cocody',
    geographicName: 'Cocody',
    zoneType: 'commune',
  ),
  ReferenceChoice('plateau', 'Plateau'),
  ReferenceChoice('intervention', 'Cocody', zoneType: 'intervention'),
];
const place = Placemark(
  isoCountryCode: 'CI',
  locality: 'Abidjan',
  subLocality: 'Cocody',
);
Position point({
  double accuracy = 60,
  DateTime? timestamp,
  double latitude = 5.35,
  double longitude = -3.98,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
void main() {
  test(
    'invalid coordinates are rejected before calling the native geocoder',
    () async {
      for (final p in [
        point(latitude: double.nan),
        point(longitude: double.infinity),
        point(latitude: 91),
        point(longitude: 181),
      ]) {
        var geocoded = false;
        final service = DeviceRequestLocationRepository(
          supported: true,
          servicesEnabled: () async => true,
          permission: () async => LocationPermission.whileInUse,
          readPosition: () async => p,
          geocode: (_, _) async {
            geocoded = true;
            return [place];
          },
        );
        await expectLater(
          service.locateAddress(zones),
          throwsA(isA<RequestLocationFailure>()),
        );
        expect(geocoded, false);
      }
    },
  );
  test(
    'French number, road, postcode and city form a readable confirmed-address suggestion',
    () {
      final value = detectedAddress(
        const Placemark(
          isoCountryCode: 'FR',
          subThoroughfare: '10',
          thoroughfare: 'rue des Ateliers',
          street: '10 rue des Ateliers',
          postalCode: '35000',
          locality: 'Rennes',
          country: 'France',
        ),
        8,
        [],
      );
      expect(value.addressLine, '10 rue des Ateliers, 35000 Rennes, France');
      expect(value.hasStreet, true);
      expect(value.hasNumber, true);
      expect(value.accuracyMeters, 8);
      final alreadyNumbered = detectedAddress(
        const Placemark(
          isoCountryCode: 'FR',
          subThoroughfare: '10',
          thoroughfare: '10 rue des Ateliers',
          locality: 'Rennes',
        ),
        12,
        [],
      );
      expect(
        alreadyNumbered.addressLine,
        '10 rue des Ateliers, Rennes, France',
      );
    },
  );
  test(
    'Ivorian street without number and coarse city results never invent street details',
    () {
      final value = detectedAddress(
        const Placemark(
          isoCountryCode: 'CI',
          thoroughfare: 'Rue des Jardins',
          subLocality: 'Cocody',
          locality: 'Abidjan',
        ),
        35,
        [],
      );
      expect(
        value.addressLine,
        'Rue des Jardins, Cocody, Abidjan, Côte d’Ivoire',
      );
      expect(value.hasStreet, true);
      expect(value.hasNumber, false);
      final coarse = detectedAddress(
        const Placemark(
          isoCountryCode: 'FR',
          street: 'Rennes',
          locality: 'Rennes',
        ),
        500,
        [],
      );
      expect(coarse.addressLine, 'Rennes, France');
      expect(coarse.hasStreet, false);
      expect(coarse.hasNumber, false);
      final numberOnly = detectedAddress(
        const Placemark(
          isoCountryCode: 'FR',
          street: '10',
          subThoroughfare: '10',
          locality: 'Rennes',
        ),
        20,
        [],
      );
      expect(numberOnly.addressLine, 'Rennes, France');
      expect(numberOnly.hasStreet, false);
    },
  );
  test('full street fallback avoids repeating city, postcode and country', () {
    final value = detectedAddress(
      const Placemark(
        isoCountryCode: 'FR',
        street: '10 rue des Ateliers, 35000 Rennes, France',
        postalCode: '35000',
        locality: 'Rennes',
      ),
      10,
      [],
    );
    expect(value.addressLine, '10 rue des Ateliers, 35000 Rennes, France');
  });
  test(
    'exact address can be suggested outside Foundi catalogue without inventing a zone',
    () async {
      final service = DeviceRequestLocationRepository(
        supported: true,
        servicesEnabled: () async => true,
        permission: () async => LocationPermission.whileInUse,
        readPosition: () async => point(),
        geocode: (_, _) async => const [
          Placemark(
            isoCountryCode: 'FR',
            thoroughfare: 'rue des Ateliers',
            subThoroughfare: '10',
            postalCode: '75000',
            locality: 'Paris',
          ),
        ],
      );
      final result = await service.locateAddress(zones);
      expect(result.addressLine, '10 rue des Ateliers, 75000 Paris, France');
      expect(result.zones, isEmpty);
    },
  );
  test(
    'address and zones come from the same geocoder result and never mix countries',
    () async {
      final service = DeviceRequestLocationRepository(
        supported: true,
        servicesEnabled: () async => true,
        permission: () async => LocationPermission.whileInUse,
        readPosition: () async => point(),
        geocode: (_, _) async => const [
          Placemark(
            isoCountryCode: 'FR',
            locality: 'Paris',
            thoroughfare: 'rue des Ateliers',
          ),
          place,
        ],
      );
      final result = await service.locateAddress(zones);
      expect(result.countryCode, 'FR');
      expect(result.zones, isEmpty);
      expect(result.addressLine, contains('Paris'));
    },
  );
  test(
    'Rennes is matched in France only and legacy untagged zones stay Ivorian',
    () {
      const choices = [
        ...zones,
        ReferenceChoice(
          'fr_commune_35238',
          'Rennes',
          countryCode: 'FR',
          zoneType: 'commune',
        ),
        ReferenceChoice(
          'ci-rennes',
          'Rennes',
          countryCode: 'CI',
          zoneType: 'commune',
        ),
      ];
      expect(
        matchLocationZones(choices, const [
          Placemark(
            isoCountryCode: 'FR',
            locality: 'Rennes',
            subLocality: 'Centre',
          ),
        ]).map((z) => z.id),
        ['fr_commune_35238'],
      );
      expect(
        matchLocationZones(choices, const [
          Placemark(isoCountryCode: 'CI', locality: 'Rennes'),
        ]).map((z) => z.id),
        ['ci-rennes'],
      );
      expect(
        matchLocationZones(choices, const [
          Placemark(isoCountryCode: 'FR', locality: 'Paris'),
        ]),
        isEmpty,
      );
      expect(
        matchLocationZones(choices, const [
          Placemark(
            isoCountryCode: 'FR',
            locality: 'Cesson-Sévigné',
            subAdministrativeArea: 'Rennes',
            administrativeArea: 'Bretagne',
          ),
        ]),
        isEmpty,
      );
      expect(
        matchLocationZones(choices, const [
          Placemark(isoCountryCode: 'BE', locality: 'Rennes'),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'French country metadata is inherited, conflicting parents are hidden, CI legacy remains compatible',
    () {
      final choices = activeGeographicChoices([
        {'id': 'fr', 'label': 'France', 'countryCode': 'FR', 'type': 'country'},
        {'id': 'r', 'label': 'Rennes', 'type': 'commune', 'parentId': 'fr'},
        {
          'id': 'wrong',
          'label': 'Incohérent',
          'parentId': 'fr',
          'countryCode': 'CI',
        },
        {'id': 'legacy', 'label': 'Cocody'},
      ]);
      expect(choices.map((z) => z.id), ['fr', 'r', 'legacy']);
      expect(choices.singleWhere((z) => z.id == 'r').countryCode, 'FR');
      expect(choices.singleWhere((z) => z.id == 'legacy').countryCode, 'CI');
    },
  );
  test(
    'device suggestion works for Rennes but does not replace other French cities with Rennes',
    () async {
      const choices = [
        ReferenceChoice(
          'fr_commune_35238',
          'Rennes',
          countryCode: 'FR',
          zoneType: 'commune',
        ),
      ];
      DeviceRequestLocationRepository service(String city) =>
          DeviceRequestLocationRepository(
            supported: true,
            servicesEnabled: () async => true,
            permission: () async => LocationPermission.whileInUse,
            readPosition: () async => point(),
            geocode: (_, _) async => [
              Placemark(isoCountryCode: 'FR', locality: city),
            ],
          );
      expect(
        (await service('Rennes').suggest(choices)).single.id,
        'fr_commune_35238',
      );
      await expectLater(
        service('Paris').suggest(choices),
        throwsA(isA<RequestLocationFailure>()),
      );
    },
  );
  test(
    'matches only active catalogue names, preferring the specific commune over the city',
    () {
      expect(matchLocationZones(zones, [place]).map((z) => z.id), ['cocody']);
      expect(
        matchLocationZones(zones, [
          const Placemark(isoCountryCode: 'FR', locality: 'Plateau'),
        ]),
        isEmpty,
      );
      expect(
        matchLocationZones(zones, [
          const Placemark(isoCountryCode: 'CI', subLocality: 'Cocody Est'),
        ]).map((z) => z.id),
        isEmpty,
      );
      expect(normalizeZoneName('Port-Bouët'), 'port bouet');
    },
  );
  test(
    'ambiguous catalogue labels remain explicit choices without guessing a hierarchy',
    () {
      expect(
        matchLocationZones(
          [...zones, const ReferenceChoice('other-cocody', 'Région › Cocody')],
          [place],
        ).map((z) => z.id),
        ['cocody', 'other-cocody'],
      );
    },
  );
  test(
    'one-shot location requests permission only on demand and passes coordinates solely to native geocoding',
    () async {
      int permissions = 0, positions = 0, geocodes = 0;
      final service = DeviceRequestLocationRepository(
        supported: true,
        servicesEnabled: () async => true,
        permission: () async => LocationPermission.denied,
        requestPermission: () async {
          permissions++;
          return LocationPermission.whileInUse;
        },
        readPosition: () async {
          positions++;
          return point();
        },
        geocode: (lat, lng) async {
          expect(lat, 5.35);
          expect(lng, -3.98);
          geocodes++;
          return [place];
        },
      );
      expect(permissions, 0);
      expect(positions, 0);
      expect((await service.suggest(zones)).single.id, 'cocody');
      expect([permissions, positions, geocodes], [1, 1, 1]);
    },
  );
  for (final permission in [
    LocationPermission.denied,
    LocationPermission.deniedForever,
  ]) {
    test('permission $permission leaves the device position unread', () async {
      final service = DeviceRequestLocationRepository(
        supported: true,
        servicesEnabled: () async => true,
        permission: () async => permission,
        requestPermission: () async => permission,
        readPosition: () async => throw StateError('Must not locate'),
      );
      await expectLater(
        service.suggest(zones),
        throwsA(
          isA<RequestLocationFailure>().having(
            (e) => e.settings,
            'settings',
            permission == LocationPermission.deniedForever,
          ),
        ),
      );
    });
  }
  test(
    'disabled location, stale/inaccurate fix, outside CI, unknown names and timeouts fall back safely',
    () async {
      Future<void> fails({
        bool enabled = true,
        Position? position,
        List<Placemark> places = const [place],
        bool timeout = false,
      }) async {
        final service = DeviceRequestLocationRepository(
          supported: true,
          servicesEnabled: () async => enabled,
          permission: () async => LocationPermission.whileInUse,
          readPosition: () async {
            if (timeout) throw TimeoutException('timeout');
            return position ?? point();
          },
          geocode: (_, _) async => places,
        );
        await expectLater(
          service.suggest(zones),
          throwsA(isA<RequestLocationFailure>()),
        );
      }

      await fails(enabled: false);
      await fails(position: point(accuracy: 3000));
      await fails(
        position: point(
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      await fails(
        places: const [Placemark(isoCountryCode: 'FR', locality: 'Paris')],
      );
      await fails(
        places: const [Placemark(isoCountryCode: 'CI', locality: 'Unlisted')],
      );
      await fails(timeout: true);
    },
  );
}
