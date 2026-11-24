# Claude Memory - My Tour Project

> This file serves as a persistent memory for Claude to remember conversations, project context, and important details.

---

## Project Overview

**Name**: My Tour
**Type**: Flutter Mobile Application
**Description**: An AI tour guide. It finds attractions around the traveller, tells their story in text and in a spoken voice in many languages, explains photos the traveller takes, and learns what they like.

**Status**: Active Development

---

## Tech Stack

### Frontend (Flutter)
- **Language**: Dart (SDK ^3.9.2)
- **Framework**: Flutter
- **State Management**: Riverpod (^3.0.3)
- **Map Integration**: Google Maps Flutter (^2.5.0)
- **Location Services**: Geolocator (^14.0.2), Geofence Service (^6.0.0+1)
- **Permissions**: Permission Handler (^12.0.1)
- **Storage**: SharedPreferences (^2.2.2)
- **HTTP Client**: http (^1.2.0)
- **Notifications**: flutter_local_notifications (^17.2.1)
- **Voice**: flutter_tts (^4.2.5) - on-device voices, iOS and Android
- **Camera / photos**: image_picker (^1.2.3)
- **In-app web pages**: webview_flutter (^4.14.1)
- **Voice requests**: speech_to_text (^7.4.0); **directions**: url_launcher; **recording (dev)**: record (^6.2.1)
- **Other**: intl, timezone, freezed_annotation, json_annotation

### Backend (Node.js)
- **Location**: `/server` directory
- **Framework**: Express
- **Port**: 1402
- **Places**: OpenStreetMap via the Overpass API (real places worldwide, no key). Falls back to the San Francisco fixtures when unreachable; tests always use fixtures.
- **AI**: Claude through `@anthropic-ai/sdk` (model `claude-opus-5-5`, override with `GUIDE_MODEL`). Needs `ANTHROPIC_API_KEY` in `server/.env`.
- **Testing**: Jest + supertest

---

## Current Features

### Core Functionality
1. **Location Tracking** - blue dot, permission flow, recenter.

2. **Tour Planning** (`features/trip_start`)
   - Interest chips plus free-text interests ("second hand stores").
   - "Classic recommendations" checkbox: museums, archaeology, historical places and landmarks are always recommended. It can be unchecked for the current tour and is checked again when a tour ends (`TripConfig.ended()`).
   - Radius slider (1-50 km, default 1 km). Tour is saved locally; edit / end from the places sheet.

3. **Place Discovery** (`features/poi`)
   - Each place carries a `reason`: `interest`, `classic`, or `for_you`.
   - `for_you` places match what the app learned and may lie beyond the radius (`outsideRadius`), up to `extendedRadius` (3x the radius, at least +5 km, capped at 60 km). Half of the 10 slots are reserved for beyond-radius places.
   - At most 30 classics, notable ones (Wikipedia/Wikidata entry) first.

4. **AI Guide** (`features/guide`)
   - Story of a place, written by Claude in the chosen language (17 languages, RTL aware).
   - "Listen" reads it aloud with the phone's voice in that language.
   - Camera / gallery: photograph an attraction or a detail and get the story behind it. Also a camera button on the map for "what am I looking at?".
   - The geofence notification's "Listen" action opens the guide and starts speaking.

5. **Place page** (`features/place`)
   - Pressing a place marker on the map opens the place's website inside the app (`place_url.dart`: own website, else Wikipedia article, else a web search), with a back arrow at the top left.
   - On that page: headphones = listen to the AI explanation while browsing; book icon = open the explanation as text in a sheet.

6. **Traveller marker and logo**
   - The user's position is a tiny blue stick-figure wanderer (pointed hat, robe, beard, tall staff), drawn in code in `features/map/traveller_icon.dart`. It replaces the blue dot.
   - The app logo / launcher icon is a traveller looking through a spyglass. `python tool/generate_logo.py` redraws it and writes every Android and iOS icon size plus `assets/logo.png`.

