import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../poi/poi_model.dart';
import '../poi/poi_service.dart' show serverErrorMessage;
import 'photo_picker.dart';

/// A problem the traveller should be told about, in plain words.
class GuideException implements Exception {
  final String message;

  GuideException(this.message);

  @override
  String toString() => message;
}

/// What the guide tells: the text, and how long it takes to say.
@immutable
class GuideStory {
  final String text;

  /// Whole minutes of speech, at least one.
  final int minutes;

  const GuideStory({required this.text, required this.minutes});
}

/// A photo and everything that helps the guide recognise it.
@immutable
class PhotoRequest {
  final PickedPhoto photo;
  final String language;
  /// Where the traveller is standing, when known.
  final double? lat;
  final double? lon;

  /// The place being visited, when the photo was taken from its page.
  final String? placeName;

  /// Names of places around the traveller.
  final List<String> nearby;

  /// What the traveller wrote or said to the guide, if anything.
  final String request;

  const PhotoRequest({
    required this.photo,
    required this.language,
    required this.lat,
    required this.lon,
    this.placeName,
    this.nearby = const [],
    this.request = '',
  });

  /// The same photo with something the traveller asked about it.
  PhotoRequest asking(String request) {
    return PhotoRequest(
      photo: photo,
      language: language,
      lat: lat,
      lon: lon,
      placeName: placeName,
      nearby: nearby,
      request: request,
    );
  }

  Map<String, dynamic> toJson() => {
        'image': base64Encode(photo.bytes),
        'mediaType': photo.mediaType,
        'language': language,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (placeName != null) 'placeName': placeName,
        'nearby': nearby,
        if (request.isNotEmpty) 'request': request,
      };
}

/// The AI tour guide.
abstract class GuideService {
  /// The story of a place, written in [language] (an English language name).
  ///
  /// [request] is what the traveller wrote or said to the guide, such as
  /// "more thorough please". Without one, a story takes at most ten minutes.
  Future<GuideStory> explainPlace(
    Poi poi, {
    required String language,
    List<String> interests,
    String request,
  });

  /// The story behind a photo.
  Future<GuideStory> explainPhoto(PhotoRequest request);
}

/// [GuideService] backed by the app's server.
class HttpGuideService implements GuideService {
  HttpGuideService({required this.baseUrl, required http.Client client})
      : _client = client;

  final String baseUrl;
  final http.Client _client;

  /// Writing a ten-minute story takes the AI about half a minute, and a
  /// thorough one over a minute.
  static const Duration timeout = Duration(seconds: 180);

  @override
  Future<GuideStory> explainPlace(
    Poi poi, {
    required String language,
    List<String> interests = const [],
    String request = '',
  }) {
    return _post('/guide/explain', {
      'place': poi.toJson(),
      'language': language,
      'interests': interests,
      if (request.isNotEmpty) 'request': request,
    });
  }

  @override
  Future<GuideStory> explainPhoto(PhotoRequest request) {
    return _post('/guide/photo', request.toJson());
  }

  /// POST [body] and return the story in the answer.
  Future<GuideStory> _post(String path, Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw GuideException('Could not reach the guide. Check your connection.');
    }

    final story = response.statusCode == 200 ? _storyOf(response) : null;
    if (story == null) throw GuideException(_failureMessage(response));
    return story;
  }

  GuideStory? _storyOf(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final minutes = (json['minutes'] as num?)?.round() ?? 1;
      return GuideStory(text: json['text'] as String, minutes: minutes);
    } catch (_) {
      return null;
    }
  }

  String _failureMessage(http.Response response) {
    return serverErrorMessage(utf8.decode(response.bodyBytes, allowMalformed: true)) ??
        'The guide is unavailable right now (error ${response.statusCode}).';
  }
}

final guideServiceProvider = Provider<GuideService>((ref) {
  return HttpGuideService(
    baseUrl: ref.watch(apiBaseUrlProvider),
    client: ref.watch(httpClientProvider),
  );
});
