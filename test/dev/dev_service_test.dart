import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_tour/src/features/dev/dev_models.dart';
import 'package:my_tour/src/features/dev/dev_service.dart';
import 'package:my_tour/src/features/dev/voice_recorder.dart';

import '../helpers/fakes.dart';

void main() {
  (HttpDevService, List<http.Request>) serviceAnswering(Object body, [int status = 200]) {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return (HttpDevService(baseUrl: 'http://host:3000', token: 'secret', client: client), requests);
  }

  const lessonJson = {
    'id': 'l1', 'source': 'recording', 'status': 'kept', 'durationMs': 42000,
    'transcript': 'words', 'notes': 'Focus on the murals.', 'awaitingTranscript': false,
  };

  test('reads a lesson', () {
    final lesson = Lesson.fromJson(lessonJson);
    expect(lesson.source, LessonSource.recording);
    expect(lesson.ignored, isFalse);
    expect(lesson.notes, 'Focus on the murals.');
    expect(lesson.durationMs, 42000);

    final ignored = Lesson.fromJson({...lessonJson, 'status': 'ignored', 'source': 'typed', 'problem': 'x'});
    expect(ignored.ignored, isTrue);
    expect(ignored.source, LessonSource.typed);
    expect(ignored.problem, 'x');
  });

  test('every request carries the developer token', () async {
    final (service, requests) = serviceAnswering({'text': 'Warm.'});
    await service.getStyle();
    expect(requests.single.headers['x-dev-token'], 'secret');
    expect(requests.single.url.path, '/dev/style');
  });

  test('creates an exhibit for a place', () async {
    final (service, requests) = serviceAnswering({'id': 'e1', 'placeName': 'Coit Tower', 'lessons': [], 'photos': []}, 201);

    final exhibit = await service.createExhibit(placeId: 'poi_4', placeName: 'Coit Tower', lat: 1.5, lon: 2.5);

    expect(exhibit.id, 'e1');
    expect(requests.single.method, 'POST');
    expect(jsonDecode(requests.single.body), {'placeId': 'poi_4', 'placeName': 'Coit Tower', 'lat': 1.5, 'lon': 2.5});
  });

  test('a recording is opened, sent in segments, and finished', () async {
    final (service, requests) = serviceAnswering({...lessonJson, 'processing': true, 'segmentCount': 3, 'transcribedCount': 1}, 201);
    final audio = RecordedAudio(
      bytes: Uint8List.fromList([9, 8, 7]),
      mediaType: 'audio/mp4',
      duration: const Duration(seconds: 42),
    );

    await service.openRecording('e1');
    final lesson = await service.uploadSegment('e1', 'l1', index: 2, audio: audio);
    await service.finishRecording('e1', 'l1');
    await service.retryLesson('e1', 'l1');

    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'POST /dev/exhibits/e1/recordings',
      'POST /dev/exhibits/e1/recordings/l1/segments',
      'POST /dev/exhibits/e1/recordings/l1/finish',
      'POST /dev/exhibits/e1/lessons/l1/retry',
    ]);
    final segment = requests[1];
    expect(segment.url.queryParameters, {'index': '2', 'durationMs': '42000'});
    expect(segment.headers['content-type'], 'audio/mp4');
    expect(segment.bodyBytes, [9, 8, 7]);
    expect(lesson.processing, isTrue);
    expect(lesson.segmentCount, 3);
    expect(lesson.transcribedCount, 1);
  });

  test('reloads an exhibit to see how transcription is going', () async {
    final (service, requests) = serviceAnswering({
      'id': 'e1', 'placeName': 'Coit Tower', 'lessons': [lessonJson], 'photos': [],
    });

    final exhibit = await service.getExhibit('e1');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/dev/exhibits/e1');
    expect(exhibit.lessons.single.notes, 'Focus on the murals.');
  });

  test('sends typed notes, ignores lessons, uploads photos, saves the style', () async {
    final (service, requests) = serviceAnswering({...lessonJson, 'id': 'p1', 'file': 'p.jpg', 'caption': 'Mural', 'text': 'Warm.'}, 201);

    await service.addTypedLesson('e1', 'Start with the view.');
    await service.ignoreLesson('e1', 'l1');
    await service.addPhoto('e1', samplePhoto, caption: 'Mural');
    await service.saveStyle('Warm.');
    await service.discardExhibit('e1');

    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'POST /dev/exhibits/e1/lessons',
      'POST /dev/exhibits/e1/lessons/l1/ignore',
      'POST /dev/exhibits/e1/photos',
      'PUT /dev/style',
      'DELETE /dev/exhibits/e1',
    ]);
    expect(jsonDecode(requests[0].body), {'text': 'Start with the view.'});
    expect(requests[2].url.queryParameters, {'caption': 'Mural'});
    expect(requests[2].headers['content-type'], 'image/jpeg');
    expect(jsonDecode(requests[3].body), {'text': 'Warm.'});
  });

  test('explains a refused token and other failures in plain words', () async {
    final (refused, _) = serviceAnswering({'error': 'Developer access only'}, 401);
    expect(
      () => refused.getStyle(),
      throwsA(isA<DevServiceException>().having((e) => e.message, 'message', contains('developer token'))),
    );

    final (missing, _) = serviceAnswering('Not found', 404);
    expect(
      () => missing.getStyle(),
      throwsA(isA<DevServiceException>().having((e) => e.message, 'message', contains('Developer mode is off'))),
    );

    final offline = HttpDevService(
      baseUrl: 'http://host:3000',
      token: 'secret',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(() => offline.getStyle(), throwsA(isA<DevServiceException>()));
  });
}
