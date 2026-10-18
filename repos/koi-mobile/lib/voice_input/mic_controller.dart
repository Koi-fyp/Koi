import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../chat/chat_api.dart' show AudioUpload;
import '../chat/conversation_service.dart' show AudioSendResult;
import '../core/key_value_store.dart';
import 'mic_recorder.dart';

/// Per-uid mic state in `koi_local_prefs` (Prompt 26): the opt-in
/// explanation is shown once per uid (accepted with Continue), and Android
/// denials are counted so the second one can point to Android Settings.
/// Prompt 29 changed the explanation, so it is asked again under a new key
/// (the Prompt 26 key `koi_mic_consent_{uid}` is no longer read here).
class MicPrefs {
  MicPrefs(this._store);

  static String consentKey(String uid) => 'koi_mic_consent_v2_$uid';
  static String deniedKey(String uid) => 'koi_mic_denied_$uid';

  final KeyValueStore _store;

  bool hasConsented(String uid) => _store.get(consentKey(uid)) == 'true';
  Future<void> setConsented(String uid) => _store.put(consentKey(uid), 'true');

  int denials(String uid) =>
      int.tryParse(_store.get(deniedKey(uid)) ?? '') ?? 0;
  Future<void> setDenials(String uid, int count) => count == 0
      ? _store.delete(deniedKey(uid))
      : _store.put(deniedKey(uid), '$count');
}

/// One line per voice message for failure reports to the backend: clip
/// length, format, file size, result code. Never audio or transcript text.
@immutable
class MicDiagnostics {
  const MicDiagnostics({
    required this.time,
    required this.clip,
    required this.bytes,
    required this.status,
    required this.attempt,
  });

  final DateTime time;
  final Duration clip;
  final int? bytes;

  /// `ok`, an HTTP status, `timeout`, `network`, `warmup`, … (the
  /// AudioSendResult code), or `record_error` / `no_file`.
  final String status;

  /// 1 for the first send, 2+ for Retry.
  final int attempt;

  String get line {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final s = (clip.inMilliseconds / 1000).toStringAsFixed(1);
    return '[KOI] mic: $t clip=${s}s format=${MicRecorder.format} '
        'bytes=${bytes ?? '-'} attempt=$attempt status=$status';
  }
}

/// The latest [MicDiagnostics] (debug menu "Copy last chat diagnostics").
class MicDiagnosticsLog {
  MicDiagnostics? last;

  void add(MicDiagnostics d) {
    last = d;
    if (kDebugMode) debugPrint(d.line);
  }
}

enum MicPhase { idle, starting, recording, sending, failed }

/// What the line above the input says (approved texts, Prompt 26).
enum MicNotice { none, denied, deniedSettings, unclear, sendFailed }

/// The call screen's mic (Prompt 26): tap to record, tap again to send,
/// auto-send at [maxLength], Cancel discards. One clip at a time; it is
/// kept only for Retry after a failed send, and deleted on success,
/// cancel, a new recording, or when the screen closes.
///
/// Opt-in: [askConsent] (the explanation, once per uid), then the Android
/// permission. If either is refused the mic stays off; typing is never
/// affected.
class MicController extends ChangeNotifier {
  MicController({
    required this.uid,
    required this.recorder,
    required this.prefs,
    required this.send,
    required this.askConsent,
    required this.isBlocked,
    this.onRecordingStarted,
    MicDiagnosticsLog? diagnostics,
    Future<String> Function()? tempDir,
    Future<void> Function(String path)? delete,
    DateTime Function()? now,
    this.maxLength = const Duration(seconds: 29),
    this.warnAt = const Duration(seconds: 25),
  }) : diagnostics = diagnostics ?? MicDiagnosticsLog(),
       _tempDir = tempDir ?? micTempDir,
       _delete = delete ?? deleteClip,
       _now = now ?? DateTime.now;

  final String uid;
  final MicRecorder recorder;
  final MicPrefs prefs;

  /// ChatController.sendVoice.
  final Future<AudioSendResult> Function(
    AudioUpload audio, {
    bool saveTranscript,
  })
  send;

  /// Shows the explanation; true = Continue.
  final Future<bool> Function() askConsent;

  /// The crisis or breathing screen is open, or a reply is pending.
  final bool Function() isBlocked;

  /// Stops voice playback and mouth movement.
  final VoidCallback? onRecordingStarted;
  final MicDiagnosticsLog diagnostics;
  final Future<String> Function() _tempDir;
  final Future<void> Function(String path) _delete;
  final DateTime Function() _now;

  /// The server decodes only the first 30 s; 29 s leaves a margin (Ahmad,
  /// Prompt 29; web MicrophoneCapture.ts stops at 29.5 s).
  final Duration maxLength;

  /// The timer turns to the warning colour from here.
  final Duration warnAt;

  MicPhase _phase = MicPhase.idle;
  MicNotice _notice = MicNotice.none;
  String? _path;
  DateTime? _startedAt;
  Duration _clip = Duration.zero;
  bool _transcriptSaved = false;
  int _attempt = 0;
  Timer? _tick;
  Timer? _limit;
  bool _disposed = false;

  MicPhase get phase => _phase;
  MicNotice get notice => _notice;
  bool get recording => _phase == MicPhase.recording;
  bool get sending => _phase == MicPhase.sending;
  bool get canRetry => _phase == MicPhase.failed;

