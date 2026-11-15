import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../professional/domain/professional_repository.dart';
import '../domain/request_location_repository.dart';

String normalizeZoneName(String value) {
  const from = 'àâäáãåçèéêëìíîïñòóôöõùúûüýÿœ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyo';
  var result = value.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

// The native geocoder identifies names, not Foundi boundaries. Always confirm a suggestion.
List<ReferenceChoice> matchLocationZones(
  List<ReferenceChoice> choices,
  List<Placemark> places,
) {
  final matches = <String, ({ReferenceChoice choice, int rank})>{};
  for (final place in places.take(5)) {
    final country = place.isoCountryCode?.toUpperCase();
    if (!const ['CI', 'FR'].contains(country)) continue;
    final names = [
      place.subLocality,
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
    ];
    for (final choice in choices) {
      if (choice.zoneType == 'country' ||
          choice.zoneType == 'intervention' ||
          (choice.countryCode ?? 'CI') != country) {
        continue;
      }
      final name = normalizeZoneName(
        choice.geographicName ?? choice.label.split(' › ').last,
      );
      if (name.isEmpty) continue;
      // A French arrondissement may carry its main city's name while covering
      // neighbouring communes. Match the municipality itself for Rennes.
      final localNames =
          country == 'FR' && const ['commune', 'city'].contains(choice.zoneType)
          ? [place.locality]
          : names;
      final index = localNames.indexWhere(
        (n) => n != null && normalizeZoneName(n) == name,
      );
      if (index < 0) continue;
      final rank = 4 - index;
      if ((matches[choice.id]?.rank ?? 0) < rank) {
        matches[choice.id] = (choice: choice, rank: rank);
      }
    }
  }
  if (matches.isEmpty) return [];
  final best = matches.values
      .map((v) => v.rank)
      .reduce((a, b) => a > b ? a : b);
  return matches.values
      .where((v) => v.rank == best)
      .map((v) => v.choice)
      .take(12)
      .toList();
}

String _addressPart(String? value) {
  final result = (value ?? '')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return const ['null', 'undefined'].contains(result.toLowerCase())
      ? ''
      : result;
}

RequestDetectedLocation detectedAddress(
  Placemark place,
  double accuracy,
  List<ReferenceChoice> zones,
) {
  final number = _addressPart(place.subThoroughfare),
      road = _addressPart(place.thoroughfare);
  var street = road.isEmpty ? _addressPart(place.street) : road;
  if (normalizeZoneName(street) == normalizeZoneName(number) ||
      street == _addressPart(place.locality) ||
      street == _addressPart(place.subLocality)) {
    street = '';
  }
  if (number.isNotEmpty &&
      street.isNotEmpty &&
      normalizeZoneName(street) != normalizeZoneName(number) &&
      !normalizeZoneName(street).startsWith('${normalizeZoneName(number)} ')) {
    street = '$number $street';
  }
  final country = place.isoCountryCode?.toUpperCase();
  final pieces = <String>[];
  void add(String part) {
    if (part.isNotEmpty &&
        !pieces.any(
          (v) => normalizeZoneName(v).contains(normalizeZoneName(part)),
        )) {
      pieces.add(part);
    }
  }

  add(street);
  add(_addressPart(place.subLocality));
  add(
    [
      _addressPart(place.postalCode),
      _addressPart(place.locality),
    ].where((v) => v.isNotEmpty).join(' '),
  );
  add(
    country == 'FR'
        ? 'France'
        : country == 'CI'
        ? 'Côte d’Ivoire'
        : _addressPart(place.country),
  );
  final hasStreet =
      street.isNotEmpty &&
      street != _addressPart(place.locality) &&
      street != _addressPart(place.subLocality);
  return RequestDetectedLocation(
    addressLine: pieces.join(', '),
    countryCode: country,
    accuracyMeters: accuracy,
    hasStreet: hasStreet,
    hasNumber: number.isNotEmpty || RegExp(r'^\d+').hasMatch(street),
    zones: zones,
  );
}

class DeviceRequestLocationRepository
    implements RequestLocationRepository, RequestAddressLocationRepository {
  DeviceRequestLocationRepository({
    Future<bool> Function()? servicesEnabled,
    Future<LocationPermission> Function()? permission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? readPosition,
    Future<List<Placemark>> Function(double, double)? geocode,
    bool? supported,
  }) : _services = servicesEnabled ?? Geolocator.isLocationServiceEnabled,
       _permission = permission ?? Geolocator.checkPermission,
       _request = requestPermission ?? Geolocator.requestPermission,
       _position =
           readPosition ??
           (() => Geolocator.getCurrentPosition(
             locationSettings: const LocationSettings(
               accuracy: LocationAccuracy.high,
               timeLimit: Duration(seconds: 20),
             ),
           )),
       _geocode =
           geocode ??
           ((lat, lng) => Geocoding(
             locale: const Locale('fr'),
           ).placemarkFromCoordinates(lat, lng)),
       _supported =
           supported ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS));
  final Future<bool> Function() _services;
  final Future<LocationPermission> Function() _permission, _request;
  final Future<Position> Function() _position;
  final Future<List<Placemark>> Function(double, double) _geocode;
  final bool _supported;
  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<List<ReferenceChoice>> suggest(List<ReferenceChoice> choices) async {
    final location = await locateAddress(choices);
    if (location.zones.isEmpty) {
      throw const RequestLocationFailure(
        'Aucune zone du catalogue ne correspond avec certitude à ta position. Choisis tes zones manuellement.',
      );
    }
    return location.zones;
  }

  @override
  Future<RequestDetectedLocation> locateAddress(
    List<ReferenceChoice> choices,
  ) async {
    if (!_supported) {
      throw const RequestLocationFailure(
        'La suggestion par position est disponible sur Android et iPhone. Choisis tes zones manuellement ici.',
      );
    }
    try {
      if (!await _services()) {
        throw const RequestLocationFailure(
          'Active la localisation de ton téléphone, puis réessaie.',
        );
      }
      var permission = await _permission();
      if (permission == LocationPermission.denied) {
        permission = await _request();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const RequestLocationFailure(
          'La localisation est refusée dans les réglages de Foundi. Tu peux l’autoriser ou choisir tes zones manuellement.',
          settings: true,
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const RequestLocationFailure(
          'Localisation non autorisée. Tu peux continuer en choisissant tes zones manuellement.',
        );
      }
      final position = await _position().timeout(const Duration(seconds: 22));
      final age = DateTime.now().difference(position.timestamp);
      if (!position.accuracy.isFinite ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          position.accuracy < 0 ||
          position.accuracy > 1000 ||
          age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -10)) {
        throw const RequestLocationFailure(
          'La position n’est pas assez précise ou récente. Réessaie ou choisis tes zones manuellement.',
        );
      }
      final places = await _geocode(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 12));
      if (places.isNotEmpty &&
          !places.any(
            (p) => const ['CI', 'FR'].contains(p.isoCountryCode?.toUpperCase()),
          )) {
        throw const RequestLocationFailure(
          'Foundi propose les zones de Côte d’Ivoire et Rennes en France. Choisis une zone du catalogue manuellement.',
        );
      }
      final place = places
          .where(
            (p) => const ['CI', 'FR'].contains(p.isoCountryCode?.toUpperCase()),
          )
          .firstOrNull;
      if (place == null) {
        return RequestDetectedLocation(accuracyMeters: position.accuracy);
      }
      // Do not combine a street from one result with a zone from another result.
      return detectedAddress(
        place,
        position.accuracy,
        matchLocationZones(choices, [place]),
      );
    } on RequestLocationFailure {
      rethrow;
    } on TimeoutException {
      throw const RequestLocationFailure(
        'La recherche de position prend trop de temps. Réessaie ou choisis tes zones manuellement.',
      );
    } catch (_) {
      throw const RequestLocationFailure(
        'Impossible de reconnaître ta zone pour le moment. Vérifie ta connexion ou choisis tes zones manuellement.',
      );
    }
  }
}
