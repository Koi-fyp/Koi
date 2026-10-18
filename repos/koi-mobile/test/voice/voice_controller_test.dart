import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
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
  late bool unavailable;

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
      serverUnavailable: () => unavailable,
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
    unavailable = false;
  });

  test('ATC-M3-05 server voice: every part, real cues, speaking then idle', () async {
    final c = make();
    await c.speak(const SpeakPlan([en, en2]));
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

  test('ATC-M3-05 the next part is fetched while the first plays', () async {
    player.hold = true;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2, en3]));
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
    // Changed in Prompt 29: a failed chunk is skipped (was: the device voice
    // for the rest of the reply); 401 / 429 end the reply, since every later
    // chunk would fail too.
    final terminal = name.startsWith('401') || name.startsWith('429');
    test('ATC-M3-06 $name → chunk skipped, never the device voice'
        '${terminal ? ', reply ends' : ', next chunk still asked'}', () async {
      http.respond = respond;
      final c = make();
      await c.speak(const SpeakPlan([en, en2]));
      expect(player.played, isEmpty);
      expect(tts.spoken, isEmpty);
      expect(http.requests, hasLength(terminal ? 1 : 2));
      expect(c.speaking, isNull);
    });
  }

  // Changed in Prompt 29: was the device voice.
  test('ATC-M3-06 a chunk over the timeout is skipped, the next is played', () async {
    var n = 0;
    http.respond = (b) => n++ == 0
        ? Completer<ResponseBody>().future
        : Future.value(FakeSpeechServer.ok(b['generation_id']! as String));
    final c = make(timeout: const Duration(milliseconds: 50));
    await c.speak(const SpeakPlan([en, en2]));
    expect(tts.spoken, isEmpty);
    expect(player.played, hasLength(1));
  });

  // Changed in Prompt 29: was a switch to the device voice from there on.
  test('ATC-M3-06 a failure on a middle part skips only that part', () async {
    var n = 0;
    http.respond = (b) async => n++ == 1
        ? FakeSpeechServer.error(503, 'speech-unavailable')
        : FakeSpeechServer.ok(b['generation_id']! as String);
    final c = make();
    await c.speak(const SpeakPlan([en, en2, en3]));
    expect(player.played, hasLength(2));
    expect(http.requests.map((r) => r['text']), [
      'One.',
      'Two more words.',
      'Three.',
    ]);
    expect(tts.spoken, isEmpty);
  });

  // Changed in Prompt 29: was the device voice for the rest.
  test('ATC-M3-06 10/min would be exceeded → the reply ends there', () async {
    var now = DateTime(2026, 10, 18);
    final limiter = SpeechRateLimiter(max: 2, now: () => now);
    final c = make(limiter: limiter);
    await c.speak(const SpeakPlan([en, en2, en3]));
    expect(http.requests, hasLength(2));
    expect(player.played, hasLength(2));
    expect(tts.spoken, isEmpty);
    now = now.add(const Duration(minutes: 1));
    expect(limiter.tryAcquire(), isTrue, reason: 'the window moves on');
  });

  test('ATC-M3-06 default limiter is 10 per minute', () {
    final l = SpeechRateLimiter(now: () => DateTime(2026));
    expect(List.generate(11, (_) => l.tryAcquire()), [
      ...List.filled(10, true),
      false,
    ]);
  });

  // Changed in Prompt 29: "not warm yet" and device-only plans no longer
  // use the device voice.
  test('ATC-M3-06 device voice only when the service is unavailable or not '
      'configured', () async {
    unavailable = true;
    await make().speak(const SpeakPlan([en]));
    unavailable = false;
    await make(server: false).speak(const SpeakPlan([en3]));
    expect(http.requests, isEmpty);
    expect(tts.spoken.map((s) => s.$1), ['One.', 'Three.']);
    // Available (warm or still warming): the server, never the device.
    await make().speak(const SpeakPlan([en2]));
    expect(http.requests.single['text'], 'Two more words.');
    expect(tts.spoken, hasLength(2));
  });

  test('ATC-M3-07 silent plan says nothing', () async {
    await make().speak(const SilentPlan(SilentReason.empty));
    expect(http.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  test('ATC-M3-08 stop: audio and mouth stop, a late answer is dropped', () async {
    final pending = Completer<ResponseBody>();
    http.respond = (_) => pending.future;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2]));
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

  test('ATC-M3-08 stop while playing ends the reply', () async {
    player.hold = true;
    final c = make();
    final done = c.speak(const SpeakPlan([en, en2]));
    await pumpEventQueue();
    expect(c.speaking, VoiceKind.server);
    await c.stop();
    await done;
    expect(player.played, hasLength(1));
    expect(c.speaking, isNull);
    expect(tts.spoken, isEmpty);
  });

  test(
    'ATC-M3-09 device voice: word cues, else timed cues — ordered and valid',
    () async {
      final c = make(server: false);
      await c.speak(const SpeakPlan([en2]));
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

  test('ATC-M3-07 a failing device voice is silent, never an error', () async {
    tts.fail = true;
    final c = make(server: false);
    await c.speak(const SpeakPlan([en]));
    expect(c.speaking, isNull);
  });

  test('ATC-M3-10 SpeechWarmup retries /health until 200', () async {
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

  test('ATC-M3-37 SpeechWarmup: unavailable only after a warm-up ended '
      'without 200; settled() waits for the running one', () async {
    var ok = false;
    var now = DateTime(2026, 10, 18);
    final gate = <Completer<void>>[];
    final w = SpeechWarmup(
      health: (_) async => ok,
      limit: const Duration(seconds: 10),
      now: () => now,
      delay: (d) {
        now = now.add(d);
        final c = Completer<void>();
        gate.add(c);
        return c.future;
      },
    );
    expect(w.isUnavailable, isFalse);
    var settled = false;
    unawaited(w.settled()!.then((_) => settled = true));
    await pumpEventQueue();
    expect(settled, isFalse, reason: 'still warming');
    expect(w.isUnavailable, isFalse, reason: 'warming is not unavailable');
    while (!settled) {
      gate.removeLast().complete();
      await pumpEventQueue();
    }
    expect(w.isReady, isFalse);
    expect(w.isUnavailable, isTrue);
    expect(w.settled(), isNull, reason: 'gave up: later turns do not wait');

    ok = true;
    now = now.add(const Duration(minutes: 5));
    await w.warmUp();
    expect(w.isReady, isTrue);
    expect(w.isUnavailable, isFalse);
    expect(w.settled(), isNull);
    expect(SpeechWarmup(health: null).settled(), isNull);
  });
}
