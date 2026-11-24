import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/speech_engine.dart';
import '../poi/poi_model.dart';
import '../profile/interest_profile.dart';
import '../trip_start/trip_state.dart';
import 'guide_language.dart';
import 'guide_service.dart';
import 'photo_picker.dart';
import 'rest_spot_service.dart';

enum GuideStatus { idle, loading, ready, error }

/// A story this long is worth sitting down for.
const int seatOfferMinMinutes = 3;

/// What the guide screen shows.
@immutable
class GuideState {
  final GuideStatus status;

  /// The story, once [status] is [GuideStatus.ready].
  final String? text;

  /// How long the story takes to say, in minutes.
  final int? minutes;

  /// What went wrong, when [status] is [GuideStatus.error].
  final String? error;

  final bool isSpeaking;

  /// The photo the story is about, for photo stories.
  final PickedPhoto? photo;

  /// Places to sit that are being offered before the story is read aloud.
  /// Empty when nothing is on offer.
  final List<RestSpot> seatOffer;

  const GuideState({
    this.status = GuideStatus.idle,
    this.text,
    this.minutes,
    this.error,
    this.isSpeaking = false,
    this.photo,
    this.seatOffer = const [],
  });

  const GuideState.loading({this.photo})
      : status = GuideStatus.loading,
        text = null,
        minutes = null,
        error = null,
        isSpeaking = false,
        seatOffer = const [];

  GuideState ready(GuideStory story) {
    return GuideState(
      status: GuideStatus.ready,
      text: story.text,
      minutes: story.minutes,
      photo: photo,
    );
  }

  GuideState failed(String error) {
    return GuideState(status: GuideStatus.error, error: error, photo: photo);
  }

  /// The same story with the voice on or off, and optionally an [offer] of
  /// places to sit. Speaking and offering never happen together.
  GuideState _with({required bool isSpeaking, List<RestSpot> offer = const []}) {
    return GuideState(
      status: status,
      text: text,
      minutes: minutes,
      error: error,
      photo: photo,
      isSpeaking: isSpeaking,
      seatOffer: offer,
    );
  }

  GuideState speaking(bool isSpeaking) => _with(isSpeaking: isSpeaking);

  GuideState offering(List<RestSpot> spots) => _with(isSpeaking: false, offer: spots);

  GuideState withoutOffer() => _with(isSpeaking: isSpeaking);
}

/// Fetches a story; `request` is what the traveller asked for, if anything.
typedef _StoryRequest = Future<void> Function({bool autoPlay});

/// Runs one guide session: fetches a story, reads it aloud, and notes what
/// the traveller engaged with so the app can learn their taste.
class GuideController extends Notifier<GuideState> {
  /// Repeats the last request; used by [retry], [ask] and [changeLanguage].
  _StoryRequest? _lastRequest;

  /// Categories of the place the current story is about.
  List<String> _categories = const [];

  /// The place the current story is about; null for a photo taken on the map.
  String? _placeId;

  /// What the traveller wrote or said about the current subject.
  String _asked = '';

  /// A seat is offered once per subject, not before every retelling.
  bool _seatOffered = false;

  SpeechEngine get _speech => ref.read(speechEngineProvider);
  GuideService get _service => ref.read(guideServiceProvider);
  RestSpotService get _restSpots => ref.read(restSpotServiceProvider);
  GuideLanguage get _language => ref.read(guideLanguageProvider);
  InterestProfileNotifier get _profile =>
      ref.read(interestProfileProvider.notifier);

  @override
  GuideState build() {
    _speech.onDone(_onSpeechDone);
    return const GuideState();
  }

  void _onSpeechDone() {
    if (ref.mounted) state = state.speaking(false);
  }

  /// A new subject starts without the previous one's request or seat offer.
  void _startSubject({required String? placeId, required List<String> categories}) {
    if (placeId == null || placeId != _placeId) {
      _asked = '';
      _seatOffered = false;
    }
    _placeId = placeId;
    _categories = categories;
  }

  /// Tell the story of [poi].
  Future<void> explainPlace(Poi poi, {bool autoPlay = false}) {
    _startSubject(placeId: poi.id, categories: poi.categories);
    _lastRequest = ({bool autoPlay = false}) => _tell(
          const GuideState.loading(),
          () => _service.explainPlace(
            poi,
            language: _language.name,
            interests: ref.read(tripStateProvider).searchTerms,
            request: _asked,
          ),
          autoPlay: autoPlay,
          seatsNear: (lat: poi.lat, lon: poi.lon),
        );
    _profile.record(poi.categories, Engagement.viewed);
    return _lastRequest!(autoPlay: autoPlay);
  }

