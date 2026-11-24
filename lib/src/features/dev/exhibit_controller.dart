import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide/photo_picker.dart';
import 'dev_models.dart';
import 'dev_service.dart';
import 'voice_recorder.dart';

enum RecordingPhase { idle, recording, paused, saving }

/// A recording is cut into pieces this long, so that hours of speech are
/// uploaded and transcribed a little at a time rather than as one huge file.
const Duration pieceLength = Duration(minutes: 10);

/// Overridden in tests.
final pieceLengthProvider = Provider<Duration>((ref) => pieceLength);

const String _offlineMessage =
    'Could not reach the server. Your recording is safe on the phone; press Save again when you are online.';

/// What the "New exhibit" screen shows.
@immutable
class ExhibitState {
  /// The exhibit being worked on; null before it is started.
  final Exhibit? exhibit;
  final RecordingPhase phase;

  /// The style the guide is asked to speak in.
  final String style;

  /// Pieces of the current recording still waiting to be uploaded.
  final int unsentPieces;

  /// The latest problem, in plain words.
  final String? error;

  const ExhibitState({
    this.exhibit,
    this.phase = RecordingPhase.idle,
    this.style = '',
    this.unsentPieces = 0,
    this.error,
  });

  /// The server is still transcribing or learning from a saved recording.
  bool get isProcessing => exhibit?.lessons.any((lesson) => lesson.processing) ?? false;

  /// [error] is replaced as given: every new action clears the last problem.
  ExhibitState copyWith({
    Exhibit? exhibit,
    RecordingPhase? phase,
    String? style,
    int? unsentPieces,
    String? error,
  }) {
    return ExhibitState(
      exhibit: exhibit ?? this.exhibit,
      phase: phase ?? this.phase,
      style: style ?? this.style,
      unsentPieces: unsentPieces ?? this.unsentPieces,
      error: error,
    );
  }
}

/// One piece of a recording, waiting to be uploaded.
typedef _Piece = ({int index, RecordedAudio audio});

/// Runs a "New exhibit" session: recording other guides, with pauses, adding
/// photos, teaching the style, and throwing away what is not good enough.
///
/// A recording is made of pieces. A piece ends at every pause and every
/// [pieceLength]; each is uploaded in the background while recording goes
/// on, and waits on the phone if there is no connection.
class ExhibitController extends Notifier<ExhibitState> {
  /// Time recorded in total, and in the current piece; pauses not counted.
  final Stopwatch _recorded = Stopwatch();
  final Stopwatch _pieceClock = Stopwatch();

  /// The server's id for the current recording, once it could be opened.
  String? _lessonId;
  int _nextIndex = 0;
  final List<_Piece> _unsent = [];
  Timer? _rotation;

  /// Recorder actions run one after another, so a pause can never overlap
  /// the automatic cut between two pieces.
  Future<void> _actions = Future.value();

  /// Uploads run one after another, in order.
  Future<void> _sending = Future.value();

