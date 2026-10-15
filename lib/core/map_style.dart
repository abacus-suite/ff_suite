import 'package:flutter/widgets.dart';

/// The look every map in the app shares: a pale, nearly colourless basemap with white streets and
/// no shop or business clutter, so the pins and the routes are what the eye finds.
///
/// Google reads this as map styling (the SDK map and the Map Tiles session); the free OpenStreetMap
/// tiles cannot be styled, so they are desaturated and lightened as they are drawn.
const uberMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f3f4f6"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6b7280"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#eceef1"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#f3f4f6"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#e5ebe7"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e5e7eb"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e5e7eb"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#d1d5db"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#d9dee5"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]}
]
''';

/// Colour matrix that turns OpenStreetMap's tiles into the same pale, quiet map.
const _paleMap = ColorFilter.matrix(<double>[
  0.30, 0.45, 0.10, 0, 52,
  0.30, 0.45, 0.10, 0, 52,
  0.30, 0.45, 0.10, 0, 54,
  0, 0, 0, 1, 0,
]);

Widget uberTileBuilder(BuildContext context, Widget tile, dynamic _) =>
    ColorFiltered(colorFilter: _paleMap, child: tile);
