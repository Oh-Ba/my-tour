import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/guide/open_guide.dart';
import 'package:my_tour/src/features/map/map_controller.dart';
import 'package:my_tour/src/features/poi/poi_model.dart';

import 'helpers/fakes.dart';

void main() {
  group('poiMarker', () {
    test('labels a place with its name and distance', () {
      final marker = poiMarker(samplePoi(distance: 850), onTap: (_) {});
      expect(marker.markerId.value, 'poi_1');
      expect(marker.infoWindow.title, 'City Museum');
      expect(marker.infoWindow.snippet, '850 m');
      expect(marker.alpha, 1.0);
    });

    test('says why a recommendation is shown and fades it beyond the radius', () {
      final marker = poiMarker(
        samplePoi(reason: PoiReason.forYou, outsideRadius: true, distance: 4200),
        onTap: (_) {},
      );
      expect(marker.infoWindow.snippet, 'For you · beyond your radius · 4.2 km');
      expect(marker.alpha, lessThan(1.0));
    });

    test('a tap opens the place instead of only showing a label', () {
      final tapped = <String>[];
      final marker = poiMarker(samplePoi(), onTap: tapped.add);
      marker.onTap!();
      expect(tapped, ['poi_1']);
      expect(marker.consumeTapEvents, isTrue);
    });
  });

  group('MapViewController', () {
    test('replaces the markers on every update', () {
      final controller = MapViewController();
      controller.updatePoiMarkers([samplePoi(id: 'a'), samplePoi(id: 'b')], onTap: (_) {});
      controller.updatePoiMarkers([samplePoi(id: 'osm_node_1')], onTap: (_) {});
      expect(controller.markers.map((m) => m.markerId.value), ['osm_node_1']);

      controller.updatePoiMarkers(const [], onTap: (_) {});
      expect(controller.markers, isEmpty);
    });
  });

  test('nearestNames gives the closest few names', () {
    final pois = List.generate(12, (i) => samplePoi(id: 'p$i', name: 'Place $i'));
    expect(nearestNames(pois), hasLength(nearbyNamesLimit));
    expect(nearestNames(pois).first, 'Place 0');
    expect(nearestNames(const []), isEmpty);
  });
}
