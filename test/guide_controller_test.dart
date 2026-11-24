import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/guide/guide_controller.dart';
import 'package:my_tour/src/features/guide/guide_language.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';
import 'package:my_tour/src/features/guide/rest_spot_service.dart';
import 'package:my_tour/src/features/profile/interest_profile.dart';
import 'package:my_tour/src/features/trip_start/trip_state.dart';
import 'package:my_tour/src/services/speech_engine.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeGuideService service;
  late FakeSpeechEngine speech;
  late FakeRestSpotService restSpots;
  late List<Uri> directions;
  late ProviderContainer container;

  GuideController controller() => container.read(guideControllerProvider.notifier);
  GuideState state() => container.read(guideControllerProvider);

  setUp(() async {
    service = FakeGuideService();
    speech = FakeSpeechEngine();
    restSpots = FakeRestSpotService();
    directions = [];
    container = ProviderContainer(
      overrides: [
        restSpotServiceProvider.overrideWithValue(restSpots),
        directionsLauncherProvider.overrideWithValue((url) async => directions.add(url)),
        keyValueStoreProvider.overrideWithValue(InMemoryStore()),
        deviceLanguageCodeProvider.overrideWithValue('en'),
        guideServiceProvider.overrideWithValue(service),
        speechEngineProvider.overrideWithValue(speech),
      ],
    );
    addTearDown(container.dispose);
    await container.read(interestProfileProvider.notifier).loaded;
    await container.read(tripStateProvider.notifier).loaded;
  });

  test('starts idle', () {
    expect(state().status, GuideStatus.idle);
    expect(state().isSpeaking, isFalse);
  });

  test('tells the story of a place in the chosen language', () async {
    await container.read(guideLanguageProvider.notifier).select(languageByCode('fr-FR'));
    await container
        .read(tripStateProvider.notifier)
        .startTrip(const TripConfig(interests: ['Museums'], customInterests: ['vinyl']));

    await controller().explainPlace(samplePoi());

    expect(state().status, GuideStatus.ready);
    expect(state().text, 'A story.');
    expect(service.placeRequests.single.language, 'French');
    expect(service.placeRequests.single.interests, ['Museums', 'vinyl']);
  });

  test('speaks the story aloud when asked to autoplay', () async {
    await controller().explainPlace(samplePoi(), autoPlay: true);

    expect(speech.spoken.single, (text: 'A story.', languageCode: 'en-US'));
    expect(state().isSpeaking, isTrue);
  });

  test('play then stop toggles the voice', () async {
    await controller().explainPlace(samplePoi());
    expect(speech.spoken, isEmpty);

    await controller().toggleSpeech();
    expect(state().isSpeaking, isTrue);

    await controller().toggleSpeech();
    expect(state().isSpeaking, isFalse);
    expect(speech.stops, greaterThan(0));
  });

  test('knows when the voice has finished', () async {
    await controller().explainPlace(samplePoi(), autoPlay: true);
    speech.finish();
    expect(state().isSpeaking, isFalse);
  });

  test('learns from what the traveller opens, hears and photographs', () async {
    final poi = samplePoi(categories: ['viewpoint']);

    await controller().explainPlace(poi);
    expect(container.read(interestProfileProvider)['viewpoint'], Engagement.viewed.weight);

    await controller().toggleSpeech();
    expect(
      container.read(interestProfileProvider)['viewpoint'],
      Engagement.viewed.weight + Engagement.listened.weight,
    );

    await controller().explainPhoto(samplePhoto, lat: 1, lon: 2, poi: poi);
    expect(
      container.read(interestProfileProvider)['viewpoint'],
      Engagement.viewed.weight + Engagement.listened.weight + Engagement.photographed.weight,
    );
  });

  test('tells the story behind a photo with location hints', () async {
    await controller().explainPhoto(
      samplePhoto,
      lat: 41.89,
      lon: 12.49,
      poi: samplePoi(),
      nearby: ['Colosseum'],
    );

    expect(state().status, GuideStatus.ready);
    expect(state().text, 'A photo story.');
    expect(state().photo, samplePhoto);
    final request = service.photoRequests.single;
    expect(request.placeName, 'City Museum');
    expect(request.nearby, ['Colosseum']);
    expect(request.language, 'English');
  });

  test('shows the error and stays silent when the guide fails', () async {
    service.error = GuideException('AI guide is not configured');

    await controller().explainPlace(samplePoi(), autoPlay: true);

    expect(state().status, GuideStatus.error);
    expect(state().error, 'AI guide is not configured');
    expect(speech.spoken, isEmpty);
  });

  test('retry repeats the last request', () async {
    service.error = GuideException('busy');
    await controller().explainPlace(samplePoi());

    service.error = null;
    await controller().retry();

    expect(state().status, GuideStatus.ready);
    expect(service.placeRequests, hasLength(2));
  });

  test('changing the language stops the voice and retells the story', () async {
    await controller().explainPlace(samplePoi(), autoPlay: true);
    service.placeStory = 'סיפור.';

    await controller().changeLanguage(languageByCode('he-IL'));

    expect(speech.stops, greaterThan(0));
    expect(state().text, 'סיפור.');
    expect(service.placeRequests.last.language, 'Hebrew');
    expect(container.read(guideLanguageProvider).code, 'he-IL');
  });

  group('on a place page', () {
    test('the first press of listen fetches the story and reads it aloud', () async {
      await controller().toggleListening(samplePoi());

      expect(service.placeRequests, hasLength(1));
      expect(speech.spoken.single.text, 'A story.');
      expect(state().isSpeaking, isTrue);
    });

    test('pressing listen again stops, then resumes, without asking again', () async {
      await controller().toggleListening(samplePoi());
      await controller().toggleListening(samplePoi());
      expect(state().isSpeaking, isFalse);

      await controller().toggleListening(samplePoi());
      expect(state().isSpeaking, isTrue);
      expect(service.placeRequests, hasLength(1));
    });

    test('listening to a different place starts its own story', () async {
      await controller().toggleListening(samplePoi());
      await controller().toggleListening(samplePoi(id: 'other', name: 'Other'));

      expect(service.placeRequests.map((r) => r.poi.id), ['poi_1', 'other']);
    });

    test('opening the text fetches the story silently', () async {
      await controller().ensureStory(samplePoi());

      expect(state().text, 'A story.');
      expect(speech.spoken, isEmpty);
    });

    test('opening the text while listening keeps the voice going', () async {
      await controller().toggleListening(samplePoi());
      await controller().ensureStory(samplePoi());

      expect(state().isSpeaking, isTrue);
      expect(speech.stops, 1); // only the stop that precedes every new story
      expect(service.placeRequests, hasLength(1));
    });

    test('opening the text after an error tries again', () async {
      service.error = GuideException('busy');
      await controller().ensureStory(samplePoi());
      service.error = null;

      await controller().ensureStory(samplePoi());

      expect(state().status, GuideStatus.ready);
    });
  });

  group('how long the story is', () {
    test('is known once the story arrives', () async {
      service.minutes = 7;
      await controller().explainPlace(samplePoi());
      expect(state().minutes, 7);
    });
  });

  group('a place to sit', () {
    setUp(() {
      service.minutes = 7;
      restSpots.spots = const [cafe, garden];
    });

    test('is offered before a long story is read aloud', () async {
      await controller().toggleListening(samplePoi());

      expect(state().seatOffer, const [cafe, garden]);
      expect(state().isSpeaking, isFalse);
      expect(speech.spoken, isEmpty);
      expect(restSpots.searches.single, (lat: 41.89, lon: 12.49), reason: 'near the place');
    });

    test('"explain here" starts the story on the spot', () async {
      await controller().toggleListening(samplePoi());
      await controller().explainHere();

      expect(state().seatOffer, isEmpty);
      expect(speech.spoken.single.text, 'A story.');
      expect(state().isSpeaking, isTrue);
    });

    test('choosing a spot opens walking directions and keeps the story ready', () async {
      await controller().toggleListening(samplePoi());
      await controller().goTo(garden);

      expect(directions.single.queryParameters['destination'], '37.51,15.08');
      expect(directions.single.queryParameters['travelmode'], 'walking');
      expect(state().seatOffer, isEmpty);
      expect(state().isSpeaking, isFalse);
      expect(state().status, GuideStatus.ready);

      await controller().toggleListening(samplePoi());
      expect(speech.spoken.single.text, 'A story.', reason: 'listen now simply plays');
      expect(service.placeRequests, hasLength(1));
    });

    test('is offered only once for a place', () async {
      await controller().toggleListening(samplePoi());
      await controller().dismissOffer();
      await controller().ask('tell me more', speak: true);

      expect(state().seatOffer, isEmpty);
      expect(state().isSpeaking, isTrue);
    });

    test('is not offered for a short story', () async {
      service.minutes = 2;
      await controller().toggleListening(samplePoi());

      expect(state().seatOffer, isEmpty);
      expect(state().isSpeaking, isTrue);
    });

    test('is not offered when nothing nice is nearby', () async {
      restSpots.spots = const [];
      await controller().toggleListening(samplePoi());

      expect(state().isSpeaking, isTrue);
    });

    test('is not offered when the story is only read as text', () async {
      await controller().ensureStory(samplePoi());

      expect(state().seatOffer, isEmpty);
      expect(restSpots.searches, isEmpty);
    });

    test('is not offered for a photo', () async {
      await controller().explainPhoto(samplePhoto, lat: 1, lon: 2, poi: samplePoi(), autoPlay: true);

      expect(state().seatOffer, isEmpty);
      expect(state().isSpeaking, isTrue);
    });
  });

  group('asking the guide', () {
    test('retells the story with what the traveller wrote', () async {
      await controller().explainPlace(samplePoi());
      service.placeStory = 'A much longer story.';
      service.minutes = 17;

      await controller().ask('  More thorough please  ');

      expect(service.placeRequests.last.request, 'More thorough please');
      expect(state().text, 'A much longer story.');
      expect(state().minutes, 17);
      expect(speech.spoken, isEmpty, reason: 'they were reading, not listening');
    });

    test('answers aloud when the traveller spoke the request', () async {
      await controller().explainPlace(samplePoi());
      await controller().ask('tell me about the architect', speak: true);

      expect(speech.spoken.single.text, 'A story.');
    });

    test('keeps speaking if the traveller was listening', () async {
      await controller().explainPlace(samplePoi(), autoPlay: true);
      await controller().ask('more detail');

      expect(state().isSpeaking, isTrue);
    });

    test('ignores an empty request', () async {
      await controller().explainPlace(samplePoi());
      await controller().ask('   ');
      expect(service.placeRequests, hasLength(1));
    });

    test('carries over when the language changes, but not to another place', () async {
      await controller().explainPlace(samplePoi());
      await controller().ask('more detail');
      await controller().changeLanguage(languageByCode('he-IL'));
      expect(service.placeRequests.last.request, 'more detail');

      await controller().explainPlace(samplePoi(id: 'other'));
      expect(service.placeRequests.last.request, '');
    });

    test('works for photos too', () async {
      await controller().explainPhoto(samplePhoto, lat: 1, lon: 2);
      await controller().ask('who made it?');

      expect(service.photoRequests.last.request, 'who made it?');
    });
  });

  test('closing stops the voice and forgets the story', () async {
    await controller().explainPlace(samplePoi(), autoPlay: true);

    await controller().close();

    expect(state().status, GuideStatus.idle);
    expect(state().text, isNull);
    expect(speech.stops, greaterThan(0));
  });
}