  /// Tell the story behind [photo], taken at ([lat], [lon]).
  ///
  /// [poi] is the place being visited, if the photo was taken from its page;
  /// [nearby] are names of places around, which help recognise the subject.
  Future<void> explainPhoto(
    PickedPhoto photo, {
    required double? lat,
    required double? lon,
    Poi? poi,
    List<String> nearby = const [],
    bool autoPlay = false,
  }) {
    _startSubject(placeId: null, categories: poi?.categories ?? const []);
    _lastRequest = ({bool autoPlay = false}) => _tell(
          GuideState.loading(photo: photo),
          () => _service.explainPhoto(
            PhotoRequest(
              photo: photo,
              language: _language.name,
              lat: lat,
              lon: lon,
              placeName: poi?.name,
              nearby: nearby,
              request: _asked,
            ),
          ),
          autoPlay: autoPlay,
        );
    _profile.record(_categories, Engagement.photographed);
    return _lastRequest!(autoPlay: autoPlay);
  }

  /// Places to sit near [where], looked for while the story is being written.
  /// Null when a seat will not be offered anyway.
  Future<List<RestSpot>>? _lookForSeats(({double lat, double lon})? where, bool autoPlay) {
    if (where == null || !autoPlay || _seatOffered) return null;
    return _restSpots.find(lat: where.lat, lon: where.lon);
  }

  /// Show [loading], fetch the story, then show it or the error. With
  /// [autoPlay] it is then read aloud, after offering a seat if it is long.
  Future<void> _tell(
    GuideState loading,
    Future<GuideStory> Function() fetch, {
    required bool autoPlay,
    ({double lat, double lon})? seatsNear,
  }) async {
    await _speech.stop();
    state = loading;
    final seats = _lookForSeats(seatsNear, autoPlay);
    try {
      final story = await fetch();
      if (!ref.mounted) return;
      state = loading.ready(story);
      if (autoPlay) await _playOrOfferSeat(story.minutes, seats);
    } on GuideException catch (e) {
      if (ref.mounted) state = loading.failed(e.message);
    }
  }

  /// Before a long story, suggest somewhere nice to sit; otherwise start.
  Future<void> _playOrOfferSeat(int minutes, Future<List<RestSpot>>? seats) async {
    final worthSitting = minutes >= seatOfferMinMinutes && seats != null;
    final spots = worthSitting ? await seats : const <RestSpot>[];
    if (!ref.mounted) return;
    if (spots.isEmpty) return _play();

    _seatOffered = true;
    state = state.offering(spots);
  }

  Future<void> _play() async {
    final text = state.text;
    if (text == null) return;
    state = state.speaking(true);
    _profile.record(_categories, Engagement.listened);
    await _speech.speak(text, languageCode: _language.code);
  }

  Future<void> _silence() async {
    await _speech.stop();
    if (ref.mounted) state = state.speaking(false);
  }

  /// Start reading the story aloud, or stop if it is being read.
  Future<void> toggleSpeech() => state.isSpeaking ? _silence() : _play();

  /// The traveller is happy where they are: read the story now.
  Future<void> explainHere() => _play();

  /// The traveller chose a place to sit: show the way there. The story stays
  /// ready, and "listen" starts it when they arrive.
  Future<void> goTo(RestSpot spot) {
    state = state.withoutOffer();
    return ref.read(directionsLauncherProvider)(directionsUrl(spot));
  }

  /// The offer was closed without choosing.
  Future<void> dismissOffer() async {
    state = state.withoutOffer();
  }

  /// Whether the story of [poi] is here or on its way.
  bool _hasStoryOf(Poi poi) {
    final usable = state.status == GuideStatus.ready || state.status == GuideStatus.loading;
    return _placeId == poi.id && usable;
  }

  /// The listen button of a place: fetch its story and read it aloud, or
  /// start / stop the voice if the story is already here.
  Future<void> toggleListening(Poi poi) async {
    if (!_hasStoryOf(poi)) return explainPlace(poi, autoPlay: true);
    if (state.status == GuideStatus.ready) return toggleSpeech();
  }

  /// Make sure the story of [poi] is available as text, without touching
  /// the voice if it is already being read.
  Future<void> ensureStory(Poi poi) async {
    if (!_hasStoryOf(poi)) return explainPlace(poi);
  }

  /// The traveller wrote or said something to the guide, such as "more
  /// thorough please" or a question: retell the story with that in mind.
  /// With [speak], or if they were listening, the answer is read aloud.
  Future<void> ask(String request, {bool speak = false}) async {
    final asked = request.trim();
    if (asked.isEmpty || _lastRequest == null) return;
    _asked = asked;
    await _lastRequest!(autoPlay: speak || state.isSpeaking);
  }

  /// Ask again after an error.
  Future<void> retry() async => _lastRequest?.call();

  /// Switch language and retell the current story in it.
  Future<void> changeLanguage(GuideLanguage language) async {
    final wasSpeaking = state.isSpeaking;
    await ref.read(guideLanguageProvider.notifier).select(language);
    await _lastRequest?.call(autoPlay: wasSpeaking);
  }

  /// Leave the guide: stop the voice and forget the story.
  Future<void> close() async {
    if (!ref.mounted) return;
    _lastRequest = null;
    _startSubject(placeId: null, categories: const []);
    await _speech.stop();
    if (ref.mounted) state = const GuideState();
  }
}

final guideControllerProvider = NotifierProvider<GuideController, GuideState>(
  GuideController.new,
);
