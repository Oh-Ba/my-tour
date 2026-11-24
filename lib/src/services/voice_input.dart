import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Hears what the traveller says and returns it as text.
abstract class VoiceInput {
  /// Listens for one request spoken in [languageCode] (e.g. `he-IL`).
  /// Returns null when nothing was said; throws when the phone cannot listen.
  Future<String?> listen({required String languageCode});
}

/// `he-IL` as the recogniser wants it: `he_IL`.
String localeIdFor(String languageCode) => languageCode.replaceAll('-', '_');

/// The phone has no speech recognition, or the microphone was refused.
class VoiceInputUnavailable implements Exception {}

/// [VoiceInput] using the phone's speech recognition (iOS and Android).
class DeviceVoiceInput implements VoiceInput {
  DeviceVoiceInput([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  Completer<String?>? _pending;
  String _heard = '';

  /// Long enough for a sentence or two; stops early after a pause.
  static const Duration longest = Duration(seconds: 20);
  static const Duration pause = Duration(seconds: 3);

  void _finish() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final said = _heard.trim();
    pending.complete(said.isEmpty ? null : said);
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus) _finish();
  }

  void _onResult(SpeechRecognitionResult result) {
    _heard = result.recognizedWords;
    if (result.finalResult) _finish();
  }

  @override
  Future<String?> listen({required String languageCode}) async {
    final ready = await _speech.initialize(onStatus: _onStatus, onError: (_) => _finish());
    if (!ready) throw VoiceInputUnavailable();

    _heard = '';
    _pending = Completer<String?>();
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        localeId: localeIdFor(languageCode),
        listenFor: longest,
        pauseFor: pause,
      ),
    );
    return _pending!.future;
  }
}

final voiceInputProvider = Provider<VoiceInput>((ref) => DeviceVoiceInput());
