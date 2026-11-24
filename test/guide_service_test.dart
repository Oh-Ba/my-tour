import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';
import 'package:my_tour/src/features/guide/photo_picker.dart';

import 'helpers/fakes.dart';

void main() {
  (HttpGuideService, List<http.Request>) serviceAnswering(http.Response response) {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return response;
    });
    return (HttpGuideService(baseUrl: 'http://host:3000', client: client), requests);
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  test('asks for a narration of a place', () async {
    final (service, requests) = serviceAnswering(json({'text': 'שלום', 'minutes': 7, 'language': 'Hebrew'}));

    final story = await service.explainPlace(
      samplePoi(),
      language: 'Hebrew',
      interests: ['Museums'],
      request: 'more thorough please',
    );

    expect(story.text, 'שלום');
    expect(story.minutes, 7);
    expect(jsonDecode(requests.single.body)['request'], 'more thorough please');
    expect(requests.single.url.toString(), 'http://host:3000/guide/explain');
    final body = jsonDecode(requests.single.body);
    expect(body['language'], 'Hebrew');
    expect(body['interests'], ['Museums']);
    expect(body['place']['name'], 'City Museum');
    expect(body['place']['id'], 'poi_1');
  });

  test('sends a photo with its context', () async {
    final (service, requests) = serviceAnswering(json({'text': 'A mural.'}));
    final request = PhotoRequest(
      photo: PickedPhoto(bytes: Uint8List.fromList(utf8.encode('hello')), mediaType: 'image/png'),
      language: 'French',
      lat: 41.89,
      lon: 12.49,
      placeName: 'City Museum',
      nearby: ['Colosseum'],
      request: 'who painted it?',
    );

    expect((await service.explainPhoto(request)).text, 'A mural.');

    expect(requests.single.url.path, '/guide/photo');
    expect(jsonDecode(requests.single.body), {
      'image': 'aGVsbG8=',
      'mediaType': 'image/png',
      'language': 'French',
      'lat': 41.89,
      'lon': 12.49,
      'placeName': 'City Museum',
      'nearby': ['Colosseum'],
      'request': 'who painted it?',
    });
  });

  test('assumes a short story when an older server sends no duration', () async {
    final (service, _) = serviceAnswering(json({'text': 'Hi.'}));
    expect((await service.explainPlace(samplePoi(), language: 'English')).minutes, 1);
  });

  test('surfaces the message the server gives', () async {
    final (service, _) = serviceAnswering(json({'error': 'AI guide is not configured'}, 503));
    expect(
      () => service.explainPlace(samplePoi(), language: 'English'),
      throwsA(isA<GuideException>().having((e) => e.message, 'message', 'AI guide is not configured')),
    );
  });

  test('gives a readable message when the server reply is not JSON', () async {
    final (service, _) = serviceAnswering(http.Response('<html>Bad gateway</html>', 502));
    expect(
      () => service.explainPlace(samplePoi(), language: 'English'),
      throwsA(isA<GuideException>().having((e) => e.message, 'message', contains('502'))),
    );
  });

  test('gives a readable message when the server cannot be reached', () async {
    final client = MockClient((_) async => throw http.ClientException('Connection refused'));
    final service = HttpGuideService(baseUrl: 'http://host:3000', client: client);
    expect(
      () => service.explainPlace(samplePoi(), language: 'English'),
      throwsA(isA<GuideException>().having((e) => e.message, 'message', contains('reach'))),
    );
  });
}
