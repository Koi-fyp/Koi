import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../avatar/avatar_state.dart' show MouthCue;
import 'speech_api.dart';
import 'voice_text.dart';

/// Which voice is speaking (the call screen's label).
enum VoiceKind { server, device }

/// What a [SpeechSource] reports while it speaks one part.
abstract class SpeechListener {
  /// Audio is now audible.
  void onAudioStart(VoiceKind kind);

  /// Mouth cues starting now (seconds from now); empty = mouth closed.
  void onMouth(List<MouthCue> cues);
}

/// Speaks one part at a time.
abstract class SpeechSource {
  VoiceKind get kind;

  /// Completes when [part] has been spoken or [stop] was called. Throws when
  /// it could not be spoken (the caller then uses the other source).
  Future<void> speak(SpeechPart part, SpeechListener listener);

  /// Stops audio at once and drops anything pending.
  Future<void> stop();
}

/// At most [max] requests in any [window] (server: 10 requests/min per
/// user).
class SpeechRateLimiter {
  SpeechRateLimiter({
    this.max = 10,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int max;
  final Duration window;
  final DateTime Function() _now;
  final List<DateTime> _sent = [];

  /// Takes a slot; false when [max] were already used in the last [window].
  bool tryAcquire() {
    final now = _now();
    _sent.removeWhere((t) => now.difference(t) >= window);
    if (_sent.length >= max) return false;
    _sent.add(now);
    return true;
  }
}

/// A random (version 4) UUID.
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

// ── Server ────────────────────────────────────────────────────────────────

/// Plays one WAV clip.
abstract class ClipPlayer {
  /// Completes when the clip ended or [stop] was called. [onStarted] runs
  /// once, when playback starts. [limit] ends a clip that never reports
  /// completion.
  Future<void> play(
    Uint8List wav, {
    required VoidCallback onStarted,
    required Duration limit,
  });
  Future<void> stop();
}

class AudioplayersClipPlayer implements ClipPlayer {
  // Created on first use, so screens that never speak never touch the
  // platform player.
  AudioPlayer? _player;
  Completer<void>? _done;

  @override
  Future<void> play(
    Uint8List wav, {
    required VoidCallback onStarted,
    required Duration limit,
  }) async {
    await stop();
    final player = _player ??= AudioPlayer();
    final done = _done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    var started = false;
    final subs = [
      player.onPlayerStateChanged.listen((s) {
        if (s == PlayerState.playing && !started && !done.isCompleted) {
          started = true;
          onStarted();
        }
      }),
      player.onPlayerComplete.listen((_) => finish()),
    ];
    final timer = Timer(limit, finish);
    try {
      await player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await done.future;
    } finally {
      timer.cancel();
      for (final s in subs) {
        unawaited(s.cancel());
      }
      if (identical(_done, done)) _done = null;
    }
  }

  @override
  Future<void> stop() async {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

/// The speech service: fetch, then play with the server's mouth cues.
/// [prefetch] starts the next part's request while one plays. Every request
/// takes a [limiter] slot (none left → `rate-limited`).
class ServerSpeechSource implements SpeechSource {
  ServerSpeechSource({
    required this.api,
    required this.idToken,
    required this.player,
    required this.limiter,
    this.timeout = defaultTimeout,
    String Function()? newGenerationId,
  }) : _newId = newGenerationId ?? uuidV4;

  /// Per request, token included (decided in Step 0).
  static const Duration defaultTimeout = Duration(seconds: 12);

  final SpeechApiClient api;
  final Future<String> Function() idToken;
  final ClipPlayer player;
  final SpeechRateLimiter limiter;
  final Duration timeout;
  final String Function() _newId;

  final Map<SpeechPart, Future<SpeechClip>> _pending = Map.identity();
  int _epoch = 0;

  @override
  VoiceKind get kind => VoiceKind.server;

  void prefetch(SpeechPart part) {
    if (_pending.containsKey(part)) return;
    _pending[part] = _fetch(part)..ignore();
  }

  Future<SpeechClip> _fetch(SpeechPart part) async {
    if (!limiter.tryAcquire()) {
      throw const SpeechApiException('rate-limited');
    }
    final watch = Stopwatch()..start();
    final String token;
    try {
      token = await idToken().timeout(timeout);
    } catch (_) {
      throw const SpeechApiException('unauthenticated');
    }
    final left = timeout - watch.elapsed;
    if (left <= Duration.zero) throw const SpeechApiException('timeout');
    return api.synthesize(
      idToken: token,
      text: part.text,
      voiceId: part.voiceId,
      language: part.language,
      generationId: _newId(),
      timeout: left,
    );
  }

  @override
  Future<void> speak(SpeechPart part, SpeechListener listener) async {
    final epoch = _epoch;
    final clip = await (_pending.remove(part) ?? _fetch(part));
    // Stopped while the request was out: the late answer is dropped.
    if (epoch != _epoch) return;
    await player.play(
      clip.audio,
      limit: Duration(milliseconds: (clip.durationS * 1000).ceil() + 3000),
      onStarted: () {
        if (epoch != _epoch) return;
        listener.onAudioStart(kind);
        listener.onMouth(clip.cues);
      },
    );
    if (epoch == _epoch) listener.onMouth(const []);
  }

  @override
  Future<void> stop() async {
    _epoch++;
    _pending.clear();
    await player.stop();
  }
}

// ── Device ────────────────────────────────────────────────────────────────

/// The phone's text-to-speech.
abstract class TtsEngine {
  /// Completes when [text] was spoken, stopped or failed. [onWord] gets the
  /// character range of each word as it is spoken, where the engine
  /// reports it (Android 26+).
  Future<void> speak(
    String text, {
    required String language,
    required VoidCallback onStart,
    required void Function(int start, int end) onWord,
  });
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  FlutterTts? _tts;
  _Utterance? _current;

  FlutterTts _engine() {
    final existing = _tts;
    if (existing != null) return existing;
    final tts = _tts = FlutterTts();
    tts.setStartHandler(() => _current?.onStart());
    tts.setProgressHandler((_, start, end, _) => _current?.onWord(start, end));
    tts.setCompletionHandler(() => _current?.finish());
    tts.setCancelHandler(() => _current?.finish());
    tts.setErrorHandler((_) => _current?.finish());
    return tts;
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required VoidCallback onStart,
    required void Function(int start, int end) onWord,
  }) async {
    final tts = _engine();
    _current?.finish();
    final u = _current = _Utterance(onStart, onWord);
    try {
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage(language == 'ur' ? 'ur-PK' : 'en-US');
      if (u.done.isCompleted) return;
      await tts.speak(text);
    } catch (_) {
      // never shown
    } finally {
      u.finish();
      if (identical(_current, u)) _current = null;
    }
    await u.done.future;
  }

  @override
  Future<void> stop() async {
    _current?.finish();
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

class _Utterance {
  _Utterance(this._onStart, this._onWord);
  final VoidCallback _onStart;
  final void Function(int, int) _onWord;
  final Completer<void> done = Completer<void>();

  void onStart() {
    if (!done.isCompleted) _onStart();
  }

  void onWord(int start, int end) {
    if (!done.isCompleted) _onWord(start, end);
  }

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

/// Approximate cues for one spoken word (device voice): open, half, closed,
/// about 70 ms per character (0.12–0.6 s).
List<MouthCue> wordCues(String word) {
  final d = (word.trim().length * 0.07).clamp(0.12, 0.6).toDouble();
  return [
    MouthCue(start: 0, end: d * 0.4, value: 'D'),
    MouthCue(start: d * 0.4, end: d * 0.75, value: 'B'),
    MouthCue(start: d * 0.75, end: d, value: 'A'),
  ];
}

/// Timed open/close (about 5 per second) for the estimated length of [text]
/// (65 ms per character, 0.4–60 s), for engines that report no words.
List<MouthCue> timedCues(String text) {
  final total = (text.length * 0.065).clamp(0.4, 60.0).toDouble();
  final cues = <MouthCue>[];
  var t = 0.0;
  var open = true;
  while (t < total) {
    final end = min(total, t + (open ? 0.12 : 0.08));
    cues.add(MouthCue(start: t, end: end, value: open ? 'D' : 'A'));
    t = end;
    open = !open;
  }
  return cues;
}

/// flutter_tts fallback with approximate mouth movement: timed open/close
/// from the start, replaced word by word when the engine reports words.
class DeviceSpeechSource implements SpeechSource {
  DeviceSpeechSource(this.engine);

  final TtsEngine engine;
  int _epoch = 0;

  @override
  VoiceKind get kind => VoiceKind.device;

  @override
  Future<void> speak(SpeechPart part, SpeechListener listener) async {
    final epoch = ++_epoch;
    final text = part.text;
    try {
      await engine.speak(
        text,
        language: part.language,
        onStart: () {
          if (epoch != _epoch) return;
          listener.onAudioStart(kind);
          listener.onMouth(timedCues(text));
        },
        onWord: (start, end) {
          if (epoch != _epoch || start < 0 || end > text.length) return;
          if (end <= start) return;
          listener.onMouth(wordCues(text.substring(start, end)));
        },
      );
    } catch (_) {
      // never shown
    }
    if (epoch == _epoch) listener.onMouth(const []);
  }

  @override
  Future<void> stop() async {
    _epoch++;
    await engine.stop();
  }
}
