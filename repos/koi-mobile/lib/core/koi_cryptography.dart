import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';

/// Speeds up PBKDF2 for flutter_lib's KoiCryptoService WITHOUT changing it or
/// the payload format (decision 2026-10-13: native + session cache).
///
/// KoiCryptoService derives its key with `Pbkdf2(...)`, which asks
/// `Cryptography.instance`. Installing [KoiCryptography] there gives it:
/// - native Android PBKDF2-HMAC-SHA256 via cryptography_flutter's
///   FlutterPbkdf2 (measured on the Infinix X663, release build: 1.7–3.6 s
///   vs 9.9–11.0 s pure Dart; derived key bytes identical), and
/// - an in-memory cache of derived keys per (password, salt, parameters) for
///   this app session, so a key is derived once per launch instead of on
///   every encrypt/decrypt.
///
/// Everything else (AES-GCM etc.) stays the pure-Dart implementation, which
/// is exactly what the crypto parity tests (6/6 both ways) exercise.
class KoiCryptography extends DartCryptography {
  KoiCryptography({this.useNative = true});

  /// false in unit tests (no platform channel there).
  final bool useNative;

  /// Install as the process-wide instance. Call once from main().
  static void install({bool useNative = true}) {
    Cryptography.instance = KoiCryptography(useNative: useNative);
  }

  @override
  Pbkdf2 pbkdf2({
    required MacAlgorithm macAlgorithm,
    required int iterations,
    required int bits,
  }) {
    final dart = DartPbkdf2(
      macAlgorithm: macAlgorithm,
      iterations: iterations,
      bits: bits,
    );
    Pbkdf2 inner = dart;
    if (useNative) {
      final native = FlutterPbkdf2(
        macAlgorithm: macAlgorithm,
        iterations: iterations,
        bits: bits,
        fallback: dart,
      );
      if (native.isSupported) inner = native;
    }
    return CachingPbkdf2(inner);
  }
}

/// A [Pbkdf2] that remembers derived keys for the rest of the session.
///
/// Keys live only in memory (never persisted). Concurrent requests for the
/// same key share one derivation. A failed derivation is not cached.
class CachingPbkdf2 extends Pbkdf2 {
  CachingPbkdf2(this._inner) : super.constructor();

  final Pbkdf2 _inner;

  static final Map<String, Future<SecretKey>> _cache = {};

  /// Upper bound on cached keys; one user normally needs exactly one.
  static const int maxEntries = 8;

  /// Forget every cached key (call on sign-out).
  static void clear() => _cache.clear();

  @visibleForTesting
  static int get cachedCount => _cache.length;

  @override
  int get bits => _inner.bits;
  @override
  int get iterations => _inner.iterations;
  @override
  MacAlgorithm get macAlgorithm => _inner.macAlgorithm;

  @override
  Future<SecretKey> deriveKey({
    required SecretKey secretKey,
    required List<int> nonce,
  }) async {
    final secretBytes = await secretKey.extractBytes();
    final id = [
      '$macAlgorithm',
      iterations,
      bits,
      base64Encode(secretBytes),
      base64Encode(nonce),
    ].join('|');

    final hit = _cache[id];
    if (hit != null) return hit;

    if (_cache.length >= maxEntries) _cache.remove(_cache.keys.first);
    final future = _inner.deriveKey(secretKey: secretKey, nonce: nonce);
    _cache[id] = future;
    try {
      return await future;
    } catch (_) {
      _cache.remove(id);
      rethrow;
    }
  }
}
