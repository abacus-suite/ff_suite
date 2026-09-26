import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/tile_cache.dart';
import '../core/services.dart';
import '../core/theme.dart';

/// CARTO basemaps: the clean, label-light look people know from Google Maps,
/// free to use with attribution and no API key.
const _voyagerTiles = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
const _darkTiles = 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png';
const _subdomains = ['a', 'b', 'c', 'd'];
const mapUserAgent = 'com.abs.fieldforce';

/// Kept for anything that still asks for a raw tile URL.
const osmTiles = _voyagerTiles;

/// The basemap: Google's own tiles when the office has set a key in Odoo,
/// otherwise the free CARTO basemap. A [preview] (small, not movable) map is
/// always free: Google is kept for the maps people actually work in.
class BaseMapLayer extends StatefulWidget {
  const BaseMapLayer({super.key, this.preview = false});

  final bool preview;

  @override
  State<BaseMapLayer> createState() => _BaseMapLayerState();
}

class _BaseMapLayerState extends State<BaseMapLayer> {
  String? _googleUrl;

  @override
  void initState() {
    super.initState();
    _loadGoogle();
  }

  Future<void> _loadGoogle() async {
    if (widget.preview || !Services.googleTiles.available) return;
    final url = await Services.googleTiles.urlTemplate();
    if (mounted && url != null) setState(() => _googleUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final google = Services.googleTiles.available ? _googleUrl : null;
    return TileLayer(
      urlTemplate: google ?? (dark ? _darkTiles : _voyagerTiles),
      subdomains: google == null ? _subdomains : const [],
      retinaMode: google == null && RetinaMode.isHighDensity(context),
      userAgentPackageName: mapUserAgent,
      // Tiles are kept on the phone; only tiles downloaded from Google are counted.
      tileProvider: CachedTileProvider(paid: google != null),
    );
  }
}

/// Google asks for its name on the map; OpenStreetMap and CARTO ask for theirs.
String mapCredit({bool preview = false}) =>
    !preview && Services.googleTiles.available ? 'Google' : '© OpenStreetMap · CARTO';

/// A map with the basemap, attribution and the controls people expect:
/// zoom buttons and a recentre button.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.children,
    this.center,
    this.fitPoints = const [],
    this.zoom = 13,
    this.interactive = true,
    this.controls = true,
    this.myLocation,
    this.borderRadius,
    this.padding = const EdgeInsets.all(48),
    this.controller,
    this.onCamera,
  });

  final List<Widget> children;
  final LatLng? center;

  /// When more than one point is given the map opens framed around all of them.
  final List<LatLng> fitPoints;
  final double zoom;
  final bool interactive;
  final bool controls;

  /// Where the recentre button takes the map. Falls back to the fit / centre.
  final LatLng? myLocation;
  final BorderRadius? borderRadius;
  final EdgeInsets padding;

  /// Drive the map from outside, for example to zoom into a cluster.
  final MapController? controller;

  /// Called whenever the map is moved or zoomed, with the camera as it stands.
  final void Function(MapCamera camera)? onCamera;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> with TickerProviderStateMixin {
  late final MapController _controller = widget.controller ?? MapController();

  LatLng get _fallbackCenter =>
      widget.center ?? (widget.fitPoints.isNotEmpty ? widget.fitPoints.first : const LatLng(20.5937, 78.9629));

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(3.0, 18.0));
  }

  void _recentre() {
    final target = widget.myLocation;
    if (target != null) {
      _controller.move(target, math.max(_controller.camera.zoom, 15));
    } else if (widget.fitPoints.length > 1) {
      _controller.fitCamera(CameraFit.coordinates(coordinates: widget.fitPoints, padding: widget.padding));
    } else {
      _controller.move(_fallbackCenter, widget.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _fallbackCenter,
            initialZoom: widget.zoom,
            initialCameraFit: widget.fitPoints.length > 1
                ? CameraFit.coordinates(coordinates: widget.fitPoints, padding: widget.padding)
                : null,
            onMapReady: () => widget.onCamera?.call(_controller.camera),
            onPositionChanged: (camera, _) => widget.onCamera?.call(camera),
            interactionOptions: InteractionOptions(
              flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
            ),
            backgroundColor: AppColors.background,
          ),
          children: [
            BaseMapLayer(preview: !widget.interactive),
            ...widget.children,
            _Attribution(preview: !widget.interactive),
          ],
        ),
        if (widget.controls)
          Positioned(
            right: 12,
            bottom: 28,
            child: Column(
              children: [
                _MapButton(icon: Icons.add_rounded, onTap: () => _zoomBy(1)),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.remove_rounded, onTap: () => _zoomBy(-1)),
                const SizedBox(height: 12),
                _MapButton(icon: Icons.my_location_rounded, onTap: _recentre, tint: AppColors.primary),
              ],
            ),
          ),
      ],
    );
    final radius = widget.borderRadius;
    return radius == null ? map : ClipRRect(borderRadius: radius, child: map);
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({this.preview = false});

  final bool preview;

  @override
  Widget build(BuildContext context) {
    // Only the map data credit, which Google and OpenStreetMap require - not
    // the "flutter_map" label SimpleAttributionWidget adds in front of it.
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(3)),
        child: Text(mapCredit(preview: preview), style: const TextStyle(fontSize: 8, color: Color(0xFF5B6478))),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap, this.tint});

  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: tint ?? AppColors.text),
        ),
      ),
    );
  }
}

