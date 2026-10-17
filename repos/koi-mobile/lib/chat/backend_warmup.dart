import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the chat service has answered yet (contract C7: after idle a
/// container takes 60-190 s to start).
enum BackendStatus { unknown, waking, ready, unreachable }

/// Warms the chat (and, when set, crisis) service with `GET /health` and
/// tracks [status] for the "waking up" line.
///
/// - [warmUp] after sign-in and when the app comes back after more than
///   [resumeAfter] in the background; never awaited by the UI.
/// - `waking` once health or a chat request has been pending for
///   [wakingAfter] while the service has not answered yet.
/// - `ready` on the first answer (health 2xx, any chat HTTP status, any SSE
///   event); `unreachable` when the deadline passes or the network fails.
class BackendWarmup extends ChangeNotifier {
  BackendWarmup({
    required this.chatHealth,
    this.crisisHealth,
    this.wakingAfter = const Duration(seconds: 3),
    this.resumeAfter = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// null when the chat service is not configured (nothing is called).
  final Future<bool> Function()? chatHealth;
  final Future<bool> Function()? crisisHealth;
  final Duration wakingAfter;
  final Duration resumeAfter;
  final DateTime Function() _now;

  BackendStatus _status = BackendStatus.unknown;
  int _pending = 0;
  Timer? _wakingTimer;
  DateTime? _backgroundedAt;
  bool _disposed = false;

  BackendStatus get status => _status;

  void _set(BackendStatus s) {
    if (_status == s || _disposed) return;
    _status = s;
    notifyListeners();
  }

  void _begin() {
    _pending++;
    _wakingTimer ??= Timer(wakingAfter, () {
      _wakingTimer = null;
      if (_pending > 0 && _status != BackendStatus.ready) {
        _set(BackendStatus.waking);
      }
    });
  }

  /// [reached]: true = the service answered, false = it did not, null = no
  /// information (status unchanged, except that `waking` ends).
  void _end({required bool? reached}) {
    if (_pending > 0) _pending--;
    if (_pending == 0) {
      _wakingTimer?.cancel();
      _wakingTimer = null;
    }
    if (reached == true) {
      _set(BackendStatus.ready);
    } else if (_pending == 0) {
      if (reached == false) {
        _set(BackendStatus.unreachable);
      } else if (_status == BackendStatus.waking) {
        _set(BackendStatus.unknown);
      }
    }
  }

  /// Fire-and-forget `GET /health` (no token) on both services.
  void warmUp() {
    final crisis = crisisHealth;
    if (crisis != null) unawaited(crisis());
    final chat = chatHealth;
    if (chat == null) return;
    _begin();
    unawaited(
      chat().then(
        (ok) => _end(reached: ok),
        onError: (Object _) => _end(reached: false),
      ),
    );
  }

  /// A chat request was sent.
  void chatStarted() => _begin();

  /// The chat service answered (an HTTP status or an SSE event).
  void chatAnswered() {
    _wakingTimer?.cancel();
    _wakingTimer = null;
    _set(BackendStatus.ready);
  }

  /// The chat request ended: [reached] is true for a reply or an HTTP
  /// status, false for timeout / network, null when unknown.
  void chatFinished({required bool? reached}) => _end(reached: reached);

  void appBackgrounded() => _backgroundedAt = _now();

  void appResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || _now().difference(since) <= resumeAfter) return;
    // The container has probably gone idle again.
    if (_pending == 0) _set(BackendStatus.unknown);
    warmUp();
  }

  @override
  void dispose() {
    _disposed = true;
    _wakingTimer?.cancel();
    super.dispose();
  }
}
