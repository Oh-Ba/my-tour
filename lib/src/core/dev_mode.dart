/// Developer mode: a module only the app's developer has.
///
/// It is compiled in only when the app is built with
///   `--dart-define=DEV_MODE=true --dart-define=DEV_TOKEN=<the server's DEV_TOKEN>`
/// In every other build this constant is false, the compiler removes the
/// developer screens, and the server refuses developer requests anyway.
const bool devModeEnabled = bool.fromEnvironment('DEV_MODE');

/// The secret the server expects on developer requests.
const String devToken = String.fromEnvironment('DEV_TOKEN');
