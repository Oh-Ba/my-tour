import 'package:flutter/foundation.dart';

import '../trip_start/trip_state.dart';

/// What to ask the backend for, apart from the position.
@immutable
class PoiQuery {
  final int radiusM;

  /// Chosen and typed interests.
  final List<String> interests;

  /// Also include tourist classics.
  final bool classics;

  /// Categories the app learned the traveller likes; searched beyond the radius.
  final List<String> learned;

  const PoiQuery({
    required this.radiusM,
    this.interests = const [],
    required this.classics,
    this.learned = const [],
  });

  @override
  bool operator ==(Object other) {
    return other is PoiQuery &&
        other.radiusM == radiusM &&
        other.classics == classics &&
        listEquals(other.interests, interests) &&
        listEquals(other.learned, learned);
  }

  @override
  int get hashCode => Object.hash(
        radiusM,
        classics,
        Object.hashAll(interests),
        Object.hashAll(learned),
      );
}

/// The query for a tour, given what the app has learned so far.
PoiQuery buildPoiQuery(TripConfig trip, List<String> learned) {
  return PoiQuery(
    radiusM: (trip.radiusKm * 1000).round(),
    interests: trip.searchTerms,
    classics: trip.includeClassics,
    learned: learned,
  );
}
