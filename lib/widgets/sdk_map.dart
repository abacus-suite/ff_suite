import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;
import 'package:latlong2/latlong.dart';

import '../core/services.dart';
import '../core/theme.dart';

/// Google's own map, drawn by the phone.
///
/// Google does not charge for the map inside an Android or iOS app, so this is
/// the way the office gets Google's roads and shop names without a bill. It is
/// used when the office chose "Google map inside the app" and a key was built
/// into this app; everything else falls back to the free tiled map.
class SdkMap extends StatefulWidget {
  const SdkMap({
    super.key,
    required this.pins,
    this.path = const [],
    this.centre,
    this.zoom = 12,
    this.myLocation,
    this.circle,
    this.circleMetres = 0,
    this.interactive = true,
    this.onCameraIdle,
  });

  /// What to draw: a single shop, or a bubble holding several.
  final List<SdkPin> pins;

  /// A line, for the day's travel.
  final List<LatLng> path;
  final LatLng? centre;
  final double zoom;
  final LatLng? myLocation;

  /// A circle around one point, for a customer's geofence.
  final LatLng? circle;
  final double circleMetres;
  final bool interactive;

  /// Called with the zoom once the map settles, so bubbles can regroup.
  final void Function(double zoom, LatLng centre)? onCameraIdle;

  /// Whether this build of the app can draw Google's map at all.
  static bool get available =>
      (Services.auth.profile?.mapMode ?? '') == 'sdk' &&
      (Services.auth.profile?.googleMapsKey ?? '').isNotEmpty;

  @override
  State<SdkMap> createState() => _SdkMapState();
}

/// One thing on the map: a shop, or a bubble with a number in it.
class SdkPin {
  const SdkPin({
    required this.id,
    required this.point,
    this.count = 1,
    this.label,
    this.colour = AppColors.primary,
    this.onTap,
  });

  final String id;
  final LatLng point;
  final int count;
  final String? label;
  final Color colour;
  final VoidCallback? onTap;
}

