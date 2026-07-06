import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

enum LocationError { serviceDisabled, permissionDenied, permissionPermanentlyDenied, timeout, unknown }

class LocationResult {
  final double? lat;
  final double? lng;
  final String? errorMessage;
  final LocationError? errorCode;

  const LocationResult.success({required double lat, required double lng})
      : lat = lat, lng = lng, errorMessage = null, errorCode = null;

  const LocationResult.failure(this.errorCode, this.errorMessage)
      : lat = null, lng = null;

  bool get hasLocation => lat != null && lng != null;
  bool get isPermanentlyDenied => errorCode == LocationError.permissionPermanentlyDenied;
  bool get isServiceDisabled => errorCode == LocationError.serviceDisabled;
}

class LocationService {
  /// Returns GPS coords. Location is MANDATORY — submissions must not proceed without it.
  static Future<LocationResult> getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult.failure(
          LocationError.serviceDisabled,
          'Location services are turned off. Please enable GPS in device settings.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(
          LocationError.permissionPermanentlyDenied,
          'Location permission is permanently denied. Please enable it in App Settings.',
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failure(
          LocationError.permissionDenied,
          'Location permission is required to submit a concern.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      debugPrint('[JanMat] GPS: ${position.latitude}, ${position.longitude}');
      return LocationResult.success(lat: position.latitude, lng: position.longitude);
    } on Exception catch (e) {
      debugPrint('[JanMat] Location error: $e');
      return LocationResult.failure(LocationError.unknown, e.toString());
    }
  }

  /// Opens device location settings so user can enable GPS.
  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Opens app settings so user can grant location permission.
  static Future<void> openAppSettings() => Geolocator.openAppSettings();
}
