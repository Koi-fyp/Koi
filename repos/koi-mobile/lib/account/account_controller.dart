import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/conversation_service.dart' show MessageCipher;
import '../chat/message_record.dart';
import '../core/auth/auth_service.dart';
import '../core/crypto_context.dart';
import '../core/key_value_store.dart';
import '../core/koi_cryptography.dart';
import '../core/onboarding_store.dart';
import 'account_migration.dart';
import 'secret_store.dart';

/// Callbacks that drop account-specific state. Every KOI 2.0 cache
/// registers here, so account switch / sign-out / relationship removal
/// cannot leave one account's data on screen for another.
class AccountCleanup {
  final List<Future<void> Function(String uid)> _onLeave = [];
  final List<Future<void> Function(String uid)> _onSignOut = [];
  final List<Future<void> Function(String uid)> _onPatientAccessLost = [];

  /// In-memory state of [uid]: run whenever the signed-in uid changes away
  /// from it (switch, sign-out).
  void onLeave(Future<void> Function(String uid) f) => _onLeave.add(f);

  /// Stored per-uid data that must not outlive the session (drafts).
  void onSignOut(Future<void> Function(String uid) f) => _onSignOut.add(f);

  /// Patient-only data (questionnaires) when the relationship ends.
  void onPatientAccessLost(Future<void> Function(String uid) f) =>
      _onPatientAccessLost.add(f);

  Future<void> leave(String uid) => _runAll(_onLeave, uid);
  Future<void> signOut(String uid) => _runAll(_onSignOut, uid);
  Future<void> patientAccessLost(String uid) =>
      _runAll(_onPatientAccessLost, uid);

  static Future<void> _runAll(
    List<Future<void> Function(String)> fs,
    String uid,
  ) async {
    for (final f in fs) {
      try {
        await f(uid);
      } catch (e) {
        debugPrint('[KOI] account: cleanup step failed (${e.runtimeType})');
      }
    }
  }
}

/// Resolves the crypto context of [uid] with [linkedSecret] (null =
/// anonymous). Injected so tests need no Firestore.
typedef ContextResolver = Future<CryptoContext> Function(
  String uid, {
  String? linkedSecret,
});

enum UnlockState { notNeeded, checking, needed }

