import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/voice_input/mic_controller.dart';

import 'fake_mic.dart';

void main() {
  late Directory dir;
  late FakeMicRecorder recorder;
  late MemoryKeyValueStore store;
  late List<(String, bool)> sent;
  late List<AudioSendResult> results;
  late int consents;
  late bool consentAnswer;
  late bool blocked;
  late List<String> log;
  late MicDiagnosticsLog diagnostics;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koi_mic_ctrl');
    recorder = FakeMicRecorder();
    store = MemoryKeyValueStore();
    sent = [];
    results = [];
    consents = 0;
    consentAnswer = true;
    blocked = false;
    log = [];
    recorder.log = log;
    diagnostics = MicDiagnosticsLog();
  });
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MicController mic({
    Duration maxLength = const Duration(seconds: 30),
    String uid = 'u1',
  }) => MicController(
    uid: uid,
    recorder: recorder,
    prefs: MicPrefs(store),
    send: (audio, {saveTranscript = true}) async {
      sent.add((audio.path, saveTranscript));
      return results.isEmpty
          ? const AudioSendResult(reply: 'ok')
          : results.removeAt(0);
    },
    askConsent: () async {
      consents++;
      return consentAnswer;
    },
    isBlocked: () => blocked,
    onRecordingStarted: () => log.add('voice-stop'),
    diagnostics: diagnostics,
    tempDir: () async => dir.path,
    maxLength: maxLength,
  );

  bool exists(String? path) => path != null && File(path).existsSync();

  test('consent once per uid; Continue then permission then record', () async {
    final m = mic();
    await m.tap();
    expect(consents, 1);
    expect(recorder.permissionAsks, 1);
    expect(m.recording, isTrue);
    expect(store.get(MicPrefs.consentKey('u1')), 'true');
    await m.cancel();

    await m.tap();
    expect(consents, 1, reason: 'not shown again for this uid');
    await m.cancel();

    final other = mic(uid: 'u2');
    await other.tap();
    expect(consents, 2);
    await other.cancel();
    m.dispose();
    other.dispose();
  });

  test('Not now: no permission asked, no recording, asked again', () async {
    consentAnswer = false;
    final m = mic();
    await m.tap();
    expect(recorder.permissionAsks, 0);
    expect(recorder.started, isEmpty);
    expect(m.phase, MicPhase.idle);
    await m.tap();
    expect(consents, 2);
    m.dispose();
  });

  test('permission denied → mic off notice; 2nd → Android Settings', () async {
    recorder.granted = false;
    final m = mic();
    await m.tap();
    expect(m.phase, MicPhase.idle);
    expect(m.notice, MicNotice.denied);
    expect(recorder.started, isEmpty);
    await m.tap();
    expect(m.notice, MicNotice.deniedSettings);
    expect(sent, isEmpty);

    recorder.granted = true;
    await m.tap();
    expect(m.recording, isTrue);
    expect(m.notice, MicNotice.none);
    expect(store.get(MicPrefs.deniedKey('u1')), isNull);
    await m.cancel();
    m.dispose();
  });

  test('recording start stops voice playback first', () async {
    final m = mic();
    await m.tap();
    expect(log, ['voice-stop', 'record']);
    await m.cancel();
    m.dispose();
  });

  test('WAV in the temp dir; tap again sends it, then deletes it', () async {
    final m = mic();
    await m.tap();
    final path = recorder.current!;
    expect(path, startsWith(dir.path));
    expect(path, endsWith('.wav'));
    expect(exists(path), isTrue);

    await m.tap();
    expect(recorder.stops, 1);
    expect(sent, [(path, true)]);
    expect(exists(path), isFalse);
    expect(m.phase, MicPhase.idle);
    m.dispose();
  });

  test('cancel: nothing sent, file deleted', () async {
    final m = mic();
    await m.tap();
    final path = recorder.current!;
    await m.cancel();
    expect(sent, isEmpty);
    expect(recorder.cancels, 1);
    expect(exists(path), isFalse);
    expect(m.phase, MicPhase.idle);
    m.dispose();
  });

  test('auto-stop and send at maxLength', () async {
    final m = mic(maxLength: const Duration(milliseconds: 60));
    await m.tap();
    expect(m.recording, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sent, hasLength(1));
    expect(m.phase, MicPhase.idle);
    m.dispose();
  });

  test('422 → Retry keeps the same clip; deleted after success', () async {
    results.add(const AudioSendResult(failureCode: '422'));
    final m = mic();
    await m.tap();
    final path = recorder.current!;
    await m.tap();
    expect(m.phase, MicPhase.failed);
    expect(m.notice, MicNotice.unclear);
    expect(m.canRetry, isTrue);
    expect(exists(path), isTrue, reason: 'kept for Retry');

    await m.retry();
    expect(sent, [(path, true), (path, true)]);
    expect(m.phase, MicPhase.idle);
    expect(m.notice, MicNotice.none);
    expect(exists(path), isFalse);
    m.dispose();
  });

  test(
    'timeout after a saved transcript: Retry does not save it again',
    () async {
      results.add(
        const AudioSendResult(failureCode: 'timeout', transcriptSaved: true),
      );
      final m = mic();
      await m.tap();
      final path = recorder.current!;
      await m.tap();
      expect(m.notice, MicNotice.sendFailed);
      await m.retry();
      expect(sent, [(path, true), (path, false)]);
      m.dispose();
    },
  );

  test('blocked (crisis / breathing / reply pending): no recording', () async {
    blocked = true;
    final m = mic();
    await m.tap();
    expect(consents, 0);
    expect(recorder.started, isEmpty);
    expect(m.phase, MicPhase.idle);
    m.dispose();
  });

  test('blocked while the consent dialog was open: no recording', () async {
    final m = MicController(
      uid: 'u1',
      recorder: recorder,
      prefs: MicPrefs(store),
      send: (a, {saveTranscript = true}) async =>
          const AudioSendResult(reply: 'x'),
      askConsent: () async {
        blocked = true; // crisis opened meanwhile
        return true;
      },
      isBlocked: () => blocked,
      tempDir: () async => dir.path,
    );
    await m.tap();
    expect(recorder.started, isEmpty);
    expect(m.phase, MicPhase.idle);
    m.dispose();
  });

  test(
    'interrupt (crisis / breathing / app hidden) discards the recording',
    () async {
      final m = mic();
      await m.tap();
      final path = recorder.current!;
      await m.interrupt();
      expect(sent, isEmpty);
      expect(exists(path), isFalse);
      m.dispose();
    },
  );

  test('dispose deletes a kept clip and a recording', () async {
    results.add(const AudioSendResult(failureCode: 'network'));
    final m = mic();
    await m.tap();
    final kept = recorder.current!;
    await m.tap();
    expect(exists(kept), isTrue);
    m.dispose();
    await pumpEventQueue();
    expect(exists(kept), isFalse);
    expect(recorder.disposed, isTrue);

    final m2 = mic();
    await m2.tap();
    final live = recorder.current!;
    m2.dispose();
    await pumpEventQueue();
    expect(exists(live), isFalse);
  });

  test('a new recording discards the clip kept for Retry', () async {
    results.add(const AudioSendResult(failureCode: '422'));
    final m = mic();
    await m.tap();
    final first = recorder.current!;
    await m.tap();
    expect(exists(first), isTrue);
    await m.tap(); // records again
    expect(exists(first), isFalse);
    expect(m.recording, isTrue);
    await m.cancel();
    m.dispose();
  });

  test('diagnostics: clip length, format, bytes, code; no text', () async {
    results.add(const AudioSendResult(failureCode: '422'));
    var now = DateTime(2026, 10, 18, 12);
    final m = MicController(
      uid: 'u1',
      recorder: recorder,
      prefs: MicPrefs(store),
      send: (a, {saveTranscript = true}) async => results.removeAt(0),
      askConsent: () async => true,
      isBlocked: () => false,
      diagnostics: diagnostics,
      tempDir: () async => dir.path,
      now: () => now,
    );
    await m.tap();
    now = now.add(const Duration(milliseconds: 12400));
    await m.tap();
    final line = diagnostics.last!.line;
    expect(line, contains('clip=12.4s'));
    expect(line, contains('format=wav/16kHz/mono'));
    expect(line, contains('bytes=13'));
    expect(line, contains('status=422'));
    expect(line, contains('attempt=1'));
    expect(line, isNot(contains('RIFF')));
    m.dispose();
  });

  test('clip length is capped at maxLength', () async {
    var now = DateTime(2026, 10, 18);
    final m = MicController(
      uid: 'u1',
      recorder: recorder,
      prefs: MicPrefs(store),
      send: (a, {saveTranscript = true}) async =>
          const AudioSendResult(reply: 'x'),
      askConsent: () async => true,
      isBlocked: () => false,
      diagnostics: diagnostics,
      tempDir: () async => dir.path,
      now: () => now,
    );
    await m.tap();
    now = now.add(const Duration(seconds: 25));
    expect(m.warning, isTrue);
    now = now.add(const Duration(seconds: 20));
    expect(m.elapsed, const Duration(seconds: 30));
    await m.tap();
    expect(diagnostics.last!.line, contains('clip=30.0s'));
    m.dispose();
  });

  test('AudioUpload default filename is voice.wav', () {
    expect(const AudioUpload('/x').filename, 'voice.wav');
  });
}
