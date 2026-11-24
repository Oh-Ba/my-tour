import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent string storage. Features depend on this interface rather
/// than on SharedPreferences, so they can be tested with an in-memory store.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [KeyValueStore] backed by the device's preferences.
class SharedPreferencesStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    return (await SharedPreferences.getInstance()).getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

final keyValueStoreProvider = Provider<KeyValueStore>((ref) {
  return SharedPreferencesStore();
});
