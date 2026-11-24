import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/guide/guide_controller.dart';
import 'package:my_tour/src/features/guide/guide_service.dart';
import 'package:my_tour/src/features/place/place_page.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

void main() {
  /// A home screen with a button that opens the place page, as the map does.
  Future<TestApp> openPlace(WidgetTester tester, {TestApp? app}) async {
    app ??= TestApp();
    await app.pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PlacePage(poi: samplePoi())),
            ),
            child: const Text('the map'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('the map'));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('shows the website of the place', (tester) async {
    final app = await openPlace(tester);

    expect(find.text('City Museum'), findsOneWidget);
    expect(app.openedUrls.single.host, 'www.google.com'); // sample place has no site
    expect(app.guide.placeRequests, isEmpty, reason: 'no AI call until asked');
  });

  testWidgets('the arrow in the top left corner returns to the app', (tester) async {
    await openPlace(tester);

    final arrow = find.byKey(const Key('backToAppButton'));
    expect(tester.getTopLeft(arrow).dx, lessThan(20));
    expect(tester.getTopLeft(arrow).dy, lessThan(40));

    await tester.tap(arrow);
    await tester.pumpAndSettle();

    expect(find.text('the map'), findsOneWidget);
    expect(find.byType(PlacePage), findsNothing);
  });

  testWidgets('listen reads the explanation aloud while the site stays open', (tester) async {
    final app = await openPlace(tester);

    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();

    expect(app.speech.spoken.single.text, 'A story.');
    expect(find.byKey(const Key('placeWebView')), findsOneWidget);
    expect(find.text('A story.'), findsNothing, reason: 'the text is only shown on request');
    expect(find.byTooltip('Stop listening'), findsOneWidget);

    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Listen to the explanation'), findsOneWidget);
  });

  testWidgets('the book icon opens the explanation as text', (tester) async {
    final app = await openPlace(tester);
    final book = find.descendant(
      of: find.byKey(const Key('readButton')),
      matching: find.byIcon(Icons.menu_book),
    );
    expect(book, findsOneWidget);

    await tester.tap(find.byKey(const Key('readButton')));
    await tester.pumpAndSettle();

    expect(find.text('A story.'), findsOneWidget);
    expect(app.speech.spoken, isEmpty, reason: 'reading is silent');
  });

  testWidgets('the text can be opened while listening without interrupting', (tester) async {
    final app = await openPlace(tester);

    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readButton')));
    await tester.pumpAndSettle();

    expect(find.text('A story.'), findsOneWidget);
    expect(app.guide.placeRequests, hasLength(1));
    expect(app.container.read(guideControllerProvider).isSpeaking, isTrue);
  });

  testWidgets('says so when the explanation cannot be fetched', (tester) async {
    final app = TestApp()..guide.error = GuideException('AI guide is not configured');
    await openPlace(tester, app: app);

    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();

    expect(find.text('AI guide is not configured'), findsOneWidget);
    expect(app.speech.spoken, isEmpty);
  });

  testWidgets('offers a seat before a long explanation, or explains on the spot', (tester) async {
    final app = TestApp()
      ..guide.minutes = 6
      ..restSpots.spots = const [garden];
    await openPlace(tester, app: app);

    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('about 6 minutes'), findsOneWidget);
    expect(find.text('Giardino Bellini'), findsOneWidget);
    expect(app.speech.spoken, isEmpty);

    await tester.tap(find.byKey(const Key('explainHereButton')));
    await tester.pumpAndSettle();
    expect(app.speech.spoken.single.text, 'A story.');
  });

  testWidgets('the text sheet shows the length and takes requests', (tester) async {
    final app = await openPlace(tester);
    app.guide.minutes = 4;

    await tester.tap(find.byKey(const Key('readButton')));
    await tester.pumpAndSettle();

    expect(find.text('About 4 min'), findsOneWidget);
    expect(find.byKey(const Key('askField')), findsOneWidget);
  });

  testWidgets('leaving the page stops the voice', (tester) async {
    final app = await openPlace(tester);
    await tester.tap(find.byKey(const Key('listenButton')));
    await tester.pumpAndSettle();
    final stopsBefore = app.speech.stops;

    await tester.tap(find.byKey(const Key('backToAppButton')));
    await tester.pumpAndSettle();

    expect(app.speech.stops, greaterThan(stopsBefore));
    expect(app.container.read(guideControllerProvider).isSpeaking, isFalse);
  });
}
