// Port of getActiveCryptoContext() and resolveSaltWithRetry() from
// repos/koi-backend/nextjs_app/src/lib/crypto.ts.
//
// Client-Side Encryption (CSE) at rest. The salt is public/server-visible by
// design; security rests on `secret` never leaving the device unencrypted.
//
// Differences from the web, all deliberate:
// - Two-argument signature (uid, authState) everywhere. Web callers in
//   conversationService.ts / useChat.ts pass only uid (playbook Q4), which
//   makes authState undefined at runtime; mobile does not copy that bug.
// - Storage: the salt cache uses flutter_secure_storage under the same key
//   pattern as web localStorage (`koi_salt_cache_{uid}`). The anonymous
//   secret comes from flutter_lib's KoiCryptoService (secure storage key
//   `koi_anon_secret`) instead of localStorage.
// - navigator.onLine → connectivity_plus (any interface other than `none`).
// - Dependencies (Firestore read, connectivity, sync queue, sleep) are
//   injected so every branch can be unit-tested.
// - Salt create-once (decided 2026-10-17, mobile is the only salt writer):
//   a new anonymous salt is stored with a Firestore transaction that never
//   overwrites an existing one (web: a blind setDoc merge). If Firestore
//   already has a salt, it wins and replaces the local cache. Offline or
//   rejected, the create-once is queued (SyncOp.saltCreateOnce).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';

import 'koi_cryptography.dart';
import 'sync_queue.dart';

/// crypto.ts SALT_CACHE_PREFIX.
const String saltCachePrefix = 'koi_salt_cache_';

/// crypto.ts `CryptoContext`.
class CryptoContext {
  const CryptoContext({required this.secret, required this.saltB64});

  final String secret;
  final String saltB64;
}

/// crypto.ts `AuthState`.
class AuthState {
  const AuthState({required this.isLinked, this.linkedSecret});

  /// From the auth layer's isLinked: true if the user linked email/password.
  final bool isLinked;

  /// Required when [isLinked] is true: the user's password for this session.
  /// (Web: "Not currently sourced anywhere" — same on mobile for now.)
  final String? linkedSecret;
}

/// crypto.ts `SaltBlockedReason`: 'no-network' | 'fetch-failed'.
enum SaltBlockedReason {
  /// Device has no connectivity at all.
  noNetwork('no-network'),

  /// Device reports online, but the Firestore read did not succeed.
  fetchFailed('fetch-failed');

  const SaltBlockedReason(this.wireName);

  /// The web string value, for UI messages and logs.
  final String wireName;
}

/// crypto.ts `SaltFetchBlockedError`.
class SaltFetchBlockedError implements Exception {
  const SaltFetchBlockedError(this.reason);

  final SaltBlockedReason reason;

  @override
  String toString() => 'Salt fetch blocked: ${reason.wireName}';
}

/// Reads users/{uid}.public_crypto_metadata.salt. Returns null when there is
/// no salt; throws when the read itself fails.
typedef SaltFetcher = Future<String?> Function(String uid);

/// Mirrors `navigator.onLine`.
typedef OnlineCheck = Future<bool> Function();

/// crypto.ts `onAttempt(attemptNumber, maxAttempts, reason)`.
typedef SaltAttemptCallback = void Function(
    int attemptNumber, int maxAttempts, SaltBlockedReason reason);

/// Extracts the salt the way crypto.ts does:
/// `snapshot.data()?.public_crypto_metadata?.salt`. JS treats '' as "no
/// salt" (`if (existingSalt)`), so an empty string returns null here too.
String? saltFromUserData(Map<String, dynamic>? data) {
  final meta = data?['public_crypto_metadata'];
  if (meta is! Map) return null;
  final salt = meta['salt'];
  return salt is String && salt.isNotEmpty ? salt : null;
}

/// Default [SaltFetcher]: `getDoc(doc(firestore, 'users', uid))`.
SaltFetcher firestoreSaltFetcher(FirebaseFirestore firestore) =>
    (uid) async {
      final snapshot = await firestore.collection('users').doc(uid).get();
      return saltFromUserData(snapshot.data());
    };

