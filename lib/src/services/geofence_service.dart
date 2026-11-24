import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geofence_service/geofence_service.dart' as geo;

import '../features/poi/poi_model.dart';

/// Provides the initialized [FlutterLocalNotificationsPlugin].
/// Overridden inside `main.dart` after the plugin is configured.
final localNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
  throw UnimplementedError(
    'localNotificationsPluginProvider must be overridden in main.dart',
  );
});

/// Exposes an instance of [AppGeofenceService] for the app.
final geofenceManagerProvider = Provider<AppGeofenceService>((ref) {
  final plugin = ref.watch(localNotificationsPluginProvider);
  final manager = AppGeofenceService(
    notificationsPlugin: plugin,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Handles registering geofences and triggering actionable notifications.
class AppGeofenceService {
  AppGeofenceService({
    required FlutterLocalNotificationsPlugin notificationsPlugin,
  })  : _notificationsPlugin = notificationsPlugin,
        _geofenceService = geo.GeofenceService.instance.setup(
          interval: 15000,
          accuracy: 75,
          loiteringDelayMs: 2000,
          statusChangeDelayMs: 2000,
          useActivityRecognition: false,
          allowMockLocations: true,
          geofenceRadiusSortType: geo.GeofenceRadiusSortType.ASC,
        ) {
    _attachListeners();
  }

  static const int maxGeofences = 20;
  static const double geofenceRadiusMeters = 120;
  static const Duration _notificationCooldown = Duration(minutes: 15);

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final geo.GeofenceService _geofenceService;
  final Map<String, Poi> _poiLookup = {};
  final Map<String, DateTime> _notificationHistory = {};

  List<String> _currentPoiIds = const [];
  bool _listenersAttached = false;
  bool _syncInProgress = false;

  void _attachListeners() {
    if (_listenersAttached) return;
    _geofenceService.addGeofenceStatusChangeListener(_onStatusChanged);
    _geofenceService.addStreamErrorListener((error) {
      debugPrint('Geofence stream error: $error');
    });
    _listenersAttached = true;
  }

  /// Register geofences for the supplied POIs, respecting the max limit.
  Future<void> syncWithPois(List<Poi> pois) async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final filtered = pois.take(maxGeofences).toList(growable: false);
      final ids = filtered.map((p) => p.id).toList(growable: false);

      _poiLookup
        ..clear()
        ..addEntries(filtered.map((p) => MapEntry(p.id, p)));

      if (listEquals(ids, _currentPoiIds)) {
        return;
      }

      _currentPoiIds = ids;

      if (_geofenceService.isRunningService) {
        await _geofenceService.stop();
      }

      if (filtered.isEmpty) {
        return;
      }

      final geofences = filtered
          .map(
            (poi) => geo.Geofence(
              id: poi.id,
              latitude: poi.lat,
              longitude: poi.lon,
              radius: <geo.GeofenceRadius>[
                geo.GeofenceRadius(
                  id: 'radius_${geofenceRadiusMeters.toInt()}m',
                  length: geofenceRadiusMeters,
                ),
              ],
            ),
          )
          .toList(growable: false);

      await _geofenceService.start(geofences);
    } on geo.ErrorCodes catch (err) {
      debugPrint('Failed to set up geofences: $err');
    } catch (err) {
      debugPrint('Unexpected geofence error: $err');
    } finally {
      _syncInProgress = false;
    }
  }

  /// Stops monitoring any active geofences.
  Future<void> clear() async {
    _currentPoiIds = const [];
    _poiLookup.clear();
    if (_geofenceService.isRunningService) {
      await _geofenceService.stop();
    }
  }

  Future<void> _onStatusChanged(
    geo.Geofence geofence,
    geo.GeofenceRadius radius,
    geo.GeofenceStatus status,
    geo.Location location,
  ) async {
    if (status != geo.GeofenceStatus.ENTER) return;
    final poi = _poiLookup[geofence.id];
    if (poi == null) return;

    final lastNotification = _notificationHistory[poi.id];
    if (lastNotification != null &&
        DateTime.now().difference(lastNotification) < _notificationCooldown) {
      return;
    }

    _notificationHistory[poi.id] = DateTime.now();
    await _showNotification(poi, location);
  }

  Future<void> _showNotification(Poi poi, geo.Location location) async {
    final payload = GeofenceNotificationPayload(
      poiId: poi.id,
      poiName: poi.name,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        GeofenceNotificationChannels.poiChannelId,
        GeofenceNotificationChannels.poiChannelName,
        channelDescription: GeofenceNotificationChannels.poiChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'poi_geofence',
        category: AndroidNotificationCategory.reminder,
        actions: const [
          AndroidNotificationAction(
            GeofenceNotificationActions.listen,
            'Listen',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            GeofenceNotificationActions.findCoffee,
            'Find Coffee',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        categoryIdentifier: GeofenceNotificationActions.categoryId,
        interruptionLevel: InterruptionLevel.active,
      ),
    );

    await _notificationsPlugin.show(
      poi.id.hashCode,
      "You're near ${poi.name}",
      'Tap to listen now or find a coffee nearby.',
      details,
      payload: payload.toJsonString(),
    );
  }

  void dispose() {
    if (_listenersAttached) {
      _geofenceService.clearAllListeners();
    }
  }
}

/// Identifiers used for Android notification channels.
class GeofenceNotificationChannels {
  static const String poiChannelId = 'poi_geofence_alerts';
  static const String poiChannelName = 'POI geofence alerts';
  static const String poiChannelDescription =
      'Alerts that trigger when you approach saved POIs';
}

/// Identifiers for notification actions/categories.
class GeofenceNotificationActions {
  static const String listen = 'action_listen';
  static const String findCoffee = 'action_find_coffee';
  static const String categoryId = 'poi_geofence_actions';
}

/// Payload stored inside a notification for routing.
class GeofenceNotificationPayload {
  final String poiId;
  final String poiName;
  final double latitude;
  final double longitude;

  const GeofenceNotificationPayload({
    required this.poiId,
    required this.poiName,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'poiId': poiId,
        'poiName': poiName,
        'lat': latitude,
        'lon': longitude,
      };

  String toJsonString() => jsonEncode(toJson());

  factory GeofenceNotificationPayload.fromJson(Map<String, dynamic> json) {
    return GeofenceNotificationPayload(
      poiId: json['poiId'] as String,
      poiName: json['poiName'] as String? ?? '',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
    );
  }
}

enum GeofenceNotificationActionType { listen, findCoffee }

/// Strongly typed notification action emitted to the UI.
class GeofenceNotificationAction {
  final GeofenceNotificationActionType type;
  final GeofenceNotificationPayload payload;

  GeofenceNotificationAction({
    required this.type,
    required this.payload,
  });
}

/// Simple event bus broadcasting notification actions across the app.
class NotificationActionBus {
  NotificationActionBus._internal();

  static final NotificationActionBus instance = NotificationActionBus._internal();

  final StreamController<GeofenceNotificationAction> _controller =
      StreamController<GeofenceNotificationAction>.broadcast();
  GeofenceNotificationAction? _lastAction;

  Stream<GeofenceNotificationAction> get stream => _controller.stream;

  void emit(GeofenceNotificationAction action) {
    if (!_controller.isClosed) {
      _controller.add(action);
    }
    _lastAction = action;
  }

  GeofenceNotificationAction? takeLastAction() {
    final action = _lastAction;
    _lastAction = null;
    return action;
  }
}

