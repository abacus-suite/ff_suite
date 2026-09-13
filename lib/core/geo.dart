import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'permissions.dart';
import 'services.dart';

/// Fresh GPS fix for check-ins. Throws a user-readable message on failure.
Future<Position> currentPosition() async {
  final error = await PermissionsHelper.ensureLocation();
  if (error != null) throw error;
  final pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      timeLimit: Duration(seconds: 25),
    ),
  );
  if (pos.isMocked && !(Services.auth.profile?.allowMock ?? false)) {
    throw 'A fake GPS app was detected. Disable it to continue.';
  }
  return pos;
}

/// Cached position for sorting lists by distance. Never prompts.
Future<Position?> lastKnownPosition() async {
  try {
    return await Geolocator.getLastKnownPosition();
  } catch (_) {
    return null;
  }
}

String fmtDistance(num? metres) {
  if (metres == null) return '';
  return metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';
}

Future<void> openDirections(num lat, num lng) async {
  await launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> callPhone(String phone) async {
  await launchUrl(Uri(scheme: 'tel', path: phone));
}
