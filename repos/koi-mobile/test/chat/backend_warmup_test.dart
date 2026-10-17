import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';

const _waking = Duration(milliseconds: 40);

Future<void> _wait([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('health slower than the threshold → waking → ready', () async {
    final health = Completer<bool>();
    var crisisCalls = 0;
    final w = BackendWarmup(
      chatHealth: () => health.future,
      crisisHealth: () async {
        crisisCalls++;
        return true;
      },
      wakingAfter: _waking,
    )..warmUp();
    expect(w.status, BackendStatus.unknown);
    expect(crisisCalls, 1);
    await _wait();
    expect(w.status, BackendStatus.waking);
    health.complete(true);
    await _wait(1);
    expect(w.status, BackendStatus.ready);
  });

  test('fast health never shows waking', () async {
    final seen = <BackendStatus>[];
    final w = BackendWarmup(chatHealth: () async => true, wakingAfter: _waking);
    w.addListener(() => seen.add(w.status));
    w.warmUp();
    await _wait();
    expect(seen, [BackendStatus.ready]);
  });

  test('not configured: nothing called, stays unknown', () async {
    final w = BackendWarmup(chatHealth: null, wakingAfter: _waking)..warmUp();
    await _wait();
    expect(w.status, BackendStatus.unknown);
  });

  test('first chat request: waking after the threshold, cleared on the '
      'first event', () async {
    final w = BackendWarmup(
      chatHealth: () async => false,
      wakingAfter: _waking,
    );
    w.chatStarted();
    expect(w.status, BackendStatus.unknown);
    await _wait();
    expect(w.status, BackendStatus.waking);
    w.chatAnswered();
    expect(w.status, BackendStatus.ready);
    w.chatFinished(reached: true);
    expect(w.status, BackendStatus.ready);

    // Once ready, a slow reply is not "waking".
    w.chatStarted();
    await _wait();
    expect(w.status, BackendStatus.ready);
    w.chatFinished(reached: true);
  });

  test(
    'timeout / network → unreachable; unknown failure ends waking',
    () async {
      final w = BackendWarmup(chatHealth: null, wakingAfter: _waking)
        ..chatStarted();
      await _wait();
      w.chatFinished(reached: false);
      expect(w.status, BackendStatus.unreachable);

      final v = BackendWarmup(chatHealth: null, wakingAfter: _waking)
        ..chatStarted();
      await _wait();
      v.chatFinished(reached: null);
      expect(v.status, BackendStatus.unknown);
    },
  );

  test('resume after more than 5 min warms again; shorter does not', () async {
    var now = DateTime(2026, 10, 18, 12);
    var calls = 0;
    final w = BackendWarmup(
      chatHealth: () async {
        calls++;
        return true;
      },
      now: () => now,
    );
    w.appBackgrounded();
    now = now.add(const Duration(minutes: 4));
    w.appResumed();
    expect(calls, 0);
    w.appBackgrounded();
    now = now.add(const Duration(minutes: 6));
    w.appResumed();
    expect(calls, 1);
  });

  test('defaults: 3 s threshold, 5 min resume', () {
    final w = BackendWarmup(chatHealth: null);
    expect(w.wakingAfter, const Duration(seconds: 3));
    expect(w.resumeAfter, const Duration(minutes: 5));
  });
}
