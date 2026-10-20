import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/care_screen.dart' show CareScreen;
import 'package:koi_mobile/applications/application_api.dart';
import 'package:koi_mobile/applications/application_models.dart';
import 'package:koi_mobile/applications/application_screens.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/appointments/appointment_models.dart';
import 'package:koi_mobile/appointments/appointment_screens.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/care_messages/message_models.dart';
import 'package:koi_mobile/care_messages/message_screens.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/experts/expert_screens.dart';
import 'package:koi_mobile/notifications/notification_api.dart';
import 'package:koi_mobile/notifications/notification_models.dart';
import 'package:koi_mobile/notifications/notification_screens.dart';
import 'package:koi_mobile/platform/demo_badge.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob2_fakes.dart';
import '../support/real_fonts.dart';

const KoiUser _general = KoiUser(
  uid: 'g1',
  isAnonymous: false,
  providerIds: ['password'],
  email: 'g@x',
);
const KoiUser _patient = KoiUser(
  uid: 'p1',
  isAnonymous: false,
  providerIds: ['password'],
  email: 'p@x',
);
const String _rel = 'demo-relationship-1';

class _FakeExperts implements ExpertDirectoryApi {
  final CallScript script = CallScript();
  List<ExpertProfile> items = [];

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<ExpertProfile>> list({String? cursor}) =>
      script.run(() => ApiPage([...items], null));
  @override
  Future<ExpertProfile> detail(String id) =>
      script.run(() => items.firstWhere((e) => e.id == id));
}

/// One screen's states: loading → error + Retry → data; empty; Urdu RTL.
class _Screen {
  _Screen({
    required this.name,
    required this.user,
    required this.role,
    required this.build,
    required this.wire,
    required this.addData,
    required this.dataText,
    required this.titleEn,
    required this.titleUr,
  });

  final String name;
  final KoiUser user;
  final KoiRole role;
  final Widget Function() build;

  /// Puts the fake API into [h] and returns its list script.
  final CallScript Function(Mob2Harness h) wire;
  final void Function(Mob2Harness h) addData;
  final String dataText;
  final String titleEn;
  final String titleUr;
}

late _FakeExperts _experts;
late FakeApplicationApi _apps;
late FakeMessageApi _messages;
late FakeAppointmentApi _appointments;
late FakeNotificationApi _notifications;

Mob2Harness _harness(_Screen s) {
  _experts = _FakeExperts();
  return Mob2Harness(user: s.user, role: s.role, experts: _experts);
}

