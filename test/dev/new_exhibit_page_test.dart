import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/dev/dev_models.dart';
import 'package:my_tour/src/features/dev/dev_service.dart';
import 'package:my_tour/src/features/dev/exhibit_controller.dart';
import 'package:my_tour/src/features/dev/new_exhibit_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  Future<TestApp> openPage(WidgetTester tester, {bool started = true}) async {
    tester.view.physicalSize = const Size(1080, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final app = TestApp()..dev.style = 'Warm.';
    await app.pump(tester, NewExhibitPage(poi: samplePoi(), lat: 1, lon: 2));
    if (started) {
      await tester.tap(find.byKey(const Key('startExhibitButton')));
      await tester.pumpAndSettle();
    }
    return app;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  ExhibitState state(TestApp app) => app.container.read(exhibitControllerProvider);

  testWidgets('is clearly marked as developer mode, in red', (tester) async {
    await openPage(tester, started: false);

    final badge = tester.widget<Text>(find.text('DEV'));
    expect(badge.style!.color, Colors.red);
    expect(find.text('New exhibit'), findsOneWidget);
  });

  testWidgets('starts an exhibit named after the place, which can be renamed', (tester) async {
    final app = await openPage(tester, started: false);
    expect(find.widgetWithText(TextField, 'City Museum'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('exhibitNameField')), 'Museum, east wing');
    await tap(tester, 'startExhibitButton');

    expect(state(app).exhibit!.placeName, 'Museum, east wing');
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
  });

  testWidgets('record, pause while walking to the next site, resume, save', (tester) async {
    final app = await openPage(tester);

    await tap(tester, 'recordButton');
    expect(find.text('Recording'), findsOneWidget);

    await tap(tester, 'pauseButton');
    expect(find.text('Paused'), findsOneWidget);

    await tap(tester, 'resumeButton');
    await tap(tester, 'saveRecordingButton');

    expect(app.recorder.calls, ['start', 'stop', 'start', 'stop']);
    expect(find.text('Focus on the murals.'), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
  });

  testWidgets('a recording can be discarded instead of saved', (tester) async {
    final app = await openPage(tester);

    await tap(tester, 'recordButton');
    await tap(tester, 'discardRecordingButton');

    expect(app.recorder.calls, ['start', 'cancel']);
    expect(state(app).exhibit!.lessons, isEmpty);
  });

  testWidgets('a saved lesson can be ignored if it is not good enough', (tester) async {
    final app = await openPage(tester);
    await tap(tester, 'recordButton');
    await tap(tester, 'saveRecordingButton');
    final id = state(app).exhibit!.lessons.single.id;

    await tap(tester, 'ignore_$id');

    expect(find.text('Ignored'), findsOneWidget);
    expect(find.byKey(Key('ignore_$id')), findsNothing);
    expect(app.dev.calls.last, 'ignoreLesson:ex1:$id');
  });

  testWidgets('shows that a saved recording is still being transcribed', (tester) async {
    final app = await openPage(tester);
    app.dev.learnedNotes = '';

    await tap(tester, 'recordButton');
    await tester.tap(find.byKey(const Key('saveRecordingButton')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Transcribing'), findsOneWidget);
    expect(find.textContaining('1 of 2'), findsOneWidget);

    // Stop the page from checking back, so the test can end.
    await app.container.read(exhibitControllerProvider.notifier).discardExhibit();
    await tester.pumpAndSettle();
  });

  testWidgets('a lesson with a problem can be retried', (tester) async {
    final app = await openPage(tester);
    await tap(tester, 'recordButton');
    await tap(tester, 'saveRecordingButton');
    final id = state(app).exhibit!.lessons.single.id;
    app.dev.onServer = Exhibit(
      id: 'ex1',
      placeName: 'City Museum',
      lessons: [Lesson(id: id, source: LessonSource.recording, problem: 'Speech-to-text failed (HTTP 500)')],
    );
    await app.container.read(exhibitControllerProvider.notifier).refresh();
    await tester.pump();

    expect(find.text('Speech-to-text failed (HTTP 500)'), findsOneWidget);
    await tester.tap(find.byKey(Key('retry_$id')));
    await tester.pump();

    expect(app.dev.calls.last, 'retryLesson:ex1:$id');

    await app.container.read(exhibitControllerProvider.notifier).discardExhibit();
    await tester.pumpAndSettle();
  });

  testWidgets('says how many pieces are waiting to upload', (tester) async {
    final app = await openPage(tester);
    app.dev.error = DevServiceException('Could not reach the server.');

    await tap(tester, 'recordButton');
    await tap(tester, 'pauseButton');

    expect(find.textContaining('1 piece waiting to upload'), findsOneWidget);
  });

  testWidgets('notes can be typed instead of recorded', (tester) async {
    final app = await openPage(tester);

    await tester.enterText(find.byKey(const Key('lessonField')), 'Start with the view.');
    await tap(tester, 'addLessonButton');

    expect(find.text('Notes on: Start with the view.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('lessonField'))).controller!.text, isEmpty);
    expect(app.dev.calls.last, 'addTypedLesson:ex1:Start with the view.');
  });

  testWidgets('photos taken here are added for travellers to see later', (tester) async {
    final app = await openPage(tester);

    await tap(tester, 'addPhotoButton');

    expect(app.picker.requests, [true]);
    expect(find.text('1 photo'), findsOneWidget);
    expect(app.dev.calls.last, startsWith('addPhoto:ex1:image/jpeg'));
  });

  testWidgets('the style the guide should use can be taught', (tester) async {
    final app = await openPage(tester);
    expect(find.widgetWithText(TextField, 'Warm.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('styleField')), 'Warm, with one joke.');
    await tap(tester, 'saveStyleButton');

    expect(app.dev.style, 'Warm, with one joke.');
    expect(find.text('Style saved'), findsOneWidget);
  });

  testWidgets('reminds the developer to ask the guide first', (tester) async {
    await openPage(tester);
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('shows problems reported by the server', (tester) async {
    final app = await openPage(tester);
    app.dev.error = DevServiceException('Could not reach the server.');

    await tester.enterText(find.byKey(const Key('lessonField')), 'x');
    await tap(tester, 'addLessonButton');

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });
}
