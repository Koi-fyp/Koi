import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_source.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/onboarding/onboarding_screen.dart';
import 'package:koi_mobile/onboarding/progress_indicator.dart';
import 'package:koi_mobile/onboarding/steps/ai_disclosure_step.dart';
import 'package:koi_mobile/onboarding/steps/companion_step.dart';
import 'package:koi_mobile/safety/breathing_screen.dart';
import 'package:koi_mobile/safety/crisis_screen.dart';
import 'package:koi_mobile/safety_plan/safety_plan_editor.dart';
import 'package:koi_mobile/safety_plan/safety_plan_models.dart';
import 'package:koi_mobile/safety_plan/safety_plan_onboarding_step.dart';
import 'package:koi_mobile/safety_plan/safety_plan_view.dart';
import 'package:koi_mobile/settings/settings_screen.dart';
import 'package:koi_mobile/settings/storage_usage.dart';

import '../support/real_fonts.dart';
import 'safety_plan_harness.dart';

void main() {
  useRealFonts();

  Future<void> pumpPage(
    WidgetTester tester,
    PlanEnv env,
    Widget page, {
    Size size = const Size(360, 800),
    bool onboardingDone = true,
  }) async {
    await setPhone(tester, size);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides(onboardingDone: onboardingDone),
        child: MaterialApp(home: page),
      ),
    );
    await settle(tester);
  }

  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    // Centred, so a focused field just above stays on screen too (it would
    // otherwise scroll its caret back into view while we tap).
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await settle(tester);
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> addItem(
    WidgetTester tester,
    SafetyPlanSection s,
    String text, {
    String? phone,
  }) async {
    await tapVisible(tester, find.byKey(Key('sp-add-${s.id}')));
    await tester.enterText(field('sp-input-text'), text);
    if (phone != null) await tester.enterText(field('sp-input-phone'), phone);
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('sp-item-save')));
  }

  Future<SafetyPlan> stored(PlanEnv env, [String uid = 'u1']) async =>
      (await env.repo().load(uid)) ?? SafetyPlan.empty;

  group('SAFE-09 editor: add, edit, delete, reorder, limits', () {
    testWidgets('every section has its helper line', (tester) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanEditor());
      for (final s in SafetyPlanSection.values) {
        expect(find.byKey(Key('sp-help-${s.id}')), findsOneWidget);
        expect(find.byKey(Key('sp-add-${s.id}')), findsOneWidget);
      }
    });

    testWidgets('add → saved encrypted at once; edit; delete', (tester) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanEditor());
      await addItem(tester, SafetyPlanSection.warningSigns, 'Not sleeping');
      expect(find.text('Not sleeping'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
      var plan = await stored(env);
      final item = plan[SafetyPlanSection.warningSigns].single;
      expect(item.text, 'Not sleeping');
      expect(env.box.rows['u1']!.contains('Not sleeping'), isFalse);

      await tapVisible(tester, find.byKey(Key('sp-edit-${item.id}')));
      await tester.enterText(field('sp-input-text'), 'Not sleeping well');
      await tapVisible(tester, find.byKey(const Key('sp-item-save')));
      plan = await stored(env);
      expect(
        plan[SafetyPlanSection.warningSigns].single.text,
        'Not sleeping well',
      );
      expect(plan[SafetyPlanSection.warningSigns].single.id, item.id);

      await tapVisible(tester, find.byKey(Key('sp-delete-${item.id}')));
      expect(find.text('Not sleeping well'), findsNothing);
      // The last item gone = no plan at all (the row is removed).
      expect(env.box.rows, isEmpty);
    });

    testWidgets('reorder with Move up / Move down', (tester) async {
      final env = PlanEnv();
      await env.seed(
        'u1',
        SafetyPlan(
          items: {
            SafetyPlanSection.reasons: [
              const SafetyPlanItem(id: 'a', text: 'A'),
              const SafetyPlanItem(id: 'b', text: 'B'),
              const SafetyPlanItem(id: 'c', text: 'C'),
            ],
          },
        ),
      );
      await pumpPage(tester, env, const SafetyPlanEditor());
      List<String> order(SafetyPlan p) => [
        for (final i in p[SafetyPlanSection.reasons]) i.id,
      ];
      // First can't go up, last can't go down.
      expect(
        tester.widget<IconButton>(find.byKey(const Key('sp-up-a'))).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('sp-down-c'))).onPressed,
        isNull,
      );
      await tapVisible(tester, find.byKey(const Key('sp-down-a')));
      expect(order(await stored(env)), ['b', 'a', 'c']);
      await tapVisible(tester, find.byKey(const Key('sp-up-c')));
      expect(order(await stored(env)), ['b', 'c', 'a']);
      // On screen too.
      final ys = [
        for (final id in ['b', 'c', 'a'])
          tester.getTopLeft(find.byKey(Key('sp-row-$id'))).dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
    });

    testWidgets('10 items max: no Add, a gentle note instead', (tester) async {
      final env = PlanEnv();
      await env.seed(
        'u1',
        SafetyPlan(
          items: {
            SafetyPlanSection.reasons: [
              for (var i = 0; i < 10; i++)
                SafetyPlanItem(id: 'r$i', text: 'R$i'),
            ],
          },
        ),
      );
      await pumpPage(tester, env, const SafetyPlanEditor());
      expect(find.byKey(const Key('sp-add-reasons')), findsNothing);
      expect(find.byKey(const Key('sp-max-reasons')), findsOneWidget);
      expect(find.text('You can keep up to 10 here.'), findsOneWidget);
    });

    testWidgets('300 characters max with a counter', (tester) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanEditor());
      await tapVisible(tester, find.byKey(const Key('sp-add-reasons')));
      await tester.enterText(field('sp-input-text'), 'x' * 400);
      await tester.pump();
      expect(
        tester.widget<TextField>(field('sp-input-text')).controller!.text,
        hasLength(300),
      );
      expect(find.text('300 / 300'), findsOneWidget);
      // Save stays off while blank.
      await tester.enterText(field('sp-input-text'), '   ');
      await tester.pump();
      expect(
        tester
            .widget<GestureDetector>(
              find
                  .descendant(
                    of: find.byKey(const Key('sp-item-save')),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );
    });

    testWidgets('phone: only in people / professionals; invalid is refused', (
      tester,
    ) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanEditor());
      await tapVisible(tester, find.byKey(const Key('sp-add-warning_signs')));
      expect(find.byKey(const Key('sp-input-phone')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('sp-item-cancel')));

      await tapVisible(tester, find.byKey(const Key('sp-add-people_to_ask')));
      await tester.enterText(field('sp-input-text'), 'My sister');
      await tester.enterText(field('sp-input-phone'), 'call her');
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('sp-item-save')));
      expect(find.text('Use digits, spaces, + or - only.'), findsOneWidget);
      expect(env.box.rows, isEmpty);
      await tester.enterText(field('sp-input-phone'), '0321 7654321');
      await tapVisible(tester, find.byKey(const Key('sp-item-save')));
      final p = (await stored(env))[SafetyPlanSection.peopleToAsk].single;
      expect((p.text, p.phone), ('My sister', '0321 7654321'));
    });

    testWidgets('a failed save says so and keeps what was written', (
      tester,
    ) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanEditor());
      env.cryptoError = StateError('disk');
      await addItem(tester, SafetyPlanSection.reasons, 'My family');
      expect(
        find.text('This could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('My family'), findsOneWidget);
      expect(env.box.rows, isEmpty);
    });
  });

  testWidgets('SAFE-10 1166 is first in Professionals and cannot be edited or '
      'deleted', (tester) async {
    final env = PlanEnv();
    await env.seed(
      'u1',
      SafetyPlan(
        items: {
          SafetyPlanSection.professionals: [
            const SafetyPlanItem(id: 'c', text: 'My clinic', phone: '042 111'),
          ],
        },
      ),
    );
    await pumpPage(tester, env, const SafetyPlanEditor());
    final fixed = find.byKey(const Key('sp-edit-helpline'));
    expect(fixed, findsOneWidget);
    expect(
      find.descendant(of: fixed, matching: find.text('1166')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fixed, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      tester.getTopLeft(fixed).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('sp-row-c'))).dy),
    );
    // Deleting every item still leaves 1166 (it is never stored).
    await tapVisible(tester, find.byKey(const Key('sp-delete-c')));
    expect(fixed, findsOneWidget);

    // Read view: first in its section too.
    await env.seed(
      'u1',
      SafetyPlan(
        items: {
          SafetyPlanSection.professionals: [
            const SafetyPlanItem(id: 'c', text: 'My clinic', phone: '042 111'),
          ],
        },
      ),
    );
    await pumpPage(tester, env, const SafetyPlanView());
    expect(
      tester.getTopLeft(find.byKey(const Key('sp-helpline'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('sp-item-c'))).dy),
    );
  });

  testWidgets('SAFE-13 read view: tapping a contact calls it (tel:), 1166 '
      'included', (tester) async {
    final env = PlanEnv();
    await env.seed('u1', samplePlan);
    final dialled = <Uri>[];
    await pumpPage(
      tester,
      env,
      SafetyPlanView(openUrl: (u) async => dialled.add(u)),
    );
    await tapVisible(tester, find.byKey(const Key('sp-helpline')));
    await tapVisible(tester, find.byKey(const Key('sp-item-p1')));
    expect(dialled, [
      CrisisScreen.telUri('1166'),
      Uri(scheme: 'tel', path: '03217654321'),
    ]);
    // Plain items are not buttons.
    expect(
      find.descendant(
        of: find.byKey(const Key('sp-view-warning_signs')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('SAFE-17 the breathing link opens the existing breathing '
      'exercise (not from the crisis screen)', (tester) async {
    final env = PlanEnv();
    await env.seed(
      'u1',
      SafetyPlan(
        items: {
          SafetyPlanSection.copingAlone: [
            const SafetyPlanItem(id: 'b', text: 'Breathe slowly'),
          ],
        },
      ),
    );
    await pumpPage(tester, env, const SafetyPlanView());
    await tapVisible(tester, find.byKey(const Key('sp-breathing')));
    expect(find.byType(BreathingScreen), findsOneWidget);
    // Private controller: nothing is sent to the chat session.
    expect(env.events, isEmpty);
    await tester.tap(find.byKey(const Key('breathing-stop')));
    await settle(tester);
  });

  group('SAFE-06 / SAFE-05 sign-out and account switch', () {
    testWidgets('the view follows the signed-in uid; nothing of A is shown to '
        'B', (tester) async {
      final env = PlanEnv();
      await env.seed('u1', samplePlan);
      await pumpPage(tester, env, const SafetyPlanView());
      expect(find.text('Not sleeping'), findsOneWidget);

      env.auth.set(user: const KoiUser(uid: 'u2', isAnonymous: true));
      await settle(tester);
      expect(find.text('Not sleeping'), findsNothing);
      expect(find.text('My sister'), findsNothing);
      expect(find.byKey(const Key('sp-helpline')), findsOneWidget);

      env.auth.set(user: null);
      await settle(tester);
      expect(find.text('Not sleeping'), findsNothing);

      // A's plan is still stored for A.
      env.auth.set(user: const KoiUser(uid: 'u1', isAnonymous: true));
      await settle(tester);
      expect(find.text('Not sleeping'), findsOneWidget);
    });

    testWidgets('an editor open during a switch never saves A\'s plan for B', (
      tester,
    ) async {
      final env = PlanEnv();
      await env.seed('u1', samplePlan);
      await pumpPage(tester, env, const SafetyPlanEditor());
      expect(find.text('Not sleeping'), findsOneWidget);
      env.auth.set(user: const KoiUser(uid: 'u2', isAnonymous: true));
      await settle(tester);
      expect(find.text('Not sleeping'), findsNothing);
      await addItem(tester, SafetyPlanSection.reasons, 'B only');
      final b = await stored(env, 'u2');
      expect(b[SafetyPlanSection.warningSigns], isEmpty);
      expect(b[SafetyPlanSection.reasons].single.text, 'B only');
      expect((await stored(env, 'u1')).items, samplePlan.items);
    });
  });

  group('SAFE-20 Settings → My safety plan', () {
    Future<void> pumpSettings(WidgetTester tester, PlanEnv env) async {
      await setPhone(tester, const Size(360, 800));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides(),
            koiStorageBytesProvider.overrideWith((ref) async => null),
            avatarSourceProvider.overrideWithValue(AvatarSource.placeholder),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsTab())),
        ),
      );
      await settle(tester);
    }

    testWidgets('the row is in Privacy, after Import Data', (tester) async {
      final env = PlanEnv();
      await pumpSettings(tester, env);
      final row = find.byKey(const Key('row-safety-plan'));
      expect(row, findsOneWidget);
      expect(find.text('My safety plan'), findsOneWidget);
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('row-import'))).dy),
      );
    });

    testWidgets('no plan yet → the editor', (tester) async {
      final env = PlanEnv();
      await pumpSettings(tester, env);
      await tapVisible(tester, find.byKey(const Key('row-safety-plan')));
      await settle(tester);
      expect(find.byType(SafetyPlanEditor), findsOneWidget);
      // Writing the first line does not swap the editor away.
      await addItem(tester, SafetyPlanSection.reasons, 'My family');
      expect(find.byType(SafetyPlanEditor), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('sp-done')));
      await settle(tester);
      expect(find.byType(SafetyPlanEditor), findsNothing);
      expect(find.byKey(const Key('row-safety-plan')), findsOneWidget);
    });

    testWidgets('a plan → the read view, with Edit', (tester) async {
      final env = PlanEnv();
      await env.seed('u1', samplePlan);
      await pumpSettings(tester, env);
      await tapVisible(tester, find.byKey(const Key('row-safety-plan')));
      await settle(tester);
      expect(find.byType(SafetyPlanView), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('sp-edit')));
      await settle(tester);
      expect(find.byType(SafetyPlanEditor), findsOneWidget);
    });
  });

  group('SAFE-18 / SAFE-19 onboarding', () {
    Future<void> toSubScreen(WidgetTester tester, PlanEnv env) async {
      await pumpPage(
        tester,
        env,
        OnboardingScreen(initialStep: 2, openUrl: (_) async {}),
        onboardingDone: false,
      );
      await tapVisible(tester, find.byKey(const Key('companion-continue')));
      expect(find.byType(SafetyPlanOnboardingStep), findsOneWidget);
    }

    int currentProgress(WidgetTester tester) => tester
        .widget<OnboardingProgressIndicator>(
          find.byType(OnboardingProgressIndicator),
        )
        .currentStep;

    testWidgets('SAFE-18 after Companion; not a counted step; Not now goes '
        'straight on', (tester) async {
      final env = PlanEnv();
      await toSubScreen(tester, env);
      expect(find.text('Create your safety plan (2 minutes)'), findsOneWidget);
      expect(currentProgress(tester), 1, reason: 'still the Companion dot');
      expect(OnboardingScreen.totalSteps, 6);
      expect(find.byKey(const Key('sp-footnote')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('sp-onboarding-skip')));
      expect(find.byType(AIDisclosureStep), findsOneWidget);
      expect(currentProgress(tester), 2);
      expect(env.box.rows, isEmpty);
    });

    testWidgets('SAFE-18 Create → write → Done → AI Disclosure', (
      tester,
    ) async {
      final env = PlanEnv();
      await toSubScreen(tester, env);
      await tapVisible(tester, find.byKey(const Key('sp-onboarding-create')));
      expect(find.byType(SafetyPlanEditor), findsOneWidget);
      await addItem(tester, SafetyPlanSection.reasons, 'My family');
      await tapVisible(tester, find.byKey(const Key('sp-done')));
      expect(find.byType(AIDisclosureStep), findsOneWidget);
      expect(
        (await stored(env))[SafetyPlanSection.reasons].single.text,
        'My family',
      );
    });

    testWidgets('SAFE-18 a failed save never blocks onboarding (Back from '
        'the editor goes on)', (tester) async {
      final env = PlanEnv();
      await toSubScreen(tester, env);
      await tapVisible(tester, find.byKey(const Key('sp-onboarding-create')));
      env.cryptoError = StateError('disk');
      await addItem(tester, SafetyPlanSection.reasons, 'My family');
      expect(
        find.text('This could not be saved. Please try again.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('koi-back')));
      expect(find.byType(AIDisclosureStep), findsOneWidget);
    });

    testWidgets('SAFE-18 Android back from the editor and the sub-screen', (
      tester,
    ) async {
      final env = PlanEnv();
      await toSubScreen(tester, env);
      await tapVisible(tester, find.byKey(const Key('sp-onboarding-create')));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(AIDisclosureStep), findsOneWidget);

      // Back on the sub-screen itself returns to Companion.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(CompanionSelectionStep), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('companion-continue')));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(CompanionSelectionStep), findsOneWidget);
    });

    testWidgets('SAFE-19 the sub-screen is only inside onboarding: a user '
        'who finished onboarding never sees it', (tester) async {
      final env = PlanEnv();
      await pumpPage(tester, env, const SafetyPlanView());
      expect(find.byType(SafetyPlanOnboardingStep), findsNothing);
      // Onboarding steps 0-5 are unchanged; the sub-screen is reached only
      // from Companion's Continue (see SAFE-18).
      expect(OnboardingScreen.previousStep(3), 2);
    });
  });

  group('SAFE-21 Urdu: right-to-left, Urdu table, user text in its own '
      'direction', () {
    testWidgets('read view', (tester) async {
      final env = PlanEnv(language: 'ur');
      await env.seed('u1', samplePlan);
      await pumpPage(tester, env, const SafetyPlanView());
      expect(find.text('میرا حفاظتی منصوبہ'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byKey(const Key('sp-helpline')))),
        TextDirection.rtl,
      );
      Text text(String key) => tester.widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      );
      // English text stays LTR inside the RTL page; Urdu text RTL.
      expect(
        tester.widget<Text>(find.byKey(const Key('sp-item-w1'))).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sp-item-r1'))).textDirection,
        TextDirection.rtl,
      );
      expect(text('sp-item-p1').textDirection, TextDirection.ltr);
    });

    testWidgets('English app: Urdu text the user wrote is still RTL', (
      tester,
    ) async {
      final env = PlanEnv();
      await env.seed('u1', samplePlan);
      await pumpPage(tester, env, const SafetyPlanView());
      expect(find.text('My safety plan'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('sp-item-r1'))).textDirection,
        TextDirection.rtl,
      );
    });
  });

  group('SAFE-22 no overflow at 360 and 320 dp (English and Urdu)', () {
    for (final size in const [Size(360, 640), Size(320, 568)]) {
      for (final lang in const [null, 'ur']) {
        final name = '${size.width.toInt()}dp ${lang ?? 'en'}';
        testWidgets('read view, editor with an open item, onboarding: $name', (
          tester,
        ) async {
          final env = PlanEnv(language: lang);
          await env.repo().fillDemo('u1', DateTime(2026, 10, 20));
          Future<void> scrollAll() async {
            final scroll = find.byType(Scrollable).first;
            for (var i = 0; i < 25; i++) {
              await tester.drag(scroll, const Offset(0, -300));
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(tester.takeException(), isNull);
          }

          await pumpPage(tester, env, const SafetyPlanView(), size: size);
          await scrollAll();

          await pumpPage(tester, env, const SafetyPlanEditor(), size: size);
          await tapVisible(
            tester,
            find.byKey(const Key('sp-add-people_to_ask')),
          );
          await tester.enterText(field('sp-input-text'), 'x ' * 150);
          await tester.pump();
          await scrollAll();

          await pumpPage(
            tester,
            env,
            SafetyPlanOnboardingStep(onNext: () {}),
            size: size,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('SAFE-23 accessibility', () {
    testWidgets('48dp tap targets and labelled buttons (view and editor)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = PlanEnv();
      await env.seed('u1', samplePlan);
      await pumpPage(tester, env, const SafetyPlanView());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(
        find.bySemanticsLabel(RegExp('^Call My sister, 0321 7654321')),
        findsOneWidget,
      );
      await pumpPage(tester, env, const SafetyPlanEditor());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.byTooltip('Move up'), findsWidgets);
      expect(find.byTooltip('Delete'), findsWidgets);
      handle.dispose();
    });
  });

  testWidgets('SAFE-27 footnote everywhere; calm crisis/breathing colours; '
      'gentle "add more"', (tester) async {
    final env = PlanEnv();
    await env.seed('u1', samplePlan);
    await pumpPage(tester, env, const SafetyPlanView());
    const footnote =
        'Based on a widely used safety-planning approach. This does not '
        'replace professional help.';
    expect(find.text(footnote), findsOneWidget);
    expect(find.text('You can add more anytime.'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      CrisisScreen.dialogBg,
    );
    expect(SafetyPlanColors.accent, BreathingScreen.progressFill);
    await pumpPage(tester, env, const SafetyPlanEditor());
    expect(find.text(footnote), findsOneWidget);
  });
}
