import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/poi/poi_model.dart';

void main() {
  final json = {
    'id': 'osm_node_1',
    'name': 'Colosseum',
    'categories': ['archaeology', 'landmark'],
    'lat': 41.89,
    'lon': 12.49,
    'snippet': 'Archaeological site',
    'distance': 16,
    'reason': 'classic',
    'outsideRadius': false,
    'wikipedia': 'en:Colosseum',
    'website': 'https://colosseo.example',
  };

  test('reads a place from the API', () {
    final poi = Poi.fromJson(json);
    expect(poi.name, 'Colosseum');
    expect(poi.reason, PoiReason.classic);
    expect(poi.outsideRadius, isFalse);
    expect(poi.wikipedia, 'en:Colosseum');
    expect(poi.website, 'https://colosseo.example');
  });

  test('reads "for you" places beyond the radius', () {
    final poi = Poi.fromJson({...json, 'reason': 'for_you', 'outsideRadius': true});
    expect(poi.reason, PoiReason.forYou);
    expect(poi.outsideRadius, isTrue);
  });

  test('tolerates older responses and fractional numbers', () {
    final poi = Poi.fromJson({
      'id': 'poi_001',
      'name': 'Bridge',
      'categories': ['landmark'],
      'lat': 37,
      'lon': -122,
      'distance': 12.0,
    });
    expect(poi.reason, PoiReason.interest);
    expect(poi.outsideRadius, isFalse);
    expect(poi.snippet, '');
    expect(poi.distance, 12);
  });

  test('round-trips through JSON', () {
    expect(Poi.fromJson(Poi.fromJson(json).toJson()).toJson(), Poi.fromJson(json).toJson());
  });

  test('reads a response whose radii are fractional or missing', () {
    final response = PoiResponse.fromJson({
      'count': 1,
      'radius': 1500.0,
      'pois': [json],
    });
    expect(response.radius, 1500);
    expect(response.pois.single.name, 'Colosseum');
  });
}
