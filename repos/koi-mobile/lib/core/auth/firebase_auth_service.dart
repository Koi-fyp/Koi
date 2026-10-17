import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// The parts of firebase_auth the app uses. [FirebaseAuthBackend] is the
/// real one; tests use a hand-written fake.
abstract interface class AuthBackend {
  /// Firebase `authStateChanges()`: the restored user (or null) first, then
  /// every sign-in / sign-out.
  Stream<KoiUser?> get userChanges;

  /// Throws [AnonymousSignInDisabledError] when anonymous sign-in is off.
  Future<KoiUser> signInAnonymously();

  Future<void> signOut();

  /// The current user's ID token. Throws when nobody is signed in.
  Future<String> getIdToken();
}

/// Firebase error codes meaning "anonymous sign-in is turned off".
const Set<String> anonymousDisabledCodes = {
  'operation-not-allowed',
  'admin-restricted-operation',
};

class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend([fb.FirebaseAuth? auth])
    : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  static KoiUser? _toKoi(fb.User? u) => u == null
      ? null
      : KoiUser(
          uid: u.uid,
          isAnonymous: u.isAnonymous,
          providerIds: [for (final p in u.providerData) p.providerId],
        );

  @override
  Stream<KoiUser?> get userChanges => _auth.authStateChanges().map(_toKoi);

  @override
  Future<KoiUser> signInAnonymously() async {
    try {
      final user = _toKoi((await _auth.signInAnonymously()).user);
      if (user == null) throw StateError('signInAnonymously returned no user');
      return user;
    } on fb.FirebaseAuthException catch (e) {
      if (anonymousDisabledCodes.contains(e.code)) {
        throw AnonymousSignInDisabledError(e.code);
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user');
    }
    final token = await user.getIdToken();
    if (token == null) throw StateError('No ID token');
    return token;
  }
}

/// [AuthService] backed by Firebase anonymous sign-in. Firebase persists the
/// session itself (AuthContext.tsx: no custom token storage).
///
/// Never logs the ID token or the uid; failures log only an error code.
class FirebaseAuthService extends AuthService {
  FirebaseAuthService(this._backend) {
    _sub = _backend.userChanges.listen(
      _onUser,
      onError: (Object e) {
        _error = e;
        _markRestored();
      },
    );
  }

  final AuthBackend _backend;
  late final StreamSubscription<KoiUser?> _sub;

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

  void _onUser(KoiUser? u) {
    _user = u;
    _markRestored();
  }

  void _markRestored() {
    if (!_restored) {
      _restored = true;
      _loading = false;
    }
    notifyListeners();
  }

  @override
  Future<String> getIdToken() => _backend.getIdToken();

  @override
  Future<void> signInAnonymously() =>
      _run(() async => _user = await _backend.signInAnonymously());

  @override
  Future<void> signOut() => _run(() async {
    await _backend.signOut();
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
      debugPrint('[KOI] auth: ${_reason(e)}');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  static String _reason(Object e) => switch (e) {
    AnonymousSignInDisabledError(:final code) =>
      'anonymous sign-in is disabled in the Firebase console ($code)',
    fb.FirebaseAuthException(:final code) => 'call failed ($code)',
    _ => 'call failed (${e.runtimeType})',
  };

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
