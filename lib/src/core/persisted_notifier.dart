import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'key_value_store.dart';

/// Gives a [Notifier] a value that survives app launches.
///
/// Call [restore] from `build()`, and change the value through [save].
mixin Persisted<T> on Notifier<T> {
  /// Completes once the saved value has been restored.
  late Future<void> loaded;

  bool _edited = false;

  String get storageKey;

  /// Saved text back into a value; return null when it is unreadable.
  T? decode(String saved);

  String encode(T value);

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  /// Start loading the saved value in the background.
  void restore() {
    _edited = false;
    loaded = _restore();
  }

  Future<void> _restore() async {
    final saved = await _store.read(storageKey);
    // A change made while loading is newer than what was saved.
    if (saved == null || _edited || !ref.mounted) return;
    final value = decode(saved);
    if (value != null) state = value;
  }

  Future<void> save(T value) {
    _edited = true;
    state = value;
    return _store.write(storageKey, encode(value));
  }
}