/// navigator.onLine is true when any network interface is up; mirror that by
/// treating every result other than [ConnectivityResult.none] as online.
bool isOnlineFrom(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

/// Default [OnlineCheck] using connectivity_plus.
OnlineCheck connectivityOnlineCheck([Connectivity? connectivity]) =>
    () async => isOnlineFrom(
        await (connectivity ?? Connectivity()).checkConnectivity());

/// Stores [candidate] as users/{uid}.public_crypto_metadata.salt only if
/// Firestore has none, and returns the salt Firestore holds afterwards.
/// Throws when Firestore can't be reached or rejects the write.
/// (UserDocumentStore.createSaltOnce.)
typedef SaltCreateOnce = Future<String> Function(String uid, String candidate);

/// The local salt cache: flutter_secure_storage key `koi_salt_cache_{uid}`
/// (crypto.ts SALT_CACHE_PREFIX).
class SaltCache {
  SaltCache({FlutterSecureStorage? storage, void Function()? onReplaced})
      : _storage = storage ?? const FlutterSecureStorage(),
        _onReplaced = onReplaced ?? CachingPbkdf2.clear;

  final FlutterSecureStorage _storage;

  /// Called when a cached salt is replaced: forgets the session keys
  /// derived with the old one, so the next encrypt re-derives.
  final void Function() _onReplaced;

  /// The cached salt, or null (JS `if (cached)`: '' counts as none).
  Future<String?> read(String uid) async {
    final v = await _storage.read(key: '$saltCachePrefix$uid');
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> write(String uid, String saltB64) =>
      _storage.write(key: '$saltCachePrefix$uid', value: saltB64);

  /// Makes Firestore's salt the cached one. Returns true when it replaced a
  /// different cached salt (and cleared the session keys). Old messages
  /// still decrypt: every v1 payload carries its own salt.
  Future<bool> adopt(String uid, String remoteSalt) async {
    final current = await read(uid);
    if (current == remoteSalt) return false;
    await write(uid, remoteSalt);
    if (current == null) return false;
    debugPrint('[KOI] crypto: local salt replaced by the stored one');
    _onReplaced();
    return true;
  }
}

class CryptoContextResolver {
  CryptoContextResolver({
    required this.fetchSalt,
    required this.createSaltOnce,
    required this.isOnline,
    required this.syncQueue,
    FlutterSecureStorage? storage,
    KoiCryptoService? crypto,
    SaltCache? saltCache,
  })  : saltCache = saltCache ?? SaltCache(storage: storage),
        _crypto = crypto ??
            KoiCryptoService(
                secureStorage: storage ?? const FlutterSecureStorage());

  final SaltFetcher fetchSalt;
  final SaltCreateOnce createSaltOnce;
  final OnlineCheck isOnline;
  final SyncQueue syncQueue;
  final SaltCache saltCache;
  final KoiCryptoService _crypto;

  /// crypto.ts getActiveCryptoContext(uid, authState). Makes exactly ONE
  /// attempt; use [resolveSaltWithRetry] from UI code.
  ///
  /// Offline-first: the local salt cache is checked before any network call.
  /// A linked user with no cached salt who is offline (or whose fetch fails)
  /// is BLOCKED with [SaltFetchBlockedError] instead of silently generating a
  /// new salt, which would break cross-device decryption later. Anonymous
  /// users still generate a salt locally on first use.
  Future<CryptoContext> getActiveCryptoContext(
      String uid, AuthState authState) async {
    final linkedSecret = authState.linkedSecret;
    if (authState.isLinked && (linkedSecret == null || linkedSecret.isEmpty)) {
      // Caller-side bug, not a network condition: fail loudly.
      throw StateError('getActiveCryptoContext: authState.isLinked is true '
          'but no linkedSecret was supplied.');
    }
    final secret = authState.isLinked
        ? linkedSecret!
        : await _crypto.getOrCreateAnonymousSecret();

    // 1. Local cache first.
    final cached = await saltCache.read(uid);
    if (cached != null) {
      return CryptoContext(secret: secret, saltB64: cached);
    }

    if (!authState.isLinked) {
      // 2a. ANONYMOUS, no cache: salt create-once.
      return CryptoContext(
          secret: secret, saltB64: await _createOrQueueSalt(uid));
    }

    // 2b. LINKED, no cache: branch point for the locked block decision.
    if (!await isOnline()) {
      throw const SaltFetchBlockedError(SaltBlockedReason.noNetwork);
    }

    String? existingSalt;
    try {
      existingSalt = await fetchSalt(uid);
    } catch (_) {
      throw const SaltFetchBlockedError(SaltBlockedReason.fetchFailed);
    }

    if (existingSalt == null || existingSalt.isEmpty) {
      // Firestore answered but has no salt for a linked user: inconsistent
      // account state. Block rather than guess.
      throw const SaltFetchBlockedError(SaltBlockedReason.fetchFailed);
    }
    await saltCache.write(uid, existingSalt);
    return CryptoContext(secret: secret, saltB64: existingSalt);
  }

  /// Anonymous user without a cached salt: offer a new salt to Firestore
  /// (create-once) and cache whichever salt Firestore holds. If Firestore
  /// can't be reached or rejects the write, cache the new salt and queue the
  /// create-once for later. Returns the cached salt.
  Future<String> _createOrQueueSalt(String uid) async {
    final candidate = _crypto.generateSalt();
    String saltB64;
    try {
      saltB64 = await createSaltOnce(uid, candidate);
    } catch (e) {
      debugPrint('[KOI] crypto: salt create-once queued '
          '(${syncFailureReason(e)})');
      saltB64 = candidate;
      syncQueue.enqueue(SyncItem.saltCreateOnce(uid, candidate));
    }
    await saltCache.write(uid, saltB64);
    return saltB64;
  }

  /// Run right after sign-in when online, so the salt is in Firestore before
  /// the first message. Anonymous only (a linked user's salt is never
  /// created on this device). Never throws.
  ///
  /// - No cached salt: same as the first encrypt ([_createOrQueueSalt]).
  /// - Cached salt: offered to Firestore; if Firestore already has a
  ///   different one, that one replaces the cache ([SaltCache.adopt]).
  Future<void> ensureSaltStored(String uid, AuthState authState) async {
    if (authState.isLinked) return;
    try {
      final cached = await saltCache.read(uid);
      if (cached == null) {
        await _createOrQueueSalt(uid);
        return;
      }
      await saltCache.adopt(uid, await createSaltOnce(uid, cached));
    } catch (e) {
      // A queued create-once (from when the salt was generated) retries it.
      debugPrint('[KOI] crypto: salt check skipped (${syncFailureReason(e)})');
    }
  }

  /// crypto.ts resolveSaltWithRetry(). Up to [maxAttempts] (locked: 5)
  /// attempts with 1s, 2s, 4s, 8s backoff between them. Errors other than
  /// [SaltFetchBlockedError] propagate immediately. [onAttempt] reports each
  /// failed attempt's reason so the UI can tell "no network" from "online,
  /// retrying". [sleep] is injectable for tests.
  Future<CryptoContext> resolveSaltWithRetry(
    String uid,
    AuthState authState, {
    SaltAttemptCallback? onAttempt,
    int maxAttempts = 5,
    Future<void> Function(Duration) sleep = _defaultSleep,
  }) async {
    var lastReason = SaltBlockedReason.noNetwork;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await getActiveCryptoContext(uid, authState);
      } on SaltFetchBlockedError catch (e) {
        lastReason = e.reason;
        onAttempt?.call(attempt, maxAttempts, lastReason);

        if (attempt < maxAttempts) {
          // 1s, 2s, 4s, 8s
          await sleep(Duration(milliseconds: 1000 * (1 << (attempt - 1))));
        }
      }
    }

    // All attempts exhausted.
    throw SaltFetchBlockedError(lastReason);
  }
}

Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);
