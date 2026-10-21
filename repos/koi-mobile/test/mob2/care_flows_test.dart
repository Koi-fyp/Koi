import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_gate_screens.dart';
import 'package:koi_mobile/account/account_providers.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/account/destinations.dart';
import 'package:koi_mobile/applications/application_screens.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/appointments/appointment_models.dart';
import 'package:koi_mobile/appointments/appointment_screens.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care/care_widgets.dart';
import 'package:koi_mobile/care_messages/message_screens.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/experts/expert_screens.dart';
import 'package:koi_mobile/notifications/notification_models.dart';
import 'package:koi_mobile/notifications/notification_screens.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/safety/safety_host.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob1_fakes.dart';
import '../support/mob2_fakes.dart';
import '../support/real_fonts.dart';

KoiUser _registered(String uid) => AccountFakeAuth.registered(uid, '$uid@x');

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<void> _openCare(WidgetTester tester) async {
  await tester.tap(navTab('care'));
  await settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('koi-back')).last);
  await settle(tester);
}

Future<void> _resume(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await settle(tester, 10);
}

/// Encrypted KOI history + check-ins + secrets of [uid], to prove they are
/// byte-for-byte unchanged.
Future<void> _seedPrivateKoi(Mob2Harness h, String uid) async {
  await h.base.secrets.setLinkedSecret(uid, 'pw');
  h.auth.accounts['$uid@x'] = (uid, 'pw');
  for (var i = 0; i < 3; i++) {
    await h.base.messages.put(
      MessageRecord(
        id: '$uid-m$i',
        conversationId: uid,
        sender: i.isEven ? 'user' : 'ai',
        content: await h.base.cipher.encrypt('private $i', 'pw', 'salt-$uid'),
        timestamp: DateTime.utc(2026, 10, 18, 9, i),
        emotion: Emotion.calm,
        emotionConfidence: 0.5,
        synced: false,
      ),
    );
  }
  await h.base.checkIns.put('${uid}_2026-10-18_morning', 'v1:SEC:checkin');
}

String _snapshot(Mob2Harness h) => jsonEncode({
  'messages': [for (final r in h.base.messages.rows.values) r.toJson()],
  'checkIns': h.base.checkIns.rows,
  'secrets': h.base.secureKv.values,
});

