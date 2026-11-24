import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/profile/interest_profile.dart';

import 'helpers/fakes.dart';

void main() {
  group('recordEngagement', () {
    test('adds the weight to every category without mutating the input', () {
      const before = {'museum': 1.0};
      final after = recordEngagement(before, ['museum', 'art'], Engagement.listened);
      expect(after, {'museum': 3.0, 'art': 2.0});
      expect(before, {'museum': 1.0});
    });

    test('stronger signals weigh more', () {
      expect(Engagement.viewed.weight, lessThan(Engagement.listened.weight));
      expect(Engagement.listened.weight, lessThan(Engagement.photographed.weight));
    });
  });

  group('topCategories', () {
    test('returns the strongest categories above the threshold, best first', () {
      const scores = {'museum': 9.0, 'viewpoint': 5.0, 'cafe': 1.0, 'second_hand': 7.0, 'park': 4.0};
      expect(topCategories(scores), ['museum', 'second_hand', 'viewpoint']);
    });

    test('returns nothing before the app has learned enough', () {
      expect(topCategories({'museum': 2.0}), isEmpty);
      expect(topCategories({}), isEmpty);
    });
  });

  group('InterestProfileNotifier', () {
    test('learns from engagement and remembers across launches', () async {
      final store = InMemoryStore();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(interestProfileProvider.notifier);
      await notifier.loaded;

      await notifier.record(['viewpoint'], Engagement.listened);
      await notifier.record(['viewpoint', 'park'], Engagement.photographed);

      expect(container.read(learnedCategoriesProvider), ['viewpoint']);
      expect(jsonDecode(store.values[profileStorageKey]!), {'viewpoint': 5.0, 'park': 3.0});

      final relaunched = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(relaunched.dispose);
      await relaunched.read(interestProfileProvider.notifier).loaded;
      expect(relaunched.read(learnedCategoriesProvider), ['viewpoint']);
    });
  });
}
