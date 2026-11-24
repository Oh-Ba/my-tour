import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'poi_model.dart';

/// How a kind of place looks in lists, cards and on the map.
@immutable
class PoiStyle {
  final Color color;
  final IconData icon;

  /// Hue of the map marker.
  final double markerHue;

  const PoiStyle(this.color, this.icon, this.markerHue);
}

const PoiStyle _defaultStyle = PoiStyle(Colors.blue, Icons.place, BitmapDescriptor.hueAzure);

const PoiStyle _history = PoiStyle(Colors.brown, Icons.account_balance, BitmapDescriptor.hueRose);
const PoiStyle _food = PoiStyle(Colors.orange, Icons.restaurant, BitmapDescriptor.hueOrange);
const PoiStyle _green = PoiStyle(Colors.green, Icons.park, BitmapDescriptor.hueGreen);
const PoiStyle _shop = PoiStyle(Colors.amber, Icons.shopping_bag, BitmapDescriptor.hueYellow);
const PoiStyle _secondHand = PoiStyle(Colors.teal, Icons.storefront, BitmapDescriptor.hueCyan);

/// Styles by category. The first category of a place found here wins.
const Map<String, PoiStyle> _styles = {
  'museum': PoiStyle(Colors.purple, Icons.museum, BitmapDescriptor.hueViolet),
  'art': PoiStyle(Colors.pink, Icons.palette, BitmapDescriptor.hueMagenta),
  'archaeology': _history,
  'historical': _history,
  'religious': _history,
  'landmark': PoiStyle(Colors.red, Icons.location_city, BitmapDescriptor.hueRed),
  'viewpoint': PoiStyle(Colors.cyan, Icons.panorama, BitmapDescriptor.hueCyan),
  'park': _green,
  'nature': _green,
  'beach': PoiStyle(Colors.lightBlue, Icons.beach_access, BitmapDescriptor.hueAzure),
  'restaurant': _food,
  'cafe': PoiStyle(Colors.orange, Icons.local_cafe, BitmapDescriptor.hueOrange),
  'bakery': PoiStyle(Colors.orange, Icons.bakery_dining, BitmapDescriptor.hueOrange),
  'winery': PoiStyle(Colors.deepPurple, Icons.wine_bar, BitmapDescriptor.hueViolet),
  'nightlife': PoiStyle(Colors.indigo, Icons.nightlife, BitmapDescriptor.hueBlue),
  'theater': PoiStyle(Colors.indigo, Icons.theater_comedy, BitmapDescriptor.hueBlue),
  'music': PoiStyle(Colors.indigo, Icons.music_note, BitmapDescriptor.hueBlue),
  'sports': PoiStyle(Colors.lightGreen, Icons.sports_soccer, BitmapDescriptor.hueGreen),
  'shopping': _shop,
  'market': _shop,
  'second_hand': _secondHand,
  'antiques': _secondHand,
  'books': PoiStyle(Colors.teal, Icons.menu_book, BitmapDescriptor.hueCyan),
};

/// The style of the first category that has one.
PoiStyle styleFor(List<String> categories) {
  for (final category in categories) {
    final style = _styles[category];
    if (style != null) return style;
  }
  return _defaultStyle;
}

/// `850 m` or `1.2 km`.
String formatDistance(int meters) {
  return meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';
}

/// `second_hand` -> `Second hand`.
String categoryLabel(String category) {
  final words = category.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// A short note on why a place is recommended; null for plain interest matches.
String? reasonLabel(Poi poi) {
  switch (poi.reason) {
    case PoiReason.interest:
      return null;
    case PoiReason.classic:
      return 'Classic';
    case PoiReason.forYou:
      return poi.outsideRadius ? 'For you · beyond your radius' : 'For you';
  }
}
