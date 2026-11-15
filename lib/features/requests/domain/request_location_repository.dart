import '../../professional/domain/professional_repository.dart';

class RequestLocationFailure implements Exception {
  const RequestLocationFailure(this.message, {this.settings = false});
  final String message;
  final bool settings;
}

abstract interface class RequestLocationRepository {
  Future<List<ReferenceChoice>> suggest(List<ReferenceChoice> choices);
  Future<void> openSettings();
}

class RequestInterventionAddress {
  const RequestInterventionAddress({
    required this.line,
    required this.countryCode,
  });
  final String line, countryCode;
  Map<String, dynamic> toMap() => {
    'line': line.trim(),
    'countryCode': countryCode,
    'confirmed': true,
  };
  factory RequestInterventionAddress.fromMap(Map<String, dynamic> value) =>
      RequestInterventionAddress(
        line: value['line'] as String,
        countryCode: value['countryCode'] as String,
      );
}

class RequestDetectedLocation {
  const RequestDetectedLocation({
    this.addressLine = '',
    this.countryCode,
    this.accuracyMeters = 0,
    this.hasStreet = false,
    this.hasNumber = false,
    this.zones = const [],
  });
  final String addressLine;
  final String? countryCode;
  final double accuracyMeters;
  final bool hasStreet, hasNumber;
  final List<ReferenceChoice> zones;
}

abstract interface class RequestAddressLocationRepository {
  Future<RequestDetectedLocation> locateAddress(List<ReferenceChoice> choices);
}
