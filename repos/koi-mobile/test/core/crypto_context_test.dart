import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
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
class _Harness {
  _Harness({this.online = true, this.fetchResult, this.fetchThrows = false}) {
    resolver = CryptoContextResolver(
      storage: storage,
      syncQueue: queue,
      isOnline: () async {
        onlineChecks++;
        return online;
      },
      fetchSalt: (uid) async {
        fetches.add(uid);
        if (fetchThrows) throw Exception('firestore unavailable');
        return fetchResult;
      },
    );
  }

  bool online;
  String? fetchResult;
  bool fetchThrows;
  int onlineChecks = 0;
  final fetches = <String>[];
  final queue = _RecordingQueue();
  final storage = const FlutterSecureStorage();
  late final CryptoContextResolver resolver;
}

Matcher _blocked(SaltBlockedReason r) => isA<SaltFetchBlockedError>()
    .having((e) => e.reason, 'reason', r);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('getActiveCryptoContext', () {
    test('linked without linkedSecret throws (not a SaltFetchBlockedError)',
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

    test('cache hit returns cached salt without touching the network',
        () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: 'cached-salt'});
      final h = _Harness(online: false, fetchThrows: true);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, 'cached-salt');
      expect(ctx.secret, 'pw');
      expect(h.onlineChecks, 0);
      expect(h.fetches, isEmpty);
    });

    test('empty cached value counts as a miss (JS `if (cached)`)', () async {
      FlutterSecureStorage.setMockInitialValues({_cacheKey: ''});
      final h = _Harness(fetchResult: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, _remoteSalt);
      expect(h.fetches, [_uid]);
    });

    test('linked + no cache + offline → no-network, no fetch', () async {
      final h = _Harness(online: false, fetchResult: _remoteSalt);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.noNetwork)));
      expect(h.fetches, isEmpty);
    });

    test('linked + online + fetch throws → fetch-failed', () async {
      final h = _Harness(fetchThrows: true);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.fetchFailed)));
    });

    test('linked + online + no salt on record → fetch-failed', () async {
      final h = _Harness(fetchResult: null);
      await expectLater(h.resolver.getActiveCryptoContext(_uid, _linked),
          throwsA(_blocked(SaltBlockedReason.fetchFailed)));
      expect(await h.storage.read(key: _cacheKey), isNull);
      expect(h.queue.items, isEmpty);
    });

    test('linked + remote salt → cached under koi_salt_cache_{uid}', () async {
      final h = _Harness(fetchResult: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _linked);
      expect(ctx.saltB64, _remoteSalt);
      expect(ctx.secret, 'pw');
      expect(await h.storage.read(key: _cacheKey), _remoteSalt);
      expect(h.queue.items, isEmpty);
    });

    test('anonymous ignores connectivity and still tries Firestore', () async {
      final h = _Harness(online: false, fetchResult: _remoteSalt);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(ctx.saltB64, _remoteSalt);
      expect(h.fetches, [_uid]);
      expect(h.onlineChecks, 0);
    });

    test('anonymous secret is created once in secure storage and reused',
        () async {
      final h = _Harness(fetchResult: _remoteSalt);
      final first = await h.resolver.getActiveCryptoContext(_uid, _anon);
      final stored = await h.storage.read(key: _anonKey);
      expect(stored, first.secret);
      expect(base64Decode(first.secret), hasLength(32));
      final second = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(second.secret, first.secret);
    });

    test('anonymous + fetch fails → generate salt, cache, queue write',
        () async {
      final h = _Harness(fetchThrows: true);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(base64Decode(ctx.saltB64), hasLength(16));
      expect(await h.storage.read(key: _cacheKey), ctx.saltB64);

      final item = h.queue.items.single;
      expect(item.collection, 'users');
      expect(item.docId, _uid);
      expect(item.priority, 4);
      expect(item.data, {
        'public_crypto_metadata': {'salt': ctx.saltB64},
      });
    });

    test('anonymous + no salt on record → generate, cache, queue', () async {
      final h = _Harness(fetchResult: null);
      final ctx = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(await h.storage.read(key: _cacheKey), ctx.saltB64);
      expect(h.queue.items, hasLength(1));
    });

    test('anonymous second call uses the cache (no new salt, no new write)',
        () async {
      final h = _Harness(fetchResult: null);
      final first = await h.resolver.getActiveCryptoContext(_uid, _anon);
      final second = await h.resolver.getActiveCryptoContext(_uid, _anon);
      expect(second.saltB64, first.saltB64);
      expect(h.queue.items, hasLength(1));
      expect(h.fetches, hasLength(1));
    });
  });

  group('resolveSaltWithRetry', () {
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

  group('helpers', () {
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
