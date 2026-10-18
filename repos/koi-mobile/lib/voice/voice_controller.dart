import 'dart:async';

import 'package:flutter/foundation.dart';

import '../avatar/avatar_state.dart' show MouthCue;
import '../chat/backend_warmup.dart' show BackendWarmup, HealthCheck;
import '../core/key_value_store.dart';
import 'speech_source.dart';
import 'voice_text.dart';

/// The call screen's voice on/off, per uid in `koi_local_prefs`
/// (`koi_voice_enabled_{uid}`, 'true' / 'false'). On by default.
class VoicePrefs {
  VoicePrefs(this._store);

  static const String key = 'koi_voice_enabled';
  static String keyFor(String uid) => '${key}_$uid';

  final KeyValueStore _store;

  bool isEnabled(String uid) => _store.get(keyFor(uid)) != 'false';

  Future<void> setEnabled(String uid, bool on) =>
      _store.put(keyFor(uid), on ? 'true' : 'false');
}

/// `GET /health` on the speech service when the call screen opens, retried
/// like BackendWarmup (2/4/8/16/30 s, 240 s limit). Until it answers 200
/// the device voice is used (decided 2026-10-18).
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
  bool _warming = false;

  bool get isReady => _ready;

  /// Never awaited by the UI; does nothing while one runs or once ready.
  Future<void> warmUp() async {
    final check = health;
    if (check == null || _ready || _warming) return;
    _warming = true;
    try {
      final start = _now();
      for (var attempt = 0; ; attempt++) {
        final left = limit - _now().difference(start);
        if (left <= Duration.zero) return;
        var ok = false;
        try {
          ok = await check(left);
        } catch (_) {}
        if (ok) {
          _ready = true;
          return;
        }
        final remaining = limit - _now().difference(start);
        if (remaining <= Duration.zero) return;
        final wait =
            retryDelays[attempt < retryDelays.length
                ? attempt
                : retryDelays.length - 1];
        await _delay(wait < remaining ? wait : remaining);
      }
    } finally {
      _warming = false;
    }
  }
}

/// Speaks completed replies on the call screen: the speech service first,
/// the device voice for the rest of a reply after any server failure
/// (error, timeout, rate limit, stale answer), or for the whole reply when
/// the service isn't warm or the plan is device-only. [speaking] is the
/// voice that is audible now (null = idle); [onMouth] gets each part's
/// cues.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.server,
    required this.device,
    required this.serverReady,
    required this.onMouth,
  });

  /// null when KOI_SPEECH_BASE is not set.
  final ServerSpeechSource? server;
  final SpeechSource device;
  final bool Function() serverReady;
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
    var useServer = server != null && !plan.deviceOnly && serverReady();
    for (var i = 0; i < parts.length; i++) {
      if (reply != _reply) return;
      final next = i + 1 < parts.length ? parts[i + 1] : null;
      final listener = _PartListener(this, reply, () {
        // Fetch the next part while this one plays.
        if (useServer && next != null) server!.prefetch(next);
      });
      if (useServer) {
        try {
          await server!.speak(parts[i], listener);
          continue;
        } catch (e) {
          debugPrint('KOI: speech fell back to device voice: $e');
          useServer = false;
          unawaited(server!.stop());
          if (reply != _reply) return;
        }
      }
      await device.speak(parts[i], listener);
    }
    if (reply == _reply) _setSpeaking(null);
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
