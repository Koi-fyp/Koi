import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/applications/application_api.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_polling.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/care_session.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/care_messages/message_models.dart';
import 'package:koi_mobile/care_messages/message_screens.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/notifications/notification_api.dart';

import '../support/mob2_fakes.dart';

const String _rel = 'demo-relationship-1';

HumanMessage _m(String id, int minute) => HumanMessage(
  id: id,
  relationshipId: _rel,
  senderUid: 'demo-expert-1',
  body: 'message $id',
  createdAt: DateTime.utc(2026, 10, 21, 8, minute),
);

/// Pages of a thread, in id order like the server; records each cursor.
class _PagedMessageApi implements CareMessageApi {
  _PagedMessageApi(this.pages);
  final List<List<HumanMessage>> pages;
  final cursors = <String?>[];

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<HumanMessage>> list(
    String relationshipId, {
    String? cursor,
  }) async {
    cursors.add(cursor);
    final i = cursor == null ? 0 : int.parse(cursor);
    return ApiPage([...pages[i]], i + 1 < pages.length ? '${i + 1}' : null);
  }

  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

Future<void> _wait([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('LIVE-06 one place for the Care intervals', () {
    test('thread poll is 30 s, used by default everywhere', () {
      expect(careThreadPollInterval, const Duration(seconds: 30));
      final t = ThreadController(api: FakeMessageApi(), relationshipId: _rel);
      expect(t.pollInterval, careThreadPollInterval);
      t.dispose();
      final s = CareSession(
        uid: 'p1',
        expertApi: const UnavailableExpertDirectoryApi(),
        applicationApi: const UnavailableApplicationApi(),
        messageApi: FakeMessageApi(),
        appointmentApi: const UnavailableAppointmentApi(),
        notificationApi: const UnavailableNotificationApi(),
      );
      expect(s.pollInterval, careThreadPollInterval);
      expect(s.thread(_rel).pollInterval, careThreadPollInterval);
      s.dispose();
    });
  });

  group('LIVE-07 a tick reads page 1 only; nothing new → nothing changes', () {
    test('full reload reads every page; ticks read the first only', () async {
      final api = _PagedMessageApi([
        [_m('a', 1), _m('b', 2)],
        [_m('c', 3)],
        [_m('d', 4)],
      ]);
      final t = ThreadController(
        api: api,
        relationshipId: _rel,
        pollInterval: const Duration(milliseconds: 5),
      );
      await t.list.refresh(merge: true); // open: full reload
      expect(api.cursors, [null, '1', '2']);
      var notified = 0;
      t.addListener(() => notified++);
      api.cursors.clear();
      t.startPolling();
      await _wait();
      t.stopPolling();
      expect(api.cursors, isNotEmpty);
      expect(api.cursors.every((c) => c == null), isTrue, reason: 'page 1');
      expect(notified, 0, reason: 'no change → no rebuild');

      // Something new on page 1: merged once, older pages kept.
      api.pages[0] = [_m('a', 1), _m('b', 2), _m('e', 5)];
      t.startPolling();
      await _wait();
      t.stopPolling();
      expect([for (final m in t.messages) m.id], ['a', 'b', 'c', 'd', 'e']);
      expect(notified, 1);
      t.dispose();
    });

    test('a tick never runs while a full reload is in flight', () async {
      final api = FakeMessageApi()..listScript.gate = Completer.sync();
      final t = ThreadController(api: api, relationshipId: _rel);
      final reload = t.list.refresh(merge: true);
      await t.list.pollFirstPage();
      expect(api.listScript.calls, 1, reason: 'only the reload');
      api.listScript.gate!.complete();
      await reload;
      t.dispose();
    });
  });

  group('LIVE-08 polls only while visible AND in the foreground', () {
    test(
      'covered route / background stop the timer; back on resumes',
      () async {
        final api = FakeMessageApi();
        final t = ThreadController(
          api: api,
          relationshipId: _rel,
          pollInterval: const Duration(milliseconds: 5),
        );
        final screen = Object();
        t.startPolling(screen);
        expect(t.isPolling, isTrue);

        t.setVisible(false, screen); // another page on top
        expect(t.isPolling, isFalse);
        var calls = api.listScript.calls;
        await _wait();
        expect(api.listScript.calls, calls);

        t.setVisible(true, screen);
        expect(t.isPolling, isTrue);
        t.setForeground(false); // app hidden
        expect(t.isPolling, isFalse);
        calls = api.listScript.calls;
        await _wait();
        expect(api.listScript.calls, calls, reason: 'no polling in background');

        t.setForeground(true);
        await _wait();
        expect(api.listScript.calls, greaterThan(calls));

        // Two screens of one thread: polls while either is on top.
        final second = Object();
        t.startPolling(second);
        t.setVisible(false, screen);
        expect(t.isPolling, isTrue);
        t.stopPolling(second);
        expect(t.isPolling, isFalse);
        expect(t.isOpen, isTrue, reason: 'the first screen is still open');
        t.stopPolling(screen);
        expect(t.isOpen, isFalse);
        t.dispose();
      },
    );
  });

  group('LIVE-09 resume: a full reload of every OPEN thread only', () {
    test('open (even covered) → all pages; closed → nothing', () async {
      final api = _PagedMessageApi([
        [_m('a', 1)],
        [_m('b', 2)],
      ]);
      final s = CareSession(
        uid: 'p1',
        expertApi: const UnavailableExpertDirectoryApi(),
        applicationApi: const UnavailableApplicationApi(),
        messageApi: api,
        appointmentApi: const UnavailableAppointmentApi(),
        notificationApi: const UnavailableNotificationApi(),
      );
      final screen = Object();
      s.thread(_rel)
        ..startPolling(screen)
        ..setVisible(false, screen);
      s.thread('closed');
      s.onResume();
      await _wait(10);
      expect(api.cursors, [null, '1'], reason: 'the open thread, every page');
      s.dispose();
    });
  });

  group('LIVE-10 the thread screen drives the timer', () {
    testWidgets('top route + foreground only', (tester) async {
      final h = Mob2Harness(
        user: const KoiUser(
          uid: 'p1',
          isAnonymous: false,
          providerIds: ['password'],
          email: 'p@x',
        ),
        role: KoiRole.patient,
      )..messageApi = FakeMessageApi();
      await pumpKoi(
        tester,
        h.overrides,
        home: const MessageThreadScreen(relationshipId: _rel),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MessageThreadScreen)),
      );
      final thread = container.read(careSessionProvider).existingThread(_rel)!;
      expect(thread.isPolling, isTrue);

      // Another page on top: no polling under it.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('x')),
        ),
      );
      await settle(tester);
      expect(thread.isPolling, isFalse);
      nav.pop();
      await settle(tester);
      expect(thread.isPolling, isTrue);

      // App to the background and back.
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      expect(thread.isPolling, isFalse);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      expect(thread.isPolling, isTrue);

      // Leaving the screen stops it.
      await tester.pumpWidget(const SizedBox());
      expect(thread.isPolling, isFalse);
      await settle(tester); // lets the closed page's timers finish
    });
  });
}
