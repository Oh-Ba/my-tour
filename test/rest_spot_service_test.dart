import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_tour/src/features/guide/rest_spot_service.dart';

void main() {
  const json = {'id': 'osm_node_9', 'name': 'Giardino Bellini', 'kind': 'garden', 'lat': 37.51, 'lon': 15.08, 'distance': 120};

  test('reads a place to sit', () {
    final spot = RestSpot.fromJson(json);
    expect(spot.name, 'Giardino Bellini');
    expect(spot.kind, RestSpotKind.garden);
    expect(spot.distance, 120);
  });

  test('each kind has its own name and icon', () {
    expect(RestSpotKind.garden.label, 'Garden');
    expect(RestSpotKind.cafe.label, 'Coffee shop');
    expect(RestSpotKind.viewpoint.label, 'Viewpoint');
    expect(RestSpotKind.cafe.icon, Icons.local_cafe);
    expect(RestSpotKind.fromWire('something new'), RestSpotKind.garden);
  });

  test('asks the server around a position', () async {
    late Uri asked;
    final client = MockClient((request) async {
      asked = request.url;
      return http.Response(jsonEncode({'spots': [json]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = HttpRestSpotService(baseUrl: 'http://host:3000', client: client);

    final spots = await service.find(lat: 37.5, lon: 15.08);

    expect(asked.path, '/rest-spots');
    expect(asked.queryParameters, {'lat': '37.5', 'lon': '15.08'});
    expect(spots.single.name, 'Giardino Bellini');
  });

  test('offers nothing, rather than failing, when the server cannot help', () async {
    for (final client in [
      MockClient((_) async => http.Response('oops', 500)),
      MockClient((_) async => http.Response('not json', 200)),
      MockClient((_) async => throw http.ClientException('offline')),
    ]) {
      final service = HttpRestSpotService(baseUrl: 'http://host:3000', client: client);
      expect(await service.find(lat: 1, lon: 2), isEmpty);
    }
  });

  test('walking directions lead to the spot', () {
    final url = directionsUrl(RestSpot.fromJson(json));
    expect(url.host, 'www.google.com');
    expect(url.path, '/maps/dir/');
    expect(url.queryParameters, {'api': '1', 'destination': '37.51,15.08', 'travelmode': 'walking'});
  });
}
