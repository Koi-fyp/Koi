import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';

/// Counts derivations, returns a fixed key (or fails on demand).
class _CountingPbkdf2 extends Pbkdf2 {
  _CountingPbkdf2() : super.constructor();
  int calls = 0;
  bool fail = false;

  @override
  int get bits => 256;
  @override
  int get iterations => 600000;
  @override
  MacAlgorithm get macAlgorithm => Hmac.sha256();

  @override
  Future<SecretKey> deriveKey({
    required SecretKey secretKey,
    required List<int> nonce,
  }) async {
    calls++;
    if (fail) throw StateError('boom');
    return SecretKey(List.filled(32, nonce.first));
  }
}

void main() {
  setUp(CachingPbkdf2.clear);

  test(
    'derives once per (password, salt); different salt derives again',
    () async {
      final inner = _CountingPbkdf2();
      final kdf = CachingPbkdf2(inner);
      await kdf.deriveKeyFromPassword(password: 'p', nonce: [1, 2]);
      await kdf.deriveKeyFromPassword(password: 'p', nonce: [1, 2]);
      // A brand-new wrapper (KoiCryptoService makes one per call) shares it.
      await CachingPbkdf2(inner)
          .deriveKeyFromPassword(password: 'p', nonce: [1, 2]);
      expect(inner.calls, 1);

      await kdf.deriveKeyFromPassword(password: 'p', nonce: [3, 4]);
      await kdf.deriveKeyFromPassword(password: 'q', nonce: [1, 2]);
      expect(inner.calls, 3);
    },
  );

  test('concurrent requests share one derivation', () async {
    final inner = _CountingPbkdf2();
    final kdf = CachingPbkdf2(inner);
    await Future.wait([
      for (var i = 0; i < 5; i++)
        kdf.deriveKeyFromPassword(password: 'p', nonce: [9]),
    ]);
    expect(inner.calls, 1);
  });

  test('a failed derivation is not cached; clear() forgets keys', () async {
    final inner = _CountingPbkdf2()..fail = true;
    final kdf = CachingPbkdf2(inner);
    await expectLater(
      kdf.deriveKeyFromPassword(password: 'p', nonce: [1]),
      throwsStateError,
    );
    inner.fail = false;
    await kdf.deriveKeyFromPassword(password: 'p', nonce: [1]);
    expect(inner.calls, 2);
    CachingPbkdf2.clear();
    expect(CachingPbkdf2.cachedCount, 0);
  });

  test('cache is bounded', () async {
    final kdf = CachingPbkdf2(_CountingPbkdf2());
    for (var i = 0; i < CachingPbkdf2.maxEntries + 3; i++) {
      await kdf.deriveKeyFromPassword(password: 'p', nonce: [i]);
    }
    expect(CachingPbkdf2.cachedCount, CachingPbkdf2.maxEntries);
  });

  group('with KoiCryptography installed (pure-Dart PBKDF2 + cache)', () {
    final original = Cryptography.instance;
    setUpAll(() => KoiCryptography.install(useNative: false));
    tearDownAll(() => Cryptography.instance = original);

    test(
      'KoiCryptoService still decrypts every web vector, format unchanged',
      () async {
        final doc = jsonDecode(
          File('test/fixtures/web_crypto_vectors.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final service = KoiCryptoService();
        for (final c in (doc['cases'] as List).cast<Map<String, dynamic>>()) {
          expect(
            await service.decrypt(
              c['payload'] as String,
              c['secret'] as String,
            ),
            c['plaintext'],
            reason: c['name'] as String,
          );
          // Re-encrypt: same v1:PBKDF2:salt:nonce:ct shape and round-trips.
          final again = await service.encrypt(
            c['plaintext'] as String,
            c['secret'] as String,
            c['salt'] as String,
          );
          final parts = again.split(':');
          expect(parts, hasLength(5));
          expect(parts.take(3), ['v1', 'PBKDF2', c['salt']]);
          expect(
            await service.decrypt(again, c['secret'] as String),
            c['plaintext'],
          );
        }
        // Six cases share two (secret, salt) pairs at most: derived a few
        // times, not once per encrypt/decrypt.
        expect(CachingPbkdf2.cachedCount, lessThanOrEqualTo(6));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
