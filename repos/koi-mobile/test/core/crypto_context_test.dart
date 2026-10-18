import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';
import 'package:koi_mobile/core/sync_queue.dart';

const _uid = 'user-123';
const _cacheKey = 'koi_salt_cache_$_uid';
const _anonKey = 'koi_anon_secret'; // flutter_lib KoiCryptoService key
const _remoteSalt = 'cmVtb3RlLXNhbHQtMTZieQ==';
const _linked = AuthState(isLinked: true, linkedSecret: 'pw');
const _anon = AuthState(isLinked: false);

class _RecordingQueue implements SyncQueue {
  final items = <SyncItem>[];
  @override
  void enqueue(SyncItem item) => items.add(item);
}

/// Test harness with scripted connectivity and Firestore results.
///
/// The create-once fake behaves like UserDocumentStore.createSaltOnce:
/// returns [remoteSalt] when Firestore "has" one, otherwise stores and
/// returns the candidate.
class _Harness {
  _Harness({
    this.online = true,
    this.fetchResult,
    this.fetchThrows = false,
    this.remoteSalt,
    this.createThrows = false,
  }) {
    resolver = CryptoContextResolver(
      storage: storage,
      syncQueue: queue,
      saltCache: SaltCache(storage: storage, onReplaced: () => keyClears++),
      isOnline: () async {
        onlineChecks++;
        return online;
      },
      fetchSalt: (uid) async {
        fetches.add(uid);
        if (fetchThrows) throw Exception('firestore unavailable');
        return fetchResult;
      },
      createSaltOnce: (uid, candidate) async {
        creates.add((uid, candidate));
        if (createThrows) throw Exception('permission-denied');
        return remoteSalt ??= candidate;
      },
    );
  }

  bool online;
  String? fetchResult;
  bool fetchThrows;
  String? remoteSalt;
  bool createThrows;
  int onlineChecks = 0;
  int keyClears = 0;
  final fetches = <String>[];
  final creates = <(String, String)>[];
  final queue = _RecordingQueue();
  final storage = const FlutterSecureStorage();
  late final CryptoContextResolver resolver;
}

