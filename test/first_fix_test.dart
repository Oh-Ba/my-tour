import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_tour/src/features/map/map_controller.dart';
import 'package:my_tour/src/services/location_service.dart';

void main() {
  final here = positionAt((lat: 37.5079, lon: 15.083));
  final before = positionAt((lat: 37.5, lon: 15.0));

  group('firstFix', () {
    test('uses a fresh reading when there is one', () async {
      final fix = await firstFix(current: () async => here, lastKnown: () async => before);
      expect(fix, here);
    });

    test('falls back to the last known position when GPS gives nothing', () async {
      final fix = await firstFix(current: () async => null, lastKnown: () async => before);
      expect(fix, before);
    });

    test('falls back to the last known position when GPS is too slow', () async {
      final never = Completer<Position?>();
      final fix = await firstFix(
        current: () => never.future,
        lastKnown: () async => before,
        timeout: const Duration(milliseconds: 20),
      );
      expect(fix, before);
    });

    test('is null when the phone has no idea where it is', () async {
      final fix = await firstFix(current: () async => null, lastKnown: () async => null);
      expect(fix, isNull);
    });
  });

  test('a test location is the initial position', () async {
    final service = FixedLocationService((lat: 37.5079, lon: 15.083));
    final fix = await service.getInitialPosition();
    expect(fix!.latitude, 37.5079);
    expect(fix.longitude, 15.083);
  });

  group('openingCamera', () {
    test('opens on the traveller, close enough to see the streets', () {
      final camera = openingCamera(here);
      expect(camera.target, const LatLng(37.5079, 15.083));
      expect(camera.zoom, 15);
    });

    test('shows the whole world when the location is unknown', () {
      final camera = openingCamera(null);
      expect(camera.zoom, lessThan(3));
    });
  });
}
