import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide/ask_guide_bar.dart';
import '../guide/guide_controller.dart';
import '../guide/guide_language.dart';
import '../guide/guide_page.dart' show GuideStory;
import '../guide/seat_offer.dart';
import '../poi/poi_model.dart';
import 'place_url.dart';
import 'site_view.dart';

/// A place opened from the map: its website, with the AI explanation to
/// listen to (headphones) or to read (book) on top of it.
class PlacePage extends ConsumerStatefulWidget {
  const PlacePage({super.key, required this.poi});

  final Poi poi;

  @override
  ConsumerState<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends ConsumerState<PlacePage> {
  late final GuideController _controller;
  late final Uri _url = placeUrl(widget.poi);

  /// While the text is open it reports problems itself.
  bool _readingText = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(guideControllerProvider.notifier);
  }

  @override
  void dispose() {
    // Provider state may not change while the widget tree is being torn down.
    Future.microtask(_controller.close);
    super.dispose();
  }

  /// Open the explanation as text, fetching it first if needed.
  Future<void> _read() async {
    _controller.ensureStory(widget.poi);
    _readingText = true;
    await showStorySheet(context, title: widget.poi.name, onRetry: _controller.retry);
    _readingText = false;
  }

  void _reportFailure(GuideState? previous, GuideState next) {
    final failedNow = next.status == GuideStatus.error && previous?.status != GuideStatus.error;
    if (!failedNow || _readingText || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(guideControllerProvider, _reportFailure);
    watchSeatOffers(ref, context);
    final state = ref.watch(guideControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('backToAppButton'),
          tooltip: 'Back to the app',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.poi.name),
        centerTitle: false,
        actions: [
          _ListenButton(state: state, onPressed: () => _controller.toggleListening(widget.poi)),
          IconButton(
            key: const Key('readButton'),
            tooltip: 'Read the explanation',
            icon: const Icon(Icons.menu_book),
            onPressed: _read,
          ),
        ],
      ),
      body: ref.watch(siteViewBuilderProvider)(_url),
    );
  }
}

/// Headphones to start, a spinner while the story is written, stop to end.
class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.state, required this.onPressed});

  final GuideState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (state.status == GuideStatus.loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      key: const Key('listenButton'),
      tooltip: state.isSpeaking ? 'Stop listening' : 'Listen to the explanation',
      icon: Icon(state.isSpeaking ? Icons.stop_circle_outlined : Icons.headphones),
      onPressed: onPressed,
    );
  }
}

/// The explanation as text, in a sheet over the website.
Future<void> showStorySheet(
  BuildContext context, {
  required String title,
  required VoidCallback onRetry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(guideControllerProvider);
          return ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (state.minutes != null)
                Text('About ${state.minutes} min', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              GuideStory(
                state: state,
                language: ref.watch(guideLanguageProvider),
                onRetry: onRetry,
              ),
              const SizedBox(height: 24),
              const AskGuideBar(),
            ],
          );
        },
      ),
    ),
  );
}