/// A teardrop pin with a shadow — the shape a phone map is expected to use.
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.color,
    this.icon,
    this.initial,
    this.selected = false,
  });

  final Color color;
  final IconData? icon;
  final String? initial;
  final bool selected;

  static const size = Size(34, 44);

  @override
  Widget build(BuildContext context) {
    final scale = selected ? 1.18 : 1.0;
    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomCenter,
      child: CustomPaint(
        painter: _PinPainter(color),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Align(
            alignment: const Alignment(0, -0.45),
            child: initial != null
                ? Text(initial!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))
                : Icon(icon ?? Icons.place_rounded, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final head = Offset(size.width / 2, size.width / 2);
    final radius = size.width / 2;
    final tip = Offset(size.width / 2, size.height);
    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(head.dx - radius * 0.92, head.dy + radius * 0.75, head.dx - radius * 0.72, head.dy + radius * 0.2)
      ..arcToPoint(Offset(head.dx + radius * 0.72, head.dy + radius * 0.2),
          radius: Radius.circular(radius), clockwise: true, largeArc: true)
      ..quadraticBezierTo(head.dx + radius * 0.92, head.dy + radius * 0.75, tip.dx, tip.dy)
      ..close();
    canvas.drawShadow(path, Colors.black54, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}

/// A pin with a name chip above it, for markers people tap.
class MapPinWithLabel extends StatelessWidget {
  const MapPinWithLabel({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.initial,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? initial;
  final VoidCallback? onTap;
  final bool selected;

  /// Marker box that fits the chip and the pin.
  static const Size size = Size(150, 66);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 2),
          MapPin(color: color, icon: icon, initial: initial, selected: selected),
        ],
      ),
    );
  }
}

/// The blue "you are here" dot with a soft halo.
class MyLocationDot extends StatelessWidget {
  const MyLocationDot({super.key, this.color = AppColors.sky});

  final Color color;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.22)),
      child: Center(
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// A travelled path drawn as a wide line with a lighter casing under it, the way
/// navigation apps draw a route.
List<Polyline> travelPath(List<LatLng> points, {Color? color}) {
  if (points.length < 2) return const [];
  final line = color ?? AppColors.primary;
  return [
    Polyline(points: points, strokeWidth: 9, color: Colors.white.withValues(alpha: 0.85)),
    Polyline(points: points, strokeWidth: 5, color: line),
  ];
}
