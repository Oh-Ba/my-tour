import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_notifier.dart';

const String languageStorageKey = 'guide.language';

/// A language the guide can write and speak.
@immutable
class GuideLanguage {
  /// Locale for the voice, e.g. `he-IL`.
  final String code;

  /// English name, sent to the AI.
  final String name;

  /// Name as its speakers write it, shown in the picker.
  final String nativeName;

  final bool isRtl;

  const GuideLanguage(this.code, this.name, this.nativeName, {this.isRtl = false});

  /// `he` for `he-IL`.
  String get languageCode => code.split('-').first;
}

const GuideLanguage english = GuideLanguage('en-US', 'English', 'English');

const List<GuideLanguage> guideLanguages = [
  english,
  GuideLanguage('he-IL', 'Hebrew', 'עברית', isRtl: true),
  GuideLanguage('ar-SA', 'Arabic', 'العربية', isRtl: true),
  GuideLanguage('es-ES', 'Spanish', 'Español'),
  GuideLanguage('fr-FR', 'French', 'Français'),
  GuideLanguage('de-DE', 'German', 'Deutsch'),
  GuideLanguage('it-IT', 'Italian', 'Italiano'),
  GuideLanguage('pt-BR', 'Portuguese', 'Português'),
  GuideLanguage('ru-RU', 'Russian', 'Русский'),
  GuideLanguage('nl-NL', 'Dutch', 'Nederlands'),
  GuideLanguage('pl-PL', 'Polish', 'Polski'),
  GuideLanguage('el-GR', 'Greek', 'Ελληνικά'),
  GuideLanguage('tr-TR', 'Turkish', 'Türkçe'),
  GuideLanguage('hi-IN', 'Hindi', 'हिन्दी'),
  GuideLanguage('zh-CN', 'Chinese', '中文'),
  GuideLanguage('ja-JP', 'Japanese', '日本語'),
  GuideLanguage('ko-KR', 'Korean', '한국어'),
];

GuideLanguage _firstWhere(bool Function(GuideLanguage) test) {
  return guideLanguages.firstWhere(test, orElse: () => english);
}

/// The language saved under [code]; English when unknown.
GuideLanguage languageByCode(String? code) => _firstWhere((l) => l.code == code);

/// The guide language matching the phone's language (`he`, `fr`, ...).
GuideLanguage languageForDevice(String languageCode) {
  return _firstWhere((l) => l.languageCode == languageCode);
}

/// The phone's language code. Overridden in tests.
final deviceLanguageCodeProvider = Provider<String>((ref) {
  return PlatformDispatcher.instance.locale.languageCode;
});

/// The language the guide speaks, remembered across launches.
class GuideLanguageNotifier extends Notifier<GuideLanguage>
    with Persisted<GuideLanguage> {
  @override
  String get storageKey => languageStorageKey;

  @override
  GuideLanguage? decode(String saved) => languageByCode(saved);

  @override
  String encode(GuideLanguage value) => value.code;

  @override
  GuideLanguage build() {
    restore();
    return languageForDevice(ref.read(deviceLanguageCodeProvider));
  }

  Future<void> select(GuideLanguage language) => save(language);
}

final guideLanguageProvider =
    NotifierProvider<GuideLanguageNotifier, GuideLanguage>(
  GuideLanguageNotifier.new,
);
