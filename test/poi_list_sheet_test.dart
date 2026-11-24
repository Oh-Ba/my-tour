import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/poi/poi_list_sheet.dart';
import 'package:my_tour/src/features/poi/poi_query.dart';
import 'package:my_tour/src/features/poi/poi_repository.dart';
import 'package:my_tour/src/features/poi/poi_service.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

class _StubPoiService implements PoiService {
  _StubPoiService(this.pois, {this.error});

  final List<Poi> pois;
  final PoiServiceException? error;

  @override
  Future<PoiResponse> fetchPois({required double lat, required double lon, required PoiQuery query}) async {
    if (error != null) throw error!;
    return PoiResponse(count: pois.length, radius: query.radiusM, pois: pois);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final pois = [
    samplePoi(id: 'thrift', name: 'Thrift Corner', categories: ['second_hand'], distance: 300),
    samplePoi(id: 'museum', name: 'City Museum', reason: PoiReason.classic, distance: 100),
    samplePoi(
      id: 'lookout',
      name: 'Hill Lookout',
      categories: ['viewpoint'],
      reason: PoiReason.forYou,
      outsideRadius: true,
      distance: 4200,
    ),
  ];

  Future<(TestApp, List<String>)> pumpSheet(WidgetTester tester, {PoiServiceException? error}) async {
    final events = <String>[];
    // The list reads the repository, so load it through a stub service.
    final app = TestApp(poiService: _StubPoiService(pois, error: error));
    await app.container.read(poiRepositoryProvider.notifier).fetchPois(
          lat: 1,
          lon: 2,
          query: const PoiQuery(radiusM: 1000, classics: true),
        );
    await app.pump(
      tester,
      Scaffold(
        body: Stack(
          children: [
            PoiListSheet(
              onPoiTap: (id) => events.add('tap:$id'),
              onEditTrip: () => events.add('edit'),
              onEndTrip: () => events.add('end'),
              onRetry: () => events.add('retry'),
            ),
          ],
        ),
      ),
    );
    return (app, events);
  }

  testWidgets('lists places nearest first and says why each is there', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pumpSheet(tester);

    expect(find.text('3 found'), findsOneWidget);
    final museum = tester.getTopLeft(find.text('City Museum')).dy;
    final thrift = tester.getTopLeft(find.text('Thrift Corner')).dy;
    final lookout = tester.getTopLeft(find.text('Hill Lookout')).dy;
    expect(museum, lessThan(thrift));
    expect(thrift, lessThan(lookout));

    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('For you · beyond your radius'), findsOneWidget);
  });

  testWidgets('the header lets the traveller edit or end the tour', (tester) async {
    final (_, events) = await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('editTripButton')));
    await tester.tap(find.byKey(const Key('endTripButton')));

    expect(events, ['edit', 'end']);
  });

  testWidgets('a failed search says why in plain words and can be retried', (tester) async {
    final (_, events) = await pumpSheet(
      tester,
      error: PoiServiceException('Could not reach the tour server.'),
    );

    expect(find.text('Could not reach the tour server.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    await tester.tap(find.byKey(const Key('retryPlacesButton')));
    expect(events, ['retry']);
  });

  testWidgets('tapping a place selects it', (tester) async {
    final (app, events) = await pumpSheet(tester);

    await tester.tap(find.text('City Museum'));
    await tester.pump();

    expect(events, ['tap:museum']);
    expect(app.container.read(poiRepositoryProvider).selectedPoiId, 'museum');
  });
}
