import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_notifier.dart';

const String profileStorageKey = 'profile.scores.v1';

/// Things a traveller does that show they like a kind of place.
enum Engagement {
  viewed(1),
  listened(2),
  photographed(3);

  const Engagement(this.weight);

  /// How strongly the action counts.
  final double weight;
}

/// Category -> how much the traveller has engaged with it.
typedef InterestScores = Map<String, double>;

/// [scores] with [engagement] added to each of [categories].
InterestScores recordEngagement(
  InterestScores scores,
  Iterable<String> categories,
  Engagement engagement,
) {
  return {
    ...scores,
    for (final category in categories)
      category: (scores[category] ?? 0) + engagement.weight,
  };
}

/// The categories the traveller clearly likes, strongest first. Nothing is
/// returned until a category has been engaged with more than in passing.
List<String> topCategories(
  InterestScores scores, {
  int limit = 3,
  double minScore = 5,
}) {
  final liked = scores.entries.where((e) => e.value >= minScore).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return liked.take(limit).map((e) => e.key).toList();
}

/// Saved text back into scores; anything unreadable gives null.
InterestScores? decodeScores(String saved) {
  try {
    final json = jsonDecode(saved) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, (value as num).toDouble()));
  } catch (_) {
    return null;
  }
}

/// Learns what the traveller likes from how they use the app.
class InterestProfileNotifier extends Notifier<InterestScores>
    with Persisted<InterestScores> {
  @override
  String get storageKey => profileStorageKey;

  @override
  InterestScores? decode(String saved) => decodeScores(saved);

  @override
  String encode(InterestScores value) => jsonEncode(value);

  @override
  InterestScores build() {
    restore();
    return const {};
  }

  Future<void> record(Iterable<String> categories, Engagement engagement) {
    return save(recordEngagement(state, categories, engagement));
  }

  /// Forget everything that was learned.
  Future<void> reset() => save(const {});
}

final interestProfileProvider =
    NotifierProvider<InterestProfileNotifier, InterestScores>(
  InterestProfileNotifier.new,
);

/// Categories to recommend from, even beyond the tour radius.
final learnedCategoriesProvider = Provider<List<String>>((ref) {
  return topCategories(ref.watch(interestProfileProvider));
});
