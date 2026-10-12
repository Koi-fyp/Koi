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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';

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

class CryptoContextResolver {
  CryptoContextResolver({
    required this.fetchSalt,
    required this.isOnline,
    required this.syncQueue,
    FlutterSecureStorage? storage,
    KoiCryptoService? crypto,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _crypto = crypto ??
            KoiCryptoService(
                secureStorage: storage ?? const FlutterSecureStorage());

  final SaltFetcher fetchSalt;
  final OnlineCheck isOnline;
  final SyncQueue syncQueue;
  final FlutterSecureStorage _storage;
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

    final cacheKey = '$saltCachePrefix$uid';

    // 1. Local cache first.
    final cached = await _storage.read(key: cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return CryptoContext(secret: secret, saltB64: cached);
    }

    // 2. No cache: branch point for the locked block decision.
    if (authState.isLinked && !await isOnline()) {
      throw const SaltFetchBlockedError(SaltBlockedReason.noNetwork);
    }

    String? existingSalt;
    try {
      existingSalt = await fetchSalt(uid);
    } catch (_) {
      if (authState.isLinked) {
        throw const SaltFetchBlockedError(SaltBlockedReason.fetchFailed);
      }
      // Anonymous: same fallback as web.
      existingSalt = null;
    }

    if (existingSalt != null && existingSalt.isNotEmpty) {
      await _storage.write(key: cacheKey, value: existingSalt);
      return CryptoContext(secret: secret, saltB64: existingSalt);
    }

    if (authState.isLinked) {
      // Firestore answered but has no salt for a linked user: inconsistent
      // account state. Block rather than guess.
      throw const SaltFetchBlockedError(SaltBlockedReason.fetchFailed);
    }

    // 3. Brand-new ANONYMOUS user only: generate, cache locally, queue the
    // Firestore write (users/{uid}.public_crypto_metadata.salt, priority 4).
    final saltB64 = _crypto.generateSalt();
    await _storage.write(key: cacheKey, value: saltB64);
    syncQueue.enqueue(SyncItem(
      collection: 'users',
      docId: uid,
      data: {
        'public_crypto_metadata': {'salt': saltB64},
      },
      priority: 4,
    ));
    return CryptoContext(secret: secret, saltB64: saltB64);
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
