import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// String key-value seam over flutter_secure_storage (Android Keystore
/// backed), so tests can use [MemorySecureKv].
abstract interface class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKv implements SecureKv {
  const FlutterSecureKv([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecureKv implements SecureKv {
  MemorySecureKv([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The CSE secrets, one set PER UID (Blueprint §3.1 two-phase secret;
/// "Client-Side Encryption (CSE) at rest").
///
/// - Anonymous phase: a random 32-byte secret, `koi_anon_secret_{uid}`.
///   flutter_lib's KoiCryptoService keeps ONE device-wide
///   `koi_anon_secret`; flutter_lib is not changed (decided 2026-10-19), so
///   that legacy secret is copied ONCE to the first uid that asks
///   (`koi_anon_secret_owner` records which). Every later anonymous uid gets
///   its own new secret.
/// - Linked phase: the account password, cached as `koi_linked_secret_{uid}`
///   (decided 2026-10-19, option a) so the unlock screen appears only on a
///   new device or after the cache is cleared; deleted on sign-out.
///
/// Secrets never leave the device and are never logged.
class AccountSecretStore {
  AccountSecretStore(this._kv, {Random? random})
    : _random = random ?? Random.secure();

  final SecureKv _kv;
  final Random _random;

  static const String legacyAnonKey = 'koi_anon_secret';
  static const String legacyOwnerKey = 'koi_anon_secret_owner';
  static String anonKey(String uid) => 'koi_anon_secret_$uid';
  static String linkedKey(String uid) => 'koi_linked_secret_$uid';

  /// Serialises get-or-create so two callers never make two secrets.
  Future<void> _lock = Future.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _lock.then((_) => body());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// This uid's anonymous-phase secret, created (or copied from the legacy
  /// device secret, once) on first use.
  Future<String> anonymousSecret(String uid) => _locked(() async {
    final existing = await _kv.read(anonKey(uid));
    if (existing != null && existing.isNotEmpty) return existing;
    final owner = await _kv.read(legacyOwnerKey);
    final legacy = await _kv.read(legacyAnonKey);
    final String secret;
    if (owner == null && legacy != null && legacy.isNotEmpty) {
      secret = legacy; // the data saved before MOB-1 used this one
    } else {
      secret = base64Encode(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      );
    }
    await _kv.write(anonKey(uid), secret);
    if (owner == null) await _kv.write(legacyOwnerKey, uid);
    return secret;
  });

  /// The anonymous secret if [uid] has one; never creates.
  Future<String?> existingAnonymousSecret(String uid) async {
    final v = await _kv.read(anonKey(uid));
    if (v != null && v.isNotEmpty) return v;
    final owner = await _kv.read(legacyOwnerKey);
    // Before the first copy, the legacy secret belongs to whoever asks
    // first; a claim source that never asked has none of its own.
    return owner == uid ? await _kv.read(legacyAnonKey) : null;
  }

  /// Call only after a migration away from [uid]'s anonymous secret is
  /// complete AND acknowledged. Also removes the legacy copy it came from.
  Future<void> deleteAnonymousSecret(String uid) => _locked(() async {
    await _kv.delete(anonKey(uid));
    if (await _kv.read(legacyOwnerKey) == uid) {
      await _kv.delete(legacyAnonKey);
    }
  });

  Future<String?> linkedSecret(String uid) async {
    final v = await _kv.read(linkedKey(uid));
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLinkedSecret(String uid, String password) =>
      _kv.write(linkedKey(uid), password);

  Future<void> clearLinkedSecret(String uid) => _kv.delete(linkedKey(uid));
}
