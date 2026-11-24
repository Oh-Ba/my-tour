import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/dev/dev_service.dart';
import 'package:my_tour/src/features/dev/voice_recorder.dart';
import 'package:my_tour/src/features/guide/guide_language.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';
import 'package:my_tour/src/features/guide/photo_picker.dart';
import 'package:my_tour/src/features/guide/rest_spot_service.dart';
import 'package:my_tour/src/features/place/site_view.dart';
import 'package:my_tour/src/features/poi/poi_service.dart';
import 'package:my_tour/src/services/speech_engine.dart';
import 'package:my_tour/src/services/voice_input.dart';

import 'dev_fakes.dart';
import 'fakes.dart';

/// The fakes behind a pumped screen, for assertions.
class TestApp {
  /// [poiService] replaces the backend for screens that list places.
  TestApp({this.poiService});

  final PoiService? poiService;
  final InMemoryStore store = InMemoryStore();
  final FakeGuideService guide = FakeGuideService();
  final FakeSpeechEngine speech = FakeSpeechEngine();
  final FakePhotoPicker picker = FakePhotoPicker(samplePhoto);

  final FakeDevService dev = FakeDevService();
  final FakeVoiceRecorder recorder = FakeVoiceRecorder();
  final FakeRestSpotService restSpots = FakeRestSpotService();
  final FakeVoiceInput voice = FakeVoiceInput();

  /// Walking directions the app asked the phone to open.
  final List<Uri> directions = [];

  /// Addresses the place page asked its web view to show.
  final List<Uri> openedUrls = [];
  late final overrides = [
    keyValueStoreProvider.overrideWithValue(store),
    deviceLanguageCodeProvider.overrideWithValue('en'),
    guideServiceProvider.overrideWithValue(guide),
    speechEngineProvider.overrideWithValue(speech),
    photoPickerProvider.overrideWithValue(picker),
    restSpotServiceProvider.overrideWithValue(restSpots),
    devServiceProvider.overrideWithValue(dev),
    voiceRecorderProvider.overrideWithValue(recorder),
    voiceInputProvider.overrideWithValue(voice),
    directionsLauncherProvider.overrideWithValue((url) async => directions.add(url)),
    // A real web view needs the phone; show the address instead.
    siteViewBuilderProvider.overrideWithValue((url) {
      openedUrls.add(url);
      return Text(url.toString(), key: const Key('placeWebView'));
    }),
    if (poiService != null) poiServiceProvider.overrideWithValue(poiService!),
  ];
  late final ProviderContainer container = ProviderContainer(overrides: overrides);

  /// Show [child] inside an app wired to the fakes.
  Future<void> pump(WidgetTester tester, Widget child) async {
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }
}
