import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads text aloud.
abstract class SpeechEngine {
  /// Start speaking [text] with a voice for [languageCode] (e.g. `he-IL`),
  /// replacing anything already being spoken.
  Future<void> speak(String text, {required String languageCode});

  Future<void> stop();

  /// [callback] runs when the voice reaches the end of the text.
  void onDone(void Function() callback);
}

/// Android refuses to speak more than 4,000 characters in one go, and a
/// ten-minute story is about twice that; longer texts are spoken in pieces.
const int maxSpeechChunkLength = 3500;

/// Join [parts] with spaces into pieces of at most [maxLength] characters.
List<String> _pack(Iterable<String> parts, int maxLength) {
  final chunks = <String>[];
  var current = '';
  for (final part in parts) {
    final joined = current.isEmpty ? part : '$current $part';
    if (joined.length <= maxLength || current.isEmpty) {
      current = joined;
    } else {
      chunks.add(current);
      current = part;
    }
  }
  return current.isEmpty ? chunks : [...chunks, current];
}

/// The sentences of [text]; a sentence too long for one piece is broken
/// between words.
Iterable<String> _speakableUnits(String text, int maxLength) {
  final sentences = text
      .split(RegExp(r'(?<=[.!?…。！？])\s+|\n+'))
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.isNotEmpty);
  return sentences.expand(
    (sentence) => sentence.length <= maxLength
        ? [sentence]
        : _pack(sentence.split(RegExp(r'\s+')), maxLength),
  );
}

/// [text] cut into pieces the phone can speak one after another, breaking
/// only at sentence ends where possible.
List<String> chunkForSpeech(String text, {int maxLength = maxSpeechChunkLength}) {
  return _pack(_speakableUnits(text, maxLength), maxLength);
}

/// [SpeechEngine] using the voices built into the phone (iOS and Android).
class DeviceSpeechEngine implements SpeechEngine {
  DeviceSpeechEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;
  void Function()? _onDone;

  /// Counts the stories started; a piece of an older one is never spoken.
  int _session = 0;

  /// Slightly slower than conversation; easier to follow while walking.
  static const double speechRate = 0.48;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // On iPhone, keep talking when the ring switch is set to silent.
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    await _tts.setSpeechRate(speechRate);
    // Lets the pieces of a long story be spoken one after another.
    await _tts.awaitSpeakCompletion(true);
  }

  @override
  Future<void> speak(String text, {required String languageCode}) async {
    await _configure();
    await _tts.stop();
    final session = ++_session;
    await _tts.setLanguage(languageCode);
    unawaited(_speakAll(chunkForSpeech(text), session));
  }

  /// Speak the pieces in order, unless another story or a stop intervenes.
  Future<void> _speakAll(List<String> chunks, int session) async {
    for (final chunk in chunks) {
      if (session != _session) return;
      await _tts.speak(chunk);
    }
    if (session == _session) _onDone?.call();
  }

  @override
  Future<void> stop() async {
    _session++;
    await _tts.stop();
  }

  @override
  void onDone(void Function() callback) => _onDone = callback;
}

final speechEngineProvider = Provider<SpeechEngine>((ref) {
  final engine = DeviceSpeechEngine();
  ref.onDispose(engine.stop);
  return engine;
});