Matcher _blocked(SaltBlockedReason r) => isA<SaltFetchBlockedError>()
    .having((e) => e.reason, 'reason', r);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('getActiveCryptoContext', () {
    test('ATC-M14-05 linked without linkedSecret throws (not a SaltFetchBlockedError)',
        () async {
      final h = _Harness();
      for (final s in [null, '']) {
        await expectLater(
            h.resolver.getActiveCryptoContext(
                _uid, AuthState(isLinked: true, linkedSecret: s)),
            throwsA(isA<StateError>()));
      }
      expect(h.fetches, isEmpty);
    });

    test('ATC-M14-05 cache hit returns cached salt without touching the network',
        () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: 'cached-salt'});
      final h = _Harness(online: false, fetchThrows: true);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, 'cached-salt');
      expect(ctx.secret, 'pw');
      expect(h.onlineChecks, 0);
      expect(h.fetches, isEmpty);
    });

    test('ATC-M14-05 empty cached value counts as a miss (JS `if (cached)`)', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: ''});
      final h = _Harness(fetchResult: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, _remoteSalt);
      expect(h.fetches, [_uid]);
    });

    test('ATC-M14-05 linked + no cache + offline → no-network, no fetch', () async {
      final h = _Harness(online: false, fetchResult: _remoteSalt);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.noNetwork)));
      expect(h.fetches, isEmpty);
    });

    test('ATC-M14-05 linked + online + fetch throws → fetch-failed', () async {
      final h = _Harness(fetchThrows: true);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.fetchFailed)));
    });

    test('ATC-M14-05 linked + online + no salt on record → fetch-failed', () async {
      final h = _Harness(fetchResult: null);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.fetchFailed)));
      expect(await h.storage.read(key: _cacheKey), isNull);
      expect(h.queue.items, isEmpty);
    });

    test('ATC-M14-05 linked + remote salt → cached under koi_salt_cache_{uid}', () async {
      final h = _Harness(fetchResult: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, _remoteSalt);
      expect(ctx.secret, 'pw');
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.queue.items, isEmpty);
    });

    test('ATC-M14-06 anonymous ignores connectivity and still tries Firestore', () async {
      final h = _Harness(online: false, remoteSalt: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(ctx.saltB64, _remoteSalt);
      expect(h.creates.single.$1, _uid);
      expect(h.onlineChecks, 0);
    });

    test('ATC-M14-06 anonymous + salt exists in Firestore → use it, cache, no queue',
        () async {
      final h = _Harness(remoteSalt: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(ctx.saltB64, _remoteSalt);
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.queue.items, isEmpty);
      expect(h.fetches, isEmpty); // the read is inside the transaction
    });

    test('ATC-M14-06 anonymous secret is created once in secure storage and reused',
        () async {
      final h = _Harness(remoteSalt: _remoteSalt);
      final first = await h.resolver.getActiveCryptoContext(_uid, _anon);
      final stored = await h.storage.read(key: _anonKey);
      expect(stored, first.secret);
      expect(base64Decode(first.secret), hasLength(32));
      final second = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(second.secret, first.secret);
    });

    test('ATC-M14-06 anonymous + create-once fails → generate, cache, queue create-once',
        () async {
      final h = _Harness(createThrows: true);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(base64Decode(ctx.saltB64), hasLength(16));
      expect(h.creates.single.$2, ctx.saltB64);
      expect(await h.storage.read(key: _cacheKey), ctx.saltB64);

      final item = h.queue.items.single;
      expect(item.op, SyncOp.saltCreateOnce);
      expect(item.collection, 'users');
      expect(item.docId, _uid);
      expect(item.priority, 4);
      expect(item.data, {
        'public_crypto_metadata': {'salt': ctx.saltB64},
      });
    });

    test('ATC-M14-06 anonymous + no salt in Firestore → ours stored, cached, no queue',
        () async {
      final h = _Harness();
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(h.remoteSalt, ctx.saltB64); // create-once stored ours
      expect(await h.storage.read(key: _cacheKey), ctx.saltB64);
      expect(h.queue.items, isEmpty);
    });

    test('ATC-M14-06 anonymous second call uses the cache (no new salt, no new write)',
        () async {
      final h = _Harness(createThrows: true);
      final first = await h.resolver.getActiveCryptoContext(_uid, _anon);
      final second = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(second.saltB64, first.saltB64);
      expect(h.queue.items, hasLength(1));
      expect(h.creates, hasLength(1));
    });

    test('ATC-M14-05 linked users never create a salt', () async {
      final h = _Harness(fetchResult: null);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.fetchFailed)));
      expect(h.creates, isEmpty);
    });
  });

  group('ATC-M14-07 ensureSaltStored (after sign-in, online)', () {
    test('no cache + Firestore has a salt → cached, no queue', () async {
      final h = _Harness(remoteSalt: _remoteSalt);
      await h.resolver.ensureSaltStored(_uid, _anon);
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.queue.items, isEmpty);
      expect(h.keyClears, 0);
    });

    test('no cache + Firestore has none → ours stored and cached', () async {
      final h = _Harness();
      await h.resolver.ensureSaltStored(_uid, _anon);
      final cached = await h.storage.read(key: _cacheKey);
      expect(cached, isNotNull);
      expect(h.remoteSalt, cached);
      expect(h.queue.items, isEmpty);
    });

    test('cache matches Firestore → nothing changes', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: _remoteSalt});
      final h = _Harness(remoteSalt: _remoteSalt);
      await h.resolver.ensureSaltStored(_uid, _anon);
      expect(h.creates.single.$2, _remoteSalt);
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.keyClears, 0);
    });

    test('remote differs from local → Firestore wins, keys cleared, '
        'Firestore not overwritten', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: 'local-salt'});
      final h = _Harness(remoteSalt: _remoteSalt);
      await h.resolver.ensureSaltStored(_uid, _anon);
      expect(h.creates.single.$2, 'local-salt'); // offered ours
      expect(h.remoteSalt, _remoteSalt); // never overwritten
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.keyClears, 1);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(ctx.saltB64, _remoteSalt);
    });

    test('Firestore fails with a cached salt → cache kept, no throw, '
        'no extra queue item', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: 'local-salt'});
      final h = _Harness(createThrows: true);
      await h.resolver.ensureSaltStored(_uid, _anon);
      expect(await h.storage.read(key: _cacheKey), 'local-salt');
      expect(h.queue.items, isEmpty);
      expect(h.keyClears, 0);
    });

    test('Firestore fails without a cache → generated, cached, queued',
        () async {
      final h = _Harness(createThrows: true);
      await h.resolver.ensureSaltStored(_uid, _anon);
      final cached = await h.storage.read(key: _cacheKey);
      expect(h.queue.items.single.op, SyncOp.saltCreateOnce);
      expect(saltFromUserData(h.queue.items.single.data), cached);
    });

    test('linked: does nothing', () async {
      final h = _Harness();
      await h.resolver.ensureSaltStored(_uid, _linked);
      expect(h.creates, isEmpty);
      expect(await h.storage.read(key: _cacheKey), isNull);
    });
  });

  group('ATC-M14-08 SaltCache.adopt', () {
    test('first salt: cached, keys not cleared', () async {
      var clears = 0;
      final c = SaltCache(onReplaced: () => clears++);
      expect(await c.adopt(_uid, 'a'), isFalse);
      expect(await c.read(_uid), 'a');
      expect(clears, 0);
    });

    test('default onReplaced clears the real session key cache', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: 'old'});
      CachingPbkdf2.clear();
      // Put one derived key into CachingPbkdf2's static cache.
      await CachingPbkdf2(
        Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1, bits: 256),
      ).deriveKey(secretKey: SecretKey([1, 2, 3]), nonce: [4, 5, 6]);
      expect(CachingPbkdf2.cachedCount, 1);

      expect(await SaltCache().adopt(_uid, 'new'), isTrue);
      expect(CachingPbkdf2.cachedCount, 0);
      expect(await const FlutterSecureStorage().read(key: _cacheKey), 'new');
    });
  });

  group('ATC-M14-08 resolveSaltWithRetry', () {
    test('succeeds on a later attempt; backoff 1s then 2s', () async {
      final h = _Harness(online: false, fetchResult: _remoteSalt);
      final sleeps = <Duration>[];
      final reports = <(int, int, SaltBlockedReason)>[];
      final ctx = await h.resolver.resolveSaltWithRetry(_uid, _linked,
          onAttempt: (a, m, r) => reports.add((a, m, r)),
          sleep: (d) async {
            sleeps.add(d);
            if (sleeps.length == 2) h.online = true; // back online
          });
      expect(ctx.saltB64, _remoteSalt);
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      expect(reports, [
        (1, 5, SaltBlockedReason.noNetwork),
        (2, 5, SaltBlockedReason.noNetwork),
      ]);
    });

    test('5 failed attempts: waits 1s/2s/4s/8s, throws the last reason',
        () async {
      final h = _Harness(online: false, fetchThrows: true);
      final sleeps = <Duration>[];
      final reasons = <SaltBlockedReason>[];
      final attempts = <int>[];
      await expectLater(
        h.resolver.resolveSaltWithRetry(_uid, _linked,
            onAttempt: (a, m, r) {
              attempts.add(a);
              reasons.add(r);
            },
            sleep: (d) async {
              sleeps.add(d);
              if (sleeps.length == 3) h.online = true; // online, fetch fails
            }),
        throwsA(_blocked(SaltBlockedReason.fetchFailed)),
      );
      expect(attempts, [1, 2, 3, 4, 5]);
      expect(sleeps, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      expect(reasons, [
        SaltBlockedReason.noNetwork,
        SaltBlockedReason.noNetwork,
        SaltBlockedReason.noNetwork,
        SaltBlockedReason.fetchFailed,
        SaltBlockedReason.fetchFailed,
      ]);
    });

    test('non-blocked errors propagate immediately without retrying',
        () async {
      final h = _Harness();
      final sleeps = <Duration>[];
      var reports = 0;
      await expectLater(
        h.resolver.resolveSaltWithRetry(
            _uid, const AuthState(isLinked: true),
            onAttempt: (_, _, _) => reports++,
            sleep: (d) async => sleeps.add(d)),
        throwsA(isA<StateError>()),
      );
      expect(sleeps, isEmpty);
      expect(reports, 0);
    });

    test('maxAttempts 0 throws no-network (web lastReason default)', () async {
      final h = _Harness();
      await expectLater(
          h.resolver.resolveSaltWithRetry(_uid, _linked, maxAttempts: 0),
          throwsA(_blocked(SaltBlockedReason.noNetwork)));
      expect(h.fetches, isEmpty);
    });
  });

  group('ATC-M14-08 helpers', () {
    test('saltFromUserData mirrors data()?.public_crypto_metadata?.salt', () {
      expect(saltFromUserData(null), isNull);
      expect(saltFromUserData({}), isNull);
      expect(saltFromUserData({'public_crypto_metadata': 'x'}), isNull);
      expect(saltFromUserData({'public_crypto_metadata': {}}), isNull);
      expect(
          saltFromUserData({
            'public_crypto_metadata': {'salt': ''},
          }),
          isNull);
      expect(
          saltFromUserData({
            'public_crypto_metadata': {'salt': 'abc'},
          }),
          'abc');
    });

    test('isOnlineFrom mirrors navigator.onLine', () {
      expect(isOnlineFrom([ConnectivityResult.none]), isFalse);
      expect(isOnlineFrom([]), isFalse);
      expect(isOnlineFrom([ConnectivityResult.wifi]), isTrue);
      expect(isOnlineFrom([ConnectivityResult.mobile]), isTrue);
      expect(
          isOnlineFrom([ConnectivityResult.none, ConnectivityResult.vpn]),
          isTrue);
    });

    test('SaltBlockedReason wire names match the web strings', () {
      expect(SaltBlockedReason.noNetwork.wireName, 'no-network');
      expect(SaltBlockedReason.fetchFailed.wireName, 'fetch-failed');
      expect(const SaltFetchBlockedError(SaltBlockedReason.fetchFailed)
          .toString(), 'Salt fetch blocked: fetch-failed');
    });
  });
}