7. **Story length, seats and requests** (`server/lib/narration.js`, `features/guide`)
   - A story takes at most 10 minutes unless the traveller asks for more (typed, spoken with the mic button, or the "More thorough" chip). Claude labels its reply `LENGTH: standard|extended`; the server trims a standard story to the limit at a sentence end.
   - The story opens by saying how long it takes. Claude writes `{{MINUTES}}`; the server measures the text (140 words/min) and fills in the number. The app shows it too ("Listen · 7 min").
   - Before reading a story of 3+ minutes aloud, the app offers the nearest cafe, garden and viewpoint (`GET /rest-spots`) with walking directions, or "It's fine, explain here". Offered once per place.
   - Long stories are spoken in chunks (`chunkForSpeech`), because Android refuses more than 4,000 characters at once.

8. **Developer mode** (`features/dev`, `server/lib/dev_routes.js`, `server/lib/store.js`)
   - Only in builds made with `--dart-define-from-file=dev.local.json` (`DEV_MODE`, `DEV_TOKEN`); the server only mounts `/dev/*` when it has `DEV_TOKEN`. Other builds do not contain the screens. "DEV" is shown in red on the title.
   - "New exhibit" (red button on the map): record another guide with pause/resume, save or discard; type notes; take photos for travellers; set the house style; ignore any lesson; discard the exhibit.
   - A lesson becomes notes via `guide.extractLesson` (what to tell, what to focus on, style) in the guide's own words. Kept notes and the house style are added to the prompt for that place (`store.knowledgeFor`); stories are rewritten when the knowledge changes.
   - Data lives in `server/data/` (JSON + files, git-ignored). Photos are public at `/places/photos` and `/media/:file`; recordings are never served.
   - **Speech-to-text**: OpenAI Whisper API (`server/lib/transcriber.js`, `OPENAI_API_KEY`). Claude's API has no audio input. Without the key, recordings are kept and wait; `npm run stt:check` tests the connection. The transcriber is one interface (`transcribe({ buffer, mediaType })`), so a local model can replace it.
   - **Long recordings (up to ~3 h)**: the app records in pieces - one per stretch between pauses, cut every 10 minutes (`pieceLength`) - and uploads each in the background; pieces wait on the phone when offline. The server transcribes pieces one at a time in a background queue (`job_queue.js`), joins them in order when the recording is finished, then extracts the lesson. Unfinished work resumes on server start (`app.resumeDevWork`). A failed piece can be retried.

9. **Learning** (`features/profile`)
   - Opening (1), listening to (2) and photographing (3) a place add to the score of its categories. Categories scoring 5+ (top 3) are sent as `learned` with every place request.

---

## Project Structure

```
my_tour/
├── lib/
│   ├── main.dart
│   └── src/
│       ├── app.dart
│       ├── core/
│       │   ├── config.dart               # API base URL, shared http client
│       │   ├── key_value_store.dart      # storage interface (+ SharedPreferences impl)
│       │   └── persisted_notifier.dart   # mixin: Notifier state that survives launches
│       ├── features/
│       │   ├── map/        map_page.dart, map_controller.dart (markers, mapStateProvider),
│       │   │               traveller_icon.dart
│       │   ├── poi/        poi_model, poi_query, poi_service, poi_repository,
│       │   │               poi_style (colors/icons/labels), poi_list_sheet, poi_detail_card
│       │   ├── trip_start/ trip_state.dart, trip_sheet.dart
│       │   ├── guide/      guide_service, guide_controller, guide_page, guide_language,
│       │   │               photo_picker, open_guide
│       │   ├── place/      place_page, place_url, site_view (in-app web view)
│       │   ├── dev/        developer mode: new_exhibit_page, exhibit_controller, dev_service,
│       │   │               voice_recorder, dev_models
│       │   ├── profile/    interest_profile.dart (learning)
│       │   └── coffee/
│       ├── services/       location_service, geofence_service, speech_engine
│       └── widgets/
├── server/
│   ├── index.js            # wiring only
│   ├── lib/
│   │   ├── app.js          # routes (createApp)
│   │   ├── poi_search.js   # interest / classic / for_you decisions
│   │   ├── providers.js    # fixture + OpenStreetMap providers
│   │   ├── overpass.js     # Overpass query builder + mirror-racing client
│   │   ├── places.js       # OSM element -> place
│   │   ├── categories.js   # category vocabulary, free-text keywords
│   │   ├── guide.js        # Claude: place story, photo story, interest -> OSM tags, lessons
│   │   ├── narration.js    # story length rules (10 min cap, announced duration)
│   │   ├── rest_spots.js   # nearest cafe / garden / viewpoint to sit at
│   │   ├── store.js        # what the developer taught (exhibits, lessons, photos, style)
│   │   ├── dev_routes.js   # /dev/* (token protected), background transcription
│   │   ├── transcriber.js  # speech-to-text (Whisper API)
│   │   ├── job_queue.js    # serial background jobs
│   │   └── geo.js
│   ├── fixtures/
│   └── tests/
└── test/                   # Flutter unit + widget tests, helpers/fakes.dart
```

