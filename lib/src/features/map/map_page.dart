import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/geofence_service.dart';
import '../../services/location_service.dart';
import '../../core/dev_mode.dart';
import '../../widgets/app_title.dart';
import '../../widgets/permission_rationale.dart';
import '../coffee/coffee_list_sheet.dart';
import '../dev/new_exhibit_page.dart';
import '../guide/open_guide.dart';
import '../guide/photo_picker.dart';
import '../place/place_page.dart';
import '../poi/poi_query.dart';
import '../poi/poi_repository.dart';
import '../poi/poi_list_sheet.dart';
import '../profile/interest_profile.dart';
import '../trip_start/trip_sheet.dart';
import '../trip_start/trip_state.dart';
import 'map_controller.dart';
import 'traveller_icon.dart';

export '../../services/location_service.dart' show locationServiceProvider;
export 'map_controller.dart' show mapStateProvider;

/// Main map page showing user location and trip controls
class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  LocationPermissionStatus _permissionStatus = LocationPermissionStatus.denied;
  bool _isLoading = true;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<GeofenceNotificationAction>? _notificationSubscription;
  Position? _currentPosition;
  late final AppGeofenceService _geofenceService;

  /// Whether the map has been centred on the traveller yet.
  bool _openedOnUser = false;

  @override
  void initState() {
    super.initState();
    _geofenceService = ref.read(geofenceManagerProvider);
    _notificationSubscription =
        NotificationActionBus.instance.stream.listen(_handleNotificationAction);
    final pendingAction = NotificationActionBus.instance.takeLastAction();
    if (pendingAction != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleNotificationAction(pendingAction),
      );
    }
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _notificationSubscription?.cancel();
    unawaited(_geofenceService.clear());
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final status = await locationService.requestPermission();
    final granted = status == LocationPermissionStatus.granted;

    // Wait for the first position, so the map opens on the traveller.
    final position = granted ? await locationService.getInitialPosition() : null;
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _currentPosition = position;
      _openedOnUser = position != null;
      _isLoading = false;
    });
    if (!granted) return;

    if (position != null) _onPosition(position);
    await _positionSubscription?.cancel();
    _positionSubscription = locationService.positionStream.listen(
      _onPosition,
      onError: (error) => debugPrint('Error getting location: $error'),
    );
  }

  /// The traveller is at [position]: remember it, centre the map on it the
  /// first time, and look for the tour's places around it.
  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _currentPosition = position);
    ref.read(mapStateProvider.notifier).updatePosition(position);

    if (!_openedOnUser) {
      _openedOnUser = true;
      unawaited(_recenterCamera());
    }
    _fetchPoisIfNeeded(position);
  }

  /// Ask for the places of the running tour around [position]. The
  /// repository skips the request when nothing relevant has changed.
  void _fetchPoisIfNeeded(Position position, {bool force = false}) {
    final trip = ref.read(tripStateProvider);
    if (!trip.isActive) return;

    ref.read(poiRepositoryProvider.notifier).fetchPois(
          lat: position.latitude,
          lon: position.longitude,
          query: buildPoiQuery(trip, ref.read(learnedCategoriesProvider)),
          forceRefresh: force,
        );
  }

  /// Look for places again where the traveller is, after a failed search.
  void _retryPlaces() {
    final position = _currentPosition;
    if (position != null) _fetchPoisIfNeeded(position, force: true);
  }

  /// Show the places on the map and watch for arriving at the ones in reach.
  void _onPoisChanged(PoiState next) {
    ref.read(mapStateProvider).mapViewController.updatePoiMarkers(
          next.pois,
          onTap: _openPlace,
        );
    setState(() {});

    if (ref.read(tripStateProvider).isActive) {
      final inReach = next.pois.where((poi) => !poi.outsideRadius).toList();
      unawaited(_geofenceService.syncWithPois(inReach));
    }
  }

  /// A tour started or changed: look for its places. A tour ended: clear up.
  void _onTripChanged(TripConfig next) {
    if (!next.isActive) {
      ref.read(poiRepositoryProvider.notifier).clear();
      unawaited(_geofenceService.clear());
      return;
    }
    if (_currentPosition != null) _fetchPoisIfNeeded(_currentPosition!);
  }

  void _selectPoi(String poiId) {
    ref.read(poiRepositoryProvider.notifier).selectPoi(poiId);
    _onPoiTap(poiId);
  }

  /// A place was pressed on the map: open its website, where its story can
  /// be listened to or read.
  void _openPlace(String poiId) {
    final poi = _findPoiById(poiId);
    if (poi == null) return;
    ref.read(poiRepositoryProvider.notifier).selectPoi(poiId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlacePage(poi: poi)),
    );
  }

  Future<void> _endTrip() async {
    await ref.read(tripStateProvider.notifier).endTrip();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tour ended'), duration: Duration(seconds: 2)),
    );
  }

  /// Developer mode: teach the guide about the selected place, or about
  /// wherever the developer is standing.
  void _newExhibit() {
    final position = _currentPosition;
    final poi = ref.read(selectedPoiProvider);
    if (position == null && poi == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewExhibitPage(
          poi: poi,
          lat: position?.latitude ?? poi!.lat,
          lon: position?.longitude ?? poi!.lon,
        ),
      ),
    );
  }

  /// "What am I looking at?": photograph anything and hear its story.
  Future<void> _photographSurroundings() async {
    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider).pick(fromCamera: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the camera. Check the camera permission in Settings.'),
        ),
      );
      return;
    }
    if (photo == null || !mounted) return;
    await openGuide(context, ref, photo: photo, autoPlay: true);
  }

  /// The tour radius drawn around the traveller.
  Set<Circle> _radiusCircle(TripConfig trip) {
    final position = _currentPosition;
    if (!trip.isActive || position == null) return const {};
    final color = Theme.of(context).colorScheme.primary;
    return {
      Circle(
        circleId: const CircleId('tour_radius'),
        center: LatLng(position.latitude, position.longitude),
        radius: trip.radiusKm * 1000,
        strokeWidth: 1,
        strokeColor: color.withValues(alpha: 0.5),
        fillColor: color.withValues(alpha: 0.05),
      ),
    };
  }

  Future<void> _retryPermission() async {
    setState(() {
      _isLoading = true;
    });
    await _initializeLocation();
  }

  Future<void> _recenterCamera() async {
    if (_currentPosition != null) {
      await ref
          .read(mapStateProvider)
          .mapViewController
          .moveCameraToPosition(_currentPosition!);
    }
  }

  /// Move the camera to a place.
  void _onPoiTap(String poiId) {
    final poi = _findPoiById(poiId);
    if (poi == null) return;

    // Move camera to POI location
    ref
        .read(mapStateProvider)
        .mapViewController
        .moveCameraToLatLng(LatLng(poi.lat, poi.lon), zoom: 16.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Finding your location…'),
            ],
          ),
        ),
      );
    }

    // Show permission rationale if needed
    if (_permissionStatus == LocationPermissionStatus.serviceDisabled) {
      return Scaffold(body: LocationServiceDisabled(onRetry: _retryPermission));
    }

    if (_permissionStatus == LocationPermissionStatus.denied ||
        _permissionStatus == LocationPermissionStatus.deniedForever) {
      return Scaffold(body: PermissionRationale(onRetry: _retryPermission));
    }

    ref.listen(poiRepositoryProvider, (previous, next) => _onPoisChanged(next));
    ref.listen(tripStateProvider, (previous, next) => _onTripChanged(next));

    final tripConfig = ref.watch(tripStateProvider);
    final hasTripActive = tripConfig.isActive;
    final travellerIcon = ref.watch(travellerIconProvider).value ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    // Keep the centre of the map clear of the places sheet.
    final mapPadding = EdgeInsets.only(
      bottom: hasTripActive ? MediaQuery.sizeOf(context).height * 0.3 : 0,
    );

    // Show map when permission is granted
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: openingCamera(_currentPosition),
            // The traveller is drawn as a marker instead of the blue dot.
            myLocationEnabled: false,
            padding: mapPadding,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: mapMarkers(
              ref.watch(mapStateProvider).mapViewController.markers,
              _currentPosition,
              travellerIcon,
            ),
            circles: _radiusCircle(tripConfig),
            onMapCreated: (GoogleMapController controller) {
              ref.read(mapStateProvider.notifier).initializeMap(controller);

              // Move to current position if available
              if (_currentPosition != null) {
                ref
                    .read(mapStateProvider)
                    .mapViewController
                    .moveCameraToPosition(_currentPosition!);
              }
            },
          ),

          // Top app bar overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const AppTitle(devMode: devModeEnabled),
              ),
            ),
          ),

          // Camera and recenter buttons, clear of the places sheet
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + 96,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'camera',
                  onPressed: _photographSurroundings,
                  tooltip: 'Photograph something and hear its story',
                  child: const Icon(Icons.photo_camera),
                ),
                const SizedBox(height: 12),
                // Developer mode only: this button, and the screen behind it,
                // are left out of every other build.
                if (devModeEnabled) ...[
                  FloatingActionButton.small(
                    heroTag: 'newExhibit',
                    onPressed: _newExhibit,
                    tooltip: 'New exhibit (developer)',
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.school),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: _recenterCamera,
                  tooltip: 'Recenter',
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
              ],
            ),
          ),

          // POI List Sheet (shown when trip is active)
          if (hasTripActive)
            PoiListSheet(
              onPoiTap: _onPoiTap,
              onEditTrip: () => showTripSheet(context),
              onEndTrip: _endTrip,
              onRetry: _retryPlaces,
            ),

          // Start/Edit Trip button
          if (!hasTripActive)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: () => showTripSheet(context),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Start Tour'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleNotificationAction(GeofenceNotificationAction action) {
    if (!mounted) return;
    final payload = action.payload;

    switch (action.type) {
      case GeofenceNotificationActionType.listen:
        final poi = _findPoiById(payload.poiId);
        if (poi != null) {
          _selectPoi(poi.id);
          openGuide(context, ref, poi: poi, autoPlay: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('POI no longer available nearby.')),
          );
        }
        break;
      case GeofenceNotificationActionType.findCoffee:
        showCoffeeListSheet(
          context,
          lat: payload.latitude,
          lon: payload.longitude,
          anchorPoiName: payload.poiName.isNotEmpty ? payload.poiName : null,
        );
        break;
    }
  }

  Poi? _findPoiById(String poiId) {
    for (final poi in ref.read(poiRepositoryProvider).pois) {
      if (poi.id == poiId) return poi;
    }
    return null;
  }
}
