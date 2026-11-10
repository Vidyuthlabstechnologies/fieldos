/// One-shot GPS fix for attendance punch-in and setting a site location.
/// Foreground only, nothing tracked in the background.
library;

import 'package:geolocator/geolocator.dart';

import 'package:fieldos_mobile/l10n/language.dart';

class LocationFix {
  const LocationFix(this.lat, this.lng, this.accuracyM);
  final double lat;
  final double lng;
  final double accuracyM;
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocationService {
  /// Asks for permission if needed, then reads the current position.
  /// Throws [LocationUnavailable] with a message a site supervisor can act
  /// on (turn on GPS, allow location) instead of a platform error.
  Future<LocationFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationUnavailable(tr('Location is turned off. Turn on GPS and try again.'));
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationUnavailable(tr('Location permission was not given.'));
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailable(tr('Location is blocked for FieldOS. Allow it in Android settings.'));
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    return LocationFix(p.latitude, p.longitude, p.accuracy);
  }
}