---

## Important Configuration

### Backend URLs
Default is `http://127.0.0.1:1402` (`lib/src/core/config.dart`).
- **Android phone on USB** (the usual setup): `adb reverse tcp:1402 tcp:1402` once per connection; the VS Code launch options run it automatically. Works whatever Wi-Fi the phone is on.
- **iOS Simulator**: works as is.
- **Android Emulator**: `--dart-define=API_BASE_URL=http://10.0.2.2:1402`
- **Phone over Wi-Fi**: `--dart-define=API_BASE_URL=http://<COMPUTER_IP>:1402`; phone and computer must be on the same network.

### Test location
Try the app as if you were somewhere else (no GPS or permission needed):
`flutter run --dart-define=TEST_LOCATION=37.5079,15.0830` (Catania). In VS Code, pick the launch option "My Tour (as if in Catania)". Implemented by `FixedLocationService` in `services/location_service.dart`.

### Server environment (`server/.env`, see `.env.example`)
- `ANTHROPIC_API_KEY` - required for the AI guide
- `GUIDE_MODEL`, `POI_PROVIDER` (`osm` | `fixtures`), `OVERPASS_URL`, `PORT` - optional
- `DEV_TOKEN` - switches developer mode on; must match `DEV_TOKEN` in `dev.local.json` (both git-ignored)
- `OPENAI_API_KEY` - speech-to-text for developer recordings; `STT_MODEL` optional (default `whisper-1`)
- `DATA_DIR` - where the developer's teaching is stored (default `server/data`)

### API Keys Required
- **Google Maps API Key**: Required for both Android and iOS
  - Android: `android/app/src/main/AndroidManifest.xml`
  - iOS: `ios/Runner/AppDelegate.swift`

### Permissions
- Android: ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, INTERNET, POST_NOTIFICATIONS; `TTS_SERVICE` query for voices
- iOS: location usage strings, NSCameraUsageDescription, NSPhotoLibraryUsageDescription, NSLocalNetworkUsageDescription

---

## Development Commands

### Flutter
```bash
flutter pub get                # Install dependencies
flutter run                    # Run app
flutter test                   # Run tests
flutter clean                  # Clean build
flutter analyze                # Analyze code
flutter format .               # Format code
```

### Backend
```bash
cd server
npm install                    # Install dependencies
npm start                      # Start server
npm run dev                    # Start with auto-reload
npm test                       # Run tests
```

### Docker (Backend)
```bash
cd server
docker build -t my-tour-poi-server .
docker run -p 1402:1402 my-tour-poi-server
```

---

## State Management (Riverpod Providers)

- `tripStateProvider` - the tour (interests, typed interests, radius, classics, active)
- `interestProfileProvider` / `learnedCategoriesProvider` - what the app learned
- `guideLanguageProvider` - language of the guide
- `guideControllerProvider` - one guide session (story, voice, photo, seat offer, requests)
- `exhibitControllerProvider` - one developer "New exhibit" session
- `poiServiceProvider`, `poiRepositoryProvider`, `sortedPoisProvider`
- `mapStateProvider`, `locationServiceProvider`
- Injectable seams, overridden in tests: `keyValueStoreProvider`, `httpClientProvider`, `apiBaseUrlProvider`, `guideServiceProvider`, `speechEngineProvider`, `photoPickerProvider`, `deviceLanguageCodeProvider`, `siteViewBuilderProvider`, `testLocationProvider`, `restSpotServiceProvider`, `voiceInputProvider`, `directionsLauncherProvider`, `devServiceProvider`, `voiceRecorderProvider`

---

## API Reference

### GET /pois
- `lat`, `lon` (required), `radiusM` (default 1000)
- `interests` - comma-separated; known categories or free text
- `classics` - `true` to add tourist classics
- `learned` - comma-separated learned categories; searched beyond the radius

