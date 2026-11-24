import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/services/geofence_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  final notificationHandler = AppNotificationHandler(
    plugin: notificationsPlugin,
    actionBus: NotificationActionBus.instance,
  );
  await notificationHandler.initialize();

  runApp(
    ProviderScope(
      overrides: [
        localNotificationsPluginProvider.overrideWithValue(notificationsPlugin),
      ],
      child: MyTourApp(navigatorKey: appNavigatorKey),
    ),
  );
}

/// Coordinates initialization of flutter_local_notifications and routes actions.
class AppNotificationHandler {
  AppNotificationHandler({
    required FlutterLocalNotificationsPlugin plugin,
    required NotificationActionBus actionBus,
  })  : _plugin = plugin,
        _actionBus = actionBus;

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationActionBus _actionBus;

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          GeofenceNotificationActions.categoryId,
          actions: [
            DarwinNotificationAction.plain(
              GeofenceNotificationActions.listen,
              'Listen',
            ),
            DarwinNotificationAction.plain(
              GeofenceNotificationActions.findCoffee,
              'Find Coffee',
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: handleResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            GeofenceNotificationChannels.poiChannelId,
            GeofenceNotificationChannels.poiChannelName,
            description: GeofenceNotificationChannels.poiChannelDescription,
            importance: Importance.max,
          ),
        );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (response != null) {
      handleResponse(response);
    }
  }

  void handleResponse(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null) return;

    try {
      final payload = GeofenceNotificationPayload.fromJson(
        jsonDecode(payloadString) as Map<String, dynamic>,
      );

      final actionType = _mapAction(response.actionId);
      if (actionType == null) return;

      _actionBus.emit(
        GeofenceNotificationAction(type: actionType, payload: payload),
      );
    } catch (err) {
      debugPrint('Failed to handle notification response: $err');
    }
  }

  GeofenceNotificationActionType? _mapAction(String? actionId) {
    if (actionId == null || actionId.isEmpty) {
      return GeofenceNotificationActionType.listen;
    }

    switch (actionId) {
      case GeofenceNotificationActions.listen:
        return GeofenceNotificationActionType.listen;
      case GeofenceNotificationActions.findCoffee:
        return GeofenceNotificationActionType.findCoffee;
      default:
        return null;
    }
  }
}
