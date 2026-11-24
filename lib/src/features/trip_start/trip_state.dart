import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_notifier.dart';

const String tripStorageKey = 'trip.v2';
const double defaultRadiusKm = 1.0;

/// What the traveller wants from a tour.
@immutable
class TripConfig {
  /// Interests picked from [availableInterests].
  final List<String> interests;

  /// Interests typed by the traveller, e.g. "second hand stores".
  final List<String> customInterests;

  final double radiusKm;

  /// Recommend tourist classics (museums, archaeology, history, landmarks)
  /// whatever the interests are. Checked again at the start of every tour.
  final bool includeClassics;

  /// Whether a tour is running.
  final bool isActive;

  const TripConfig({
    this.interests = const [],
    this.customInterests = const [],
    this.radiusKm = defaultRadiusKm,
    this.includeClassics = true,
    this.isActive = false,
  });

  static const TripConfig empty = TripConfig();

  /// Everything to search for, chosen and typed.
  List<String> get searchTerms => [...interests, ...customInterests];

  /// A tour needs something to look for.
  bool get canStart => includeClassics || searchTerms.isNotEmpty;

  /// The tour is over: keep the preferences for next time, but the next tour
  /// starts with the classics recommended again.
  TripConfig ended() => copyWith(isActive: false, includeClassics: true);

  TripConfig copyWith({
    List<String>? interests,
    List<String>? customInterests,
    double? radiusKm,
    bool? includeClassics,
    bool? isActive,
  }) {
    return TripConfig(
      interests: interests ?? this.interests,
      customInterests: customInterests ?? this.customInterests,
      radiusKm: radiusKm ?? this.radiusKm,
      includeClassics: includeClassics ?? this.includeClassics,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'interests': interests,
        'customInterests': customInterests,
        'radiusKm': radiusKm,
        'includeClassics': includeClassics,
        'isActive': isActive,
      };

  factory TripConfig.fromJson(Map<String, dynamic> json) {
    return TripConfig(
      interests: List<String>.from(json['interests'] ?? const []),
      customInterests: List<String>.from(json['customInterests'] ?? const []),
      radiusKm: (json['radiusKm'] as num? ?? defaultRadiusKm).toDouble(),
      includeClassics: json['includeClassics'] as bool? ?? true,
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TripConfig &&
        listEquals(other.interests, interests) &&
        listEquals(other.customInterests, customInterests) &&
        other.radiusKm == radiusKm &&
        other.includeClassics == includeClassics &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(interests),
        Object.hashAll(customInterests),
        radiusKm,
        includeClassics,
        isActive,
      );
}

/// [current] plus [typed], trimmed; blanks and duplicates are ignored.
List<String> addCustomInterest(List<String> current, String typed) {
  final interest = typed.trim();
  final exists = current.any((c) => c.toLowerCase() == interest.toLowerCase());
  return interest.isEmpty || exists ? current : [...current, interest];
}

/// Saved text back into a config; anything unreadable gives null.
TripConfig? decodeTripConfig(String? saved) {
  if (saved == null) return null;
  try {
    return TripConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Holds the current tour and keeps it across app launches.
class TripStateNotifier extends Notifier<TripConfig> with Persisted<TripConfig> {
  @override
  String get storageKey => tripStorageKey;

  @override
  TripConfig? decode(String saved) => decodeTripConfig(saved);

  @override
  String encode(TripConfig value) => jsonEncode(value.toJson());

  @override
  TripConfig build() {
    restore();
    return TripConfig.empty;
  }

  /// Start a tour, or apply changes to the one that is running.
  Future<void> startTrip(TripConfig config) => save(config.copyWith(isActive: true));

  Future<void> endTrip() => save(state.ended());
}

final tripStateProvider = NotifierProvider<TripStateNotifier, TripConfig>(
  TripStateNotifier.new,
);

/// Interest categories offered as chips. Anything else can be typed.
const List<String> availableInterests = [
  'Restaurants',
  'Museums',
  'Parks',
  'Shopping',
  'Nightlife',
  'Art Galleries',
  'Historical Sites',
  'Cafes',
  'Theater',
  'Sports',
];
