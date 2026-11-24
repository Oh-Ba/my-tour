import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/trip_start/trip_state.dart';

import 'helpers/fakes.dart';

void main() {
  group('TripConfig', () {
    test('a new tour always recommends the classics', () {
      expect(TripConfig.empty.includeClassics, isTrue);
      expect(TripConfig.empty.isActive, isFalse);
    });

    test('search terms combine chosen and typed interests', () {
      const config = TripConfig(
        interests: ['Museums'],
        customInterests: ['second hand stores'],
      );
      expect(config.searchTerms, ['Museums', 'second hand stores']);
    });

    test('can start with classics only, or with any interest', () {
      expect(TripConfig.empty.canStart, isTrue);
      expect(TripConfig.empty.copyWith(includeClassics: false).canStart, isFalse);
      expect(
        TripConfig.empty.copyWith(includeClassics: false, customInterests: ['vinyl']).canStart,
        isTrue,
      );
    });

    test('survives a JSON round trip', () {
      const config = TripConfig(
        interests: ['Parks'],
        customInterests: ['vinyl'],
        radiusKm: 2.5,
        includeClassics: false,
        isActive: true,
      );
      final restored = TripConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
      expect(restored, config);
    });

    test('ending a tour keeps the preferences but re-checks the classics', () {
      const config = TripConfig(
        interests: ['Parks'],
        radiusKm: 3,
        includeClassics: false,
        isActive: true,
      );
      final ended = config.ended();
      expect(ended.isActive, isFalse);
      expect(ended.includeClassics, isTrue);
      expect(ended.interests, ['Parks']);
      expect(ended.radiusKm, 3);
    });
  });

  group('addCustomInterest', () {
    test('trims and appends', () {
      expect(addCustomInterest(['a'], '  Second hand  '), ['a', 'Second hand']);
    });

    test('ignores blanks and duplicates in any case', () {
      expect(addCustomInterest(['Vinyl'], '   '), ['Vinyl']);
      expect(addCustomInterest(['Vinyl'], 'vinyl'), ['Vinyl']);
    });
  });

  group('TripStateNotifier', () {
    ProviderContainer containerWith(InMemoryStore store) {
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('restores the saved tour', () async {
      const saved = TripConfig(interests: ['Parks'], includeClassics: false, isActive: true);
      final store = InMemoryStore({tripStorageKey: jsonEncode(saved.toJson())});
      final container = containerWith(store);

      await container.read(tripStateProvider.notifier).loaded;
      expect(container.read(tripStateProvider), saved);
    });

    test('ignores unreadable saved data', () async {
      final container = containerWith(InMemoryStore({tripStorageKey: 'not json'}));
      await container.read(tripStateProvider.notifier).loaded;
      expect(container.read(tripStateProvider), TripConfig.empty);
    });

    test('starting a tour activates and saves it', () async {
      final store = InMemoryStore();
      final container = containerWith(store);
      final notifier = container.read(tripStateProvider.notifier);
      await notifier.loaded;

      await notifier.startTrip(const TripConfig(customInterests: ['vinyl'], radiusKm: 2));

      expect(container.read(tripStateProvider).isActive, isTrue);
      final persisted = TripConfig.fromJson(jsonDecode(store.values[tripStorageKey]!));
      expect(persisted.customInterests, ['vinyl']);
      expect(persisted.isActive, isTrue);
    });

    test('the next tour after ending has the classics checked again', () async {
      final container = containerWith(InMemoryStore());
      final notifier = container.read(tripStateProvider.notifier);
      await notifier.loaded;

      await notifier.startTrip(const TripConfig(interests: ['Parks'], includeClassics: false));
      expect(container.read(tripStateProvider).includeClassics, isFalse);

      await notifier.endTrip();
      final next = container.read(tripStateProvider);
      expect(next.isActive, isFalse);
      expect(next.includeClassics, isTrue);
    });
  });
}
