import 'dart:math';

import 'package:flutter/foundation.dart';

import '../key_value_store.dart';
import 'auth_service.dart';

/// ⚠ TEMPORARY, DEBUG-ONLY stand-in for the real AuthService. ⚠
///
/// It talks to no server and creates no Firebase user. It only lets the app
/// flow (splash → landing → onboarding → shell) be exercised before Q1 is
/// answered and google-services.json exists. See the TODO in
/// auth_service.dart. Delete this file when the real implementation lands.
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
      _user = uid == null ? null : KoiUser(uid: uid, isAnonymous: true);
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

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return List.generate(
      bytes,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
