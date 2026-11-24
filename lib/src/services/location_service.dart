import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to handle location permissions and provide location stream
class LocationService {
  StreamController<Position>? _positionStreamController;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastKnownPosition;

  /// Get the last known position
  Position? get lastKnownPosition => _lastKnownPosition;

  /// Request location permission from the user
  Future<LocationPermissionStatus> requestPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    // Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationPermissionStatus.denied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }

    return LocationPermissionStatus.granted;
  }

  /// Start streaming position updates
  Stream<Position> get positionStream {
    _positionStreamController ??= StreamController<Position>.broadcast(
      onCancel: () {
        _positionStreamSubscription?.cancel();
      },
    );

    if (_positionStreamSubscription == null) {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              _lastKnownPosition = position;
              _positionStreamController?.add(position);
            },
            onError: (error) {
              _positionStreamController?.addError(error);
            },
          );
    }

    return _positionStreamController!.stream;
  }

  /// Get current position once
  Future<Position?> getCurrentPosition() async {
    try {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
      );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      _lastKnownPosition = position;
      return position;
    } catch (e) {
      return null;
    }
  }

  /// The position to open the map on: a fresh reading, or the last one the
  /// phone remembers if GPS is slow or unavailable (indoors, for example).
  Future<Position?> getInitialPosition() {
    return firstFix(current: getCurrentPosition, lastKnown: _lastKnownOnDevice);
  }

  Future<Position?> _lastKnownOnDevice() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Check if permission is granted
  Future<bool> isPermissionGranted() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Open app settings
  Future<void> openAppSettings() async {
    await Permission.location.request();
    if (await Permission.location.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _positionStreamController?.close();
    _positionStreamController = null;
    _positionStreamSubscription = null;
  }
}

/// Enum to represent location permission status
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// The first usable position: what [current] reports within [timeout],
/// otherwise whatever [lastKnown] has. Null when neither knows.
Future<Position?> firstFix({
  required Future<Position?> Function() current,
  required Future<Position?> Function() lastKnown,
  Duration timeout = const Duration(seconds: 10),
}) async {
  // Re-wrapped so that giving up can answer null whatever [current] returns.
  Future<Position?> reading() async => current();
  final fresh = await reading().timeout(timeout, onTimeout: () => null);
  return fresh ?? await lastKnown();
}

/// A point on the map.
typedef LatLon = ({double lat, double lon});

/// Reads a `lat,lon` pair such as `37.5079,15.0830`; null when it is not one.
LatLon? parseTestLocation(String value) {
  final parts = value.split(',').map((part) => double.tryParse(part.trim())).toList();
  if (parts.length != 2 || parts.contains(null)) return null;
  final (lat, lon) = (parts[0]!, parts[1]!);
  return lat.abs() <= 90 && lon.abs() <= 180 ? (lat: lat, lon: lon) : null;
}

/// A [Position] at [place], as if the phone's GPS had just reported it.
Position positionAt(LatLon place) {
  return Position(
    latitude: place.lat,
    longitude: place.lon,
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    timestamp: DateTime.now(),
  );
}

/// A [LocationService] that pretends the phone is at a fixed place, for
/// trying the app as if you were somewhere else. Needs no GPS or permission.
class FixedLocationService extends LocationService {
  FixedLocationService(this.place);

  final LatLon place;

  @override
  Position? get lastKnownPosition => positionAt(place);

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    return LocationPermissionStatus.granted;
  }

  @override
  Stream<Position> get positionStream => Stream.value(positionAt(place));

  @override
  Future<Position?> getCurrentPosition() async => positionAt(place);

  @override
  Future<bool> isPermissionGranted() async => true;
}

/// Where the app pretends to be, from
/// `flutter run --dart-define=TEST_LOCATION=37.5079,15.0830`.
/// Null (the normal case) means the phone's real location is used.
final testLocationProvider = Provider<LatLon?>((ref) {
  return parseTestLocation(const String.fromEnvironment('TEST_LOCATION'));
});

/// Provider for location service
final locationServiceProvider = Provider<LocationService>((ref) {
  final testLocation = ref.watch(testLocationProvider);
  return testLocation == null ? LocationService() : FixedLocationService(testLocation);
});
