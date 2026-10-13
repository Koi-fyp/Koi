import 'package:hive/hive.dart';

/// Tiny string key-value seam over a plain Hive box, so stores can be tested
/// with [MemoryKeyValueStore] instead of Hive files.
abstract class KeyValueStore {
  String? get(String key);
  Future<void> put(String key, String value);
  Future<void> delete(String key);
}

class HiveKeyValueStore implements KeyValueStore {
  HiveKeyValueStore(this._box);
  final Box<String> _box;

  /// Opens (or reuses) the plain, unencrypted Hive box [name].
  static Future<HiveKeyValueStore> open(String name) async =>
      HiveKeyValueStore(await Hive.openBox<String>(name));

  @override
  String? get(String key) => _box.get(key);
  @override
  Future<void> put(String key, String value) => _box.put(key, value);
  @override
  Future<void> delete(String key) => _box.delete(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  MemoryKeyValueStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  String? get(String key) => values[key];
  @override
  Future<void> put(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
