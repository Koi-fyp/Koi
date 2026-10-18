import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';

const _waking = Duration(milliseconds: 40);

Future<void> _wait([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// A fake clock: [delay] moves [now] forward at once and records the wait.
class _Clock {
  DateTime now = DateTime(2026, 10, 18, 12);
  final waits = <Duration>[];

  Future<void> delay(Duration d) async {
    waits.add(d);
    now = now.add(d);
  }

  void advance(Duration d) => now = now.add(d);
}

/// A health check that answers from [answers] in order (the last repeats),
/// optionally taking [takes] of fake time per try, and records each try's
/// timeout.
class _Health {
  _Health(this.clock, this.answers, {this.takes = Duration.zero});
  final _Clock clock;
  final List<bool> answers;
  final Duration takes;
  final timeouts = <Duration>[];

  Future<bool> call(Duration timeout) async {
    timeouts.add(timeout);
    clock.advance(takes);
    final i = timeouts.length - 1;
    return answers[i < answers.length ? i : answers.length - 1];
  }
}

void main() {
  test('health slower than the threshold → waking → ready', () async {
    final health = Completer<bool>();
    var crisisCalls = 0;
    final w = BackendWarmup(
      chatHealth: (_) => health.future,
      crisisHealth: (_) async {
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
    final w = BackendWarmup(
      chatHealth: (_) async => true,
      wakingAfter: _waking,
    );
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

  group('retry until 200 (fake clock)', () {
    test('backs off 2, 4, 8 s and stops at the first 200', () async {
      final clock = _Clock();
      final chat = _Health(clock, [false, false, false, true]);
      final w = BackendWarmup(
        chatHealth: chat.call,
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      await _wait(1);
      expect(chat.timeouts, hasLength(4));
      expect(clock.waits, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      // Each try gets the time left of the 240 s limit.
      expect(chat.timeouts, const [
        Duration(seconds: 240),
        Duration(seconds: 238),
        Duration(seconds: 234),
        Duration(seconds: 226),
      ]);
      expect(w.status, BackendStatus.ready);
    });

    test('never 200: gives up at exactly 240 s → unreachable', () async {
      final clock = _Clock();
      final start = clock.now;
      final chat = _Health(clock, [false]);
      final w = BackendWarmup(
        chatHealth: chat.call,
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      await _wait(1);
      expect(clock.now.difference(start), const Duration(seconds: 240));
      // 2+4+8+16 = 30, then 30 s steps; the last wait is cut to the limit.
      expect(clock.waits.take(5), const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 30),
      ]);
      expect(
        clock.waits.skip(5).every((d) => d <= const Duration(seconds: 30)),
        isTrue,
      );
      expect(w.status, BackendStatus.unreachable);
    });

    test('a slow cold start (~100 s per try) still fits in 240 s', () async {
      final clock = _Clock();
      final chat = _Health(clock, [
        false,
        true,
      ], takes: const Duration(seconds: 100));
      final w = BackendWarmup(
        chatHealth: chat.call,
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      await _wait(1);
      expect(chat.timeouts, const [
        Duration(seconds: 240),
        Duration(seconds: 138), // 240 - 100 - 2
      ]);
      expect(w.status, BackendStatus.ready);
    });

    test('a throwing check counts as a failed try', () async {
      final clock = _Clock();
      var tries = 0;
      final w = BackendWarmup(
        chatHealth: (_) async {
          if (++tries == 1) throw StateError('socket');
          return true;
        },
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      await _wait(1);
      expect(tries, 2);
      expect(w.status, BackendStatus.ready);
    });

    test('warmUp while a warm-up runs does not start a second one', () async {
      final first = Completer<bool>();
      var tries = 0;
      final w = BackendWarmup(
        chatHealth: (_) {
          tries++;
          return first.future;
        },
      )..warmUp();
      w.warmUp();
      expect(tries, 1);
      first.complete(true);
      await _wait(1);
      w.warmUp(); // finished: a new warm-up may start
      expect(tries, 2);
    });
  });

  group('crisis health never blocks chat', () {
    test('crisis failing for the whole limit: chat ready, first send '
        'released by chat alone', () async {
      final clock = _Clock();
      final crisisDone = Completer<void>();
      final crisis = _Health(clock, [false]);
      final chatAnswer = Completer<bool>();
      final w = BackendWarmup(
        chatHealth: (_) => chatAnswer.future,
        crisisHealth: (t) async {
          // Crisis keeps failing until chat has answered.
          await crisisDone.future;
          return crisis(t);
        },
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      var released = false;
      unawaited(w.holdFirstSend().then((_) => released = true));
      chatAnswer.complete(true);
      await _wait(1);
      expect(released, isTrue);
      expect(w.status, BackendStatus.ready);
      crisisDone.complete();
      await _wait(1);
      expect(crisis.timeouts, isNotEmpty);
      expect(w.status, BackendStatus.ready); // crisis result ignored
    });

    test('crisis check throwing changes nothing', () async {
      final w = BackendWarmup(
        chatHealth: (_) async => true,
        crisisHealth: (_) async => throw StateError('down'),
      )..warmUp();
      await _wait(1);
      expect(w.status, BackendStatus.ready);
    });

    test(
      'only crisis configured: status stays unknown, nothing held',
      () async {
        final w = BackendWarmup(
          chatHealth: null,
          crisisHealth: (_) async => false,
          wakingAfter: _waking,
        )..warmUp();
        await w.holdFirstSend();
        await _wait();
        expect(w.status, BackendStatus.unknown);
      },
    );
  });

  group('first send hold', () {
    test('held until chat health 200, waking shown at once; later sends '
        'not held', () async {
      final health = Completer<bool>();
      final w = BackendWarmup(chatHealth: (_) => health.future)..warmUp();
      var released = false;
      unawaited(w.holdFirstSend().then((_) => released = true));
      await _wait(1);
      expect(released, isFalse);
      expect(w.status, BackendStatus.waking); // no 3 s wait while held
      health.complete(true);
      await _wait(1);
      expect(released, isTrue);
      expect(w.status, BackendStatus.ready);
    });

    test(
      'only the first send waits, even while the warm-up still runs',
      () async {
        final w = BackendWarmup(chatHealth: (_) => Completer<bool>().future)
          ..warmUp();
        var first = false;
        var second = false;
        unawaited(w.holdFirstSend().then((_) => first = true));
        unawaited(w.holdFirstSend().then((_) => second = true));
        await _wait(1);
        expect(first, isFalse);
        expect(second, isTrue);
      },
    );

    test('released when the 240 s limit passes without a 200', () async {
      final clock = _Clock();
      final w = BackendWarmup(
        chatHealth: _Health(clock, [false]).call,
        now: () => clock.now,
        delay: clock.delay,
      )..warmUp();
      await w.holdFirstSend();
      expect(w.status, BackendStatus.unreachable);
    });

    test('not held when the warm-up already finished', () async {
      final w = BackendWarmup(chatHealth: (_) async => true)..warmUp();
      await _wait(1);
      var released = false;
      unawaited(w.holdFirstSend().then((_) => released = true));
      await _wait(1);
      expect(released, isTrue);
    });
  });

  test('first chat request: waking after the threshold, cleared on the '
      'first event', () async {
    final w = BackendWarmup(
      chatHealth: (_) async => false,
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

  test(
    'resume after more than 5 min warms both again; shorter does not',
    () async {
      var now = DateTime(2026, 10, 18, 12);
      var chat = 0;
      var crisis = 0;
      final w = BackendWarmup(
        chatHealth: (_) async {
          chat++;
          return true;
        },
        crisisHealth: (_) async {
          crisis++;
          return true;
        },
        now: () => now,
      );
      w.appBackgrounded();
      now = now.add(const Duration(minutes: 4));
      w.appResumed();
      expect((chat, crisis), (0, 0));
      w.appBackgrounded();
      now = now.add(const Duration(minutes: 6));
      w.appResumed();
      expect((chat, crisis), (1, 1));
    },
  );

  test('defaults: 3 s threshold, 5 min resume, 240 s limit, backoff', () {
    final w = BackendWarmup(chatHealth: null);
    expect(w.wakingAfter, const Duration(seconds: 3));
    expect(w.resumeAfter, const Duration(minutes: 5));
    expect(w.limit, const Duration(seconds: 240));
    expect(w.retryDelays, BackendWarmup.defaultRetryDelays);
  });
}
