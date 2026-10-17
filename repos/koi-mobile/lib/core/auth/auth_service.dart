import 'package:flutter/foundation.dart';

// Implementations:
// - FirebaseAuthService (firebase_auth_service.dart): Firebase anonymous
//   sign-in (Q1 decided 2026-10-17: native signInAnonymously, not web's
//   POST /api/auth/anonymous + signInWithCustomToken). Used whenever the
//   Firebase config is present (core/firebase/firebase_config.dart).
// - DebugLocalAuthService: debug builds WITHOUT the private Firebase config,
//   so teammates can still run the app.

/// Firebase rejected anonymous sign-in because it is turned off for the
/// project (Firebase console → Authentication → Sign-in method → Anonymous).
class AnonymousSignInDisabledError implements Exception {
  const AnonymousSignInDisabledError(this.code);

  /// The Firebase error code, e.g. `operation-not-allowed`.
  final String code;

  @override
  String toString() => 'Anonymous sign-in is disabled ($code)';
}

/// The signed-in user, reduced to the fields AuthContext.tsx reads from the
/// Firebase `User` (repos/koi-backend/nextjs_app/src/contexts/AuthContext.tsx).
@immutable
class KoiUser {
  const KoiUser({
    required this.uid,
    required this.isAnonymous,
    this.providerIds = const [],
  });

  final String uid;

  /// Firebase `user.isAnonymous`.
  final bool isAnonymous;

  /// Firebase `user.providerData.map((p) => p.providerId)`.
  final List<String> providerIds;
}

/// Mobile equivalent of AuthContext.tsx's `AuthContextType` (minus
/// linkWithEmail, which is out of scope for this prompt).
///
/// Implementations own `user`, `loading` and `error` and must follow the web
/// contract: `loading` starts true and turns false once the persisted session
/// has been restored (web: first `onAuthStateChanged` callback);
/// signInAnonymously/signOut set loading=true and error=null, store any
/// failure in `error` instead of throwing, and finish with loading=false.
/// Session persistence is the auth backend's job (AuthContext.tsx header:
/// no custom token storage).
abstract class AuthService extends ChangeNotifier {
  KoiUser? get user;
  bool get loading;
  Object? get error;

  /// AuthContext.tsx: `user?.isAnonymous ?? false`. Derived, never stored.
  bool get isAnonymous => user?.isAnonymous ?? false;

  /// AuthContext.tsx: `user != null && !user.isAnonymous &&
  /// user.providerData.some((p) => p.providerId === 'password')`.
  bool get isLinked {
    final u = user;
    return u != null && !u.isAnonymous && u.providerIds.contains('password');
  }

  /// True once the persisted session has been restored at app start (web:
  /// the first onAuthStateChanged callback has fired). Only before that does
  /// the root show the splash; later loading states (e.g. sign-in on the
  /// landing page) keep the current screen, like web (decided 2026-10-13).
  bool get sessionRestored;

  /// Firebase `user.getIdToken()` for the chat endpoint's Bearer header.
  /// Throws when there is no Firebase user (web: "No authenticated Firebase
  /// user -- cannot call /api/v1/chat"), which takes the fallback path.
  Future<String> getIdToken();

  Future<void> signInAnonymously();
  Future<void> signOut();
}
