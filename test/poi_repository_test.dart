import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/poi/poi_query.dart';
import 'package:my_tour/src/features/poi/poi_repository.dart';
import 'package:my_tour/src/features/poi/poi_service.dart';
import 'package:my_tour/src/features/trip_start/trip_state.dart';

import 'helpers/fakes.dart';

class FakePoiService implements PoiService {
  FakePoiService(this.pois);

  List<Poi> pois;
  Object? error;
  final List<PoiQuery> queries = [];

  @override
  Future<PoiResponse> fetchPois({required double lat, required double lon, required PoiQuery query}) async {
    queries.add(query);
    if (error != null) throw error!;
    return PoiResponse(count: pois.length, radius: query.radiusM, pois: pois);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('buildPoiQuery', () {
    test('turns the tour and what was learned into a query', () {
      const trip = TripConfig(
        interests: ['Museums'],
        customInterests: ['vinyl'],
        radiusKm: 2.5,
        includeClassics: true,
        isActive: true,
      );
      expect(
        buildPoiQuery(trip, ['viewpoint']),
        const PoiQuery(
          radiusM: 2500,
          interests: ['Museums', 'vinyl'],
          classics: true,
          learned: ['viewpoint'],
        ),
      );
    });
  });

  group('shouldFetch', () {
    const query = PoiQuery(radiusM: 1000, classics: true);

    test('always fetches the first time', () {
      expect(shouldFetch(query: query, movedMeters: null, lastQuery: null), isTrue);
    });

    test('skips when the traveller has barely moved and asks the same thing', () {
      expect(shouldFetch(query: query, movedMeters: 40, lastQuery: query), isFalse);
    });

    test('fetches after moving far enough', () {
      expect(shouldFetch(query: query, movedMeters: 150, lastQuery: query), isTrue);
    });

    test('fetches when the tour changed, even without moving', () {
      const changed = PoiQuery(radiusM: 1000, classics: false);
      expect(shouldFetch(query: changed, movedMeters: 0, lastQuery: query), isTrue);
    });
  });

  group('PoiRepository', () {
    const query = PoiQuery(radiusM: 1000, classics: true);

    (ProviderContainer, FakePoiService) setup(List<Poi> pois) {
      final service = FakePoiService(pois);
      final container = ProviderContainer(
        overrides: [poiServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      return (container, service);
    }

    test('loads places and skips a repeat from the same spot', () async {
      final (container, service) = setup([samplePoi()]);
      final repository = container.read(poiRepositoryProvider.notifier);

      await repository.fetchPois(lat: 1, lon: 2, query: query);
      await repository.fetchPois(lat: 1, lon: 2, query: query);

      expect(container.read(poiRepositoryProvider).pois.single.id, 'poi_1');
      expect(service.queries, hasLength(1));
    });

    test('refetches from the same spot when the tour changes', () async {
      final (container, service) = setup([samplePoi()]);
      final repository = container.read(poiRepositoryProvider.notifier);

      await repository.fetchPois(lat: 1, lon: 2, query: query);
      await repository.fetchPois(lat: 1, lon: 2, query: const PoiQuery(radiusM: 3000, classics: true));

      expect(service.queries, hasLength(2));
    });

    test('keeps the error and clears it on the next success', () async {
      final (container, service) = setup([samplePoi()]);
      final repository = container.read(poiRepositoryProvider.notifier);

      service.error = PoiServiceException('Network error');
      await repository.fetchPois(lat: 1, lon: 2, query: query);
      expect(container.read(poiRepositoryProvider).error, contains('Network error'));
      expect(container.read(poiRepositoryProvider).isLoading, isFalse);

      service.error = null;
      await repository.fetchPois(lat: 1, lon: 2, query: query);
      expect(container.read(poiRepositoryProvider).error, isNull);
    });

    test('clears everything when the tour ends', () async {
      final (container, _) = setup([samplePoi()]);
      final repository = container.read(poiRepositoryProvider.notifier);
      await repository.fetchPois(lat: 1, lon: 2, query: query);
      repository.selectPoi('poi_1');

      repository.clear();

      final state = container.read(poiRepositoryProvider);
      expect(state.pois, isEmpty);
      expect(state.selectedPoiId, isNull);
    });

    test('sorts by distance for the list', () async {
      final (container, _) = setup([
        samplePoi(id: 'far', distance: 900),
        samplePoi(id: 'near', distance: 10),
      ]);
      await container.read(poiRepositoryProvider.notifier).fetchPois(lat: 1, lon: 2, query: query);
      expect(container.read(sortedPoisProvider).map((p) => p.id), ['near', 'far']);
    });
  });
}
