import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../poi/poi_model.dart';
import '../poi/poi_style.dart';
import 'traveller_icon.dart';

/// The map marker for a place. Tapping it opens the place; "for you" places
/// beyond the radius are faded.
Marker poiMarker(Poi poi, {required void Function(String poiId) onTap}) {
  final note = reasonLabel(poi);
  final distance = formatDistance(poi.distance);
  return Marker(
    markerId: MarkerId(poi.id),
    position: LatLng(poi.lat, poi.lon),
    alpha: poi.outsideRadius ? 0.6 : 1.0,
    icon: BitmapDescriptor.defaultMarkerWithHue(styleFor(poi.categories).markerHue),
    infoWindow: InfoWindow(
      title: poi.name,
      snippet: note == null ? distance : '$note · $distance',
    ),
    // The tap opens the place page; do not also pan and pop up the label.
    consumeTapEvents: true,
    onTap: () => onTap(poi.id),
  );
}

/// Street-level zoom used when the map is centred on the traveller.
const double userZoom = 15;

/// Where the map opens: on the traveller, or on the whole world while the
/// location is still unknown.
CameraPosition openingCamera(Position? position) {
  if (position == null) return const CameraPosition(target: LatLng(20, 0), zoom: 2);
  return CameraPosition(
    target: LatLng(position.latitude, position.longitude),
    zoom: userZoom,
  );
}

/// The traveller on the map, drawn with [icon] and standing on the spot.
Marker travellerMarker(Position position, BitmapDescriptor icon) {
  return Marker(
    markerId: const MarkerId('traveller'),
    position: LatLng(position.latitude, position.longitude),
    icon: icon,
    anchor: travellerAnchor,
    infoWindow: const InfoWindow(title: 'You are here'),
    zIndexInt: 1,
  );
}

/// Everything to draw: the places, plus the traveller once located.
Set<Marker> mapMarkers(Set<Marker> poiMarkers, Position? position, BitmapDescriptor travellerIcon) {
  return {...poiMarkers, if (position != null) travellerMarker(position, travellerIcon)};
}

/// Controller for managing the Google Map
class MapViewController {
  GoogleMapController? _controller;
  final Set<Marker> markers = {};

  /// Set the Google Map controller
  void setController(GoogleMapController controller) {
    _controller = controller;
  }

  /// Move camera to a specific position
  Future<void> moveCameraToPosition(Position position) async {
    if (_controller == null) return;

    final cameraPosition = CameraPosition(
      target: LatLng(position.latitude, position.longitude),
      zoom: 15.0,
    );

    await _controller!.animateCamera(
      CameraUpdate.newCameraPosition(cameraPosition),
    );
  }

  /// Move camera to a specific LatLng
  Future<void> moveCameraToLatLng(LatLng latLng, {double zoom = 15.0}) async {
    if (_controller == null) return;

    final cameraPosition = CameraPosition(target: latLng, zoom: zoom);

    await _controller!.animateCamera(
      CameraUpdate.newCameraPosition(cameraPosition),
    );
  }

  /// Add a marker to the map
  void addMarker(Marker marker) {
    markers.add(marker);
  }

  /// Remove a marker from the map
  void removeMarker(String markerId) {
    markers.removeWhere((marker) => marker.markerId.value == markerId);
  }

  /// Clear all markers
  void clearMarkers() {
    markers.clear();
  }

  /// Replace the POI markers on the map. [onTap] runs when one is tapped.
  void updatePoiMarkers(List<Poi> pois, {required void Function(String poiId) onTap}) {
    markers
      ..clear()
      ..addAll(pois.map((poi) => poiMarker(poi, onTap: onTap)));
  }

  /// Dispose the controller
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

/// Map state model
class MapState {
  final MapViewController mapViewController;
  final Position? currentPosition;
  final bool isInitialized;

  MapState({
    required this.mapViewController,
    this.currentPosition,
    this.isInitialized = false,
  });

  MapState copyWith({
    MapViewController? mapViewController,
    Position? currentPosition,
    bool? isInitialized,
  }) {
    return MapState(
      mapViewController: mapViewController ?? this.mapViewController,
      currentPosition: currentPosition ?? this.currentPosition,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// Notifier for managing map state with Riverpod
class MapStateNotifier extends Notifier<MapState> {
  @override
  MapState build() {
    return MapState(mapViewController: MapViewController());
  }

  /// Initialize the map with a controller
  void initializeMap(GoogleMapController controller) {
    state.mapViewController.setController(controller);
    state = state.copyWith(isInitialized: true);
  }

  /// Update current position
  void updatePosition(Position position) {
    state = state.copyWith(currentPosition: position);
  }

  /// Recenter the map to current position
  Future<void> recenterToCurrentPosition() async {
    if (state.currentPosition != null) {
      await state.mapViewController.moveCameraToPosition(state.currentPosition!);
    }
  }
}

/// Provider for map state
final mapStateProvider = NotifierProvider<MapStateNotifier, MapState>(
  MapStateNotifier.new,
);
