import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../avatar/avatar_state.dart' show MouthCue;
import '../chat/chat_api.dart' show parseApiBase;

/// Base URL of the speech service, from `--dart-define=KOI_SPEECH_BASE=...`.
/// No default and the URL is not written anywhere in the repo; until it is
/// set, the call screen only uses the device voice.
const String koiSpeechBase = String.fromEnvironment('KOI_SPEECH_BASE');

/// The Rhubarb shapes the server (and lib/speech/mouthCues.ts) use.
const Set<String> rhubarbShapes = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'X'};

/// Server limit on `text` (characters).
const int maxSpeechChars = 450;

/// A failed speech request. [code] is the server's `error.code`
/// (invalid-request, unauthenticated, text-too-long, audio-too-long,
/// voice-not-allowed, language-mismatch, rate-limited, speech-unavailable),
/// the HTTP status when there was none, or one of ours: `timeout`,
/// `network`, `bad-response`, `stale`, `not-configured`. Never shown.
class SpeechApiException implements Exception {
  const SpeechApiException(this.code);
  final String code;

  @override
  String toString() => 'SpeechApiException($code)';
}

/// One synthesized sentence.
class SpeechClip {
  const SpeechClip({
    required this.generationId,
    required this.voiceId,
    required this.sampleRate,
    required this.audio,
    required this.cues,
    required this.durationS,
  });

  final String generationId;
  final String voiceId;
  final int sampleRate;

  /// The decoded WAV file.
  final Uint8List audio;
  final List<MouthCue> cues;
  final double durationS;
}

/// Mouth cues as lib/speech/mouthCues.ts parseMouthCues() accepts them:
/// finite, start < end, ordered, non-overlapping, value A–H or X. Throws
/// [FormatException] otherwise.
List<MouthCue> parseCues(Object? json) {
  if (json is! List) throw const FormatException('mouth_cues');
  var previousEnd = 0.0;
  final cues = <MouthCue>[];
  for (final item in json) {
    if (item is! Map) throw const FormatException('mouth cue');
    final start = item['start'], end = item['end'], value = item['value'];
    if (start is! num ||
        end is! num ||
        !start.isFinite ||
        !end.isFinite ||
        start < previousEnd ||
        end <= start ||
        value is! String ||
        !rhubarbShapes.contains(value)) {
      throw const FormatException('mouth cue');
    }
    previousEnd = end.toDouble();
    cues.add(
      MouthCue(start: start.toDouble(), end: end.toDouble(), value: value),
    );
  }
  return List.unmodifiable(cues);
}

/// `POST {KOI_SPEECH_BASE}/api/v1/speech` (Bearer Firebase ID token). The
/// service warm-up uses a ChatApiClient on the same base for `GET /health`.
class SpeechApiClient {
  SpeechApiClient({required String baseUrl, Dio? dio})
    : base = parseApiBase(baseUrl),
      _dio = dio ?? Dio();

  final Uri? base;
  final Dio _dio;

  bool get isConfigured => base != null;

  /// One request limited to [timeout]. The response must be for
  /// [generationId] (else `stale`), WAV, with valid audio and cues (else
  /// `bad-response`).
  Future<SpeechClip> synthesize({
    required String idToken,
    required String text,
    required String voiceId,
    required String language,
    required String generationId,
    required Duration timeout,
  }) async {
    final base = this.base;
    if (base == null) {
      throw const SpeechApiException('not-configured');
    }
    final cancel = CancelToken();
    final timer = Timer(timeout, cancel.cancel);
    Response<Object?> res;
    try {
      res = await _dio.requestUri<Object?>(
        base.replace(path: '${base.path}/api/v1/speech'),
        data: jsonEncode({
          'text': text,
          'voice_id': voiceId,
          'language': language,
          'generation_id': generationId,
        }),
        cancelToken: cancel,
        options: Options(
          method: 'POST',
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
          // A 303 poll hop only happens after 150 s; never followed here.
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw SpeechApiException(
        e.type == DioExceptionType.cancel ? 'timeout' : 'network',
      );
    } finally {
      timer.cancel();
    }
    final status = res.statusCode ?? 0;
    Object? body;
    try {
      final data = res.data;
      body = data is String ? jsonDecode(data) : data;
    } catch (_) {}
    if (status != 200) {
      final error = body is Map ? body['error'] : null;
      final code = error is Map ? error['code'] : null;
      throw SpeechApiException(code is String ? code : '$status');
    }
    return _clip(body, generationId);
  }

  static SpeechClip _clip(Object? body, String generationId) {
    if (body is! Map) throw const SpeechApiException('bad-response');
    if (body['generation_id'] != generationId) {
      throw const SpeechApiException('stale');
    }
    try {
      final voiceId = body['voice_id'] as String;
      final rate = body['sample_rate'] as int;
      final duration = (body['duration_s'] as num).toDouble();
      if (body['audio_format'] != 'wav') throw const FormatException('wav');
      final audio = base64Decode(body['audio_b64'] as String);
      if (audio.isEmpty) throw const FormatException('audio');
      return SpeechClip(
        generationId: generationId,
        voiceId: voiceId,
        sampleRate: rate,
        audio: audio,
        cues: parseCues(body['mouth_cues']),
        durationS: duration,
      );
    } catch (_) {
      throw const SpeechApiException('bad-response');
    }
  }
}
