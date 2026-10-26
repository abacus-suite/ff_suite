import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'permissions.dart';
import 'services.dart';

/// Fresh GPS fix for check-ins. Throws a user-readable message on failure.
Future<Position> currentPosition({bool recentOk = false}) async {
  final error = await PermissionsHelper.ensureLocation();
  if (error != null) throw error;
  if (recentOk) {
    // Lists sorted by distance do not need a fresh fix: a recent one answers at once.
    final last = await lastKnownPosition();
    if (last != null &&
        !last.isMocked &&
        last.accuracy <= 150 &&
        DateTime.now().difference(last.timestamp).inMinutes < 10) {
      return last;
    }
  }
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

/// Metres from [here] to a customer: by the phone's own fix when the customer has a location,
/// else what the server measured (distance_m, or distance_km).
double? metresTo(Position? here, Map<String, dynamic> c) {
  final lat = c['lat'], lng = c['lng'];
  if (here != null && lat is num && lng is num) {
    return Geolocator.distanceBetween(here.latitude, here.longitude, lat.toDouble(), lng.toDouble());
  }
  final metres = c['distance_m'];
  if (metres is num) return metres.toDouble();
  final km = c['distance_km'];
  return km is num ? km * 1000.0 : null;
}

/// Nearest first; customers with no known distance keep their order at the end.
List<Map<String, dynamic>> nearestFirst(List<Map<String, dynamic>> list, Position? here) {
  final measured = [for (final (i, c) in list.indexed) (i, c, metresTo(here, c))];
  measured.sort((a, b) {
    if (a.$3 == null || b.$3 == null) {
      return a.$3 == null && b.$3 == null ? a.$1.compareTo(b.$1) : (a.$3 == null ? 1 : -1);
    }
    final by = a.$3!.compareTo(b.$3!);
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  return [for (final m in measured) m.$2];
}

String fmtDistance(num? metres) {
  if (metres == null) return '';
  return metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';
}

Future<void> openDirections(num lat, num lng) async {
  // Directions are free either way. On open maps the phone offers whichever
  // navigation app the person uses; Google's link is the fallback.
  if (Services.auth.profile?.mapProvider != 'google') {
    final opened = await launchUrl(Uri.parse('geo:$lat,$lng?q=$lat,$lng'), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (opened) return;
  }
  await launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> callPhone(String phone) async {
  await launchUrl(Uri(scheme: 'tel', path: phone));
}

/// Opens the phone's dialler with a customer's number ready to call.
Future<void> callNumber(String number) async {
  final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return;
  await launchUrl(Uri.parse('tel:$cleaned'), mode: LaunchMode.externalApplication);
}
