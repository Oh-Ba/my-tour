import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/core/key_value_store.dart';
import 'package:my_tour/src/features/dev/dev_models.dart';
import 'package:my_tour/src/features/dev/dev_service.dart';
import 'package:my_tour/src/features/dev/exhibit_controller.dart';
import 'package:my_tour/src/features/dev/voice_recorder.dart';
import 'package:my_tour/src/features/guide/guide_language.dart';

import '../helpers/dev_fakes.dart';
import '../helpers/fakes.dart';

void main() {
  late FakeDevService service;
  late FakeVoiceRecorder recorder;
  late ProviderContainer container;

  ExhibitController controller() => container.read(exhibitControllerProvider.notifier);
  ExhibitState state() => container.read(exhibitControllerProvider);

  setUp(() {
    service = FakeDevService();
    recorder = FakeVoiceRecorder();
    container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryStore()),
        deviceLanguageCodeProvider.overrideWithValue('it'),
        devServiceProvider.overrideWithValue(service),
        voiceRecorderProvider.overrideWithValue(recorder),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> begin() => controller().begin(placeId: 'poi_1', placeName: 'City Museum', lat: 1, lon: 2);

  test('starts with no exhibit', () {
    expect(state().exhibit, isNull);
    expect(state().phase, RecordingPhase.idle);
  });

  test('a new exhibit is created for the place', () async {
    await begin();
    expect(state().exhibit!.placeName, 'City Museum');
    expect(service.calls, ['createExhibit:City Museum:poi_1']);
  });

  group('recording a guide', () {
    setUp(begin);

    List<String> uploads() => service.calls.where((c) => c.startsWith('uploadSegment')).toList();

    test('each stretch between pauses is sent as its own piece, then the recording is finished', () async {
      await controller().startRecording();
      expect(state().phase, RecordingPhase.recording);

      await controller().pauseRecording();
      expect(state().phase, RecordingPhase.paused);

      await controller().resumeRecording();
      expect(state().phase, RecordingPhase.recording);

      await controller().saveRecording();

      expect(recorder.calls, ['start', 'stop', 'start', 'stop']);
      expect(uploads(), ['uploadSegment:ex1:rec2:0:4', 'uploadSegment:ex1:rec2:1:4']);
      expect(service.calls.last, 'finishRecording:ex1:rec2');
      expect(state().phase, RecordingPhase.idle);
      expect(state().exhibit!.lessons.single.notes, 'Focus on the murals.');
      expect(state().unsentPieces, 0);
    });

    test('can be saved while paused', () async {
      await controller().startRecording();
      await controller().pauseRecording();
      await controller().saveRecording();

      expect(recorder.calls, ['start', 'stop']);
      expect(state().exhibit!.lessons, hasLength(1));
    });

    test('a long stretch is cut into pieces without stopping the recording', () async {
      await controller().startRecording();
      await controller().rotatePiece();
      await controller().settled;

      expect(recorder.calls, ['start', 'stop', 'start']);
      expect(state().phase, RecordingPhase.recording);
      expect(uploads(), ['uploadSegment:ex1:rec2:0:4']);
    });

    test('cuts pieces by itself as time passes', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryStore()),
          deviceLanguageCodeProvider.overrideWithValue('it'),
          devServiceProvider.overrideWithValue(service),
          voiceRecorderProvider.overrideWithValue(recorder),
          pieceLengthProvider.overrideWithValue(const Duration(milliseconds: 20)),
        ],
      );
      await begin();
      await controller().startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await controller().saveRecording();

      expect(uploads().length, greaterThan(2));
      expect(pieceLength, const Duration(minutes: 10));
    });

    test('keeps recording without a connection and sends everything once back online', () async {
      service.error = DevServiceException('Could not reach the server.');
      await controller().startRecording();
      await controller().pauseRecording();
      await controller().settled;

      expect(state().unsentPieces, 1);
      expect(state().error, isNull, reason: 'a lost connection must not interrupt the recording');

      await controller().resumeRecording();
      await controller().saveRecording();
      expect(state().phase, RecordingPhase.paused);
      expect(state().error, contains('safe on the phone'));
      expect(state().unsentPieces, 2);

      service.error = null;
      await controller().saveRecording();

      expect(uploads(), ['uploadSegment:ex1:rec2:0:4', 'uploadSegment:ex1:rec2:1:4']);
      expect(state().phase, RecordingPhase.idle);
      expect(state().unsentPieces, 0);
      expect(state().exhibit!.lessons, hasLength(1));
    });

    test('a recording that is not good enough can be thrown away', () async {
      await controller().startRecording();
      await controller().pauseRecording();
      await controller().settled;
      await controller().resumeRecording();

      await controller().discardRecording();

      expect(recorder.calls.last, 'cancel');
      expect(state().phase, RecordingPhase.idle);
      expect(state().exhibit!.lessons, isEmpty);
      expect(service.calls.last, 'ignoreLesson:ex1:rec2', reason: 'the piece already sent is erased too');
    });

    test('throwing away a recording that never left the phone needs no server', () async {
      await controller().startRecording();
      await controller().discardRecording();

      expect(recorder.calls, ['start', 'cancel']);
      expect(service.calls, ['createExhibit:City Museum:poi_1']);
    });

    test('says so when the microphone is not available', () async {
      recorder.startError = RecorderUnavailable();
      await controller().startRecording();

      expect(state().phase, RecordingPhase.idle);
      expect(state().error, contains('microphone'));
    });

    test('nothing happens when saving without a recording', () async {
      await controller().saveRecording();
      expect(recorder.calls, isEmpty);
    });

    test('checks back with the server to see what was learned', () async {
      service.learnedNotes = '';
      await controller().startRecording();
      await controller().saveRecording();
      expect(state().isProcessing, isTrue);

      service.onServer = Exhibit(
        id: 'ex1',
        placeName: 'City Museum',
        lessons: const [Lesson(id: 'rec2', source: LessonSource.recording, notes: 'Learned at last.')],
      );
      await controller().refresh();

      expect(state().exhibit!.lessons.single.notes, 'Learned at last.');
      expect(state().isProcessing, isFalse);
    });

    test('a lesson that failed can be tried again', () async {
      await controller().startRecording();
      await controller().saveRecording();
      await controller().retryLesson('rec2');

      expect(service.calls.last, 'retryLesson:ex1:rec2');
      expect(state().exhibit!.lessons.single.processing, isTrue);
    });
  });

  group('curating', () {
    setUp(begin);

    test('a saved lesson can be ignored afterwards', () async {
      await controller().startRecording();
      await controller().saveRecording();
      final id = state().exhibit!.lessons.single.id;

      await controller().ignoreLesson(id);

      expect(state().exhibit!.lessons.single.ignored, isTrue);
      expect(service.calls.last, 'ignoreLesson:ex1:$id');
    });

    test('typed notes become a lesson', () async {
      await controller().addTypedLesson('  Start with the view.  ');
      expect(state().exhibit!.lessons.single.notes, 'Notes on: Start with the view.');

      await controller().addTypedLesson('   ');
      expect(state().exhibit!.lessons, hasLength(1));
    });

    test('photos are added to the exhibit', () async {
      await controller().addPhoto(samplePhoto, caption: 'The murals');
      expect(state().exhibit!.photos.single.caption, 'The murals');
      expect(service.calls.last, 'addPhoto:ex1:image/jpeg:The murals');
    });

    test('discarding the exhibit forgets it', () async {
      await controller().discardExhibit();
      expect(state().exhibit, isNull);
      expect(service.calls.last, 'discardExhibit:ex1');
    });
  });

  group('teaching the style', () {
    test('loads the current style and saves a new one', () async {
      service.style = 'Warm.';
      await controller().loadStyle();
      expect(state().style, 'Warm.');

      await controller().saveStyle('Warm, with short sentences.');
      expect(state().style, 'Warm, with short sentences.');
      expect(service.style, 'Warm, with short sentences.');
    });

    test('reports why the style could not be loaded', () async {
      service.error = DevServiceException('Developer mode is off on the server.');
      await controller().loadStyle();
      expect(state().error, 'Developer mode is off on the server.');
    });
  });
}