Future<void> _apply(WidgetTester tester) async {
  await tapKey(tester, 'care-experts');
  await tapKey(tester, 'expert-demo-expert-1');
  await tapKey(tester, 'expert-apply');
  await tapKey(tester, 'apply-consent');
  await tapKey(tester, 'apply-continue');
  await tapKey(tester, 'apply-confirm-send');
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('MOB2-25 apply: consent + confirm, simulated payment, '
      'duplicate blocked, withdraw', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await _seedPrivateKoi(h, 'g1');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    await tapKey(tester, 'care-experts');
    await tapKey(tester, 'expert-demo-expert-1');
    await tapKey(tester, 'expert-apply');

    // No consent → nothing is sent.
    await tapKey(tester, 'apply-continue');
    expect(find.text(CareStrings.en.t(CareText.consentNeeded)), findsOneWidget);
    expect(find.byKey(const Key('apply-confirm-send')), findsNothing);

    await tapKey(tester, 'apply-consent');
    await tapKey(tester, 'apply-continue');
    expect(find.text(CareStrings.en.t(CareText.confirmTitle)), findsOneWidget);
    await tapKey(tester, 'apply-confirm-send');

    expect(find.byType(ApplicationDetailScreen), findsOneWidget);
    expect(
      find.text(CareStrings.en.t(CareText.stateAwaitingPayment)),
      findsWidgets,
    );
    expect(find.text('Payment: Pending (simulated)'), findsOneWidget);
    expect(
      find.byType(EditableText),
      findsNothing,
      reason: 'no card fields, nothing that looks like a checkout',
    );
    await tapKey(tester, 'application-demo-payment');
    expect(
      find.text(CareStrings.en.t(CareText.statePendingReview)),
      findsWidgets,
    );
    expect(find.text('Payment: Confirmed (simulated)'), findsOneWidget);
    expect(find.byKey(const Key('application-demo-payment')), findsNothing);

    // Back on the profile: a second application is blocked kindly.
    await _back(tester);
    expect(find.byKey(const Key('expert-active-application')), findsOneWidget);
    expect(find.byKey(const Key('expert-apply')), findsNothing);

    // Withdraw (confirmation dialog), then no more actions.
    await tapKey(tester, 'notice-action');
    await tapKey(tester, 'application-withdraw');
    expect(find.text(CareStrings.en.t(CareText.withdrawTitle)), findsOneWidget);
    await tapKey(tester, 'withdraw-confirm');
    expect(find.text(CareStrings.en.t(CareText.stateWithdrawn)), findsWidgets);
    expect(find.byKey(const Key('application-withdraw')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('MOB2-26 recent-sign-in 401 opens the re-check, never revocation', () {
    testWidgets('re-check then the SAME call is retried', (tester) async {
      final h = Mob2Harness(user: _registered('g1'));
      await _seedPrivateKoi(h, 'g1');
      final apps = FakeApplicationApi()..mutateScript.errorOnce = reauthError;
      h.applicationApi = apps;
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      final fetchesBefore = h.counting.fetches;
      await _apply(tester);

      expect(find.byKey(const Key('care-reauth')), findsOneWidget);
      expect(find.byType(ApplyScreen), findsOneWidget, reason: 'still there');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('care-reauth-password')),
          matching: find.byType(EditableText),
        ),
        'wrong',
      );
      await tapKey(tester, 'care-reauth-confirm');
      expect(find.text(CareStrings.en.t(CareText.reauthWrong)), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('care-reauth-password')),
          matching: find.byType(EditableText),
        ),
        'pw',
      );
      await tapKey(tester, 'care-reauth-confirm');

      expect(find.byType(ApplicationDetailScreen), findsOneWidget);
      expect(apps.keys[0], apps.keys[1], reason: 'same Idempotency-Key');
      expect(
        h.counting.fetches,
        fetchesBefore,
        reason: 'no capability re-check',
      );
      expect(find.byType(AccessEndedScreen), findsNothing);
      expect(navTab('care'), findsOneWidget);
    });
    testWidgets('cancelling the re-check keeps every screen visible', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('g1'));
      await _seedPrivateKoi(h, 'g1');
      final apps = FakeApplicationApi()..mutateScript.error = reauthError;
      h.applicationApi = apps;
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      final fetchesBefore = h.counting.fetches;
      await _apply(tester);
      await tapKey(tester, 'care-reauth-cancel');

      expect(find.byType(ApplyScreen), findsOneWidget);
      expect(find.byKey(const Key('koi-error')), findsOneWidget);
      expect(find.byKey(const Key('capability-denied')), findsNothing);
      expect(find.byType(AccessEndedScreen), findsNothing);
      expect(navTab('care'), findsOneWidget);
      expect(h.counting.fetches, fetchesBefore);
      final caps = _container(tester).read(capabilityControllerProvider);
      expect(caps.status, CapabilityStatus.ready);
      expect(caps.accessEnded, isFalse);
      expect(caps.effective.canDiscoverExperts, isTrue);
    });
  });

  testWidgets('MOB2-27 General applies → accepted → Patient Care appears '
      '(same uid, no sign-out), private KOI data unchanged', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await _seedPrivateKoi(h, 'g1');
    final before = _snapshot(h);
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    expect(find.byKey(const Key('care-messages')), findsNothing);
    await _apply(tester);
    await tapKey(tester, 'application-demo-payment');

    // The psychologist accepts on the server; the app learns it on resume.
    h.backend.simulateDecision('demo-request-demo-expert-1', accept: true);
    await _resume(tester);
    expect(find.text(CareStrings.en.t(CareText.stateAccepted)), findsWidgets);
    await _back(tester);
    await _back(tester);
    await _back(tester);
    expect(find.byKey(const Key('care-psychologist')), findsOneWidget);
    expect(find.byKey(const Key('care-messages')), findsOneWidget);
    expect(find.byKey(const Key('care-appointments')), findsOneWidget);
    expect(find.text('Demo Psychologist A'), findsOneWidget);
    expect(h.auth.user?.uid, 'g1', reason: 'same account');
    expect(find.byType(AccessEndedScreen), findsNothing);
    expect(_snapshot(h), before, reason: 'chat, check-ins, secrets unchanged');
  });

  testWidgets('MOB2-28 relationship closure: Patient screens gone, caches '
      'and drafts cleared, calm notice, KOI chat intact', (tester) async {
    final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
    await _seedPrivateKoi(h, 'p1');
    await h.base.drafts.put(DraftRepository.keyFor('p1', 'att-1'), '{}');
    final before = _snapshot(h);
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    await tapKey(tester, 'care-messages');
    await tapKey(tester, 'conversation-demo-relationship-1');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('thread-composer')),
        matching: find.byType(EditableText),
      ),
      'hello',
    );
    await tapKey(tester, 'thread-send');
    expect(find.text('hello'), findsOneWidget);
    final session = _container(tester).read(careSessionProvider);
    expect(session.hasPatientData, isTrue);

    // The psychologist ends the relationship while the thread is open.
    h.backend.simulateEndRelationship();
    await _resume(tester);
    expect(find.byType(AccessEndedScreen), findsOneWidget);
    expect(find.text('Your care relationship has ended'), findsOneWidget);
    expect(find.byType(MessageThreadScreen), findsNothing);
    expect(session.hasPatientData, isFalse, reason: 'messages etc. cleared');
    expect(h.base.drafts.rows, isEmpty, reason: 'questionnaire drafts gone');
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'access-ended-continue');
    expect(find.byType(AppShell), findsOneWidget);
    await _openCare(tester);
    expect(find.byKey(const Key('care-messages')), findsNothing);
    expect(find.byKey(const Key('care-experts')), findsOneWidget);
    expect(_snapshot(h), before, reason: 'KOI chat fully intact');
  });

  testWidgets('MOB2-29 a screen whose access is removed while open is '
      'popped safely, with a calm notice', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    final nav = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const MyApplicationsScreen()),
    );
    await settle(tester);
    expect(find.byType(MyApplicationsScreen), findsOneWidget);

    h.caps.role.value = KoiRole.anonymous; // the server: no discovery now
    unawaited(
      _container(tester)
          .read(capabilityControllerProvider)
          .refresh(silent: true),
    );
    await settle(tester, 15);
    expect(find.byType(MyApplicationsScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(
      _container(tester).read(careSessionProvider).notice,
      CareText.noLongerAvailable,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MOB2-30 account switch / sign-out: nothing leaks between '
      'accounts', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await _seedPrivateKoi(h, 'g1');
    await h.base.secrets.setLinkedSecret('u2', 'pw2');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    await _apply(tester);
    final first = _container(tester).read(careSessionProvider);
    expect(first.applications.items, hasLength(1));

    h.auth.set(user: _registered('u2'));
    await settle(tester);
    final second = _container(tester).read(careSessionProvider);
    expect(identical(first, second), isFalse, reason: 'new session per uid');
    expect(second.uid, 'u2');
    expect(second.applications.items, isEmpty);
    expect(find.byType(ApplicationDetailScreen), findsNothing);
    await _openCare(tester);
    await tapKey(tester, 'care-applications');
    expect(find.byKey(const Key('care-empty')), findsOneWidget);
    expect(
      find.text(CareStrings.en.t(CareText.stateAwaitingPayment)),
      findsNothing,
    );

    h.auth.set(user: null);
    await settle(tester);
    expect(_container(tester).read(careSessionProvider).uid, '');
  });

  testWidgets('MOB2-31 403 from a care endpoint: one capability re-check, '
      'never a loop; still denied → screens removed + notice', (tester) async {
    // MOB-5: questionnaires from the demo source, so only the appointment
    // call gets the 403 (the My Care hub now loads the assignments).
    final h = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: MockQuestionnaireRemote(),
    );
    await _seedPrivateKoi(h, 'p1');
    final t = RecordingTransport(
      (_, _) => const PlatformHttpResponse(
        403,
        '{"code":"forbidden","request_id":"r","retryable":false}',
      ),
    );
    final client = recordingClient(t);
    h.appointmentApi = HttpAppointmentApi(client);
    await pumpKoi(tester, [
      ...h.overrides,
      platformClientProvider.overrideWithValue(client),
    ]);
    await _openCare(tester);
    final fetches = h.counting.fetches;
    await tapKey(tester, 'care-appointments');
    await settle(tester, 30);
    expect(h.counting.fetches, fetches + 1, reason: 'exactly one re-check');
    final calls = t.requests.length;
    await settle(tester, 30);
    expect(t.requests.length, calls, reason: 'no request loop');
    expect(find.byKey(const Key('care-error')), findsOneWidget);
    expect(
      find.text(CareStrings.en.t(CareText.noLongerAvailable)),
      findsOneWidget,
    );

    // The server really ended it: the re-check removes the Patient area.
    h.caps.role.value = KoiRole.general;
    unawaited(_container(tester).read(capabilityControllerProvider).refresh());
    await settle(tester);
    expect(find.byType(AccessEndedScreen), findsOneWidget);
    expect(find.byType(AppointmentListScreen), findsNothing);
  });

  group('MOB2-32 notification deep links (re-checked on tap)', () {
    test('targets per kind; revoked target → no page', () {
      KoiDestination? d(NotificationKind k, KoiCapabilities caps) {
        final t = notificationTarget(
          note('n', k, 'ref'),
          status: CapabilityStatus.ready,
          caps: caps,
        );
        return t.page == null ? null : t.destination;
      }

      expect(
        d(NotificationKind.assignment, contractPatientCaps),
        KoiDestination.questionnaires,
      );
      expect(
        d(NotificationKind.newMessage, contractPatientCaps),
        KoiDestination.messageThread,
      );
      expect(
        d(NotificationKind.appointmentChange, contractPatientCaps),
        KoiDestination.appointment,
      );
      expect(
        d(NotificationKind.applicationState, generalCaps),
        KoiDestination.application,
      );
      for (final k in [
        NotificationKind.assignment,
        NotificationKind.newMessage,
        NotificationKind.appointmentChange,
      ]) {
        expect(d(k, generalCaps), isNull, reason: 'revoked: $k');
      }
      expect(
        d(NotificationKind.applicationState, KoiCapabilities.none),
        isNull,
      );
    });
    testWidgets('tap opens the right screen, or a friendly message', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('g1'));
      final api = FakeNotificationApi()
        ..items = [
          note('a', NotificationKind.applicationState, 'r1'),
          note('m', NotificationKind.newMessage, 'msg-1'),
        ];
      h.notificationApi = api;
      h.applicationApi = FakeApplicationApi()
        ..items = [request('r1', 'demo-expert-1')];
      await pumpKoi(tester, h.overrides, home: const NotificationInboxScreen());
      await tapKey(tester, 'notification-m');
      expect(
        find.byKey(const Key('notification-notice')),
        findsOneWidget,
        reason: 'a General user: the thread is not accessible',
      );
      expect(find.byType(MessageThreadScreen), findsNothing);
      await tapKey(tester, 'notification-a');
      expect(find.byType(ApplicationDetailScreen), findsOneWidget);
      expect(api.items.every((n) => n.isRead), isTrue, reason: 'marked read');
    });
    testWidgets('mark all as read → unread badge gone', (tester) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      final api = FakeNotificationApi()
        ..items = [
          note('1', NotificationKind.assignment, 'x'),
          note('2', NotificationKind.appointmentChange, 'y'),
        ];
      h.notificationApi = api;
      await pumpKoi(tester, h.overrides, home: const NotificationInboxScreen());
      expect(
        find.byKey(const Key('notification-unread-dot')),
        findsNWidgets(2),
      );
      await tapKey(tester, 'notifications-mark-all');
      expect(find.byKey(const Key('notification-unread-dot')), findsNothing);
      expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
    });
    testWidgets('assignment opens the questionnaire list', (tester) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      h.notificationApi = FakeNotificationApi()
        ..items = [note('q', NotificationKind.assignment, 'as-1')];
      await pumpKoi(tester, h.overrides, home: const NotificationInboxScreen());
      await tapKey(tester, 'notification-q');
      expect(find.byType(QuestionnaireListScreen), findsOneWidget);
    });
  });

  group(
    'MOB2-33 professional messages are separate from the KOI companion',
    () {
      test('lib/care_messages imports no companion chat, avatar, voice, '
          'safety or environment code', () {
        final banned = RegExp(
          r"import '\.\./(chat|avatar|voice|voice_input|safety|environment|camera|modes)/",
        );
        for (final f in Directory(
          'lib/care_messages',
        ).listSync().whereType<File>()) {
          for (final line in f.readAsLinesSync()) {
            expect(banned.hasMatch(line), isFalse, reason: '${f.path}: $line');
          }
        }
      });
      testWidgets('a professional message never reaches /api/v1/chat', (
        tester,
      ) async {
        final chatCalls = <Uri>[];
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, handler) {
                chatCalls.add(o.uri);
                handler.reject(DioException(requestOptions: o));
              },
            ),
          );
        final h = Mob2Harness(
          user: _registered('p1'),
          role: KoiRole.patient,
          chatApi: ChatApiClient(baseUrl: 'https://chat.test', dio: dio),
        );
        final messages = FakeMessageApi();
        h.messageApi = messages;
        await pumpKoi(
          tester,
          h.overrides,
          home: const MessageThreadScreen(
            relationshipId: 'demo-relationship-1',
          ),
        );
        expect(find.text('Message to Demo Psychologist A'), findsOneWidget);
        expect(
          find.byKey(const Key('professional-message-label')),
          findsOneWidget,
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('thread-composer')),
            matching: find.byType(EditableText),
          ),
          'I feel low today',
        );
        await tapKey(tester, 'thread-send');
        expect(messages.sentKeys, hasLength(1));
        expect(chatCalls, isEmpty, reason: 'nothing sent to the AI');
      });
    },
  );

  group('MOB2-34 thread safety footer; the KOI crisis path is unchanged', () {
    testWidgets('static 1166 footer; SafetyHost still wraps the shell', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      await _seedPrivateKoi(h, 'p1');
      await pumpKoi(tester, h.overrides);
      expect(find.byType(SafetyHost), findsOneWidget);
      await _openCare(tester);
      await tapKey(tester, 'care-messages');
      await tapKey(tester, 'conversation-demo-relationship-1');
      final footer = tester.widget<Text>(
        find.byKey(const Key('thread-safety-footer')),
      );
      expect(footer.data, contains('1166'));
      expect(find.byType(SafetyHost), findsOneWidget);
    });
  });

  group('MOB2-35 appointments: server state only, dialogs, no actions when '
      'final', () {
    testWidgets('request → propose → confirm → ask another → cancel', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      await pumpKoi(tester, h.overrides, home: const AppointmentListScreen());
      await tapKey(tester, 'appointment-request');
      expect(find.text('Requested'), findsOneWidget);
      expect(
        find.byKey(const Key('appointment-section-pending')),
        findsOneWidget,
      );

      h.backend.simulateProposeTime();
      await tester.tap(find.byType(CareCard).first);
      await settle(tester);
      expect(find.text('Time proposed'), findsOneWidget);
      await tapKey(tester, 'appointment-confirm');
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byKey(const Key('appointment-confirm')), findsNothing);

      await tapKey(tester, 'appointment-ask-another');
      await tapKey(tester, 'appointment-ask-confirm');
      final list = _container(tester)
          .read(careSessionProvider)
          .appointmentsFor('demo-relationship-1');
      expect(list.items, hasLength(2), reason: 'a NEW request');
      expect(find.text('Confirmed'), findsOneWidget, reason: 'old one stays');

      await tapKey(tester, 'appointment-cancel');
      expect(find.text(CareStrings.en.t(CareText.cancelTitle)), findsOneWidget);
      await tapKey(tester, 'appointment-cancel-confirm');
      expect(find.text('Cancelled'), findsOneWidget);
      for (final k in [
        'appointment-confirm',
        'appointment-cancel',
        'appointment-ask-another',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });
    testWidgets('while the server is answering: KoiLoader, old state shown', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      final api = FakeAppointmentApi()
        ..items = [
          appointment(
            'a1',
            AppointmentState.proposed,
            relationshipId: 'demo-relationship-1',
            start: DateTime.utc(2026, 10, 21, 5),
          ),
        ];
      h.appointmentApi = api;
      await pumpKoi(
        tester,
        h.overrides,
        home: const AppointmentDetailScreen(
          relationshipId: 'demo-relationship-1',
          appointmentId: 'a1',
        ),
      );
      final gate = api.mutateScript.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('appointment-confirm')));
      await settle(tester, 2);
      expect(find.byType(KoiLoader), findsWidgets);
      expect(
        find.text('Time proposed'),
        findsOneWidget,
        reason: 'not optimistic',
      );
      expect(find.text('Confirmed'), findsNothing);
      gate.complete();
      await settle(tester);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(api.calls, ['confirmed:a1']);
    });
  });

  group('MOB2-36 anonymous can never reach Care / MOB-2 screens', () {
    test('router guard: every MOB-2 destination asks to sign in', () {
      for (final d in [
        KoiDestination.experts,
        KoiDestination.applications,
        KoiDestination.application,
        KoiDestination.messages,
        KoiDestination.messageThread,
        KoiDestination.appointments,
        KoiDestination.appointment,
        KoiDestination.notifications,
      ]) {
        expect(
          decideDestination(
            d,
            status: CapabilityStatus.anonymous,
            caps: contractPatientCaps,
          ),
          LinkDecision.signIn,
          reason: '$d',
        );
      }
      expect(
        parseKoiLink(Uri.parse('koi://care/messages/r1')).destination,
        KoiDestination.messageThread,
      );
      expect(
        parseKoiLink(Uri.parse('koi://care/applications/x')).destination,
        KoiDestination.application,
      );
    });
    testWidgets('capability gate on every screen', (tester) async {
      final h = Mob2Harness(user: const KoiUser(uid: 'u1', isAnonymous: true));
      for (final screen in <Widget>[
        const ExpertListScreen(),
        const MyApplicationsScreen(),
        const ConversationListScreen(),
        const MessageThreadScreen(relationshipId: 'r'),
        const AppointmentListScreen(),
        const NotificationInboxScreen(),
      ]) {
        await pumpKoi(tester, h.overrides, home: screen);
        expect(
          find.byKey(const Key('capability-denied')),
          findsOneWidget,
          reason: '$screen',
        );
      }
      expect(h.counting.fetches, 0, reason: 'never fetched for anonymous');
    });
  });

  group('MOB2-37 Patient switch-over also on pull-to-refresh and on an '
      'application notification', () {
    testWidgets('pull-to-refresh on Care', (tester) async {
      final h = Mob2Harness(user: _registered('g1'));
      await _seedPrivateKoi(h, 'g1');
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      expect(find.byKey(const Key('care-messages')), findsNothing);
      h.caps.role.value = KoiRole.patient; // accepted on the server
      await tester.fling(
        find.byKey(const Key('care-experts')),
        const Offset(0, 400),
        1000,
      );
      await settle(tester, 12);
      expect(find.byKey(const Key('care-messages')), findsOneWidget);
      expect(h.auth.user?.uid, 'g1');
    });
    testWidgets('the debug-only simulate menu accepts; the application '
        'notification turns on the Patient area', (tester) async {
      final h = Mob2Harness(user: _registered('g1'), simulateMenu: true);
      await _seedPrivateKoi(h, 'g1');
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      await _apply(tester);
      await tapKey(tester, 'application-demo-payment');
      await _back(tester);
      await _back(tester);
      await _back(tester);
      await tapKey(tester, 'care-simulate');
      await tapKey(tester, 'simulate-accept-demo-request-demo-expert-1');
      await settle(tester, 12);
      expect(find.byKey(const Key('care-messages')), findsOneWidget);
      expect(find.byKey(const Key('nav-bell-badge')), findsOneWidget);
    });
  });

  group('MOB2-15 simulate menu absent unless kDebugMode AND KOI_MOCKS', () {
    testWidgets('Care home without the flag (tests have no KOI_MOCKS)', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('g1'));
      await _seedPrivateKoi(h, 'g1');
      await pumpKoi(tester, h.overrides); // real provider: no override
      await _openCare(tester);
      expect(find.byKey(const Key('care-simulate')), findsNothing);
    });
  });
}
