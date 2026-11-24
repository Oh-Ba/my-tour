import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'poi_model.dart';
import 'poi_query.dart';
import 'poi_service.dart';

export 'poi_model.dart';
export 'poi_service.dart' show poiServiceProvider;

/// Minimum distance in meters to trigger a new fetch for the same query.
const double minDistanceForRefetch = 100;

/// Where and what the last successful fetch asked for.
typedef LastFetch = ({double lat, double lon, PoiQuery query});

/// State for POI repository
class PoiState {
  final List<Poi> pois;
  final bool isLoading;
  final String? error;
  final LastFetch? lastFetch;
  final String? selectedPoiId;

  const PoiState({
    this.pois = const [],
    this.isLoading = false,
    this.error,
    this.lastFetch,
    this.selectedPoiId,
  });

  /// [error] and [selectedPoiId] are replaced as given: omit them to clear.
  PoiState copyWith({
    List<Poi>? pois,
    bool? isLoading,
    String? error,
    LastFetch? lastFetch,
    String? selectedPoiId,
  }) {
    return PoiState(
      pois: pois ?? this.pois,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastFetch: lastFetch ?? this.lastFetch,
      selectedPoiId: selectedPoiId,
    );
  }
}

/// Whether asking the backend again is worthwhile.
///
/// [movedMeters] is the distance from the last fetch, null if there was none.
bool shouldFetch({
  required PoiQuery query,
  required double? movedMeters,
  required PoiQuery? lastQuery,
}) {
  if (movedMeters == null || lastQuery == null) return true;
  return query != lastQuery || movedMeters >= minDistanceForRefetch;
}

double? _metersFrom(LastFetch? last, double lat, double lon) {
  if (last == null) return null;
  return Geolocator.distanceBetween(last.lat, last.lon, lat, lon);
}

/// Repository for managing POI data
class PoiRepository extends Notifier<PoiState> {
  PoiService get _service => ref.read(poiServiceProvider);

  @override
  PoiState build() => const PoiState();

  /// Fetch the places for a tour [query] around a position, unless the same
  /// query was already answered from (nearly) the same spot.
  Future<void> fetchPois({
    required double lat,
    required double lon,
    required PoiQuery query,
    bool forceRefresh = false,
  }) async {
    final last = state.lastFetch;
    final needed = shouldFetch(
      query: query,
      movedMeters: _metersFrom(last, lat, lon),
      lastQuery: last?.query,
    );
    if (!forceRefresh && !needed) return;

    state = state.copyWith(isLoading: true, selectedPoiId: state.selectedPoiId);
    try {
      final response = await _service.fetchPois(lat: lat, lon: lon, query: query);
      state = state.copyWith(
        pois: response.pois,
        isLoading: false,
        lastFetch: (lat: lat, lon: lon, query: query),
        selectedPoiId: state.selectedPoiId,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        selectedPoiId: state.selectedPoiId,
      );
    }
  }

  /// Select a POI by ID
  void selectPoi(String poiId) {
    state = state.copyWith(selectedPoiId: poiId, error: state.error);
  }

  /// Clear selected POI
  void clearSelection() {
    state = state.copyWith(error: state.error);
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(selectedPoiId: state.selectedPoiId);
  }

  /// Forget everything; used when a tour ends.
  void clear() {
    state = const PoiState();
  }
}

/// Provider for POI repository
final poiRepositoryProvider = NotifierProvider<PoiRepository, PoiState>(
  PoiRepository.new,
);

/// Provider for getting POIs sorted by distance
final sortedPoisProvider = Provider<List<Poi>>((ref) {
  final pois = List<Poi>.from(ref.watch(poiRepositoryProvider).pois);
  pois.sort((a, b) => a.distance.compareTo(b.distance));
  return pois;
});

/// Provider for getting the selected POI
final selectedPoiProvider = Provider<Poi?>((ref) {
  final state = ref.watch(poiRepositoryProvider);
  for (final poi in state.pois) {
    if (poi.id == state.selectedPoiId) return poi;
  }
  return null;
});