  DevService get _service => ref.read(devServiceProvider);
  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);

  /// How long the current recording is so far.
  Duration get elapsed => _recorded.elapsed;

  /// Completes when the uploads started so far have finished or given up.
  Future<void> get settled => _sending;

  @override
  ExhibitState build() {
    ref.onDispose(() => _rotation?.cancel());
    return const ExhibitState();
  }

  /// Run [action]; a problem is shown instead of thrown, and the recording
  /// phase becomes [whenFailed] if one is given.
  Future<void> _attempt(Future<void> Function() action, {RecordingPhase? whenFailed}) async {
    try {
      await action();
    } on DevServiceException catch (e) {
      if (ref.mounted) state = state.copyWith(phase: whenFailed, error: e.message);
    }
  }

  /// Queue a recorder action behind the ones already running.
  Future<void> _inTurn(Future<void> Function() action) {
    return _actions = _actions.then((_) => action());
  }

  Future<void> loadStyle() {
    return _attempt(() async {
      final style = await _service.getStyle();
      if (ref.mounted) state = state.copyWith(style: style);
    });
  }

  Future<void> saveStyle(String text) {
    return _attempt(() async {
      final saved = await _service.saveStyle(text.trim());
      if (ref.mounted) state = state.copyWith(style: saved);
    });
  }

  /// Start a new exhibit about a place.
  Future<void> begin({
    String? placeId,
    required String placeName,
    required double lat,
    required double lon,
  }) {
    return _attempt(() async {
      final exhibit = await _service.createExhibit(
        placeId: placeId,
        placeName: placeName.trim(),
        lat: lat,
        lon: lon,
      );
      if (ref.mounted) state = ExhibitState(exhibit: exhibit, style: state.style);
    });
  }

  // ---- recording -----------------------------------------------------------

  bool get _hasRecording =>
      state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused;

  void _startClocks() {
    _recorded.start();
    _pieceClock.start();
    _rotation?.cancel();
    _rotation = Timer.periodic(ref.read(pieceLengthProvider), (_) => rotatePiece());
  }

  void _stopClocks() {
    _rotation?.cancel();
    _recorded.stop();
    _pieceClock.stop();
  }

  void _forgetRecording() {
    _lessonId = null;
    _nextIndex = 0;
    _unsent.clear();
    _recorded.reset();
    _pieceClock.reset();
  }

  /// Recording works without a connection: the server is only needed when
  /// the first piece is uploaded.
  Future<void> startRecording() {
    return _inTurn(() async {
      if (state.exhibit == null || state.phase != RecordingPhase.idle) return;
      try {
        await _recorder.start();
      } on RecorderUnavailable {
        state = state.copyWith(error: 'The microphone is not available. Allow it in the phone settings.');
        return;
      }
      _forgetRecording();
      _startClocks();
      state = state.copyWith(phase: RecordingPhase.recording, unsentPieces: 0);
    });
  }

  /// End the piece being recorded and queue it for upload.
  Future<void> _closePiece() async {
    final bytes = await _recorder.stop();
    final duration = _pieceClock.elapsed;
    _pieceClock.reset();
    if (bytes != null && bytes.isNotEmpty) {
      final audio = RecordedAudio(bytes: bytes, mediaType: VoiceRecorder.mediaType, duration: duration);
      _unsent.add((index: _nextIndex++, audio: audio));
      _showUnsent();
    }
    unawaited(_send());
  }

  /// Stop listening while walking to the next site.
  Future<void> pauseRecording() {
    return _inTurn(() async {
      if (state.phase != RecordingPhase.recording) return;
      _stopClocks();
      await _closePiece();
      state = state.copyWith(phase: RecordingPhase.paused, error: state.error);
    });
  }

  Future<void> resumeRecording() {
    return _inTurn(() async {
      if (state.phase != RecordingPhase.paused) return;
      await _recorder.start();
      _startClocks();
      state = state.copyWith(phase: RecordingPhase.recording);
    });
  }

  /// Cut the recording here and carry straight on in a new piece. Called by
  /// the timer every [pieceLength].
  Future<void> rotatePiece() {
    return _inTurn(() async {
      if (state.phase != RecordingPhase.recording) return;
      await _closePiece();
      await _recorder.start();
      _pieceClock.start();
    });
  }

  void _showUnsent() {
    if (ref.mounted) state = state.copyWith(unsentPieces: _unsent.length, error: state.error);
  }

  /// Upload the waiting pieces, after any upload already under way.
  Future<void> _send() => _sending = _sending.then((_) => _sendUnsent());

  /// Upload pieces in order until done or the server cannot be reached. What
  /// is left stays queued and is tried again with the next piece or on Save.
  Future<void> _sendUnsent() async {
    final exhibit = state.exhibit;
    if (exhibit == null || _unsent.isEmpty) return;
    try {
      _lessonId ??= (await _service.openRecording(exhibit.id)).id;
      while (_unsent.isNotEmpty) {
        final piece = _unsent.first;
        await _service.uploadSegment(exhibit.id, _lessonId!, index: piece.index, audio: piece.audio);
        _unsent.remove(piece);
        _showUnsent();
      }
    } on DevServiceException {
      // No connection right now; recording carries on.
    }
  }

  /// End the recording and have the guide learn from all of it.
  Future<void> saveRecording() {
    return _inTurn(() async {
      final exhibit = state.exhibit;
      if (exhibit == null || !_hasRecording) return;

      _stopClocks();
      if (state.phase == RecordingPhase.recording) await _closePiece();
      state = state.copyWith(phase: RecordingPhase.saving);
      await _send();
      if (!ref.mounted) return;

      if (_unsent.isNotEmpty) {
        state = state.copyWith(phase: RecordingPhase.paused, error: _offlineMessage);
        return;
      }
      final lessonId = _lessonId;
      if (lessonId == null) {
        state = state.copyWith(phase: RecordingPhase.idle, error: 'Nothing was recorded.');
        return;
      }
      await _attempt(
        () async {
          final lesson = await _service.finishRecording(exhibit.id, lessonId);
          _forgetRecording();
          _show(lesson, phase: RecordingPhase.idle);
        },
        whenFailed: RecordingPhase.paused,
      );
    });
  }

  /// The recording is not good enough: throw it away, including any pieces
  /// already uploaded.
  Future<void> discardRecording() {
    return _inTurn(() async {
      final exhibit = state.exhibit;
      if (exhibit == null || !_hasRecording) return;

      _stopClocks();
      if (state.phase == RecordingPhase.recording) await _recorder.cancel();
      _unsent.clear();
      await _sending;
      final lessonId = _lessonId;
      _forgetRecording();
      if (lessonId != null) {
        await _attempt(() => _service.ignoreLesson(exhibit.id, lessonId));
      }
      if (ref.mounted) {
        state = state.copyWith(phase: RecordingPhase.idle, unsentPieces: 0, error: state.error);
      }
    });
  }

  // ---- lessons, photos, exhibit --------------------------------------------

  /// Show a lesson the server returned, new or changed.
  void _show(Lesson lesson, {RecordingPhase? phase}) {
    if (!ref.mounted) return;
    state = state.copyWith(
      exhibit: state.exhibit!.withLesson(lesson),
      phase: phase,
      unsentPieces: _unsent.length,
    );
  }

  /// Run [action] on the current exhibit, if there is one.
  Future<void> _onExhibit(Future<void> Function(Exhibit exhibit) action) async {
    final exhibit = state.exhibit;
    if (exhibit != null) await _attempt(() => action(exhibit));
  }

  /// Ask the server how transcription and learning are getting on.
  Future<void> refresh() {
    return _onExhibit((exhibit) async {
      final current = await _service.getExhibit(exhibit.id);
      if (ref.mounted && state.exhibit?.id == current.id) {
        state = state.copyWith(exhibit: current, error: state.error);
      }
    });
  }

  /// "Ignore what I copied": forget a saved lesson.
  Future<void> ignoreLesson(String lessonId) {
    return _onExhibit((exhibit) async => _show(await _service.ignoreLesson(exhibit.id, lessonId)));
  }

  /// Try again a lesson whose transcription or learning failed.
  Future<void> retryLesson(String lessonId) {
    return _onExhibit((exhibit) async => _show(await _service.retryLesson(exhibit.id, lessonId)));
  }

  /// Learn from notes or a transcript typed by the developer.
  Future<void> addTypedLesson(String text) async {
    final words = text.trim();
    if (words.isEmpty) return;
    await _onExhibit((exhibit) async => _show(await _service.addTypedLesson(exhibit.id, words)));
  }

  Future<void> addPhoto(PickedPhoto photo, {String caption = ''}) {
    return _onExhibit((exhibit) async {
      final added = await _service.addPhoto(exhibit.id, photo, caption: caption);
      if (ref.mounted) state = state.copyWith(exhibit: state.exhibit!.withPhoto(added));
    });
  }

  /// Throw the whole exhibit away.
  Future<void> discardExhibit() {
    return _onExhibit((exhibit) async {
      await _service.discardExhibit(exhibit.id);
      _stopClocks();
      _forgetRecording();
      if (ref.mounted) state = ExhibitState(style: state.style);
    });
  }
}

final exhibitControllerProvider = NotifierProvider<ExhibitController, ExhibitState>(
  ExhibitController.new,
);
