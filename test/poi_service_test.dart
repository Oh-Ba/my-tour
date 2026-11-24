import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_tour/src/features/poi/poi_query.dart';
import 'package:my_tour/src/features/poi/poi_service.dart';

void main() {
  const query = PoiQuery(
    radiusM: 2000,
    interests: ['Museums', 'second hand stores'],
    classics: true,
    learned: ['viewpoint'],
  );

  group('buildPoisUri', () {
    test('encodes the whole tour query', () {
      final uri = buildPoisUri('http://host:3000', lat: 41.89, lon: 12.49, query: query);
      expect(uri.path, '/pois');
      expect(uri.queryParameters, {
        'lat': '41.89',
        'lon': '12.49',
        'radiusM': '2000',
        'interests': 'Museums,second hand stores',
        'classics': 'true',
        'learned': 'viewpoint',
      });
    });

    test('omits empty lists', () {
      final uri = buildPoisUri(
        'http://host:3000',
        lat: 1,
        lon: 2,
        query: const PoiQuery(radiusM: 1000, classics: false),
      );
      expect(uri.queryParameters.keys, ['lat', 'lon', 'radiusM', 'classics']);
    });
  });

  group('fetchPois', () {
    PoiService serviceAnswering(http.Response response, [List<Uri>? seen]) {
      final client = MockClient((request) async {
        seen?.add(request.url);
        return response;
      });
      return PoiService(baseUrl: 'http://host:3000', client: client);
    }

    test('returns the places from the server', () async {
      final seen = <Uri>[];
      final body = jsonEncode({
        'count': 1,
        'radius': 2000,
        'pois': [
          {'id': 'a', 'name': 'A', 'categories': ['museum'], 'lat': 1, 'lon': 2, 'snippet': '', 'distance': 5},
        ],
      });
      final service = serviceAnswering(http.Response(body, 200), seen);

      final response = await service.fetchPois(lat: 41.89, lon: 12.49, query: query);

      expect(response.pois.single.name, 'A');
      expect(seen.single.queryParameters['classics'], 'true');
    });

    test('reports the server error message', () async {
      final service = serviceAnswering(http.Response('{"error":"lat and lon are required"}', 400));
      expect(
        () => service.fetchPois(lat: 0, lon: 0, query: query),
        throwsA(isA<PoiServiceException>().having((e) => e.message, 'message', 'lat and lon are required')),
      );
    });

    test('says in plain words when the server cannot be reached', () async {
      final service = PoiService(
        baseUrl: 'http://host:3000',
        client: MockClient((_) async => throw http.ClientException('Connection refused')),
      );
      expect(
        () => service.fetchPois(lat: 0, lon: 0, query: query),
        throwsA(isA<PoiServiceException>().having(
          (e) => e.message,
          'message',
          'Could not reach the tour server. Check that it is running and the phone is connected.',
        )),
      );
    });

    test('reports other failures with their status', () async {
      final service = serviceAnswering(http.Response('oops', 500));
      expect(
        () => service.fetchPois(lat: 0, lon: 0, query: query),
        throwsA(isA<PoiServiceException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });
}
