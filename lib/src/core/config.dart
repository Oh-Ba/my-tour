import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Address of the backend in `/server`.
///
/// The default reaches a server on the development computer:
///  - Android phone on USB: run `adb reverse tcp:1402 tcp:1402` once per
///    connection (the VS Code launch options do it for you). The phone's own
///    port 1402 then leads to the computer through the cable, so it works
///    whatever Wi-Fi the phone is on.
///  - iOS simulator: works as is.
///
/// Anything else, override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:1402
///
/// Android emulator:      http://10.0.2.2:1402
/// Phone over Wi-Fi:      `http://<your computer's IP>:1402` (same network)
/// Deployed server:       its https address
const String defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:1402',
);

final apiBaseUrlProvider = Provider<String>((ref) => defaultApiBaseUrl);

/// One HTTP client shared by every service, closed with the app.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
