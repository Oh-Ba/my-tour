import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/trip_start/trip_sheet.dart';
import 'package:my_tour/src/features/trip_start/trip_state.dart';

import 'helpers/pump.dart';

void main() {
  /// A page with one button that opens the tour sheet.
  Future<TestApp> openSheet(WidgetTester tester, {TestApp? app}) async {
    app ??= TestApp();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await app.pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTripSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return app;
  }

  Checkbox classicsCheckbox(WidgetTester tester) {
    return tester.widget<Checkbox>(
      find.descendant(of: find.byKey(const Key('classicsCheckbox')), matching: find.byType(Checkbox)),
    );
  }

  ElevatedButton startButton(WidgetTester tester) {
    return tester.widget<ElevatedButton>(find.byKey(const Key('startTripButton')));
  }

  TripConfig trip(TestApp app) => app.container.read(tripStateProvider);

  testWidgets('a new tour has classic recommendations checked and can start at once', (tester) async {
    final app = await openSheet(tester);

    expect(classicsCheckbox(tester).value, isTrue);
    expect(startButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('startTripButton')));
    await tester.pumpAndSettle();

    expect(trip(app).isActive, isTrue);
    expect(trip(app).includeClassics, isTrue);
    expect(find.byKey(const Key('startTripButton')), findsNothing);
  });

  testWidgets('cannot start with nothing to look for', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('classicsCheckbox')));
    await tester.pumpAndSettle();

    expect(classicsCheckbox(tester).value, isFalse);
    expect(startButton(tester).onPressed, isNull);

    await tester.tap(find.text('Museums'));
    await tester.pumpAndSettle();
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('the traveller can type their own interest', (tester) async {
    final app = await openSheet(tester);

    await tester.enterText(find.byKey(const Key('customInterestField')), 'Second hand stores');
    await tester.tap(find.byKey(const Key('addCustomInterestButton')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Second hand stores'), findsOneWidget);

    await tester.tap(find.text('Parks'));
    await tester.tap(find.byKey(const Key('startTripButton')));
    await tester.pumpAndSettle();

    expect(trip(app).customInterests, ['Second hand stores']);
    expect(trip(app).interests, ['Parks']);
  });

  testWidgets('a typed interest that was not added yet is still used', (tester) async {
    final app = await openSheet(tester);

    await tester.enterText(find.byKey(const Key('customInterestField')), 'vinyl');
    await tester.tap(find.byKey(const Key('startTripButton')));
    await tester.pumpAndSettle();

    expect(trip(app).customInterests, ['vinyl']);
  });

  testWidgets('classic recommendations are checked again on the next tour', (tester) async {
    final app = TestApp();
    final notifier = app.container.read(tripStateProvider.notifier);
    await notifier.loaded;
    await notifier.startTrip(const TripConfig(interests: ['Parks'], includeClassics: false));
    await notifier.endTrip();

    await openSheet(tester, app: app);

    expect(classicsCheckbox(tester).value, isTrue);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Parks')).selected, isTrue);
  });

  testWidgets('editing a running tour keeps its choices', (tester) async {
    final app = TestApp();
    final notifier = app.container.read(tripStateProvider.notifier);
    await notifier.loaded;
    await notifier.startTrip(const TripConfig(interests: ['Parks'], includeClassics: false));

    await openSheet(tester, app: app);

    expect(classicsCheckbox(tester).value, isFalse);
    expect(find.text('Update Tour'), findsOneWidget);
  });
}
