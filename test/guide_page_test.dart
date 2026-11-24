import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/guide/guide_page.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

void main() {
  GuidePage pageFor({bool autoPlay = false}) {
    return GuidePage(
      poi: samplePoi(),
      lat: 41.89,
      lon: 12.49,
      nearby: const ['Colosseum'],
      autoPlay: autoPlay,
    );
  }

  testWidgets('shows the story of the place', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());

    expect(find.text('City Museum'), findsOneWidget);
    expect(find.text('A story.'), findsOneWidget);
    expect(app.speech.spoken, isEmpty);
  });

  testWidgets('the listen button reads the story aloud and then stops it', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('speakButton')));
    await tester.pumpAndSettle();
    expect(app.speech.spoken.single.text, 'A story.');
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('speakButton')));
    await tester.pumpAndSettle();
    expect(find.text('Listen · 1 min'), findsOneWidget);
  });

  testWidgets('offers a place to sit before a long story and can explain on the spot', (tester) async {
    final app = TestApp()
      ..guide.minutes = 7
      ..restSpots.spots = const [cafe, garden];
    await app.pump(tester, pageFor(autoPlay: true));

    expect(find.textContaining('about 7 minutes'), findsOneWidget);
    expect(find.text('Caffè Europa'), findsOneWidget);
    expect(find.text('Giardino Bellini'), findsOneWidget);
    expect(find.textContaining('120 m'), findsOneWidget);
    expect(app.speech.spoken, isEmpty);

    await tester.tap(find.byKey(const Key('explainHereButton')));
    await tester.pumpAndSettle();

    expect(app.speech.spoken.single.text, 'A story.');
    expect(find.byKey(const Key('explainHereButton')), findsNothing);
  });

  testWidgets('"take me there" opens walking directions to the chosen spot', (tester) async {
    final app = TestApp()
      ..guide.minutes = 7
      ..restSpots.spots = const [cafe, garden];
    await app.pump(tester, pageFor(autoPlay: true));

    await tester.tap(find.byKey(const Key('goTo_g')));
    await tester.pumpAndSettle();

    expect(app.directions.single.queryParameters['destination'], '37.51,15.08');
    expect(app.speech.spoken, isEmpty);
    expect(find.text('A story.'), findsOneWidget, reason: 'the story waits for them');
  });

  testWidgets('the traveller can write to ask for a more thorough explanation', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());
    app.guide.placeStory = 'The thorough story.';

    await tester.enterText(find.byKey(const Key('askField')), 'Please be more thorough');
    await tester.tap(find.byKey(const Key('askSendButton')));
    await tester.pumpAndSettle();

    expect(app.guide.placeRequests.last.request, 'Please be more thorough');
    expect(find.text('The thorough story.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('askField'))).controller!.text, isEmpty);
  });

  testWidgets('the traveller can say what they want instead of writing it', (tester) async {
    final app = TestApp()..voice.heard = 'tell me more about the builders';
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('askMicButton')));
    await tester.pumpAndSettle();

    expect(app.voice.languages, ['en-US']);
    expect(app.guide.placeRequests.last.request, 'tell me more about the builders');
    expect(app.speech.spoken, isNotEmpty, reason: 'a spoken question gets a spoken answer');
  });

  testWidgets('one tap asks for a more thorough explanation', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('moreThoroughChip')));
    await tester.pumpAndSettle();

    expect(app.guide.placeRequests.last.request, contains('thorough'));
  });

  testWidgets('says so when the phone cannot listen', (tester) async {
    final app = TestApp()..voice.error = Exception('no recogniser');
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('askMicButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Voice input is not available'), findsOneWidget);
    expect(app.guide.placeRequests, hasLength(1));
  });

  testWidgets('starts speaking by itself when opened from a notification', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor(autoPlay: true));

    expect(app.speech.spoken.single.text, 'A story.');
  });

  testWidgets('taking a photo tells the story behind it', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('cameraButton')));
    await tester.pumpAndSettle();

    expect(app.picker.requests, [true]);
    expect(find.text('A photo story.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(app.guide.photoRequests.single.placeName, 'City Museum');
    expect(app.guide.photoRequests.single.nearby, ['Colosseum']);
  });

  testWidgets('cancelling the camera keeps the current story', (tester) async {
    final app = TestApp()..picker.photo = null;
    await app.pump(tester, pageFor());

    await tester.tap(find.byKey(const Key('cameraButton')));
    await tester.pumpAndSettle();

    expect(find.text('A story.'), findsOneWidget);
    expect(app.guide.photoRequests, isEmpty);
  });

  testWidgets('shows what went wrong and lets the traveller retry', (tester) async {
    final app = TestApp()..guide.error = GuideException('AI guide is not configured');
    await app.pump(tester, pageFor());

    expect(find.text('AI guide is not configured'), findsOneWidget);

    app.guide.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('A story.'), findsOneWidget);
  });

  testWidgets('choosing another language retells the story in it', (tester) async {
    final app = TestApp();
    await app.pump(tester, pageFor());
    app.guide.placeStory = 'סיפור.';

    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עברית').last);
    await tester.pumpAndSettle();

    expect(find.text('סיפור.'), findsOneWidget);
    expect(app.guide.placeRequests.last.language, 'Hebrew');
    expect(
      Directionality.of(tester.element(find.text('סיפור.'))),
      TextDirection.rtl,
    );
  });

  testWidgets('a photo taken from the map gets its story without a place', (tester) async {
    final app = TestApp();
    await app.pump(
      tester,
      GuidePage(initialPhoto: samplePhoto, lat: 41.89, lon: 12.49),
    );

    expect(find.text('A photo story.'), findsOneWidget);
    expect(app.guide.photoRequests.single.placeName, isNull);
    expect(app.guide.placeRequests, isEmpty);
  });
}
