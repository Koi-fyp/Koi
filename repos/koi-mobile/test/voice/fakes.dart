import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:koi_mobile/voice/speech_api.dart';
import 'package:koi_mobile/voice/speech_source.dart';

/// Plays instantly unless [hold] is set; records what played.
class FakeClipPlayer implements ClipPlayer {
  final List<Uint8List> played = [];
  int stops = 0;
  Completer<void>? _playing;

  /// When true, a clip plays until [finish] or [stop].
  bool hold = false;

  bool get isPlaying => _playing != null && !_playing!.isCompleted;

  @override
  Future<void> play(
    Uint8List wav, {
    required VoidCallback onStarted,
    required Duration limit,
  }) async {
    played.add(wav);
    final done = _playing = Completer<void>();
    onStarted();
    if (!hold) done.complete();
    await done.future;
  }

  void finish() {
    if (isPlaying) _playing!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}

/// Device TTS: starts at once, reports [words], finishes unless [hold].
class FakeTtsEngine implements TtsEngine {
  final List<(String, String)> spoken = [];
  int stops = 0;
  bool hold = false;
  bool reportWords = true;
  bool fail = false;
  Completer<void>? _speaking;

  bool get isSpeaking => _speaking != null && !_speaking!.isCompleted;

  @override
  Future<void> speak(
    String text, {
    required String language,
    required VoidCallback onStart,
    required void Function(int start, int end) onWord,
  }) async {
    if (fail) throw StateError('tts');
    spoken.add((text, language));
    final done = _speaking = Completer<void>();
    onStart();
    if (reportWords) {
      final space = text.indexOf(' ');
      onWord(0, space < 0 ? text.length : space);
    }
    if (!hold) done.complete();
    await done.future;
  }

  void finish() {
    if (isSpeaking) _speaking!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}

/// The speech server: answers with [respond] per request.
class FakeSpeechServer implements HttpClientAdapter {
  FakeSpeechServer([this.respond]);

  /// null = a valid answer for the request's generation_id.
  Future<ResponseBody> Function(Map<String, Object?> body)? respond;
  final List<Map<String, Object?>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonDecode(
      utf8.decode(await requestStream!.expand((c) => c).toList()),
    ) as Map<String, Object?>;
    requests.add(body);
    final r = respond;
    if (r != null) return r(body);
    return ok(body['generation_id']! as String);
  }

  static ResponseBody ok(String id) => ResponseBody.fromString(
    jsonEncode({
      'generation_id': id,
      'voice_id': 'raza_en',
      'audio_format': 'wav',
      'sample_rate': 24000,
      'audio_b64': base64Encode([1, 2, 3]),
      'mouth_cues': [
        {'start': 0.0, 'end': 0.2, 'value': 'D'},
        {'start': 0.2, 'end': 0.4, 'value': 'X'},
      ],
      'duration_s': 0.4,
      'timings_ms': {},
    }),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  static ResponseBody error(int status, String code) => ResponseBody.fromString(
    jsonEncode({
      'error': {'code': code},
    }),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

SpeechApiClient fakeApi(FakeSpeechServer server) => SpeechApiClient(
  baseUrl: 'https://speech.example.test',
  dio: Dio()..httpClientAdapter = server,
);
