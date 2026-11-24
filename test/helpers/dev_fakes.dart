import 'dart:typed_data';

import 'package:my_tour/src/features/dev/dev_models.dart';
import 'package:my_tour/src/features/dev/dev_service.dart';
import 'package:my_tour/src/features/dev/voice_recorder.dart';
import 'package:my_tour/src/features/guide/photo_picker.dart';

/// A developer backend that lives in memory and records what it was asked.
class FakeDevService implements DevService {
  final List<String> calls = [];
  DevServiceException? error;
  String style = '';

  /// What the server "learns" from the next upload; empty means it could not
  /// transcribe and is waiting.
  String learnedNotes = 'Focus on the murals.';
  int _nextId = 0;

  String _id(String prefix) => '$prefix${++_nextId}';

  void _check(String call) {
    calls.add(call);
    if (error != null) throw error!;
  }

  @override
  Future<Exhibit> createExhibit({String? placeId, required String placeName, required double lat, required double lon}) async {
    _check('createExhibit:$placeName:$placeId');
    return Exhibit(id: _id('ex'), placeName: placeName);
  }

  /// What a refresh from the server returns, when set.
  Exhibit? onServer;

  @override
  Future<Lesson> openRecording(String exhibitId) async {
    _check('openRecording:$exhibitId');
    return Lesson(id: _id('rec'), source: LessonSource.recording, processing: true);
  }

  @override
  Future<Lesson> uploadSegment(String exhibitId, String lessonId, {required int index, required RecordedAudio audio}) async {
    _check('uploadSegment:$exhibitId:$lessonId:$index:${audio.bytes.length}');
    return Lesson(id: lessonId, source: LessonSource.recording, processing: true, segmentCount: index + 1);
  }

  @override
  Future<Lesson> finishRecording(String exhibitId, String lessonId) async {
    _check('finishRecording:$exhibitId:$lessonId');
    return Lesson(
      id: lessonId,
      source: LessonSource.recording,
      notes: learnedNotes,
      processing: learnedNotes.isEmpty,
      segmentCount: 2,
      transcribedCount: learnedNotes.isEmpty ? 1 : 2,
    );
  }

  @override
  Future<Lesson> retryLesson(String exhibitId, String lessonId) async {
    _check('retryLesson:$exhibitId:$lessonId');
    return Lesson(id: lessonId, source: LessonSource.recording, processing: true);
  }

  @override
  Future<Exhibit> getExhibit(String exhibitId) async {
    _check('getExhibit:$exhibitId');
    return onServer!;
  }

  @override
  Future<Lesson> addTypedLesson(String exhibitId, String text) async {
    _check('addTypedLesson:$exhibitId:$text');
    return Lesson(id: _id('typed'), source: LessonSource.typed, notes: 'Notes on: $text');
  }

  @override
  Future<Lesson> ignoreLesson(String exhibitId, String lessonId) async {
    _check('ignoreLesson:$exhibitId:$lessonId');
    return Lesson(id: lessonId, source: LessonSource.recording, ignored: true);
  }

  @override
  Future<ExhibitPhoto> addPhoto(String exhibitId, PickedPhoto photo, {String caption = ''}) async {
    _check('addPhoto:$exhibitId:${photo.mediaType}:$caption');
    return ExhibitPhoto(id: _id('photo'), file: 'p.jpg', caption: caption);
  }

  @override
  Future<void> discardExhibit(String exhibitId) async => _check('discardExhibit:$exhibitId');

  @override
  Future<String> getStyle() async {
    _check('getStyle');
    return style;
  }

  @override
  Future<String> saveStyle(String text) async {
    _check('saveStyle:$text');
    return style = text;
  }
}

/// A microphone that produces prepared bytes and notes what it was told.
class FakeVoiceRecorder implements VoiceRecorder {
  final List<String> calls = [];
  Object? startError;
  Uint8List? recorded = Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    calls.add('start');
  }

  @override
  Future<Uint8List?> stop() async {
    calls.add('stop');
    return recorded;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');
}
