import 'dart:typed_data';

import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';
import 'package:my_tour/src/features/guide/photo_picker.dart';
import 'package:my_tour/src/features/guide/rest_spot_service.dart';
import 'package:my_tour/src/features/poi/poi_model.dart';
import 'package:my_tour/src/services/speech_engine.dart';
import 'package:my_tour/src/services/voice_input.dart';

/// Storage that lives in memory.
class InMemoryStore implements KeyValueStore {
  InMemoryStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Records what was spoken instead of making sound.
class FakeSpeechEngine implements SpeechEngine {
  final List<({String text, String languageCode})> spoken = [];
  int stops = 0;
  void Function()? _onDone;

  @override
  Future<void> speak(String text, {required String languageCode}) async {
    spoken.add((text: text, languageCode: languageCode));
  }

  @override
  Future<void> stop() async => stops++;

  @override
  void onDone(void Function() callback) => _onDone = callback;

  /// Simulate the voice reaching the end of the text.
  void finish() => _onDone?.call();
}

/// Answers with canned stories and records the requests.
class FakeGuideService implements GuideService {
  FakeGuideService({this.placeStory = 'A story.', this.photoStory = 'A photo story.', this.error});

  String placeStory;
  String photoStory;

  /// How long the stories claim to take.
  int minutes = 1;
  GuideException? error;
  final List<({Poi poi, String language, List<String> interests, String request})> placeRequests = [];
  final List<PhotoRequest> photoRequests = [];

  @override
  Future<GuideStory> explainPlace(
    Poi poi, {
    required String language,
    List<String> interests = const [],
    String request = '',
  }) async {
    placeRequests.add((poi: poi, language: language, interests: interests, request: request));
    if (error != null) throw error!;
    return GuideStory(text: placeStory, minutes: minutes);
  }

  @override
  Future<GuideStory> explainPhoto(PhotoRequest request) async {
    photoRequests.add(request);
    if (error != null) throw error!;
    return GuideStory(text: photoStory, minutes: minutes);
  }
}

/// Offers prepared places to sit and records where it was asked about.
class FakeRestSpotService implements RestSpotService {
  List<RestSpot> spots = const [];
  final List<({double lat, double lon})> searches = [];

  @override
  Future<List<RestSpot>> find({required double lat, required double lon}) async {
    searches.add((lat: lat, lon: lon));
    return spots;
  }
}

const garden = RestSpot(id: 'g', name: 'Giardino Bellini', kind: RestSpotKind.garden, lat: 37.51, lon: 15.08, distance: 120);
const cafe = RestSpot(id: 'c', name: 'Caffè Europa', kind: RestSpotKind.cafe, lat: 37.50, lon: 15.09, distance: 60);

/// "Hears" a prepared sentence, or nothing.
class FakeVoiceInput implements VoiceInput {
  String? heard;
  Object? error;
  final List<String> languages = [];

  @override
  Future<String?> listen({required String languageCode}) async {
    languages.add(languageCode);
    if (error != null) throw error!;
    return heard;
  }
}

/// Returns a prepared photo, or null as if the user cancelled.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.photo);

  PickedPhoto? photo;
  final List<bool> requests = [];

  @override
  Future<PickedPhoto?> pick({required bool fromCamera}) async {
    requests.add(fromCamera);
    return photo;
  }
}

final samplePhoto = PickedPhoto(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg');

Poi samplePoi({
  String id = 'poi_1',
  String name = 'City Museum',
  List<String> categories = const ['museum'],
  PoiReason reason = PoiReason.interest,
  bool outsideRadius = false,
  int distance = 120,
}) {
  return Poi(
    id: id,
    name: name,
    categories: categories,
    lat: 41.89,
    lon: 12.49,
    snippet: 'A museum',
    distance: distance,
    reason: reason,
    outsideRadius: outsideRadius,
  );
}
