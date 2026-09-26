import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'photos.dart';
import 'services.dart';
import 'theme.dart';

/// The app's own camera, with the place and time shown across the bottom of
/// the viewfinder exactly as they will be written on the picture. People see
/// the tag before they shoot, so there is no doubt about what is recorded.
class GeoCameraScreen extends StatefulWidget {
  const GeoCameraScreen({super.key, this.selfie = false, this.title = 'Photo'});

  final bool selfie;
  final String title;

  @override
  State<GeoCameraScreen> createState() => _GeoCameraScreenState();
}

class _GeoCameraScreenState extends State<GeoCameraScreen> {
  CameraController? _camera;
  PhotoPlace? _place;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
    currentPlace(fresh: true).then((place) {
      if (mounted) setState(() => _place = place);
    });
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw 'No camera on this phone.';
      final wanted = widget.selfie ? CameraLensDirection.front : CameraLensDirection.back;
      final camera = cameras.firstWhere((c) => c.lensDirection == wanted, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      final stamped = await stampPhoto(bytes, place: _place ?? await currentPlace());
      if (mounted) Navigator.of(context).pop<Uint8List>(stamped);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (camera != null) CameraPreview(camera),
                if (camera == null)
                  Center(
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                          )
                        : const CircularProgressIndicator(color: Colors.white),
                  ),
                Positioned(left: 0, right: 0, bottom: 0, child: _tag()),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white38, width: 5),
                  ),
                  child: _busy
                      ? const Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 3))
                      : const Icon(Icons.camera_alt_rounded, color: Colors.black54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The same three lines the photo will carry, shown live on the viewfinder.
  Widget _tag() {
    final place = _place;
    return Container(
      width: double.infinity,
      color: const Color(0xAA000000),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white70),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place == null
                      ? 'Reading your location…'
                      : (place.address.isEmpty ? 'Location tagged' : place.address),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                if (place != null) ...[
                  Text(place.coordinates, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                  Text(place.stampedAt, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the app's camera from anywhere, without needing a context to hand.
Future<Uint8List?> openGeoCamera({bool selfie = false, String title = 'Photo'}) {
  final navigator = Services.navigatorKey.currentState;
  if (navigator == null) return Future.value(null);
  return navigator.push<Uint8List>(
    MaterialPageRoute(builder: (_) => GeoCameraScreen(selfie: selfie, title: title)),
  );
}