/// MOB-1 account flows: create, upgrade (link, same uid), sign in to an
/// existing account (with an explicit, re-authenticated claim of this
/// device's anonymous history), unlock, sign out.
///
/// Errors from these calls are thrown to the form that started them
/// ([AccountAuthException], [SaltFetchBlockedError], ...). Never logs an
/// email, password, secret or uid.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.auth,
    required this.secrets,
    required this.migration,
    required this.resolveContext,
    required this.ensureSalt,
    required this.onboarding,
    required this.messages,
    required this.cipher,
    required this.prefs,
    required this.cleanup,
  }) {
    auth.addListener(_onAuth);
    _onAuth();
  }

  final AuthService auth;
  final AccountSecretStore secrets;
  final CseMigration migration;
  final ContextResolver resolveContext;

  /// Salt for a registered account (create-once; returns Firestore's).
  final Future<String> Function(String uid) ensureSalt;
  final OnboardingStore onboarding;
  final MessageStore messages;
  final MessageCipher cipher;
  final KeyValueStore prefs;
  final AccountCleanup cleanup;

  /// Set right before an anonymous user signs in to an existing account:
  /// the anonymous uid whose history may be claimed.
  static const String pendingClaimSourceKey = 'koi_claim_pending_source';

  String? _uid;
  UnlockState _unlock = UnlockState.notNeeded;
  bool _migrating = false;
  Object? _migrationError;
  MigrationReport? _lastReport;
  bool _disposed = false;

  /// A create / upgrade / sign-in flow is running: it sets the password
  /// itself, so the auth changes it causes must not open the unlock screen
  /// (or start a second migration) in between.
  bool _inFlow = false;

  UnlockState get unlock => _unlock;
  bool get migrating => _migrating;
  Object? get migrationError => _migrationError;
  MigrationReport? get lastReport => _lastReport;

  /// Linked but the local re-encryption is not finished: the app waits.
  bool get migrationPending {
    final uid = auth.user?.uid;
    if (uid == null || !auth.isLinked) return false;
    return _migrating ||
        migration.linkMarker(uid)?.state == MigrationState.pending;
  }

  /// This account was signed in to from an anonymous account on this
  /// device and the user has not chosen yet.
  bool get claimOffered {
    final uid = auth.user?.uid;
    if (uid == null || !auth.isLinked) return false;
    final m = migration.claimMarker(uid);
    return m != null &&
        (m.state == MigrationState.pending ||
            (_migrating && m.state != MigrationState.left));
  }

  void _onAuth() {
    final uid = auth.user?.uid;
    if (uid == _uid) {
      // Same uid, but it may just have been linked.
      if (uid != null &&
          !_inFlow &&
          auth.isLinked &&
          _unlock == UnlockState.notNeeded) {
        unawaited(_checkUnlock(uid));
      }
      return;
    }
    final previous = _uid;
    _uid = uid;
    // Keys derived for another account are forgotten.
    CachingPbkdf2.clear();
    if (previous != null) unawaited(cleanup.leave(previous));
    _unlock = UnlockState.notNeeded;
    _migrationError = null;
    _lastReport = null;
    if (uid != null && auth.isLinked && !_inFlow) {
      unawaited(_checkUnlock(uid));
      unawaited(_resumeLinkMigration(uid));
    }
    _notify();
  }

  Future<void> _checkUnlock(String uid) async {
    _unlock = UnlockState.checking;
    _notify();
    final cached = await secrets.linkedSecret(uid);
    if (_uid != uid) return;
    _unlock = cached == null ? UnlockState.needed : UnlockState.notNeeded;
    _notify();
  }

  /// A link migration interrupted by a crash or kill resumes here, once
  /// the password is available.
  Future<void> _resumeLinkMigration(String uid) async {
    final m = migration.linkMarker(uid);
    if (m == null || m.state == MigrationState.done) return;
    final password = await secrets.linkedSecret(uid);
    if (password == null || _uid != uid) return; // after unlock
    await _runLink(uid, password);
  }

  /// Retries whatever is pending (migration error screen / resume).
  Future<void> retryPending() async {
    final uid = _uid;
    if (uid == null) return;
    await _resumeLinkMigration(uid);
  }

  Future<void> _runLink(String uid, String password) async {
    if (_migrating) return;
    _migrating = true;
    _migrationError = null;
    _notify();
    try {
      final from = await secrets.existingAnonymousSecret(uid);
      final to = await resolveContext(uid, linkedSecret: password);
      if (from == null) {
        // Nothing was ever encrypted anonymously for this uid.
        await prefs.put(
          CseMigration.linkKey(uid),
          const MigrationMarker(state: MigrationState.done).encode(),
        );
      } else {
        _lastReport = await migration.runLink(
          uid: uid,
          fromSecret: from,
          to: to,
        );
        // A copy the server refused (serverStale) still holds the OLD
        // ciphertext, so the secret stays until the rules allow it.
        if (_lastReport!.state == MigrationState.done &&
            _lastReport!.serverStale == 0) {
          // Every server copy is acknowledged: the anonymous secret is no
          // longer needed (web: clearAnonymousSecret after migration).
          await secrets.deleteAnonymousSecret(uid);
        }
      }
    } catch (e) {
      _migrationError = e;
      debugPrint('[KOI] account: link migration paused (${e.runtimeType})');
    } finally {
      _migrating = false;
      _notify();
    }
  }

  // ── Flows ────────────────────────────────────────────────────────────

  /// Signed out → a brand-new registered account.
  Future<void> createAccount(String email, String password) => _flow(() async {
    await auth.createAccountWithEmail(email, password);
    final uid = auth.user!.uid;
    await secrets.setLinkedSecret(uid, password);
    await ensureSalt(uid);
    await prefs.put(
      CseMigration.linkKey(uid),
      const MigrationMarker(state: MigrationState.done).encode(),
    );
  });

  /// Runs [body] with [_inFlow] set; the password is in place afterwards.
  Future<T> _flow<T>(Future<T> Function() body) async {
    _inFlow = true;
    try {
      return await body();
    } finally {
      _inFlow = false;
      _unlock = UnlockState.notNeeded;
      _notify();
    }
  }

  /// Anonymous → registered, SAME uid (Firebase linkWithCredential). The
  /// local history is re-encrypted with the password (two-phase secret).
  /// A collision throws [AccountAuthException] emailInUse: the form then
  /// offers "Sign in instead".
  Future<void> upgradeAnonymous(String email, String password) async {
    await _flow(() => _link(email, password));
    final uid = auth.user?.uid;
    if (uid != null) await _runLink(uid, password);
  }

  Future<void> _link(String email, String password) async {
    final u = auth.user;
    if (u == null || !u.isAnonymous) {
      throw const AccountAuthException(AccountAuthError.unknown);
    }
    final uid = u.uid;
    // Make sure the anonymous secret is the per-uid one before linking.
    await secrets.anonymousSecret(uid);
    // Marker first: a crash right after linking resumes the migration.
    await migration.beginLink(uid);
    try {
      await auth.linkWithEmail(email, password);
    } catch (_) {
      await prefs.delete(CseMigration.linkKey(uid));
      rethrow;
    }
    await secrets.setLinkedSecret(uid, password);
  }

  /// Signs in to an EXISTING account. From an anonymous account, that
  /// history is never attached silently: a claim is only OFFERED (and needs
  /// re-authentication to accept).
  Future<void> signInExisting(String email, String password) => _flow(() async {
    final before = auth.user;
    final source = before != null && before.isAnonymous ? before.uid : null;
    if (source != null) {
      // The source's secret must be per-uid before its account goes away.
      await secrets.anonymousSecret(source);
      await prefs.put(pendingClaimSourceKey, source);
    }
    try {
      await auth.signInWithEmail(email, password);
    } catch (_) {
      if (source != null) await prefs.delete(pendingClaimSourceKey);
      rethrow;
    }
    final target = auth.user!.uid;
    await secrets.setLinkedSecret(target, password);
    try {
      // Caches the account's salt (or creates it once if it has none).
      await ensureSalt(target);
    } catch (e) {
      // Encrypting waits until the salt can be fetched (crypto_context).
      debugPrint('[KOI] account: salt not ready (${e.runtimeType})');
    }
    if (source != null && source != target) {
      final hasHistory = (await messages.byConversation(source)).isNotEmpty;
      final existing = migration.claimMarker(target);
      if (hasHistory && (existing == null || existing.source != source)) {
        await migration.offerClaim(source: source, target: target);
      }
    }
    await prefs.delete(pendingClaimSourceKey);
  });

  /// "Bring this device's KOI history into this account": re-authenticate
  /// the TARGET account, then copy + re-encrypt (resumable, idempotent).
  Future<MigrationReport> acceptClaim(String password) async {
    final target = auth.user?.uid;
    final m = target == null ? null : migration.claimMarker(target);
    final source = m?.source;
    if (target == null || source == null) {
      throw StateError('No claim to accept');
    }
    await auth.reauthenticate(password);
    final from = await secrets.existingAnonymousSecret(source);
    if (from == null) {
      await migration.leaveClaim(target);
      throw StateError('The anonymous history can no longer be opened');
    }
    _migrating = true;
    _notify();
    try {
      final to = await resolveContext(target, linkedSecret: password);
      final report = await migration.runClaim(
        target: target,
        fromSecret: from,
        to: to,
      );
      if (onboarding.isCompleteFor(source)) {
        await onboarding.markComplete(target);
      }
      _lastReport = report;
      return report;
    } finally {
      _migrating = false;
      _notify();
    }
  }

  /// "Leave it": the anonymous history stays on the device, hidden.
  Future<void> leaveClaim() async {
    final target = auth.user?.uid;
    if (target == null) return;
    await migration.leaveClaim(target);
    _notify();
  }

  /// Unlock on a new device / cleared cache. Online: Firebase
  /// re-authentication. Offline: the password must open this account's own
  /// local data; with none, it waits for a connection.
  Future<void> unlockWith(String password) async {
    final uid = auth.user?.uid;
    if (uid == null) return;
    try {
      await auth.reauthenticate(password);
    } on AccountAuthException catch (e) {
      if (e.error != AccountAuthError.network ||
          !await _opensLocalData(uid, password)) {
        rethrow;
      }
    }
    await secrets.setLinkedSecret(uid, password);
    _unlock = UnlockState.notNeeded;
    _notify();
    await _resumeLinkMigration(uid);
  }

  Future<bool> _opensLocalData(String uid, String password) async {
    final rows = await messages.byConversation(uid);
    if (rows.isEmpty) return false;
    try {
      await cipher.decrypt(rows.first.content, password);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Registered sign-out: the cached password, derived keys and every
  /// account-scoped store of this uid go first.
  Future<void> signOut() async {
    final uid = auth.user?.uid;
    if (uid != null) {
      await secrets.clearLinkedSecret(uid);
      await cleanup.signOut(uid);
      await cleanup.leave(uid);
    }
    CachingPbkdf2.clear();
    await auth.signOut();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_onAuth);
    super.dispose();
  }
}
