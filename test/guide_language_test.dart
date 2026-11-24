import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/guide/guide_language.dart';

import 'helpers/fakes.dart';

void main() {
  test('offers many languages with unique codes', () {
    expect(guideLanguages.length, greaterThanOrEqualTo(12));
    expect(guideLanguages.map((l) => l.code).toSet().length, guideLanguages.length);
  });

  test('knows which languages read right to left', () {
    expect(languageByCode('he-IL').isRtl, isTrue);
    expect(languageByCode('ar-SA').isRtl, isTrue);
    expect(languageByCode('en-US').isRtl, isFalse);
  });

  test('falls back to English for unknown codes', () {
    expect(languageByCode('xx-XX').name, 'English');
    expect(languageByCode(null).name, 'English');
  });

  test('picks the language of the device', () {
    expect(languageForDevice('he').name, 'Hebrew');
    expect(languageForDevice('fr').name, 'French');
    expect(languageForDevice('tlh').name, 'English');
  });

  group('GuideLanguageNotifier', () {
    ProviderContainer containerWith(InMemoryStore store, {String device = 'en'}) {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          deviceLanguageCodeProvider.overrideWithValue(device),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('starts with the device language', () {
      final container = containerWith(InMemoryStore(), device: 'es');
      expect(container.read(guideLanguageProvider).name, 'Spanish');
    });

    test('remembers the chosen language', () async {
      final store = InMemoryStore();
      final container = containerWith(store);
      await container.read(guideLanguageProvider.notifier).select(languageByCode('he-IL'));
      expect(store.values[languageStorageKey], 'he-IL');

      final relaunched = containerWith(store);
      await relaunched.read(guideLanguageProvider.notifier).loaded;
      expect(relaunched.read(guideLanguageProvider).name, 'Hebrew');
    });
  });
}
