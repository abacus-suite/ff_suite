import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelper {
  /// Returns an error message, or null when location can be used.
  static Future<String?> ensureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on location (GPS) to continue.';
    }
    final status = await Permission.locationWhenInUse.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return 'Allow location permission in Settings, then try again.';
    }
    if (!status.isGranted) return 'Location permission is required to punch.';
    return null;
  }

  /// Best effort: background location, notifications and battery exemption.
  /// Returns false when background location was not granted.
  static Future<bool> ensureBackgroundTracking() async {
    await Permission.notification.request();
    final always = await Permission.locationAlways.request();
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    return always.isGranted;
  }
}
