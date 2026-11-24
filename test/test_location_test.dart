import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_tour/src/features/map/map_controller.dart';
import 'package:my_tour/src/features/map/traveller_icon.dart';
import 'package:my_tour/src/services/location_service.dart';

void main() {
  const catania = (lat: 37.5079, lon: 15.083);

  group('parseTestLocation', () {
    test('reads "lat,lon"', () {
      expect(parseTestLocation('37.5079,15.0830'), catania);
      expect(parseTestLocation(' 37.5079 , 15.0830 '), catania);
      expect(parseTestLocation('-33.86,151.21'), (lat: -33.86, lon: 151.21));
    });

    test('is null when nothing usable is given', () {
      expect(parseTestLocation(''), isNull);
      expect(parseTestLocation('catania'), isNull);
      expect(parseTestLocation('37.5'), isNull);
      expect(parseTestLocation('37.5,abc'), isNull);
      expect(parseTestLocation('1,2,3'), isNull);
    });

    test('rejects coordinates that are not on Earth', () {
      expect(parseTestLocation('91,0'), isNull);
      expect(parseTestLocation('0,181'), isNull);
    });
  });

  group('FixedLocationService', () {
    final service = FixedLocationService(catania);

    test('needs no permission', () async {
      expect(await service.requestPermission(), LocationPermissionStatus.granted);
      expect(await service.isPermissionGranted(), isTrue);
    });

    test('always reports the fixed place', () async {
      final current = await service.getCurrentPosition();
      expect(current!.latitude, 37.5079);
      expect(current.longitude, 15.083);
      expect(service.lastKnownPosition, isNotNull);

      final streamed = await service.positionStream.first;
      expect(streamed.latitude, 37.5079);
      expect(streamed.longitude, 15.083);
    });
  });

  group('locationServiceProvider', () {
    test('uses the device location by default', () {
      final container = ProviderContainer(
        overrides: [testLocationProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      expect(container.read(locationServiceProvider), isNot(isA<FixedLocationService>()));
    });

    test('pretends to be at the test location when one is set', () async {
      final container = ProviderContainer(
        overrides: [testLocationProvider.overrideWithValue(catania)],
      );
      addTearDown(container.dispose);
      final service = container.read(locationServiceProvider);
      expect(service, isA<FixedLocationService>());
      expect((await service.getCurrentPosition())!.latitude, 37.5079);
    });
  });

  group('the traveller on the map', () {
    final icon = BitmapDescriptor.defaultMarker;

    test('stands where the traveller is', () {
      final marker = travellerMarker(positionAt(catania), icon);
      expect(marker.markerId.value, 'traveller');
      expect(marker.position.latitude, 37.5079);
      expect(marker.position.longitude, 15.083);
      expect(marker.icon, icon);
      expect(marker.infoWindow.title, 'You are here');
    });

    test('is drawn above the places, standing on the spot', () {
      final marker = travellerMarker(positionAt(catania), icon);
      expect(marker.anchor, travellerAnchor);
      expect(marker.zIndexInt, greaterThan(0));
    });

    test('mapMarkers adds the traveller only once the position is known', () {
      final controller = MapViewController();
      expect(mapMarkers(controller.markers, null, icon), isEmpty);
      expect(
        mapMarkers(controller.markers, positionAt(catania), icon).single.markerId.value,
        'traveller',
      );
    });
  });
}
