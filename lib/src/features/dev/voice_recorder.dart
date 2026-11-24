import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, ready to upload.
@immutable
class RecordedAudio {
  final Uint8List bytes;
  final String mediaType;
  final Duration duration;

  const RecordedAudio({required this.bytes, required this.mediaType, required this.duration});
}

/// The microphone is missing or the permission was refused.
class RecorderUnavailable implements Exception {}

/// Records one piece of audio at a time. A long recording is a series of
/// pieces: the session ends one at every pause and every ten minutes.
abstract class VoiceRecorder {
  /// The format of what [stop] returns.
  static const String mediaType = 'audio/mp4';

  /// Throws [RecorderUnavailable] when the phone cannot record.
  Future<void> start();

  /// Ends the piece and returns it; null if nothing was recorded.
  Future<Uint8List?> stop();

  /// Ends the piece and throws it away.
  Future<void> cancel();
}

/// [VoiceRecorder] using the phone's microphone (iOS and Android).
class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder([AudioRecorder? recorder]) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// Speech needs little: mono at a modest bit rate keeps an hour near 15 MB.
  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 32000,
    sampleRate: 22050,
    numChannels: 1,
  );

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) throw RecorderUnavailable();
    final folder = await getTemporaryDirectory();
    final name = 'guide_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(config, path: '${folder.path}/$name');
  }

  @override
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  @override
  Future<void> cancel() => _recorder.cancel();
}

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) => DeviceVoiceRecorder());
