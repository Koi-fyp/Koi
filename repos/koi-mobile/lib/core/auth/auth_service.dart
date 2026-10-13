import 'package:flutter/foundation.dart';

// TODO(Q1, firebase): the real AuthService is NOT implemented yet. It depends
// on (a) playbook Q1 — mirror the web's POST /api/auth/anonymous +
// signInWithCustomToken (needs the deployed web base URL), or use
// flutter_lib's native signInAnonymously() — and (b) google-services.json so
// Firebase can be initialised. Until both are settled, debug builds use the
// TEMPORARY DebugLocalAuthService (debug_local_auth_service.dart).

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

  Future<void> signInAnonymously();
  Future<void> signOut();
}
