import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/voice/speech_api.dart';

/// Answers every request with [handler]; records the requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o, String body) handler;
  final List<RequestOptions> requests = [];
  final List<Map<String, Object?>> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((c) => c).toList());
    requests.add(options);
    if (body.isNotEmpty) bodies.add(jsonDecode(body) as Map<String, Object?>);
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

Map<String, Object?> okBody(String id, {Object? cues}) => {
  'generation_id': id,
  'voice_id': 'raza_en',
  'audio_format': 'wav',
  'sample_rate': 24000,
  'audio_b64': base64Encode([82, 73, 70, 70, 1, 2, 3]),
  'mouth_cues':
      cues ??
      [
        {'start': 0.0, 'end': 0.1, 'value': 'X'},
        {'start': 0.1, 'end': 0.3, 'value': 'D'},
      ],
  'duration_s': 0.3,
  'timings_ms': {'total': 900},
};

void main() {
  SpeechApiClient client(FakeAdapter a) => SpeechApiClient(
    baseUrl: 'https://speech.example.test',
    dio: Dio()..httpClientAdapter = a,
  );

  Future<SpeechClip> call(
    SpeechApiClient c, {
    String id = 'gen-1',
    Duration timeout = const Duration(seconds: 12),
  }) => c.synthesize(
    idToken: 'tok',
    text: 'Hello.',
    voiceId: 'raza_en',
    language: 'en',
    generationId: id,
    timeout: timeout,
  );

  test('ATC-M3-03 request shape and a valid response', () async {
    final a = FakeAdapter((o, b) async => json(200, okBody('gen-1')));
    final clip = await call(client(a));
    final req = a.requests.single;
    expect(req.method, 'POST');
    expect(req.uri.toString(), 'https://speech.example.test/api/v1/speech');
    expect(req.headers['Authorization'], 'Bearer tok');
    expect(a.bodies.single, {
      'text': 'Hello.',
      'voice_id': 'raza_en',
      'language': 'en',
      'generation_id': 'gen-1',
    });
    expect(clip.audio, [82, 73, 70, 70, 1, 2, 3]);
    expect(clip.cues.map((c) => c.value), ['X', 'D']);
    expect(clip.durationS, 0.3);
  });

  test('ATC-M3-03 not configured without KOI_SPEECH_BASE', () async {
    final c = SpeechApiClient(baseUrl: '');
    expect(c.isConfigured, isFalse);
    await expectLater(
      call(c),
      throwsA(
        isA<SpeechApiException>().having(
          (e) => e.code,
          'code',
          'not-configured',
        ),
      ),
    );
  });

  final errors = <int, String>{
    400: 'invalid-request',
    401: 'unauthenticated',
    413: 'text-too-long',
    422: 'language-mismatch',
    429: 'rate-limited',
    503: 'speech-unavailable',
  };
  for (final MapEntry(key: status, value: code) in errors.entries) {
    test(
      'ATC-M3-04 $status {"error":{"code":"$code"}} → SpeechApiException($code)',
      () async {
        final a = FakeAdapter(
          (o, b) async => json(status, {
            'error': {'code': code},
          }),
        );
        await expectLater(
          call(client(a)),
          throwsA(
            isA<SpeechApiException>().having((e) => e.code, 'code', code),
          ),
        );
      },
    );
  }

  test('ATC-M3-04 an error without a body → the status', () async {
    final a = FakeAdapter((o, b) async => ResponseBody.fromString('', 500));
    await expectLater(
      call(client(a)),
      throwsA(isA<SpeechApiException>().having((e) => e.code, 'code', '500')),
    );
  });

  test('ATC-M3-04 timeout', () async {
    final a = FakeAdapter((o, b) => Completer<ResponseBody>().future);
    await expectLater(
      call(client(a), timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<SpeechApiException>().having((e) => e.code, 'code', 'timeout'),
      ),
    );
  });

  test('ATC-M3-04 a network failure', () async {
    final a = FakeAdapter((o, b) async => throw const FormatException('boom'));
    await expectLater(
      call(client(a)),
      throwsA(
        isA<SpeechApiException>().having((e) => e.code, 'code', 'network'),
      ),
    );
  });

  test('ATC-M3-04 a stale generation_id is rejected', () async {
    final a = FakeAdapter((o, b) async => json(200, okBody('older')));
    await expectLater(
      call(client(a)),
      throwsA(isA<SpeechApiException>().having((e) => e.code, 'code', 'stale')),
    );
  });

  test('ATC-M3-04 bad audio or cues → bad-response', () async {
    final bodies = [
      {...okBody('gen-1'), 'audio_format': 'mp3'},
      {...okBody('gen-1'), 'audio_b64': ''},
      okBody(
        'gen-1',
        cues: [
          {'start': 0.2, 'end': 0.1, 'value': 'D'},
        ],
      ),
      okBody(
        'gen-1',
        cues: [
          {'start': 0.0, 'end': 0.2, 'value': 'D'},
          {'start': 0.1, 'end': 0.3, 'value': 'A'},
        ],
      ),
      okBody(
        'gen-1',
        cues: [
          {'start': 0.0, 'end': 0.2, 'value': 'Q'},
        ],
      ),
    ];
    for (final body in bodies) {
      final a = FakeAdapter((o, b) async => json(200, body));
      await expectLater(
        call(client(a)),
        throwsA(
          isA<SpeechApiException>().having(
            (e) => e.code,
            'code',
            'bad-response',
          ),
        ),
      );
    }
  });

  test('ATC-M3-03 parseCues accepts ordered, touching cues A–H/X', () {
    final cues = parseCues([
      for (final (i, v) in 'ABCDEFGHX'.split('').indexed)
        {'start': i * 0.1, 'end': (i + 1) * 0.1, 'value': v},
    ]);
    expect(cues.map((c) => c.value).join(), 'ABCDEFGHX');
    expect(() => parseCues('nope'), throwsFormatException);
    expect(
      () => parseCues([
        {'start': double.nan, 'end': 1, 'value': 'A'},
      ]),
      throwsFormatException,
    );
  });
}
