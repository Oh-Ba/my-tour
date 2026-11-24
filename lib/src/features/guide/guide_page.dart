import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../poi/poi_model.dart';
import 'ask_guide_bar.dart';
import 'guide_controller.dart';
import 'guide_language.dart';
import 'photo_picker.dart';
import 'seat_offer.dart';

/// The AI guide: tells the story of a place or of a photo, in the traveller's
/// language, as text and as a voice.
class GuidePage extends ConsumerStatefulWidget {
  const GuidePage({
    super.key,
    this.poi,
    this.initialPhoto,
    this.lat,
    this.lon,
    this.nearby = const [],
    this.autoPlay = false,
  }) : assert(poi != null || initialPhoto != null);

  /// The place to talk about. Null for a photo taken from the map.
  final Poi? poi;

  /// A photo to explain straight away.
  final PickedPhoto? initialPhoto;

  /// Where the traveller is standing, when known.
  final double? lat;
  final double? lon;

  /// Names of places around the traveller, to help recognise photos.
  final List<String> nearby;

  /// Start reading aloud as soon as the story arrives.
  final bool autoPlay;

  @override
  ConsumerState<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends ConsumerState<GuidePage> {
  late final GuideController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(guideControllerProvider.notifier);
    Future.microtask(_start);
  }

  @override
  void dispose() {
    // Provider state may not change while the widget tree is being torn down.
    Future.microtask(_controller.close);
    super.dispose();
  }

  Future<void> _start() {
    final photo = widget.initialPhoto;
    if (photo != null) return _explainPhoto(photo, autoPlay: widget.autoPlay);
    return _controller.explainPlace(widget.poi!, autoPlay: widget.autoPlay);
  }

  Future<void> _explainPhoto(PickedPhoto photo, {required bool autoPlay}) {
    return _controller.explainPhoto(
      photo,
      lat: widget.lat ?? widget.poi?.lat,
      lon: widget.lon ?? widget.poi?.lon,
      poi: widget.poi,
      nearby: widget.nearby,
      autoPlay: autoPlay,
    );
  }

  /// Let the traveller take or choose a photo, then explain it.
  Future<void> _pickPhoto({required bool fromCamera}) async {
    final wasSpeaking = ref.read(guideControllerProvider).isSpeaking;
    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider).pick(fromCamera: fromCamera);
    } catch (_) {
      _showMessage(fromCamera
          ? 'Could not open the camera. Check the camera permission in Settings.'
          : 'Could not open your photos.');
      return;
    }
    if (photo == null || !mounted) return;
    await _explainPhoto(photo, autoPlay: wasSpeaking);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    watchSeatOffers(ref, context);
    final state = ref.watch(guideControllerProvider);
    final language = ref.watch(guideLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.poi?.name ?? 'Photo story'),
        actions: [
          _LanguageButton(selected: language, onSelected: _controller.changeLanguage),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.photo != null) _PhotoPreview(photo: state.photo!),
          GuideStory(state: state, language: language, onRetry: _controller.retry),
          const SizedBox(height: 24),
          const AskGuideBar(),
        ],
      ),
      bottomNavigationBar: _GuideActions(
        canSpeak: state.status == GuideStatus.ready,
        isSpeaking: state.isSpeaking,
        minutes: state.minutes,
        onSpeak: _controller.toggleSpeech,
        onCamera: () => _pickPhoto(fromCamera: true),
        onGallery: () => _pickPhoto(fromCamera: false),
      ),
    );
  }
}

/// Picks the language the guide writes and speaks.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.selected, required this.onSelected});

  final GuideLanguage selected;
  final ValueChanged<GuideLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GuideLanguage>(
      key: const Key('languageButton'),
      tooltip: 'Guide language',
      icon: const Icon(Icons.translate),
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final language in guideLanguages)
          PopupMenuItem(value: language, child: Text(language.nativeName)),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo});

  final PickedPhoto photo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          photo.bytes,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// The story itself, or what is happening instead of it.
class GuideStory extends StatelessWidget {
  const GuideStory({super.key, required this.state, required this.language, required this.onRetry});

  final GuideState state;
  final GuideLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case GuideStatus.idle:
      case GuideStatus.loading:
        return const _Preparing();
      case GuideStatus.error:
        return _Failure(message: state.error!, onRetry: onRetry);
      case GuideStatus.ready:
        return Directionality(
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Text(
            state.text!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        );
    }
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Your guide is preparing the story…'),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// Listen / stop, and the two ways to give the guide a photo.
class _GuideActions extends StatelessWidget {
  const _GuideActions({
    required this.canSpeak,
    required this.isSpeaking,
    required this.minutes,
    required this.onSpeak,
    required this.onCamera,
    required this.onGallery,
  });

  final bool canSpeak;
  final bool isSpeaking;

  /// How long the story takes to hear, once known.
  final int? minutes;
  final VoidCallback onSpeak;

  String get _listenLabel => minutes == null ? 'Listen' : 'Listen · $minutes min';
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('speakButton'),
                onPressed: canSpeak ? onSpeak : null,
                icon: Icon(isSpeaking ? Icons.stop : Icons.volume_up),
                label: Text(isSpeaking ? 'Stop' : _listenLabel),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('cameraButton'),
              tooltip: 'Photograph something and hear its story',
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera),
            ),
            IconButton.filledTonal(
              key: const Key('galleryButton'),
              tooltip: 'Choose a photo',
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library),
            ),
          ],
        ),
      ),
    );
  }
}
