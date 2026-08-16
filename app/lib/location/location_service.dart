import 'package:geolocator/geolocator.dart';

/// Device location WITHOUT Google Play Services: forces the platform
/// LocationManager (GPS/network) instead of the fused provider, which is
/// Play-Services-only. Core to the Google-free requirement.
class LocationService {
  /// Returns (lat, lon), or null when permission is denied or no fix is
  /// available within the time limit. Never throws.
  static Future<(double, double)?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          forceLocationManager: true, // no fused provider = no Play Services
          timeLimit: const Duration(seconds: 10),
        ),
      );
      return (p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}
