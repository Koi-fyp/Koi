import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_gate_screens.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/applications/application_models.dart';
import 'package:koi_mobile/applications/application_screens.dart';
import 'package:koi_mobile/care/become_psychologist_screen.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care_messages/message_screens.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/platform/demo_badge.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/widgets/neo_button.dart';

import '../support/mob1_fakes.dart';
import '../support/mob2_fakes.dart';
import '../support/real_fonts.dart';

// MOB-5 Care hubs (origin/feat/koi2-ui-overhaul f9ed940, mobile-native):
// Care Home for General, My Care for Patient, switched ONLY by the
// confirmed capabilities.

const _en = CareStrings.en;
const _ur = CareStrings.ur;

KoiUser _registered(String uid) => AccountFakeAuth.registered(uid, '$uid@x');

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

Finder _key(String k) => find.byKey(Key(k));

/// A registered account needs its linked secret before the shell opens.
Future<void> _start(
  WidgetTester tester,
  Mob2Harness h, {
  double width = 360,
}) async {
  await h.base.secrets.setLinkedSecret(h.auth.user!.uid, 'pw');
  await pumpKoi(tester, h.overrides, width: width);
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    )
    .position;

/// Jumps the top page's list to its end so every lazy row has been built
/// (a jump, not a drag: no pull-to-refresh).
Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final p = _position(tester);
    p.jumpTo(p.maxScrollExtent);
    await tester.pump();
  }
}

Future<void> _scrollToTop(WidgetTester tester) async {
  _position(tester).jumpTo(0);
  await tester.pump();
}

/// Every text on screen (Text and RichText), for wording checks.
List<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final t in tester.widgetList<RichText>(find.byType(RichText)))
    t.text.toPlainText(),
];

/// Only the assignment list (the hub card reads nothing else).
class _ListOnly implements QuestionnaireApi {
  _ListOnly(this.items);
  final List<Assignment> items;

  @override
  bool get isMock => false;

