import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_gate_screens.dart';
import 'package:koi_mobile/account/care_screen.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/platform/demo_badge.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob1_fakes.dart';
import '../support/real_fonts.dart';

Future<void> pumpApp(WidgetTester tester, Mob1Harness h) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3; // 360 x 800 dp
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: const MaterialApp(home: RootRouter()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _tab(String name) => find.byKey(Key('nav-tab-$name'));

Future<void> _openCare(WidgetTester tester) async {
  await tester.tap(_tab('care'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'MOB1-07 anonymous: existing KOI + Sign in / Create account only',
    (tester) async {
      final h = Mob1Harness(
        user: const KoiUser(uid: 'u1', isAnonymous: true),
        caps: {'u1': patientCaps}, // must be ignored: isAnonymous
      );
      await pumpApp(tester, h);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(_tab('care'), findsNothing);
      expect(h.source.fetches, 0);
      await tester.tap(_tab('settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('row-create-account')), findsOneWidget);
      expect(find.byKey(const Key('row-sign-in')), findsOneWidget);
      expect(find.byKey(const Key('row-sign-out')), findsNothing);
      expect(
        find.byKey(const Key('row-demo-role')),
        findsNothing,
        reason: 'MOB1-38: role picker needs debug AND KOI_MOCKS',
      );
    },
  );

  testWidgets(
    'MOB1-07b anonymous opening a protected screen directly sees nothing',
    (tester) async {
      final h = Mob1Harness(user: const KoiUser(uid: 'u1', isAnonymous: true));
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: const MaterialApp(home: QuestionnaireListScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('capability-denied')), findsOneWidget);
      expect(find.text('Questionnaires'), findsNothing);
    },
  );

  testWidgets(
    'MOB1-03b capability check shows the loader, then the shell (no tab flash)',
    (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('g1', 'g@x'),
        caps: {'g1': generalCaps},
      );
      await h.secrets.setLinkedSecret('g1', 'pw');
      h.source.gate = Completer<void>();
      await pumpApp(tester, h);
      expect(find.byType(CapabilityCheckScreen), findsOneWidget);
      expect(find.byType(KoiLoader), findsOneWidget);
      expect(
        find.bySemanticsLabel(CapabilityCheckScreen.label),
        findsOneWidget,
      );
      expect(_tab('care'), findsNothing);
      expect(find.byType(AppShell), findsNothing);
      h.source.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byType(KoiLoader),
        findsNothing,
        reason: 'loader gone afterwards',
      );
      expect(_tab('care'), findsOneWidget);
    },
  );

  testWidgets('MOB1-08 general: Care = Find an Expert only (read-only list)', (
    tester,
  ) async {
    final h = Mob1Harness(
      user: AccountFakeAuth.registered('g1', 'g@x'),
      caps: {'g1': generalCaps},
      experts: MockExpertDirectoryApi(latency: const Duration(seconds: 2)),
    );
    await h.secrets.setLinkedSecret('g1', 'pw');
    await pumpApp(tester, h);
    await _openCare(tester);
    expect(find.byKey(const Key('care-experts')), findsOneWidget);
    expect(find.byKey(const Key('care-questionnaires')), findsNothing);
    expect(find.byKey(const Key('care-psychologist')), findsNothing);
    expect(find.byKey(const Key('care-messages')), findsNothing);
    await tester.tap(find.byKey(const Key('care-experts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byKey(const Key('neo-skeleton')),
      findsOneWidget,
      reason: 'list loading',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('neo-skeleton')), findsNothing);
    expect(find.text('Demo Psychologist A'), findsOneWidget);
    expect(find.byType(DemoDataBadge), findsOneWidget, reason: 'mock adapter');
  });

  testWidgets(
    'MOB1-09 patient: My Psychologist, Questionnaires, later-update entries',
    (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('p1', 'p@x'),
        caps: {'p1': patientCaps},
        questionnaires: MockQuestionnaireRemote(),
      );
      await h.secrets.setLinkedSecret('p1', 'pw');
      await pumpApp(tester, h);
      await _openCare(tester);
      expect(find.text('Test Psychologist'), findsOneWidget);
      expect(find.byKey(const Key('care-questionnaires')), findsOneWidget);
      for (final k in [
        'care-messages',
        'care-appointments',
        'care-notifications',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget);
      }
      expect(find.text(CareScreen.comingLater), findsNWidgets(3));
    },
  );

  testWidgets(
    'MOB1-10 psychologist: landing only, never companion or patient screens',
    (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('psy', 'd@x'),
        caps: {'psy': psychologistCaps},
      );
      await pumpApp(tester, h);
      expect(find.byType(PsychologistLandingScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.byType(ChatScreen), findsNothing);
      expect(
        find.byKey(const Key('pro-portal')),
        findsNothing,
        reason: 'URL unset → hidden',
      );
      expect(find.byKey(const Key('pro-sign-out')), findsOneWidget);

      final opened = <Uri>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp(
            home: PsychologistLandingScreen(
              portal: Uri.parse('https://pro.example'),
              openUrl: (u) async {
                opened.add(u);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('pro-portal')));
      expect(opened, [Uri.parse('https://pro.example')]);
    },
  );

  testWidgets(
    'MOB1-11 relationship revoked → access ended, patient state dropped',
    (tester) async {
      final remote = MockQuestionnaireRemote();
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('p1', 'p@x'),
        caps: {'p1': patientCaps},
        questionnaires: remote,
      );
      await h.secrets.setLinkedSecret('p1', 'pw');
      await h.drafts.put(DraftRepository.keyFor('p1', 'demo-attempt-en'), '{}');
      await pumpApp(tester, h);
      await _openCare(tester);
      expect(find.byKey(const Key('care-questionnaires')), findsOneWidget);

      h.source.byUid['p1'] = generalCaps; // the server ended the relationship
      h.auth.fireTokenChange();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AccessEndedScreen), findsOneWidget);
      expect(find.byKey(const Key('care-questionnaires')), findsNothing);
      expect(h.drafts.rows, isEmpty, reason: 'patient drafts discarded');

      await tester.tap(find.byKey(const Key('access-ended-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AppShell), findsOneWidget);
      await _openCare(tester);
      expect(find.byKey(const Key('care-questionnaires')), findsNothing);
      expect(find.byKey(const Key('care-experts')), findsOneWidget);
    },
  );

  testWidgets(
    'MOB1-19 account switch: nothing of the previous account is shown',
    (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('p1', 'p@x'),
        caps: {'p1': patientCaps, 'g1': generalCaps},
        questionnaires: MockQuestionnaireRemote(),
      );
      h.auth.accounts['g@x'] = ('g1', 'pwG');
      await h.secrets.setLinkedSecret('p1', 'pw');
      await h.drafts.put(DraftRepository.keyFor('p1', 'demo-attempt-en'), '{}');
      await pumpApp(tester, h);
      await _openCare(tester);
      expect(find.text('Test Psychologist'), findsOneWidget);

      // Sign out from Settings.
      await tester.tap(_tab('settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('row-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-out-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.auth.user, isNull);
      expect(await h.secrets.linkedSecret('p1'), isNull);
      expect(h.drafts.rows, isEmpty);

      // Another account signs in on the same device.
      await h.secrets.setLinkedSecret('g1', 'pwG');
      h.auth.set(user: AccountFakeAuth.registered('g1', 'g@x'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Test Psychologist'), findsNothing);
      expect(
        find.byType(ChatScreen),
        findsOneWidget,
        reason: 'navigation reset to Chat',
      );
      await _openCare(tester);
      expect(find.byKey(const Key('care-questionnaires')), findsNothing);
      expect(find.byKey(const Key('care-psychologist')), findsNothing);
    },
  );

  testWidgets('MOB1-20b linked user without a cached password sees Unlock', (
    tester,
  ) async {
    final h = Mob1Harness(
      user: AccountFakeAuth.registered('g1', 'g@x'),
      caps: {'g1': generalCaps},
    );
    h.auth.accounts['g@x'] = ('g1', 'pwG');
    await pumpApp(tester, h);
    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.textContaining('reset your password'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('unlock-password')),
        matching: find.byType(TextField),
      ),
      'pwG',
    );
    await tester.tap(find.byKey(const Key('unlock-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets(
    'MOB1-18b collision while saving to an account offers "Sign in instead"',
    (tester) async {
      final h = Mob1Harness(user: const KoiUser(uid: 'u1', isAnonymous: true));
      h.auth.accounts['taken@x'] = ('zz', 'pw');
      await pumpApp(tester, h);
      await tester.tap(_tab('settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('row-create-account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('password-warning')), findsOneWidget);
      Finder field(String k) => find.descendant(
        of: find.byKey(Key(k)),
        matching: find.byType(TextField),
      );
      await tester.enterText(field('account-email'), 'taken@x');
      await tester.enterText(field('account-password'), 'secret1');
      await tester.enterText(field('account-confirm'), 'secret1');
      await tester.ensureVisible(find.byKey(const Key('account-submit')));
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('already has a KOI account'), findsOneWidget);
      expect(find.byKey(const Key('account-sign-in-instead')), findsOneWidget);
      expect(h.auth.user!.isAnonymous, isTrue);
    },
  );

  testWidgets('MOB1-38 demo badge on every mocked screen (capabilities mock)', (
    tester,
  ) async {
    final h = Mob1Harness(
      user: AccountFakeAuth.registered('p1', 'p@x'),
      caps: {'p1': patientCaps},
      questionnaires: MockQuestionnaireRemote(),
    );
    h.source.mock = true;
    await h.secrets.setLinkedSecret('p1', 'pw');
    await pumpApp(tester, h);
    await _openCare(tester);
    expect(find.byType(DemoDataBadge), findsOneWidget);
    await tester.tap(find.byKey(const Key('care-questionnaires')));
    await tester.pumpAndSettle();
    expect(find.byType(DemoDataBadge), findsOneWidget);
  });
}
