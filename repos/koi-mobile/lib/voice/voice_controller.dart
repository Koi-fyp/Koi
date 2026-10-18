import 'dart:async';

import 'package:flutter/foundation.dart';

import '../avatar/avatar_state.dart' show MouthCue;
import '../chat/backend_warmup.dart' show BackendWarmup, HealthCheck;
import 'speech_api.dart' show SpeechApiException;
import 'speech_source.dart';
import 'voice_text.dart';

/// `GET /health` on the speech service, retried like BackendWarmup
/// (2/4/8/16/30 s, 240 s limit): started when the call screen opens and
/// awaited before the first voice turn (Prompt 29, [settled]). The service
/// is [isUnavailable] once a warm-up ended without a 200; replies then use
/// the device voice until a later warm-up gets one.
class SpeechWarmup {
  SpeechWarmup({
    required this.health,
    this.limit = const Duration(seconds: 240),
    this.retryDelays = BackendWarmup.defaultRetryDelays,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// null when KOI_SPEECH_BASE is not set.
  final HealthCheck? health;
  final Duration limit;
  final List<Duration> retryDelays;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  bool _ready = false;
  bool _gaveUp = false;
  Completer<void>? _run;

  bool get isReady => _ready;

  /// The last warm-up ended without a 200 (and none has had one since).
  bool get isUnavailable => !_ready && _gaveUp;

  /// Never awaited by the UI; joins the warm-up that is running, does
  /// nothing once ready. Completes when this warm-up ends.
  Future<void> warmUp() {
    final check = health;
    if (check == null || _ready) return Future.value();
    final running = _run;
    if (running != null) return running.future;
    final run = _run = Completer<void>();
    unawaited(() async {
      try {
        _ready = await _attempts(check);
        if (!_ready) _gaveUp = true;
      } finally {
        _run = null;
        run.complete();
      }
    }());
    return run.future;
  }

  /// Before a voice turn: the warm-up to wait for (one is started if none
  /// has run yet). null when not configured, ready, or after a warm-up
  /// already ended without a 200 (the turn is then sent and replies use the
  /// device voice).
  Future<void>? settled() {
    if (health == null || _ready) return null;
    final running = _run;
    if (running != null) return running.future;
    if (_gaveUp) return null;
    return warmUp();
  }

  Future<bool> _attempts(HealthCheck check) async {
    final start = _now();
    for (var attempt = 0; ; attempt++) {
      final left = limit - _now().difference(start);
      if (left <= Duration.zero) return false;
      var ok = false;
      try {
        ok = await check(left);
      } catch (_) {}
      if (ok) return true;
      final remaining = limit - _now().difference(start);
      if (remaining <= Duration.zero) return false;
      final wait =
          retryDelays[attempt < retryDelays.length
              ? attempt
              : retryDelays.length - 1];
      await _delay(wait < remaining ? wait : remaining);
    }
  }
}

/// Speaks completed replies on the call screen (Prompt 29 rule, decided
/// per reply): the speech service, skipping a chunk that fails or takes
/// longer than 12 s (ServerSpeechSource.timeout); `unauthenticated` /
/// `rate-limited` end the reply, as later chunks would fail too (web
/// speechReplyController.ts TERMINAL). The device voice only when the
/// service is not configured or [serverUnavailable]. [speaking] is the
/// voice that is audible now (null = idle); [onMouth] gets each part's
/// cues.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.server,
    required this.device,
    required this.serverUnavailable,
    required this.onMouth,
  });

  /// Codes that end the reply instead of skipping one chunk.
  static const Set<String> terminalCodes = {
    'unauthenticated',
    'rate-limited',
    '401',
    '429',
  };

  /// null when KOI_SPEECH_BASE is not set.
  final ServerSpeechSource? server;
  final SpeechSource device;
  final bool Function() serverUnavailable;
  final void Function(List<MouthCue> cues) onMouth;

  VoiceKind? _speaking;
  int _reply = 0;
  bool _disposed = false;

  VoiceKind? get speaking => _speaking;

  /// Stops whatever is playing, then speaks [plan] part by part.
  Future<void> speak(VoicePlan plan) async {
    await stop();
    if (_disposed || plan is! SpeakPlan || plan.parts.isEmpty) return;
    final reply = _reply;
    final parts = plan.parts;
    final server = this.server;
    final useServer = server != null && !serverUnavailable();
    for (var i = 0; i < parts.length; i++) {
      if (reply != _reply) return;
      final next = i + 1 < parts.length ? parts[i + 1] : null;
      final listener = _PartListener(this, reply, () {
        // Fetch the next part while this one plays.
        if (useServer && next != null) server.prefetch(next);
      });
      if (!useServer) {
        await device.speak(parts[i], listener);
        continue;
      }
      try {
        await server.speak(parts[i], listener);
      } on SpeechApiException catch (e) {
        debugPrint('KOI: speech chunk skipped: ${e.code}');
        if (terminalCodes.contains(e.code)) break;
      } catch (e) {
        debugPrint('KOI: speech chunk skipped: ${e.runtimeType}');
      }
    }
    if (reply == _reply) {
      onMouth(const []);
      _setSpeaking(null);
    }
  }

  /// Stops audio and mouth at once and drops pending requests.
  Future<void> stop() async {
    _reply++;
    onMouth(const []);
    _setSpeaking(null);
    await Future.wait([if (server != null) server!.stop(), device.stop()])
        .catchError((_) => const <void>[]);
  }

  void _setSpeaking(VoiceKind? kind) {
    if (_speaking == kind || _disposed) return;
    _speaking = kind;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    _disposed = true;
    super.dispose();
  }
}

class _PartListener implements SpeechListener {
  _PartListener(this._c, this._reply, this._started);
  final VoiceController _c;
  final int _reply;
  final VoidCallback _started;

  bool get _current => _reply == _c._reply && !_c._disposed;

  @override
  void onAudioStart(VoiceKind kind) {
    if (!_current) return;
    _c._setSpeaking(kind);
    _started();
  }

  @override
  void onMouth(List<MouthCue> cues) {
    if (_current) _c.onMouth(cues);
  }
}