  @override
  Future<AssignmentPage> assignments({String? cursor}) async =>
      AssignmentPage(items, null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Assignment _assignment(String id, AssignmentState state) => Assignment(
  assignmentId: 'as-$id',
  attemptId: 'at-$id',
  versionId: 'v-$id',
  title: {'en': 'Form $id'},
  state: state,
);

const _generalOnly = [
  'care-hero',
  'care-experts',
  'care-applications',
  'care-notifications',
  'care-invitation',
  'care-become-psychologist',
];
const _patientOnly = [
  'care-psychologist',
  'care-hero-messages',
  'care-questionnaires',
  'care-messages',
  'care-appointments',
  'care-more-options',
];

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('MOB5-10 anonymous: Care is still the information page with '
      'Create account / Sign in; no hub, no Care call', (tester) async {
    final h = Mob2Harness(user: const KoiUser(uid: 'a1', isAnonymous: true));
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    expect(_key('care-anonymous'), findsOneWidget);
    expect(_key('care-home-hub'), findsNothing);
    expect(_key('my-care-hub'), findsNothing);
    expect(h.counting.fetches, 0);
  });

  testWidgets('MOB5-11 General → Care Home: Find a Psychologist, My '
      'Applications, Notifications, invitation code, Become a Psychologist; '
      'no Patient entries', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await _start(tester, h);
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);
    expect(find.text('Care Home'), findsOneWidget);
    expect(find.text('General User'), findsOneWidget);
    expect(find.text('Start your care journey'), findsOneWidget);
    expect(find.text('Find a Psychologist'), findsOneWidget);
    for (final k in _generalOnly) {
      await revealKey(tester, k);
      expect(_key(k), findsOneWidget, reason: k);
    }
    await _scrollToEnd(tester);
    for (final k in _patientOnly) {
      expect(_key(k), findsNothing, reason: k);
    }
    expect(_key('my-care-hub'), findsNothing);
    expect(_key('care-ended-notice'), findsNothing);
  });

  testWidgets('MOB5-12 Patient → My Care: My Psychologist, Questionnaires, '
      'Messages, Appointments, Notifications; General entries only under '
      '"Additional care options"', (tester) async {
    final h = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: MockQuestionnaireRemote(),
    );
    await _start(tester, h);
    await _openCare(tester);
    expect(_key('my-care-hub'), findsOneWidget);
    expect(find.text('My Care'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Your care is active'), findsOneWidget);
    expect(find.text('Demo Psychologist A'), findsOneWidget);
    expect(find.text('3 awaiting completion'), findsOneWidget);
    expect(find.text('• Placeholder form (English)'), findsOneWidget);
    for (final k in _patientOnly) {
      await revealKey(tester, k);
      expect(_key(k), findsOneWidget, reason: k);
    }
    await _scrollToEnd(tester);
    for (final k in [
      'care-experts',
      'care-applications',
      'care-invitation',
      'care-become-psychologist',
    ]) {
      expect(_key(k), findsNothing, reason: '$k collapsed');
    }
    await tapKey(tester, 'care-more-options');
    await _scrollToEnd(tester);
    for (final k in [
      'care-experts',
      'care-applications',
      'care-invitation',
      'care-become-psychologist',
    ]) {
      expect(_key(k), findsOneWidget, reason: k);
    }
    expect(find.text('Start your care journey'), findsNothing);
  });

  testWidgets('MOB5-13 General → Patient switches AUTOMATICALLY on the '
      'capability re-check (no extra tap); closure → access-ended screen → '
      'Care Home with the ended notice once', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await _start(tester, h);
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);

    h.caps.role.value = KoiRole.patient; // the server now lists a relationship
    await _resume(tester);
    expect(_key('my-care-hub'), findsOneWidget);
    expect(_key('care-home-hub'), findsNothing);

    h.backend.simulateEndRelationship();
    await _resume(tester);
    expect(find.byType(AccessEndedScreen), findsOneWidget);
    await tapKey(tester, 'access-ended-continue');
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);
    expect(_key('care-ended-notice'), findsOneWidget);
    expect(find.text(_en.t(CareText.m5Ended)), findsOneWidget);
    await tapKey(tester, 'notice-action');
    expect(_key('care-ended-notice'), findsNothing);
    await _resume(tester);
    expect(_key('care-ended-notice'), findsNothing, reason: 'once');
  });

  testWidgets('MOB5-14 Become a Psychologist is information only: no form, '
      'no website button, no capability change (General and Patient)', (
    tester,
  ) async {
    for (final role in [KoiRole.general, KoiRole.patient]) {
      final h = Mob2Harness(user: _registered('u1'), role: role);
      await _start(tester, h);
      await _openCare(tester);
      if (role == KoiRole.patient) await tapKey(tester, 'care-more-options');
      final fetches = h.counting.fetches;
      final before = h.caps.role.value;
      await tapKey(tester, 'care-become-psychologist');
      expect(find.byType(BecomePsychologistScreen), findsOneWidget);
      expect(find.text('Become a Psychologist'), findsOneWidget);
      expect(
        find.text('Professional registration is not available yet'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Psychologist accounts are created and verified on the KOI website.',
        ),
        findsOneWidget,
      );
      final page = find.byKey(const Key('become-psychologist'));
      expect(
        find.descendant(of: page, matching: find.byType(NeoButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: page, matching: find.byType(EditableText)),
        findsNothing,
      );
      expect(h.counting.fetches, fetches, reason: 'no access request');
      expect(h.caps.role.value, before);
      await _back(tester);
      expect(
        _key(role == KoiRole.patient ? 'my-care-hub' : 'care-home-hub'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('MOB5-15 Patient screens never show scores, evaluations, '
      'reviews or job state', (tester) async {
    final h = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: MockQuestionnaireRemote(),
    );
    await _start(tester, h);
    await _openCare(tester);
    final forbidden = RegExp(
      r'score|evaluat|review|job|result|severity|diagnos',
      caseSensitive: false,
    );
    Future<void> check(String where) async {
      await _scrollToEnd(tester);
      for (final t in _texts(tester)) {
        expect(forbidden.hasMatch(t), isFalse, reason: '$where: "$t"');
      }
      await _scrollToTop(tester);
    }

    await check('My Care');
    await tapKey(tester, 'care-psychologist');
    await check('My Psychologist');
    await _back(tester);
    await tapKey(tester, 'care-questionnaires');
    expect(find.byType(QuestionnaireListScreen), findsOneWidget);
    await check('Questionnaires');
  });

  testWidgets('MOB5-16 a relationship object without the server\'s patient '
      'role never opens My Care (capabilities only, default deny)', (
    tester,
  ) async {
    final h = Mob1Harness(
      user: _registered('g1'),
      caps: {
        'g1': const KoiCapabilities(
          role: KoiRole.general,
          expertDiscovery: true,
          relationship: RelationshipSummary(
            id: 'stale',
            active: true,
            psychologistDisplayName: 'Stale Psychologist',
          ),
        ),
      },
    );
    await h.secrets.setLinkedSecret('g1', 'pw');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);
    expect(_key('my-care-hub'), findsNothing);
    expect(find.text('Stale Psychologist'), findsNothing);
    expect(_key('care-psychologist'), findsNothing);
  });

  testWidgets('MOB5-17 My Applications and the detail use the web labels '
      'and helper lines; "accepted previously" for history, "care is '
      'active" only with the matching relationship', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    final apps = FakeApplicationApi()
      ..items = [
        request(
          'r1',
          'demo-expert-1',
          state: ApplicationState.pendingPsychologistReview,
        ),
        request('r2', 'demo-expert-2', state: ApplicationState.accepted),
      ];
    h.applicationApi = apps;
    await _start(tester, h);
    await _openCare(tester);
    await tapKey(tester, 'care-applications');
    expect(find.text('My Applications'), findsOneWidget);
    expect(find.text('Waiting for practice review'), findsOneWidget);
    expect(find.text('Application accepted previously'), findsOneWidget);
    await tapKey(tester, 'application-r1');
    expect(find.text(_en.t(CareText.m5PendingReviewNote)), findsOneWidget);
    await _back(tester);
    await tapKey(tester, 'application-r2');
    expect(find.text(_en.t(CareText.m5AcceptedPreviousNote)), findsOneWidget);
    expect(
      find.text('Application accepted · Your care is active'),
      findsNothing,
    );
  });

  for (final width in [320.0, 360.0]) {
    for (final urdu in [false, true]) {
      testWidgets('MOB5-18 ${width.toInt()}dp ${urdu ? 'ur' : 'en'}: both '
          'hubs (options open) and Become a Psychologist, no overflow', (
        tester,
      ) async {
        for (final role in [KoiRole.general, KoiRole.patient]) {
          final h = Mob2Harness(
            user: _registered('u1'),
            role: role,
            questionnaires: MockQuestionnaireRemote(),
          );
          if (urdu) h.urdu('u1');
          await _start(tester, h, width: width);
          await _openCare(tester);
          if (role == KoiRole.patient) {
            await tapKey(tester, 'care-more-options');
          }
          await _scrollToEnd(tester);
          expect(tester.takeException(), isNull);
          await tapKey(tester, 'care-become-psychologist');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  testWidgets('MOB5-19 48dp targets and screen-reader labels on every hub '
      'control; the options toggle reports collapsed / expanded', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final role in [KoiRole.general, KoiRole.patient]) {
      final h = Mob2Harness(
        user: _registered('u1'),
        role: role,
        questionnaires: MockQuestionnaireRemote(),
      );
      await _start(tester, h, width: 320);
      await _openCare(tester);
      if (role == KoiRole.patient) {
        await revealKey(tester, 'care-more-options');
        expect(
          tester.getSemantics(_key('care-more-options')),
          isSemantics(
            label: 'Additional care options',
            isButton: true,
            hasExpandedState: true,
            isExpanded: false,
          ),
        );
        await tapKey(tester, 'care-more-options');
        expect(
          tester.getSemantics(_key('care-more-options')),
          isSemantics(isExpanded: true),
        );
        expect(
          tester.getSemantics(_key('care-questionnaires')),
          isSemantics(
            label:
                'Questionnaires. 3 awaiting completion. '
                'Placeholder form (English). نمونہ فارم (اردو). '
                'Namoona form (Roman Urdu)',
            isButton: true,
          ),
        );
      }
      final keys = role == KoiRole.patient
          ? [..._patientOnly, ..._generalOnly.skip(1)]
          : _generalOnly.skip(1);
      for (final k in keys) {
        await revealKey(tester, k);
        await tester.ensureVisible(_key(k));
        await tester.pump();
        expect(
          tester.getSize(_key(k)).height,
          greaterThanOrEqualTo(48),
          reason: k,
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
    semantics.dispose();
  });

  testWidgets('MOB5-20 Urdu: both hubs are right-to-left with Urdu titles', (
    tester,
  ) async {
    for (final role in [KoiRole.general, KoiRole.patient]) {
      final h = Mob2Harness(user: _registered('u1'), role: role);
      h.urdu('u1');
      await _start(tester, h);
      await _openCare(tester);
      final hub = _key(
        role == KoiRole.patient ? 'my-care-hub' : 'care-home-hub',
      );
      expect(
        Directionality.of(
          tester.element(
            find.descendant(of: hub, matching: find.byType(ListView)),
          ),
        ),
        TextDirection.rtl,
      );
      expect(
        find.text(
          _ur.t(
            role == KoiRole.patient ? CareText.m5MyCare : CareText.m5CareHome,
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final role in [KoiRole.general, KoiRole.patient]) {
    testWidgets('MOB5-21 demo mode (mock source): the Demo data badge on the '
        '${role.name} hub', (tester) async {
      final h = Mob2Harness(user: _registered('u1'), role: role);
      await _start(tester, h);
      await _openCare(tester);
      expect(find.byType(DemoDataBadge), findsOneWidget);
    });
  }

  for (final caps in [generalCaps, patientCaps]) {
    testWidgets('MOB5-21 a normal (non-mock) ${caps.role.name} account: no '
        'Demo data badge and no Simulate', (tester) async {
      // g1 / p1: the MOB-1 harness has their onboarding completed.
      final uid = caps.isPatient ? 'p1' : 'g1';
      final h = Mob1Harness(user: _registered(uid), caps: {uid: caps});
      await h.secrets.setLinkedSecret(uid, 'pw');
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      expect(
        _key(caps.isPatient ? 'my-care-hub' : 'care-home-hub'),
        findsOneWidget,
      );
      if (caps.isPatient) await tapKey(tester, 'care-more-options');
      await _scrollToEnd(tester);
      expect(find.byType(DemoDataBadge), findsNothing);
      expect(_key('care-simulate'), findsNothing);
    });
  }

  testWidgets('MOB5-22 the Simulate menu shows on both hubs only when '
      'debug + KOI_MOCKS allow it (test builds: never by default)', (
    tester,
  ) async {
    for (final allowed in [true, null]) {
      for (final role in [KoiRole.general, KoiRole.patient]) {
        final h = Mob2Harness(
          user: _registered('u1'),
          role: role,
          simulateMenu: allowed,
        );
        await _start(tester, h);
        await _openCare(tester);
        await _scrollToEnd(tester);
        expect(
          _key('care-simulate'),
          allowed == true ? findsOneWidget : findsNothing,
          reason: '$role allowed=$allowed',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('MOB5-23 demo checklist: Care Home → Find a Psychologist → '
      'apply → demo step → accepted → My Care with the "care is active" '
      'label (same uid)', (tester) async {
    final h = Mob2Harness(user: _registered('g1'));
    await h.base.secrets.setLinkedSecret('g1', 'pw');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);
    await tapKey(tester, 'care-experts');
    await tapKey(tester, 'expert-demo-expert-1');
    await tapKey(tester, 'expert-apply');
    await tapKey(tester, 'apply-consent');
    await tapKey(tester, 'apply-continue');
    await tapKey(tester, 'apply-confirm-send');
    expect(find.text('Demo step required'), findsWidgets);
    await tapKey(tester, 'application-demo-payment');
    expect(find.text('Waiting for practice review'), findsWidgets);

    h.backend.simulateDecision('demo-request-demo-expert-1', accept: true);
    await _resume(tester);
    expect(
      find.text('Application accepted · Your care is active'),
      findsWidgets,
    );
    expect(find.text(_en.t(CareText.m5AcceptedActiveNote)), findsOneWidget);
    await _back(tester);
    await _back(tester);
    await _back(tester);
    expect(_key('my-care-hub'), findsOneWidget);
    expect(find.text('Demo Psychologist A'), findsOneWidget);
    expect(find.byType(DemoDataBadge), findsOneWidget);
    expect(h.auth.user?.uid, 'g1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('MOB5-24 My Psychologist: name, access line, and the two '
      'links open Messages and Appointments', (tester) async {
    final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
    await h.base.secrets.setLinkedSecret('p1', 'pw');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    await tapKey(tester, 'care-psychologist');
    expect(find.text('Demo Psychologist A'), findsOneWidget);
    expect(find.text(_en.t(CareText.m5PsyAccess)), findsOneWidget);
    await tapKey(tester, 'mypsy-messages');
    expect(find.byType(ConversationListScreen), findsOneWidget);
    await _back(tester);
    await tapKey(tester, 'mypsy-appointments');
    expect(find.text(_en.t(CareText.appointments)), findsWidgets);
    await _back(tester);
    await _back(tester);
    await tapKey(tester, 'care-hero-messages');
    expect(find.byType(ConversationListScreen), findsOneWidget);
  });

  testWidgets('MOB5-25 questionnaire card: none assigned → the web empty '
      'line; unavailable → the calm subtitle, never an error', (tester) async {
    final empty = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: MockQuestionnaireRemote(seeds: const []),
    );
    await _start(tester, empty);
    await _openCare(tester);
    await revealKey(tester, 'care-questionnaires');
    expect(find.text(_en.t(CareText.m5QEmpty)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final down = MockQuestionnaireRemote()..offline = true;
    final h = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: down,
    );
    await _start(tester, h);
    await _openCare(tester);
    await revealKey(tester, 'care-questionnaires');
    expect(
      tester.widget<Text>(_key('care-questionnaires-line')).data,
      _en.t(CareText.questionnairesSub),
    );
    expect(_key('care-error'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MOB5-26 a Patient screen open when the relationship closes is '
      'removed; nothing patient-only is rebuilt on Care Home', (tester) async {
    final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
    await h.base.secrets.setLinkedSecret('p1', 'pw');
    await pumpKoi(tester, h.overrides);
    await _openCare(tester);
    await tapKey(tester, 'care-psychologist');
    h.backend.simulateEndRelationship();
    await _resume(tester);
    await tapKey(tester, 'access-ended-continue');
    await _openCare(tester);
    expect(_key('care-home-hub'), findsOneWidget);
    expect(find.text('Demo Psychologist A'), findsNothing);
    await _scrollToEnd(tester);
    for (final k in _patientOnly) {
      expect(_key(k), findsNothing, reason: k);
    }
    expect(find.byType(MyApplicationsScreen), findsNothing);
  });

  testWidgets('MOB5-27 the questionnaire card counts only forms still to '
      'complete (submitted ones are not "awaiting")', (tester) async {
    final h = Mob2Harness(
      user: _registered('p1'),
      role: KoiRole.patient,
      questionnaires: _ListOnly([
        _assignment('1', AssignmentState.submitted),
        _assignment('2', AssignmentState.inProgress),
        _assignment('3', AssignmentState.assigned),
        _assignment('4', AssignmentState.assigned),
      ]),
    );
    await _start(tester, h);
    await _openCare(tester);
    await revealKey(tester, 'care-questionnaires');
    expect(find.text('3 awaiting completion'), findsOneWidget);
    expect(find.text('• Form 1'), findsOneWidget);
    expect(find.text('• Form 3'), findsOneWidget);
    expect(find.text('• Form 4'), findsNothing, reason: 'first three only');
  });
}