Returns `{ count, radius, extendedRadius, source, pois: [{ id, name, categories, lat, lon, snippet, distance, reason, outsideRadius, notable?, wikipedia?, website? }] }`

### POST /guide/explain
Body `{ place: { id, name, categories, lat, lon, snippet, wikipedia }, language, interests, request? }` -> `{ text, minutes, language }`

### POST /guide/photo
Body `{ image (base64), mediaType, language, lat, lon, placeName?, nearby[], request? }` -> `{ text, minutes, language }`

### GET /rest-spots
`lat`, `lon`, `radiusM` (default 400) -> `{ spots: [{ id, name, kind: garden|cafe|viewpoint, lat, lon, distance }] }`

### GET /places/photos, GET /media/:file
Photos the developer took of a place.

### /dev/* (header `x-dev-token`)
`GET|PUT /style`, `GET|POST /exhibits`, `DELETE /exhibits/:id`, `GET /exhibits/:id`, `POST /exhibits/:id/recordings` (open), `POST /exhibits/:id/recordings/:lessonId/segments?index=&durationMs=` (raw audio, answers 202), `POST /exhibits/:id/recordings/:lessonId/finish`, `POST /exhibits/:id/lessons` (`{ text }`), `POST /exhibits/:id/lessons/:lessonId/ignore`, `POST /exhibits/:id/lessons/:lessonId/retry`, `POST /exhibits/:id/photos` (raw image)

### GET /coffee, GET /health

---

## Marker Colors by Category

Defined once in `lib/src/features/poi/poi_style.dart` (`styleFor`), shared by markers, list and cards.

---

## Known Issues / TODOs

### Known limitations
- The voice is the phone's built-in text-to-speech. A more natural cloud voice can be added behind `SpeechEngine` (`services/speech_engine.dart`).
- Public Overpass servers are sometimes overloaded; for production host one or switch provider behind `createOsmProvider`.
- Writing a story takes the AI about 30 s (standard) to over a minute (thorough); the app waits with a spinner. Streaming the story would remove the wait.
- Developer photos are stored and served, but no screen shows them to travellers yet.
- iOS builds need a Mac with Xcode; the Google Maps key in `ios/Runner/AppDelegate.swift` is still a placeholder.

### Future Enhancements
- Turn-by-turn navigation
- Favorites, trip history
- Offline caching, marker clustering

---

## Platform Support

- ✅ Android (API 21+)
- ✅ iOS (13.0+)
- ⚠️ Web (limited - location services may vary)
- ❌ Desktop (not configured)

---

## Conversation History

### Session 1 - 2026-01-27
- Created CLAUDE.md, documented the project.

### Session 3 - 2026-11-18
- Story length rules (10 min cap, announced duration), seat offer, ask-the-guide bar (typed or spoken).
- Developer mode: record other guides, lessons, photos, house style.

### Session 2 - 2026-11-16
- Built the AI tour guide: real places (OpenStreetMap), classics checkbox, free-text interests, learned "for you" recommendations beyond the radius, AI stories for places and photos, voice in 17 languages, iPhone permissions.
- Restructured the server into injectable modules; added Jest and Flutter test suites.

---

## Developer Preferences

- **TDD**: write the unit test first, then the code. Every feature is covered by unit tests.
- **Small functions** that do one thing (functional style); prefer pure functions for logic.
- **Dependency injection**: collaborators (HTTP, AI client, storage, clock, plugins) are passed in or provided, never constructed inside the logic. Server modules are `createX({deps})` factories; Flutter uses Riverpod providers that tests override.
- **Reuse**: look for an existing helper before writing one; shared logic lives in its own module (`poi_style.dart`, `persisted_notifier.dart`, `server/lib/geo.js`).
- **Modules loaded when needed**: e.g. the Anthropic SDK is only `require`d on the first guide call.

---

## Important Notes

1. **Sample Data**: `server/fixtures` (San Francisco) is used by tests and as the fallback when OpenStreetMap cannot be reached.
2. **Network Configuration**: Backend URL must match the testing environment (emulator vs. physical device).
3. **POI Refetch**: a new request is sent after moving 100 m, or at once when the tour or the learned categories change (`shouldFetch` in poi_repository.dart).
4. **Code Style**: Follows Flutter style guidelines with flutter_lints package.

---

*Last Updated: 2026-11-18*
