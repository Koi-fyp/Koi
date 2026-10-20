import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:flutter/foundation.dart';

import '../key_value_store.dart';
import 'auth_service.dart';

/// ⚠ DEBUG-ONLY stand-in for FirebaseAuthService. ⚠
///
/// It talks to no server and creates no Firebase user. main.dart uses it
/// only in debug builds that were started WITHOUT the private Firebase
/// config (firebase.local.json), so teammates without it can still run the
/// app flow (splash → landing → onboarding → shell).
///
/// "Session persistence" is a fake uid in a plain local Hive box, standing in
/// for Firebase's own persisted session so a restart keeps you signed in.
/// The uid is prefixed `debug-` so it can never be mistaken for a real one.
class DebugLocalAuthService extends AuthService {
  /// [openStore] is awaited by [restoreSession]; until then `loading` is true,
  /// like web before the first onAuthStateChanged callback.
  DebugLocalAuthService(this._openStore) {
    assert(kDebugMode, 'DebugLocalAuthService must never ship.');
  }

  static const String boxName = 'koi_debug_auth';
  static const String uidKey = 'uid';

  final Future<KeyValueStore> Function() _openStore;
  KeyValueStore? _store;

  KoiUser? _user;
  bool _loading = true;
  bool _restored = false;
  Object? _error;

  @override
  KoiUser? get user => _user;
  @override
  bool get loading => _loading;
  @override
  Object? get error => _error;
  @override
  bool get sessionRestored => _restored;

  /// The stand-in has no Firebase user, so there is never an ID token.
  @override
  Future<String> getIdToken() =>
      Future.error(StateError('No Firebase user (debug stand-in, Q1)'));

  /// Web: the first onAuthStateChanged callback delivers the cached user (or
  /// null) and sets loading=false.
  Future<void> restoreSession() async {
    try {
      final store = _store ??= await _openStore();
      final uid = store.get(uidKey);
      _user = uid == null ? null : _userFor(store, uid);
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _restored = true;
      notifyListeners();
    }
  }

  @override
  Future<void> signInAnonymously() => _run(() async {
    final uid = 'debug-${_randomHex(16)}';
    await (_store ??= await _openStore()).put(uidKey, uid);
    _user = KoiUser(uid: uid, isAnonymous: true);
  });

  @override
  Future<void> signOut() => _run(() async {
    await (_store ??= await _openStore()).delete(uidKey);
    _user = null;
  });

  /// AuthContext.tsx pattern: loading=true, error=null, try, catch → error,
  /// finally loading=false. Never rethrows.
  Future<void> _run(Future<void> Function() body) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── MOB-1 accounts (debug stand-in only): fake email accounts in the
  // same local box, so the account flows can be tried without Firebase.
  // Passwords are stored only as a SHA-256 hash.

  static String _accountKey(String email) =>
      'account_${email.trim().toLowerCase()}';
  static String _emailKey(String uid) => 'email_$uid';

  KoiUser _userFor(KeyValueStore store, String uid) {
    final email = store.get(_emailKey(uid));
    return email == null
        ? KoiUser(uid: uid, isAnonymous: true)
        : KoiUser(
            uid: uid,
            isAnonymous: false,
            providerIds: const ['password'],
            email: email,
          );
  }

  static Future<String> _hash(String password) async =>
      base64Encode((await Sha256().hash(utf8.encode(password))).bytes);

  Future<void> _register(String uid, String email, String password) async {
    final store = _store ??= await _openStore();
    if (password.length < 6) {
      throw const AccountAuthException(AccountAuthError.weakPassword);
    }
    if (!email.contains('@')) {
      throw const AccountAuthException(AccountAuthError.invalidEmail);
    }
    if (store.get(_accountKey(email)) != null) {
      throw const AccountAuthException(AccountAuthError.emailInUse);
    }
    await store.put(
      _accountKey(email),
      jsonEncode({'uid': uid, 'hash': await _hash(password)}),
    );
    await store.put(_emailKey(uid), email.trim());
    await store.put(uidKey, uid);
    _user = _userFor(store, uid);
    notifyListeners();
  }

  @override
  Future<void> linkWithEmail(String email, String password) async {
    final u = _user;
    if (u == null || !u.isAnonymous) {
      throw const AccountAuthException(AccountAuthError.unknown);
    }
    await _register(u.uid, email, password);
  }

  @override
  Future<void> createAccountWithEmail(String email, String password) =>
      _register('debug-${_randomHex(16)}', email, password);

  Future<String> _check(String email, String password) async {
    final store = _store ??= await _openStore();
    final raw = store.get(_accountKey(email));
    if (raw == null) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
    final j = jsonDecode(raw) as Map;
    if (j['hash'] != await _hash(password)) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
    return j['uid'] as String;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final uid = await _check(email, password);
    final store = _store ??= await _openStore();
    await store.put(uidKey, uid);
    _user = _userFor(store, uid);
    notifyListeners();
  }

  @override
  Future<void> reauthenticate(String password) async {
    final email = _user?.email;
    if (email == null) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
    if (await _check(email, password) != _user?.uid) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
  }

  /// No email leaves the device in the stand-in: accepted and dropped.
  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (!email.contains('@')) {
      throw const AccountAuthException(AccountAuthError.invalidEmail);
    }
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return List.generate(
      bytes,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