  /// Time recorded so far (while recording).
  Duration get elapsed {
    final started = _startedAt;
    if (started == null || !recording) return Duration.zero;
    final e = _now().difference(started);
    return e > maxLength ? maxLength : e;
  }

  bool get warning => elapsed >= warnAt;

  void _set(MicPhase phase, [MicNotice? notice]) {
    _phase = phase;
    if (notice != null) _notice = notice;
    if (!_disposed) notifyListeners();
  }

  /// The mic button.
  Future<void> tap() async {
    switch (_phase) {
      case MicPhase.recording:
        return stopAndSend();
      case MicPhase.starting:
      case MicPhase.sending:
        return;
      case MicPhase.idle:
      case MicPhase.failed:
        return _start();
    }
  }

  Future<void> _start() async {
    if (isBlocked()) return;
    _set(MicPhase.starting, MicNotice.none);
    // A new recording replaces the clip kept for Retry.
    await _discardClip();
    if (!prefs.hasConsented(uid)) {
      final ok = await askConsent();
      if (_disposed) return;
      if (!ok) return _set(MicPhase.idle);
      await prefs.setConsented(uid);
    }
    bool granted;
    try {
      granted = await recorder.hasPermission();
    } catch (_) {
      granted = false;
    }
    if (_disposed) return;
    if (!granted) {
      final denials = prefs.denials(uid) + 1;
      await prefs.setDenials(uid, denials);
      // Android stops showing its dialog after the second denial.
      return _set(
        MicPhase.idle,
        denials >= 2 ? MicNotice.deniedSettings : MicNotice.denied,
      );
    }
    await prefs.setDenials(uid, 0);
    // The crisis or breathing screen may have opened meanwhile.
    if (_disposed || isBlocked()) return _set(MicPhase.idle);
    onRecordingStarted?.call();
    final path =
        '${await _tempDir()}${Platform.pathSeparator}'
        'koi_voice_${_now().microsecondsSinceEpoch}.wav';
    try {
      await recorder.start(path);
    } catch (_) {
      await _delete(path);
      _log(Duration.zero, null, 'record_error');
      return _set(MicPhase.idle, MicNotice.denied);
    }
    if (_disposed) {
      await recorder.cancel();
      await _delete(path);
      return;
    }
    _path = path;
    _startedAt = _now();
    _transcriptSaved = false;
    _attempt = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_disposed) notifyListeners();
    });
    _limit = Timer(maxLength, () => unawaited(stopAndSend()));
    _set(MicPhase.recording);
  }

  void _stopTimers() {
    _tick?.cancel();
    _limit?.cancel();
    _tick = _limit = null;
  }

  /// Tap again, or [maxLength] reached.
  Future<void> stopAndSend() async {
    if (!recording) return;
    _clip = elapsed;
    _stopTimers();
    _set(MicPhase.sending);
    String? path;
    try {
      path = await recorder.stop() ?? _path;
    } catch (_) {
      path = null;
    }
    if (path == null) {
      await _discardClip();
      _log(_clip, null, 'no_file');
      return _set(MicPhase.idle, MicNotice.sendFailed);
    }
    _path = path;
    return _send();
  }

  /// Resends the same clip. A transcript an earlier attempt already saved
  /// is not saved again.
  Future<void> retry() async {
    if (!canRetry || _path == null || isBlocked()) return;
    _set(MicPhase.sending, MicNotice.none);
    return _send();
  }

  Future<void> _send() async {
    final path = _path!;
    _attempt++;
    final bytes = _size(path);
    final result = await send(
      AudioUpload(path),
      saveTranscript: !_transcriptSaved,
    );
    _transcriptSaved = _transcriptSaved || result.transcriptSaved;
    _log(_clip, bytes, result.failureCode ?? 'ok');
    if (_disposed) {
      await _delete(path);
      return;
    }
    if (result.ok) {
      await _discardClip();
      return _set(MicPhase.idle, MicNotice.none);
    }
    final code = result.failureCode;
    _set(
      MicPhase.failed,
      code == '422' || code == 'no_transcript'
          ? MicNotice.unclear
          : MicNotice.sendFailed,
    );
  }

  /// Cancel: the recording is discarded and nothing is sent.
  Future<void> cancel() async {
    if (!recording) return;
    _stopTimers();
    _set(MicPhase.idle, MicNotice.none);
    try {
      await recorder.cancel();
    } catch (_) {}
    await _discardClip();
  }

  /// The crisis or breathing screen opened, an exercise started, the mode
  /// changed, the user signed out or the app went to the background: a
  /// recording in progress is discarded.
  Future<void> interrupt() => cancel();

  Future<void> _discardClip() async {
    final path = _path;
    _path = null;
    if (path != null) await _delete(path);
  }

  static int? _size(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  void _log(Duration clip, int? bytes, String status) => diagnostics.add(
    MicDiagnostics(
      time: _now(),
      clip: clip,
      bytes: bytes,
      status: status,
      attempt: _attempt,
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    final wasRecording = recording;
    final path = _path;
    _path = null;
    unawaited(() async {
      if (wasRecording) {
        try {
          await recorder.cancel();
        } catch (_) {}
      }
      // A send still running deletes its clip when it ends.
      if (path != null && _phase != MicPhase.sending) await _delete(path);
      try {
        await recorder.dispose();
      } catch (_) {}
    }());
    super.dispose();
  }
}