class _SdkMapState extends State<SdkMap> {
  g.GoogleMapController? _controller;
  Set<g.Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _drawPins();
  }

  @override
  void didUpdateWidget(SdkMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) _drawPins();
  }

  Future<void> _drawPins() async {
    final markers = <g.Marker>{};
    for (final pin in widget.pins) {
      final icon = pin.count > 1
          ? await _bubbleIcon(pin.count, pin.colour)
          : await _pinIcon(pin.colour, pin.label);
      markers.add(g.Marker(
        markerId: g.MarkerId(pin.id),
        position: g.LatLng(pin.point.latitude, pin.point.longitude),
        icon: icon,
        // A bubble sits on its middle; a pin stands on its point.
        anchor: pin.count > 1 ? const Offset(0.5, 0.5) : const Offset(0.5, 1),
        infoWindow: g.InfoWindow.noText,
        onTap: pin.onTap,
      ));
    }
    if (mounted) setState(() => _markers = markers);
  }

  /// The bubble with a number: a soft halo, a deep blue face and a white ring.
  Future<g.BitmapDescriptor> _bubbleIcon(int count, Color colour) async {
    final text = count > 999 ? '999+' : '$count';
    final face = count >= 100 ? 74.0 : (count >= 50 ? 68.0 : (count >= 10 ? 62.0 : 56.0));
    final size = face + 26;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centre = Offset(size / 2, size / 2);
    final tint = Color.lerp(colour, AppColors.sky, 0.25) ?? colour;

    // Two soft rings, so the bubble lifts off the map.
    canvas.drawCircle(centre, face / 2 + 12, Paint()..color = colour.withValues(alpha: 0.10));
    canvas.drawCircle(centre, face / 2 + 6, Paint()..color = colour.withValues(alpha: 0.18));
    canvas.drawCircle(
      centre,
      face / 2,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(centre.dx - face / 2, centre.dy - face / 2),
          Offset(centre.dx + face / 2, centre.dy + face / 2),
          [tint, colour],
        ),
    );
    canvas.drawCircle(
      centre,
      face / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: Colors.white,
            fontSize: face * (text.length > 3 ? 0.28 : 0.36),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
    return _toIcon(recorder, size.round(), size.round());
  }

  /// One shop: its name on a white chip, over a teardrop pin with a shop glyph.
  Future<g.BitmapDescriptor> _pinIcon(Color colour, String? label) async {
    const pinWidth = 50.0;
    const pinHeight = 66.0;
    const gap = 5.0;

    TextPainter? name;
    if (label != null && label.isNotEmpty) {
      final short = label.length > 16 ? '${label.substring(0, 15)}…' : label;
      name = TextPainter(
        text: TextSpan(
          text: short,
          style: const TextStyle(
              color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final chipWidth = name == null ? 0.0 : name.width + 18;
    final chipHeight = name == null ? 0.0 : name.height + 10;
    final width = math.max(pinWidth, chipWidth) + 10;
    final height = pinHeight + (name == null ? 0 : chipHeight + gap);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (name != null) {
      final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH((width - chipWidth) / 2, 0, chipWidth, chipHeight),
        const Radius.circular(10),
      );
      canvas.drawShadow(ui.Path()..addRRect(chip), Colors.black26, 2, true);
      canvas.drawRRect(chip, Paint()..color = Colors.white);
      name.paint(canvas, Offset((width - name.width) / 2, 5));
    }

    final top = name == null ? 0.0 : chipHeight + gap;
    final head = Offset(width / 2, top + pinWidth / 2);
    final body = ui.Path()
      ..addOval(Rect.fromCircle(center: head, radius: pinWidth / 2 - 3))
      ..moveTo(head.dx - 10, head.dy + pinWidth / 2 - 9)
      ..quadraticBezierTo(head.dx, top + pinHeight, head.dx, top + pinHeight - 2)
      ..quadraticBezierTo(head.dx, top + pinHeight, head.dx + 10, head.dy + pinWidth / 2 - 9)
      ..close();
    canvas.drawShadow(body, Colors.black38, 2, true);
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(head.dx - 20, head.dy - 20),
          Offset(head.dx + 20, head.dy + 26),
          [Color.lerp(colour, Colors.white, 0.18) ?? colour, colour],
        ),
    );
    canvas.drawCircle(head, pinWidth / 2 - 8, Paint()..color = Colors.white);

    // The shop glyph, painted from the icon font the app already ships.
    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.storefront_rounded.codePoint),
        style: TextStyle(
          fontSize: 22,
          fontFamily: Icons.storefront_rounded.fontFamily,
          package: Icons.storefront_rounded.fontPackage,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(canvas, head - Offset(glyph.width / 2, glyph.height / 2));

    return _toIcon(recorder, width.round(), height.round());
  }

  Future<g.BitmapDescriptor> _toIcon(ui.PictureRecorder recorder, int width, int height) async {
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return g.BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final centre = widget.centre ??
        (widget.pins.isNotEmpty ? widget.pins.first.point : const LatLng(20.5937, 78.9629));
    return g.GoogleMap(
      initialCameraPosition: g.CameraPosition(
        target: g.LatLng(centre.latitude, centre.longitude),
        zoom: widget.zoom,
      ),
      markers: _markers,
      circles: widget.circle == null
          ? const {}
          : {
              g.Circle(
                circleId: const g.CircleId('geofence'),
                center: g.LatLng(widget.circle!.latitude, widget.circle!.longitude),
                radius: widget.circleMetres,
                fillColor: AppColors.primary.withValues(alpha: 0.12),
                strokeColor: AppColors.success,
                strokeWidth: 2,
              ),
            },
      polylines: widget.path.length < 2
          ? const {}
          : {
              g.Polyline(
                polylineId: const g.PolylineId('day'),
                points: [for (final p in widget.path) g.LatLng(p.latitude, p.longitude)],
                color: AppColors.primary,
                width: 5,
              ),
            },
      myLocationEnabled: widget.myLocation != null,
      myLocationButtonEnabled: widget.interactive && widget.myLocation != null,
      zoomControlsEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) => _controller = controller,
      onCameraIdle: () async {
        final camera = _controller;
        if (camera == null || widget.onCameraIdle == null) return;
        final zoom = await camera.getZoomLevel();
        final bounds = await camera.getVisibleRegion();
        final middle = LatLng(
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
        );
        widget.onCameraIdle!(zoom, middle);
      },
    );
  }

  /// Frames the map around everything it holds.
  Future<void> fit(List<LatLng> points) async {
    final controller = _controller;
    if (controller == null || points.isEmpty) return;
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    await controller.animateCamera(g.CameraUpdate.newLatLngBounds(
      g.LatLngBounds(
        southwest: g.LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
        northeast: g.LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
      ),
      48,
    ));
  }
}
