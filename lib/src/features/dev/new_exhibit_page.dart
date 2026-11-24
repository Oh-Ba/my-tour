import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_title.dart' show DevBadge;
import '../guide/photo_picker.dart';
import '../poi/poi_model.dart';
import 'dev_models.dart';
import 'exhibit_controller.dart';

/// Developer mode: teach the guide about a place by recording other guides,
/// adding photos and setting the style.
class NewExhibitPage extends ConsumerStatefulWidget {
  const NewExhibitPage({super.key, this.poi, required this.lat, required this.lon});

  /// The place the exhibit is about, when opened from one.
  final Poi? poi;

  /// Where the developer is standing.
  final double lat;
  final double lon;

  @override
  ConsumerState<NewExhibitPage> createState() => _NewExhibitPageState();
}

class _NewExhibitPageState extends ConsumerState<NewExhibitPage> {
  late final TextEditingController _name = TextEditingController(text: widget.poi?.name ?? '');
  final TextEditingController _lesson = TextEditingController();
  final TextEditingController _style = TextEditingController();

  /// Checks back with the server while it is transcribing a recording.
  Timer? _progressCheck;

  /// How often to ask the server how transcription is going.
  static const Duration _checkEvery = Duration(seconds: 8);

  ExhibitController get _controller => ref.read(exhibitControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadStyle);
    _progressCheck = Timer.periodic(_checkEvery, (_) => _checkProgress());
  }

  void _checkProgress() {
    if (ref.read(exhibitControllerProvider).isProcessing) _controller.refresh();
  }

  @override
  void dispose() {
    _progressCheck?.cancel();
    _name.dispose();
    _lesson.dispose();
    _style.dispose();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    await _controller.loadStyle();
    if (mounted) _style.text = ref.read(exhibitControllerProvider).style;
  }

  Future<void> _start() {
    return _controller.begin(
      placeId: widget.poi?.id,
      placeName: _name.text,
      lat: widget.poi?.lat ?? widget.lat,
      lon: widget.poi?.lon ?? widget.lon,
    );
  }

  Future<void> _addLesson() async {
    await _controller.addTypedLesson(_lesson.text);
    if (mounted && ref.read(exhibitControllerProvider).error == null) _lesson.clear();
  }

  Future<void> _addPhoto() async {
    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider).pick(fromCamera: true);
    } catch (_) {
      _say('Could not open the camera.');
      return;
    }
    if (photo != null) await _controller.addPhoto(photo);
  }

  Future<void> _saveStyle() async {
    await _controller.saveStyle(_style.text);
    if (ref.read(exhibitControllerProvider).error == null) _say('Style saved');
  }

  Future<void> _discardExhibit() async {
    await _controller.discardExhibit();
    if (mounted && ref.read(exhibitControllerProvider).exhibit == null) Navigator.of(context).maybePop();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exhibitControllerProvider);
    final exhibit = state.exhibit;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('New exhibit'), SizedBox(width: 10), DevBadge()],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error != null) _Problem(message: state.error!),
          if (exhibit == null)
            _StartExhibit(name: _name, onStart: _start)
          else ...[
            Text(exhibit.placeName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _RecorderPanel(
              phase: state.phase,
              unsentPieces: state.unsentPieces,
              elapsed: () => _controller.elapsed,
              onRecord: _controller.startRecording,
              onPause: _controller.pauseRecording,
              onResume: _controller.resumeRecording,
              onSave: _controller.saveRecording,
              onDiscard: _controller.discardRecording,
            ),
            const SizedBox(height: 16),
            for (final (index, lesson) in exhibit.lessons.indexed)
              _LessonTile(
                number: index + 1,
                lesson: lesson,
                onIgnore: () => _controller.ignoreLesson(lesson.id),
                onRetry: () => _controller.retryLesson(lesson.id),
              ),
            const _SectionTitle('Or type what you learned'),
            TextField(
              key: const Key('lessonField'),
              controller: _lesson,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Notes, or a transcript, for the guide to learn from',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('addLessonButton'),
                onPressed: _addLesson,
                child: const Text('Learn from this'),
              ),
            ),
            const _SectionTitle('Photos for travellers'),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('addPhotoButton'),
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Take a photo'),
                ),
                const SizedBox(width: 12),
                Text(_photoCount(exhibit.photos.length)),
              ],
            ),
          ],
          const _SectionTitle('The style I want from the guide'),
          TextField(
            key: const Key('styleField'),
            controller: _style,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. Warm and curious. Start with a question. One good story beats five dates.',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: const Key('saveStyleButton'),
              onPressed: _saveStyle,
              child: const Text('Save style'),
            ),
          ),
          if (exhibit != null) ...[
            const SizedBox(height: 32),
            TextButton.icon(
              key: const Key('discardExhibitButton'),
              onPressed: _discardExhibit,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard this whole exhibit'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

String _photoCount(int count) => count == 1 ? '1 photo' : '$count photos';

/// `1:05` for sixty-five seconds.
String formatElapsed(Duration elapsed) {
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '${elapsed.inMinutes}:$seconds';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}

/// Name the exhibit and begin.
class _StartExhibit extends StatelessWidget {
  const _StartExhibit({required this.name, required this.onStart});

  final TextEditingController name;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('exhibitNameField'),
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Place or exhibit',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('startExhibitButton'),
          onPressed: onStart,
          child: const Text('Start exhibit'),
        ),
      ],
    );
  }
}