final _screens = <_Screen>[
  _Screen(
    name: 'MOB2-16 Find an Expert',
    user: _general,
    role: KoiRole.general,
    build: () => const ExpertListScreen(),
    wire: (h) => _experts.script,
    addData: (h) => _experts.items = [MockExpertDirectoryApi.profiles.first],
    dataText: 'Demo Psychologist A',
    titleEn: 'Find an Expert',
    titleUr: CareStrings.ur.t(CareText.findExpert),
  ),
  _Screen(
    name: 'MOB2-17 My applications',
    user: _general,
    role: KoiRole.general,
    build: () => const MyApplicationsScreen(),
    wire: (h) {
      h.applicationApi = _apps = FakeApplicationApi();
      return _apps.listScript;
    },
    addData: (h) => _apps.items = [
      request(
        'r1',
        'demo-expert-1',
        state: ApplicationState.awaitingDemoPayment,
      ),
    ],
    dataText: 'Waiting for demo payment',
    titleEn: 'My applications',
    titleUr: CareStrings.ur.t(CareText.myApplications),
  ),
  _Screen(
    name: 'MOB2-18 Message thread',
    user: _patient,
    role: KoiRole.patient,
    build: () => const MessageThreadScreen(relationshipId: _rel),
    wire: (h) {
      h.messageApi = _messages = FakeMessageApi();
      _experts.items = [MockExpertDirectoryApi.profiles.first]; // the name
      return _messages.listScript;
    },
    addData: (h) => _messages.byRelationship[_rel] = [
      HumanMessage(
        id: 'm1',
        relationshipId: _rel,
        senderUid: 'demo-expert-1',
        body: 'Hello from your psychologist',
        createdAt: DateTime.utc(2026, 10, 19, 8),
      ),
    ],
    dataText: 'Hello from your psychologist',
    titleEn: 'Message to Demo Psychologist A',
    titleUr: CareStrings.ur.messageTo('Demo Psychologist A'),
  ),
  _Screen(
    name: 'MOB2-19 Appointments',
    user: _patient,
    role: KoiRole.patient,
    build: () => const AppointmentListScreen(),
    wire: (h) {
      h.appointmentApi = _appointments = FakeAppointmentApi();
      return _appointments.listScript;
    },
    addData: (h) => _appointments.items = [
      appointment('a1', AppointmentState.requested, relationshipId: _rel),
    ],
    dataText: 'Pending',
    titleEn: 'Appointments',
    titleUr: CareStrings.ur.t(CareText.appointments),
  ),
  _Screen(
    name: 'MOB2-20 Notifications',
    user: _general,
    role: KoiRole.general,
    build: () => const NotificationInboxScreen(),
    wire: (h) {
      h.notificationApi = _notifications = FakeNotificationApi();
      return _notifications.listScript;
    },
    addData: (h) => _notifications.items = [
      note('n1', NotificationKind.applicationState, 'r1'),
    ],
    dataText: 'Your application was updated',
    titleEn: 'Notifications',
    titleUr: CareStrings.ur.t(CareText.notifications),
  ),
];

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final s in _screens) {
    group(s.name, () {
      testWidgets('loading → error + Retry → data', (tester) async {
        final h = _harness(s);
        final script = s.wire(h);
        script.gate = Completer<void>();
        await pumpKoi(tester, h.overrides, home: s.build());
        expect(
          find.byType(NeoSkeletonList).evaluate().isNotEmpty ||
              find.byType(KoiLoader).evaluate().isNotEmpty,
          isTrue,
          reason: 'KoiLoader / skeleton while loading',
        );
        script.error = offlineError;
        script.gate!.complete();
        script.gate = null;
        await settle(tester);
        expect(find.byKey(const Key('care-error')), findsOneWidget);
        expect(find.text(CareStrings.en.t(CareText.offline)), findsOneWidget);
        script.error = null;
        s.addData(h);
        await tapKey(tester, 'notice-action'); // Retry
        expect(find.text(s.dataText), findsWidgets);
        expect(find.text(s.titleEn), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets('empty', (tester) async {
        final h = _harness(s);
        s.wire(h);
        await pumpKoi(tester, h.overrides, home: s.build());
        expect(find.byKey(const Key('care-empty')), findsOneWidget);
      });
      testWidgets('Urdu: right-to-left with Urdu text', (tester) async {
        final h = _harness(s);
        s.wire(h);
        s.addData(h);
        h.urdu(s.user.uid);
        await pumpKoi(tester, h.overrides, home: s.build());
        final title = find.text(s.titleUr);
        expect(title, findsOneWidget);
        expect(Directionality.of(tester.element(title)), TextDirection.rtl);
        expect(tester.takeException(), isNull, reason: 'no overflow at 360dp');
      });
    });
  }

  group(
    'MOB2-21 endpoint missing / not configured → calm "Not available yet"',
    () {
      testWidgets('no fake data, no Retry, no crash', (tester) async {
        final h = Mob2Harness(user: _patient, role: KoiRole.patient)
          ..notificationApi = const UnavailableNotificationApi()
          ..appointmentApi = const UnavailableAppointmentApi()
          ..messageApi = const UnavailableCareMessageApi()
          ..applicationApi = const UnavailableApplicationApi();
        for (final screen in <Widget>[
          const NotificationInboxScreen(),
          const AppointmentListScreen(),
          const MessageThreadScreen(relationshipId: _rel),
          const MyApplicationsScreen(),
        ]) {
          await pumpKoi(tester, h.overrides, home: screen);
          expect(
            find.byKey(const Key('care-not-available')),
            findsOneWidget,
            reason: '$screen',
          );
          expect(
            find.text(CareStrings.en.t(CareText.notAvailableYet)),
            findsOneWidget,
          );
          expect(find.byKey(const Key('notice-action')), findsNothing);
          expect(find.byType(DemoDataBadge), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
      testWidgets('a route the server does not have yet (404 without a '
          'contract body) also reads "Not available yet"', (tester) async {
        final h = Mob2Harness(user: _general);
        final api = _notifications = FakeNotificationApi();
        api.listScript.error = const PlatformException(
          PlatformErrorCode.notFound,
          status: 404,
        );
        h.notificationApi = api;
        await pumpKoi(
          tester,
          h.overrides,
          home: const NotificationInboxScreen(),
        );
        expect(find.byKey(const Key('care-not-available')), findsOneWidget);
      });
    },
  );

  group('MOB2-23 "Demo data" badge whenever an adapter is a mock', () {
    testWidgets('mock adapters → badge; real adapters → none', (tester) async {
      final mocked = Mob2Harness(user: _patient, role: KoiRole.patient);
      for (final screen in <Widget>[
        const NotificationInboxScreen(),
        const AppointmentListScreen(),
        const MessageThreadScreen(relationshipId: _rel),
        const MyApplicationsScreen(),
        const ConversationListScreen(),
      ]) {
        await pumpKoi(tester, mocked.overrides, home: screen);
        expect(find.byType(DemoDataBadge), findsOneWidget, reason: '$screen');
      }
      final real = Mob2Harness(user: _general)
        ..notificationApi = FakeNotificationApi();
      await pumpKoi(
        tester,
        real.overrides,
        home: const NotificationInboxScreen(),
      );
      expect(find.byType(DemoDataBadge), findsNothing);
    });
  });

  group('MOB2-24 notification bell in the top bar', () {
    Future<Mob2Harness> shell(
      WidgetTester tester, {
      required double width,
      int unread = 0,
      KoiUser user = _general,
    }) async {
      final h = Mob2Harness(user: user);
      await h.base.secrets.setLinkedSecret(user.uid, 'pw');
      final api = _notifications = FakeNotificationApi()
        ..items = [
          for (var i = 0; i < unread; i++)
            note('n$i', NotificationKind.applicationState, 'r$i'),
        ];
      h.notificationApi = api;
      await pumpKoi(tester, h.overrides, width: width);
      return h;
    }

    for (final width in [360.0, 320.0]) {
      testWidgets('fits at ${width.toInt()}dp; existing nav items unchanged', (
        tester,
      ) async {
        await shell(tester, width: width, unread: 12);
        expect(find.byKey(const Key('nav-bell')), findsOneWidget);
        for (final t in ['chat', 'progress', 'care', 'settings']) {
          expect(navTab(t), findsOneWidget, reason: t);
        }
        expect(find.byKey(const Key('mode-selector-button')), findsOneWidget);
        expect(find.byKey(const Key('nav-logo')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        final bell = tester.getSize(find.byKey(const Key('nav-bell')));
        expect(bell.width, greaterThanOrEqualTo(48));
        if (width < 340) {
          expect(find.byKey(const Key('nav-bell-dot')), findsOneWidget);
          expect(find.byKey(const Key('nav-bell-badge')), findsNothing);
        } else {
          expect(find.text('9+'), findsOneWidget);
        }
        expect(
          find.bySemanticsLabel('Notifications, 12 unread'),
          findsOneWidget,
        );
      });
    }
    // AUTH-ENTRY (approved 2026-10-20): anonymous users now get the Care
    // tab as an information page only.
    testWidgets('anonymous: no bell, Care tab = info page, no fetches', (
      tester,
    ) async {
      final h = Mob2Harness(user: const KoiUser(uid: 'u1', isAnonymous: true));
      await pumpKoi(tester, h.overrides);
      expect(find.byKey(const Key('nav-bell')), findsNothing);
      await tester.tap(navTab('care'));
      await settle(tester);
      expect(find.byKey(const Key('care-anonymous')), findsOneWidget);
      expect(find.byType(CareScreen), findsNothing);
      expect(find.byKey(const Key('nav-bell')), findsNothing);
      expect(h.counting.fetches, 0);
    });
    testWidgets('tapping the bell opens the inbox inside the Care tab', (
      tester,
    ) async {
      await shell(tester, width: 360, unread: 1);
      await tapKey(tester, 'nav-bell');
      expect(find.byType(NotificationInboxScreen), findsOneWidget);
      expect(
        find.byKey(const Key('nav-pill-tabs')),
        findsOneWidget,
        reason: 'the top nav stays',
      );
    });
  });
}
