import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../core/services.dart';
import '../core/theme.dart';
import 'map.dart';

/// The place the phone is at: a small map with a pin on it (tap the card to open it in Google Maps), and under it
/// the address read from that position - street, area, city, state, PIN code - as plain text that can still be
/// edited. The map is only for showing the spot; it cannot be dragged. [onPlace] is told the point and what the
/// lookup found; [onRefresh] reads the phone's position again.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.start,
    required this.controller,
    required this.onPlace,
    this.onRefresh,
    this.height = 150,
    this.label = 'Location',
  });

  final LatLng start;
  final TextEditingController controller;
  final void Function(LatLng point, Map<String, dynamic> place) onPlace;
  final VoidCallback? onRefresh;
  final double height;
  final String label;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  bool _loading = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _fetch(widget.start);
  }

  @override
  void didUpdateWidget(LocationPicker old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start) _fetch(widget.start);
  }

  Future<void> _fetch(LatLng point) async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    Map<String, dynamic> place = {};
    try {
      place = await Services.api.get('/api/v1/geo/place', query: {'lat': point.latitude, 'lng': point.longitude})
          as Map<String, dynamic>;
      if (!mounted || widget.start != point) return;
      final line = asText(place['formatted']);
      if (line != null) {
        widget.controller.text = line;
      } else {
        _problem = 'No address found here. Type the location.';
      }
    } catch (_) {
      if (mounted && widget.start == point) _problem = 'Could not read the address. Type the location.';
    } finally {
      if (mounted && widget.start == point) {
        setState(() => _loading = false);
        widget.onPlace(point, place);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.start;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: widget.height,
          child: Stack(children: [
            AppMap(
              center: point,
              zoom: 16,
              interactive: false,
              controls: false,
              children: [
                MarkerLayer(
                  alignment: Alignment.topCenter,
                  markers: [
                    Marker(
                      point: point,
                      width: MapPin.size.width,
                      height: MapPin.size.height,
                      alignment: Alignment.topCenter,
                      child: const MapPin(color: AppColors.danger, icon: Icons.place_rounded),
                    ),
                  ],
                ),
              ],
            ),
            // The whole card opens Google Maps at the pin.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: () => openDirections(point.latitude, point.longitude)),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
                  child: Text(_loading ? 'Finding the address…' : 'Tap to open in Google Maps',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            if (widget.onRefresh != null)
              Positioned(
                right: 8,
                top: 8,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Read my location again',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.my_location_rounded, size: 20, color: AppColors.primary),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: widget.controller,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: _problem,
          helperStyle: const TextStyle(color: AppColors.warning),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.place_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        ),
      ),
    ]);
  }
}