/// Record, pause between sites, resume, then save or discard.
class _RecorderPanel extends StatelessWidget {
  const _RecorderPanel({
    required this.phase,
    required this.unsentPieces,
    required this.elapsed,
    required this.onRecord,
    required this.onPause,
    required this.onResume,
    required this.onSave,
    required this.onDiscard,
  });

  final RecordingPhase phase;

  /// Pieces recorded but not yet uploaded, e.g. while out of signal.
  final int unsentPieces;
  final Duration Function() elapsed;
  final VoidCallback onRecord;

  String get _waiting => unsentPieces == 1
      ? '1 piece waiting to upload'
      : '$unsentPieces pieces waiting to upload';
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Record a guide only with their permission.'),
            const SizedBox(height: 12),
            switch (phase) {
              RecordingPhase.idle => FilledButton.icon(
                  key: const Key('recordButton'),
                  onPressed: onRecord,
                  icon: const Icon(Icons.mic),
                  label: const Text('Record'),
                ),
              RecordingPhase.saving => const Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Saving and learning from it…'),
                  ],
                ),
              RecordingPhase.recording || RecordingPhase.paused => _ActiveRecording(
                  paused: phase == RecordingPhase.paused,
                  elapsed: elapsed,
                  onPause: onPause,
                  onResume: onResume,
                  onSave: onSave,
                  onDiscard: onDiscard,
                ),
            },
            if (unsentPieces > 0) ...[
              const SizedBox(height: 8),
              Text(_waiting, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveRecording extends StatelessWidget {
  const _ActiveRecording({
    required this.paused,
    required this.elapsed,
    required this.onPause,
    required this.onResume,
    required this.onSave,
    required this.onDiscard,
  });

  final bool paused;
  final Duration Function() elapsed;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(paused ? Icons.pause_circle : Icons.fiber_manual_record, color: Colors.red),
            const SizedBox(width: 8),
            Text(paused ? 'Paused' : 'Recording'),
            const SizedBox(width: 12),
            _ElapsedClock(elapsed: elapsed, running: !paused),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (paused)
              FilledButton.icon(
                key: const Key('resumeButton'),
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
              )
            else
              FilledButton.tonalIcon(
                key: const Key('pauseButton'),
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
            OutlinedButton.icon(
              key: const Key('saveRecordingButton'),
              onPressed: onSave,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
            TextButton.icon(
              key: const Key('discardRecordingButton'),
              onPressed: onDiscard,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The recorded time, refreshed every second while recording.
class _ElapsedClock extends StatefulWidget {
  const _ElapsedClock({required this.elapsed, required this.running});

  final Duration Function() elapsed;
  final bool running;

  @override
  State<_ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<_ElapsedClock> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ElapsedClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// Tick only while recording.
  void _syncTicker() {
    _ticker?.cancel();
    _ticker = widget.running
        ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}))
        : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(formatElapsed(widget.elapsed()));
}

/// One lesson: what was learned, and a way to ignore it or try it again.
class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.number,
    required this.lesson,
    required this.onIgnore,
    required this.onRetry,
  });

  final int number;
  final Lesson lesson;
  final VoidCallback onIgnore;
  final VoidCallback onRetry;

  String get _title {
    if (lesson.source == LessonSource.typed) return 'Lesson $number · typed';
    return 'Lesson $number · recording ${formatElapsed(Duration(milliseconds: lesson.durationMs))}';
  }

  String get _body {
    if (lesson.ignored) return 'Ignored';
    if (lesson.notes.isNotEmpty) return lesson.notes;
    if (lesson.problem != null) return lesson.problem!;
    if (lesson.processing) {
      return 'Transcribing… ${lesson.transcribedCount} of ${lesson.segmentCount} pieces done';
    }
    return 'Nothing was learned from this.';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(_title, style: Theme.of(context).textTheme.labelLarge),
        subtitle: Text(
          _body,
          style: lesson.ignored ? TextStyle(color: Theme.of(context).disabledColor) : null,
        ),
        trailing: lesson.ignored
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (lesson.problem != null)
                    TextButton(
                      key: Key('retry_${lesson.id}'),
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  TextButton(
                    key: Key('ignore_${lesson.id}'),
                    onPressed: onIgnore,
                    child: const Text('Ignore'),
                  ),
                ],
              ),
      ),
    );
  }
}
