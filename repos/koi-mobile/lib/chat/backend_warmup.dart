import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the chat service has answered yet (contract C7: after idle a
/// container takes 60-190 s to start; Ahmad measured ~100 s on /health and
/// ~122 s on the first chat, 2026-10-18).
enum BackendStatus { unknown, waking, ready, unreachable }

/// One `GET /health` with no token, limited to [timeout]. true only on 200.
typedef HealthCheck = Future<bool> Function(Duration timeout);

/// Warms the chat and crisis services with `GET /health` and tracks
/// [status] for the "waking up" line (decisions from Ahmad, 2026-10-18).
///
/// - [warmUp] after sign-in and when the app comes back after more than
///   [resumeAfter] in the background; never awaited by the UI. Each service
///   is retried with [retryDelays] backoff until it answers 200 or [limit]
///   has passed since the warm-up started.
/// - The crisis service is only warmed (health only, never
///   /api/v1/crisis); its result never changes [status] or holds text
///   chat. Audio turns wait for both services ([holdForAudio], Prompt 26).
/// - [holdFirstSend]: the first chat send waits until chat /health
///   returned 200 or the limit passed. Later sends are not held.
/// - `waking` once health or a chat request has been pending for
///   [wakingAfter] while the service has not answered yet, and at once while
///   the first send is held.
/// - `ready` on the first answer (health 200, any chat HTTP status, any SSE
///   event); `unreachable` when the limit passes or a chat request fails on
///   the network.
class BackendWarmup extends ChangeNotifier {
  BackendWarmup({
    required this.chatHealth,
    this.crisisHealth,
    this.wakingAfter = const Duration(seconds: 3),
    this.resumeAfter = const Duration(minutes: 5),
    this.limit = const Duration(seconds: 240),
    this.retryDelays = defaultRetryDelays,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// null when the chat service is not configured (nothing is called).
  final HealthCheck? chatHealth;

  /// null when KOI_CRISIS_BASE is not set.
  final HealthCheck? crisisHealth;
  final Duration wakingAfter;
  final Duration resumeAfter;

  /// Overall limit for one warm-up of one service (240 s).
  final Duration limit;

  /// Wait after each failed try; the last value repeats.
  final List<Duration> retryDelays;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  static const List<Duration> defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  BackendStatus _status = BackendStatus.unknown;
  int _pending = 0;
  Timer? _wakingTimer;
  DateTime? _backgroundedAt;
  bool _disposed = false;
  bool _chatWarming = false;
  bool _crisisWarming = false;
  bool _firstSendHeld = false;

  /// Completes when the current chat warm-up ends (200 or limit).
  Completer<void>? _chatWarm;

  /// The last warm-up of each service ended with HTTP 200.
  bool _chatOk = false;
  bool _crisisOk = false;

  /// Completes when the current crisis warm-up ends (200 or limit).
  Completer<void>? _crisisWarmDone;
  bool _holdingAudio = false;

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

  /// Tries [check] until it returns true or [limit] has passed. Each try is
  /// limited to the time left.
  Future<bool> _retry(HealthCheck check) async {
    final start = _now();
    for (var attempt = 0; !_disposed; attempt++) {
      final left = limit - _now().difference(start);
      if (left <= Duration.zero) return false;
      bool ok;
      try {
        ok = await check(left);
      } catch (_) {
        ok = false;
      }
      if (ok) return true;
      final remaining = limit - _now().difference(start);
      if (remaining <= Duration.zero) return false;
      final wait =
          retryDelays[attempt < retryDelays.length
              ? attempt
              : retryDelays.length - 1];
      await _delay(wait < remaining ? wait : remaining);
    }
    return false;
  }

  /// Fire-and-forget health warm-up of both services. A service that is
  /// still warming is not started twice.
  void warmUp() {
    _warmCrisis();
    _warmChat();
  }

  void _warmCrisis() {
    final crisis = crisisHealth;
    if (crisis == null || _crisisWarming) return;
    _crisisWarming = true;
    _crisisOk = false;
    final warm = _crisisWarmDone = Completer<void>();
    // Failures stay here: text chat never waits for or sees the crisis
    // result (only audio turns wait, see holdForAudio).
    unawaited(
      _retry(crisis).catchError((Object _) => false).then((ok) {
        _crisisWarming = false;
        _crisisOk = ok;
        warm.complete();
      }),
    );
  }

  void _warmChat() {
    final chat = chatHealth;
    if (chat == null || _chatWarming) return;
    _chatWarming = true;
    _chatOk = false;
    final warm = _chatWarm = Completer<void>();
    _begin();
    unawaited(
      _retry(chat).then((ok) {
        _chatWarming = false;
        _chatOk = ok;
        _end(reached: ok);
        warm.complete();
      }),
    );
  }

  /// True while an audio turn waits in [holdForAudio] (the waking line is
  /// shown, even when chat itself is already `ready`).
  bool get holdingAudio => _holdingAudio;

  /// Mic tapped (Prompt 26): warms whichever service has not answered 200
  /// yet, so the warm-up overlaps the recording.
  void prepareAudio() {
    if (!_crisisOk) _warmCrisis();
    if (!_chatOk) _warmChat();
  }

  /// Before an audio upload (Ahmad's audio instructions: /health on both
  /// first): waits until chat AND crisis /health returned 200. A service
  /// that is not configured is not waited for. false when one of them did
  /// not answer 200 within [limit]; the upload is then not sent. Text turns
  /// never call this.
  Future<bool> holdForAudio() async {
    prepareAudio();
    final waits = [
      if (chatHealth != null && !_chatOk) _chatWarm!.future,
      if (crisisHealth != null && !_crisisOk) _crisisWarmDone!.future,
    ];
    if (waits.isNotEmpty) {
      _holdingAudio = true;
      if (!_disposed) notifyListeners();
      try {
        await Future.wait(waits);
      } finally {
        _holdingAudio = false;
        if (!_disposed) notifyListeners();
      }
    }
    return (chatHealth == null || _chatOk) &&
        (crisisHealth == null || _crisisOk);
  }

  /// Called before the request of every send; only the first one waits, for
  /// the chat warm-up that is running (200 or [limit]).
  Future<void> holdFirstSend() async {
    if (_firstSendHeld) return;
    _firstSendHeld = true;
    final warm = _chatWarm;
    if (warm == null || warm.isCompleted) return;
    if (_status != BackendStatus.ready) _set(BackendStatus.waking);
    await warm.future;
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
