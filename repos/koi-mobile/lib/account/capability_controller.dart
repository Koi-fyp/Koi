import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/auth/auth_service.dart';
import '../platform/platform_client.dart';
import 'capabilities.dart';

enum CapabilityStatus {
  /// Nobody signed in.
  signedOut,

  /// Firebase `isAnonymous` (or the debug stand-in): never fetched, never
  /// privileged.
  anonymous,

  /// A registered user whose capabilities are being confirmed. Default-deny:
  /// [CapabilityController.effective] is [KoiCapabilities.none] and the root
  /// shows the loader instead of any tab.
  loading,
  ready,

  /// Could not be confirmed (offline, not configured, server error): the
  /// registered user keeps the KOI companion only, with a Retry.
  unavailable,
}

/// Resolves privileges ONLY from the backend capabilities endpoint and
/// re-checks them on: sign-in / account switch (uid change), token refresh,
/// app resume, any 403, and on demand. Nothing is cached across launches,
/// so a cold start can never flash a protected tab.
///
/// When a confirmed patient relationship disappears (revoked / ended), the
/// patient's caches are dropped via [onPatientAccessLost] and [accessEnded]
/// stays true until the user acknowledges the "access ended" screen.
class CapabilityController extends ChangeNotifier {
  CapabilityController({
    required this.auth,
    required this.source,
    this.onPatientAccessLost,
    this.timeout = const Duration(seconds: 20),
  }) {
    auth.addListener(_onAuth);
    _tokenSub = auth.tokenChanges.listen((_) => _onToken());
    _onAuth();
  }

  final AuthService auth;
  final CapabilitiesSource source;
  final Future<void> Function(String uid)? onPatientAccessLost;
  final Duration timeout;
  StreamSubscription<void>? _tokenSub;

  String? _uid;
  bool _registered = false;
  CapabilityStatus _status = CapabilityStatus.signedOut;
  KoiCapabilities _caps = KoiCapabilities.none;
  PlatformErrorCode? _error;
  bool _accessEnded = false;
  int _generation = 0;
  bool _disposed = false;

  CapabilityStatus get status => _status;
  PlatformErrorCode? get error => _error;
  bool get accessEnded => _accessEnded;
  bool get isMock => source.isMock;

  /// The ONLY capabilities the UI may act on: the confirmed ones of the
  /// CURRENT uid, or none.
  KoiCapabilities get effective {
    final current = auth.user;
    if (_status != CapabilityStatus.ready ||
        current == null ||
        current.isAnonymous ||
        current.uid != _uid) {
      return KoiCapabilities.none;
    }
    return _caps;
  }

  void _onAuth() {
    final u = auth.user;
    final registered = u != null && !u.isAnonymous;
    if (u?.uid == _uid && registered == _registered) return;
    _uid = u?.uid;
    _registered = registered;
    _caps = KoiCapabilities.none;
    _accessEnded = false;
    // Patient history belongs to the previous account only.
    _wasPatient = false;
    _error = null;
    _generation++;
    if (u == null) {
      _status = CapabilityStatus.signedOut;
      _notify();
    } else if (!registered) {
      _status = CapabilityStatus.anonymous;
      _notify();
    } else {
      unawaited(refresh());
    }
  }

  void _onToken() {
    if (_status == CapabilityStatus.ready ||
        _status == CapabilityStatus.unavailable) {
      unawaited(refresh(silent: true));
    }
  }

  /// App came back to the foreground.
  void appResumed() => _onToken();

  /// A platform call answered 403: drop to default-deny and re-check.
  void onForbidden() {
    if (_registered) unawaited(refresh());
  }

  /// Re-checks. [silent] keeps the current (confirmed) capabilities on
  /// screen while checking; otherwise the state goes back to loading
  /// (default-deny) first.
  Future<void> refresh({bool silent = false}) async {
    final uid = _uid;
    if (uid == null || !_registered) return;
    final gen = ++_generation;
    final hadQuestionnaires =
        _status == CapabilityStatus.ready && _caps.isPatient;
    final previouslyPatient = hadQuestionnaires || _wasPatient;
    if (!silent || _status != CapabilityStatus.ready) {
      _status = CapabilityStatus.loading;
      _notify();
    }
    try {
      final caps = await source.fetch(uid).timeout(timeout);
      if (gen != _generation || _disposed) return;
      _caps = caps;
      _status = CapabilityStatus.ready;
      _error = null;
      if (previouslyPatient && !caps.isPatient) {
        _accessEnded = true;
        await onPatientAccessLost?.call(uid);
      }
      _wasPatient = caps.isPatient;
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _caps = KoiCapabilities.none;
      _status = CapabilityStatus.unavailable;
      _error = e is PlatformException
          ? e.code
          : e is TimeoutException
          ? PlatformErrorCode.timeout
          : PlatformErrorCode.badResponse;
      debugPrint('[KOI] capabilities unavailable (${_error!.name})');
      if (previouslyPatient &&
          e is PlatformException &&
          (e.code == PlatformErrorCode.forbidden ||
              e.code == PlatformErrorCode.unauthorized)) {
        // The server refused: treat like a lost relationship.
        _accessEnded = true;
        _wasPatient = false;
        await onPatientAccessLost?.call(uid);
      }
    }
    _notify();
  }

  /// Patient privileges were confirmed for this uid at some point in this
  /// session (survives a non-silent refresh going through loading).
  bool _wasPatient = false;

  void acknowledgeAccessEnded() {
    if (!_accessEnded) return;
    _accessEnded = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_onAuth);
    _tokenSub?.cancel();
    super.dispose();
  }
}
