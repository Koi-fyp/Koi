import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/voice/speech_source.dart';
import 'package:koi_mobile/voice/voice_controller.dart';
import 'package:koi_mobile/voice/voice_text.dart';

import 'fakes.dart';

const en = SpeechPart('One.', voiceId: 'raza_en', language: 'en');
const en2 = SpeechPart('Two more words.', voiceId: 'raza_en', language: 'en');
const en3 = SpeechPart('Three.', voiceId: 'raza_en', language: 'en');

void expectValidCues(List<MouthCue> cues) {
  var previous = 0.0;
  for (final c in cues) {
    expect(c.start, greaterThanOrEqualTo(previous));
    expect(c.end, greaterThan(c.start));
    expect('ABCDEFGHX'.contains(c.value) && c.value.length == 1, isTrue);
    previous = c.end;
  }
}

void main() {
  late FakeSpeechServer http;
  late FakeClipPlayer player;
  late FakeTtsEngine tts;
  late List<List<MouthCue>> mouth;
  late List<VoiceKind?> states;
  late bool warm;

  VoiceController make({
    SpeechRateLimiter? limiter,
    Duration timeout = const Duration(seconds: 12),
    bool server = true,
  }) {
    final c = VoiceController(
      server: server
          ? ServerSpeechSource(
              api: fakeApi(http),
              idToken: () async => 'tok',
              player: player,
              limiter: limiter ?? SpeechRateLimiter(),
              timeout: timeout,
            )
          : null,
      device: DeviceSpeechSource(tts),
      serverReady: () => warm,
      onMouth: mouth.add,
    );
    c.addListener(() => states.add(c.speaking));
    return c;
  }

  setUp(() {
    http = FakeSpeechServer();
    player = FakeClipPlayer();
    tts = FakeTtsEngine();
    mouth = [];
    states = [];
    warm = true;
  });

  test('server voice: every part, real cues, speaking then idle', () async {
    final c = make();
    await c.speak(const SpeakPlan([en, en2], deviceOnly: false));
    expect(http.requests.map((r) => r['text']), ['One.', 'Two more words.']);
    expect(http.requests.first['voice_id'], 'raza_en');
    expect(http.requests.first['language'], 'en');
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(http.requests.first['generation_id']! as String),
      isTrue,
    );
    expect(player.played, hasLength(2));
    expect(tts.spoken, isEmpty);
    expect(mouth.where((m) => m.isNotEmpty).first.map((m) => m.value), [
      'D',
      'X',
    ]);
    expect(states.where((s) => s != null).toSet(), {VoiceKind.server});
    expect(c.speaking, isNull);
    expect(mouth.last, isEmpty);
  });

  test('the next part is fetched while the first plays', () async {
    player.hold = true;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2, en3], deviceOnly: false));
    await pumpEventQueue();
    expect(player.played, hasLength(1));
    expect(http.requests.map((r) => r['text']), ['One.', 'Two more words.']);
    player.finish();
    await pumpEventQueue();
    expect(http.requests, hasLength(3));
    player.finish();
    await pumpEventQueue();
    player.finish();
    await done;
    expect(player.played, hasLength(3));
  });

  final failures =
      <String, Future<ResponseBody> Function(Map<String, Object?>)>{
        '400 invalid-request': (_) async =>
            FakeSpeechServer.error(400, 'invalid-request'),
        '401 unauthenticated': (_) async =>
            FakeSpeechServer.error(401, 'unauthenticated'),
        '413 text-too-long': (_) async =>
            FakeSpeechServer.error(413, 'text-too-long'),
        '413 audio-too-long': (_) async =>
            FakeSpeechServer.error(413, 'audio-too-long'),
        '422 voice-not-allowed': (_) async =>
            FakeSpeechServer.error(422, 'voice-not-allowed'),
        '422 language-mismatch': (_) async =>
            FakeSpeechServer.error(422, 'language-mismatch'),
        '429 rate-limited': (_) async =>
            FakeSpeechServer.error(429, 'rate-limited'),
        '503 speech-unavailable': (_) async =>
            FakeSpeechServer.error(503, 'speech-unavailable'),
        'stale generation_id': (_) async => FakeSpeechServer.ok('someone-else'),
        'network failure': (_) async => throw const FormatException('down'),
      };
  for (final MapEntry(key: name, value: respond) in failures.entries) {
    test('$name → device voice for the rest of the reply', () async {
      http.respond = respond;
      final c = make();
      await c.speak(const SpeakPlan([en, en2], deviceOnly: false));
      expect(player.played, isEmpty);
      expect(tts.spoken, [('One.', 'en'), ('Two more words.', 'en')]);
      expect(http.requests, hasLength(1), reason: 'no more server calls');
      expect(states.where((s) => s != null).toSet(), {VoiceKind.device});
    });
  }

  test('timeout → device voice', () async {
    http.respond = (_) => Completer<ResponseBody>().future;
    final c = make(timeout: const Duration(milliseconds: 50));
    await c.speak(const SpeakPlan([en], deviceOnly: false));
    expect(tts.spoken, [('One.', 'en')]);
    expect(player.played, isEmpty);
  });

  test('a server failure on a later part switches only from there', () async {
    var n = 0;
    http.respond = (b) async => n++ == 0
        ? FakeSpeechServer.ok(b['generation_id']! as String)
        : FakeSpeechServer.error(503, 'speech-unavailable');
    final c = make();
    await c.speak(const SpeakPlan([en, en2, en3], deviceOnly: false));
    expect(player.played, hasLength(1));
    expect(tts.spoken.map((s) => s.$1), ['Two more words.', 'Three.']);
  });

  test('10/min would be exceeded → the rest uses the device voice', () async {
    var now = DateTime(2026, 10, 18);
    final limiter = SpeechRateLimiter(max: 2, now: () => now);
    final c = make(limiter: limiter);
    await c.speak(const SpeakPlan([en, en2, en3], deviceOnly: false));
    expect(http.requests, hasLength(2));
    expect(tts.spoken.map((s) => s.$1), ['Three.']);
    now = now.add(const Duration(minutes: 1));
    expect(limiter.tryAcquire(), isTrue, reason: 'the window moves on');
  });

  test('default limiter is 10 per minute', () {
    final l = SpeechRateLimiter(now: () => DateTime(2026));
    expect(List.generate(11, (_) => l.tryAcquire()), [
      ...List.filled(10, true),
      false,
    ]);
  });

  test('not warm yet, device-only plan or no server → device voice', () async {
    warm = false;
    await make().speak(const SpeakPlan([en], deviceOnly: false));
    warm = true;
    await make().speak(const SpeakPlan([en2], deviceOnly: true));
    await make(server: false).speak(const SpeakPlan([en3], deviceOnly: false));
    expect(http.requests, isEmpty);
    expect(tts.spoken.map((s) => s.$1), ['One.', 'Two more words.', 'Three.']);
  });

  test('silent plan says nothing', () async {
    await make().speak(const SilentPlan());
    expect(http.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  test('stop: audio and mouth stop, a late answer is dropped', () async {
    final pending = Completer<ResponseBody>();
    http.respond = (_) => pending.future;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2], deviceOnly: false));
    await pumpEventQueue();
    mouth.clear();
    await c.stop();
    expect(player.stops, greaterThan(0));
    expect(tts.stops, greaterThan(0));
    expect(mouth.single, isEmpty);
    pending.complete(
      FakeSpeechServer.ok(http.requests.single['generation_id']! as String),
    );
    await done;
    expect(player.played, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(c.speaking, isNull);
  });

  test('stop while playing ends the reply', () async {
    player.hold = true;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2], deviceOnly: false));
    await pumpEventQueue();
    expect(c.speaking, VoiceKind.server);
    await c.stop();
    await done;
    expect(player.played, hasLength(1));
    expect(c.speaking, isNull);
    expect(tts.spoken, isEmpty);
  });

  test(
    'device voice: word cues, else timed cues — ordered and valid',
    () async {
      final c = make(server: false);
      await c.speak(const SpeakPlan([en2], deviceOnly: false));
      final sent = mouth.where((m) => m.isNotEmpty).toList();
      expect(sent, hasLength(2), reason: 'timed at start, then the word');
      for (final cues in sent) {
        expectValidCues(cues);
      }
      expect(states.where((s) => s != null).toSet(), {VoiceKind.device});

      expectValidCues(timedCues('a' * 2000));
      expect(timedCues('a' * 2000).last.end, closeTo(60, 1e-9));
      expectValidCues(wordCues('x'));
      expectValidCues(wordCues('supercalifragilistic'));
    },
  );

  test('a failing device voice is silent, never an error', () async {
    tts.fail = true;
    final c = make(server: false);
    await c.speak(const SpeakPlan([en], deviceOnly: false));
    expect(c.speaking, isNull);
  });

  test('VoicePrefs: on by default, per uid', () async {
    final store = MemoryKeyValueStore();
    final prefs = VoicePrefs(store);
    expect(prefs.isEnabled('u1'), isTrue);
    await prefs.setEnabled('u1', false);
    expect(prefs.isEnabled('u1'), isFalse);
    expect(prefs.isEnabled('u2'), isTrue);
    expect(store.values, {'koi_voice_enabled_u1': 'false'});
  });

  test('SpeechWarmup retries /health until 200', () async {
    var calls = 0;
    final waits = <Duration>[];
    final w = SpeechWarmup(
      health: (_) async => ++calls == 3,
      delay: (d) async => waits.add(d),
    );
    expect(w.isReady, isFalse);
    await w.warmUp();
    expect(w.isReady, isTrue);
    expect(waits, const [Duration(seconds: 2), Duration(seconds: 4)]);
    await w.warmUp();
    expect(calls, 3, reason: 'ready: no more checks');
    final none = SpeechWarmup(health: null);
    await none.warmUp();
    expect(none.isReady, isFalse);
  });
}
