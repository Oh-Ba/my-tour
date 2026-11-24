import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/dev_mode.dart';
import '../guide/photo_picker.dart';
import '../poi/poi_service.dart' show serverErrorMessage;
import 'dev_models.dart';
import 'voice_recorder.dart';

/// A problem the developer should be told about, in plain words.
class DevServiceException implements Exception {
  final String message;

  DevServiceException(this.message);

  @override
  String toString() => message;
}

/// The developer's side of the server: teaching the guide.
abstract class DevService {
  Future<Exhibit> createExhibit({
    String? placeId,
    required String placeName,
    required double lat,
    required double lon,
  });

  /// Start a recording of a guide. Its audio follows in pieces.
  Future<Lesson> openRecording(String exhibitId);

  /// Send one piece of a recording; the server transcribes it in the
  /// background. [index] is its position in the recording.
  Future<Lesson> uploadSegment(
    String exhibitId,
    String lessonId, {
    required int index,
    required RecordedAudio audio,
  });

  /// All pieces are sent: the server learns from the whole recording.
  Future<Lesson> finishRecording(String exhibitId, String lessonId);

  /// Try again what failed in a lesson.
  Future<Lesson> retryLesson(String exhibitId, String lessonId);

  /// The exhibit as the server has it now, with transcription progress.
  Future<Exhibit> getExhibit(String exhibitId);

  /// Learn from notes or a transcript typed by the developer.
  Future<Lesson> addTypedLesson(String exhibitId, String text);

  /// Forget a lesson that was not good enough.
  Future<Lesson> ignoreLesson(String exhibitId, String lessonId);

  Future<ExhibitPhoto> addPhoto(String exhibitId, PickedPhoto photo, {String caption});

  Future<void> discardExhibit(String exhibitId);

  /// The style the guide is asked to speak in.
  Future<String> getStyle();

  Future<String> saveStyle(String text);
}

/// [DevService] backed by the app's server.
class HttpDevService implements DevService {
  HttpDevService({required this.baseUrl, required this.token, required http.Client client})
      : _client = client;

  final String baseUrl;
  final String token;
  final http.Client _client;

  /// A ten-minute piece is a few megabytes; allow for a slow connection.
  static const Duration timeout = Duration(minutes: 2);

  Uri _url(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl/dev$path').replace(queryParameters: query);
  }

  /// Why a request was turned down, for the developer to act on.
  String _failure(http.Response response) {
    if (response.statusCode == 401) {
      return 'The server refused the developer token. Check DEV_TOKEN in the app and the server.';
    }
    if (response.statusCode == 404 && serverErrorMessage(response.body) == null) {
      return 'Developer mode is off on the server. Set DEV_TOKEN in server/.env and restart it.';
    }
    return serverErrorMessage(response.body) ?? 'The server answered with error ${response.statusCode}.';
  }

  /// Send a request and return the decoded JSON answer (null if empty).
  Future<dynamic> _send(
    String method,
    Uri url, {
    Object? json,
    List<int>? bytes,
    String? contentType,
  }) async {
    final request = http.Request(method, url)..headers['x-dev-token'] = token;
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    if (bytes != null) {
      request.headers['Content-Type'] = contentType!;
      request.bodyBytes = bytes;
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } catch (_) {
      throw DevServiceException('Could not reach the server.');
    }
    if (response.statusCode >= 300) throw DevServiceException(_failure(response));
    return response.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Lesson> _lesson(Future<dynamic> answer) async {
    return Lesson.fromJson(await answer as Map<String, dynamic>);
  }

  @override
  Future<Exhibit> createExhibit({
    String? placeId,
    required String placeName,
    required double lat,
    required double lon,
  }) async {
    final answer = await _send('POST', _url('/exhibits'), json: {
      if (placeId != null) 'placeId': placeId,
      'placeName': placeName,
      'lat': lat,
      'lon': lon,
    });
    return Exhibit.fromJson(answer as Map<String, dynamic>);
  }

  @override
  Future<Lesson> openRecording(String exhibitId) {
    return _lesson(_send('POST', _url('/exhibits/$exhibitId/recordings')));
  }

  @override
  Future<Lesson> uploadSegment(
    String exhibitId,
    String lessonId, {
    required int index,
    required RecordedAudio audio,
  }) {
    final query = {'index': '$index', 'durationMs': '${audio.duration.inMilliseconds}'};
    return _lesson(_send(
      'POST',
      _url('/exhibits/$exhibitId/recordings/$lessonId/segments', query),
      bytes: audio.bytes,
      contentType: audio.mediaType,
    ));
  }

  @override
  Future<Lesson> finishRecording(String exhibitId, String lessonId) {
    return _lesson(_send('POST', _url('/exhibits/$exhibitId/recordings/$lessonId/finish')));
  }

  @override
  Future<Lesson> retryLesson(String exhibitId, String lessonId) {
    return _lesson(_send('POST', _url('/exhibits/$exhibitId/lessons/$lessonId/retry')));
  }

  @override
  Future<Exhibit> getExhibit(String exhibitId) async {
    final answer = await _send('GET', _url('/exhibits/$exhibitId'));
    return Exhibit.fromJson(answer as Map<String, dynamic>);
  }

  @override
  Future<Lesson> addTypedLesson(String exhibitId, String text) {
    return _lesson(_send('POST', _url('/exhibits/$exhibitId/lessons'), json: {'text': text}));
  }

  @override
  Future<Lesson> ignoreLesson(String exhibitId, String lessonId) {
    return _lesson(_send('POST', _url('/exhibits/$exhibitId/lessons/$lessonId/ignore')));
  }

  @override
  Future<ExhibitPhoto> addPhoto(String exhibitId, PickedPhoto photo, {String caption = ''}) async {
    final answer = await _send(
      'POST',
      _url('/exhibits/$exhibitId/photos', caption.isEmpty ? null : {'caption': caption}),
      bytes: photo.bytes,
      contentType: photo.mediaType,
    );
    return ExhibitPhoto.fromJson(answer as Map<String, dynamic>);
  }

  @override
  Future<void> discardExhibit(String exhibitId) => _send('DELETE', _url('/exhibits/$exhibitId'));

  @override
  Future<String> getStyle() async {
    return (await _send('GET', _url('/style')) as Map<String, dynamic>)['text'] as String? ?? '';
  }

  @override
  Future<String> saveStyle(String text) async {
    final answer = await _send('PUT', _url('/style'), json: {'text': text});
    return (answer as Map<String, dynamic>)['text'] as String? ?? '';
  }
}

final devServiceProvider = Provider<DevService>((ref) {
  return HttpDevService(
    baseUrl: ref.watch(apiBaseUrlProvider),
    token: devToken,
    client: ref.watch(httpClientProvider),
  );
});
