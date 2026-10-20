import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/safety/crisis_screen.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';
import 'package:koi_mobile/safety/safety_host.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_view.dart';

import '../support/real_fonts.dart';
import 'safety_plan_harness.dart';

void main() {
  useRealFonts();

  final planButton = find.byKey(const Key('crisis-safety-plan'));
  final callButton = find.byKey(const Key('crisis-call'));
  final helplineText = find.byKey(const Key('crisis-helpline'));

  Future<void> pumpHost(
    WidgetTester tester,
    PlanEnv env, {
    Size size = const Size(360, 800),
    bool debugMenu = true,
    bool planDebugTools = true,
  }) async {
    await setPhone(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides(),
          safetyDebugMenuEnabledProvider.overrideWithValue(debugMenu),
          safetyPlanDebugToolsProvider.overrideWithValue(planDebugTools),
        ],
        child: const MaterialApp(
          home: SafetyHost(
            child: Scaffold(
              body: Center(child: SafetyDebugTrigger(child: Text('Settings'))),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openCrisis(WidgetTester tester, PlanEnv env) async {
    env.safety.handleRisk(SimulatedSafetyEvents.high());
    await settle(tester);
  }

  group(
    'SAFE-14 no plan / loading / error: the button is hidden, 1166 shows',
    () {
      testWidgets('no plan', (tester) async {
        final env = PlanEnv();
        await pumpHost(tester, env);
        await openCrisis(tester, env);
        expect(find.byType(CrisisScreen), findsOneWidget);
        expect(callButton, findsOneWidget);
        expect(find.text('Call 1166'), findsOneWidget);
        expect(planButton, findsNothing);
      });

      testWidgets('the plan fails to load (decrypt error)', (tester) async {
        final env = PlanEnv();
        await env.seed('u1', samplePlan);
        env.cryptoError = StateError('locked');
        await pumpHost(tester, env);
        await openCrisis(tester, env);
        expect(callButton, findsOneWidget);
        expect(helplineText, findsOneWidget);
        expect(planButton, findsNothing);
      });

      testWidgets('the plan is still loading: the crisis screen is not held '
          'back', (tester) async {
        final env = PlanEnv();
        await env.seed('u1', samplePlan);
        final gate = Completer<void>();
        env.cryptoGate = gate.future;
        await pumpHost(tester, env);
        env.safety.handleRisk(SimulatedSafetyEvents.high());
        await tester.pump();
        await tester.pump();
        // First frames: crisis screen + helpline, no plan button yet.
        expect(find.byType(CrisisScreen), findsOneWidget);
        expect(callButton, findsOneWidget);
        expect(planButton, findsNothing);
        gate.complete();
        await settle(tester);
        expect(planButton, findsOneWidget, reason: 'appears once loaded');
      });

      testWidgets('no signed-in user', (tester) async {
        final env = PlanEnv();
        await env.seed('u1', samplePlan);
        env.auth.set(user: null);
        await pumpHost(tester, env);
        await openCrisis(tester, env);
        expect(callButton, findsOneWidget);
        expect(planButton, findsNothing);
      });
    },
  );

  testWidgets('SAFE-14 with a plan: the button is BELOW the helpline, the '
      'call button and every path', (tester) async {
    final env = PlanEnv();
    await env.seed('u1', samplePlan);
    await pumpHost(tester, env);
    await openCrisis(tester, env);
    expect(planButton, findsOneWidget);
    expect(find.text('Open my safety plan'), findsOneWidget);
    final planTop = tester.getRect(planButton).top;
    expect(tester.getRect(helplineText).bottom, lessThan(planTop));
    expect(tester.getRect(callButton).bottom, lessThan(planTop));
    for (final p in CrisisPath.values) {
      expect(
        tester.getRect(find.byKey(Key('crisis-path-${p.wire}'))).bottom,
        lessThan(planTop),
        reason: p.wire,
      );
    }
  });

  testWidgets('SAFE-14 Urdu app language: the crisis button uses the Urdu '
      'table', (tester) async {
    final env = PlanEnv(language: 'ur');
    await env.seed('u1', samplePlan);
    await pumpHost(tester, env);
    await openCrisis(tester, env);
    expect(find.text('میرا حفاظتی منصوبہ کھولیں'), findsOneWidget);
  });

  group('SAFE-15 1166 is first and visible without scrolling; the plan '
      'button moves nothing', () {
    for (final size in const [Size(360, 640), Size(320, 568)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        Future<(Rect, Rect)> measure(bool withPlan) async {
          final env = PlanEnv();
          if (withPlan) await env.seed('u1', samplePlan);
          await pumpHost(tester, env, size: size);
          await openCrisis(tester, env);
          expect(planButton, withPlan ? findsOneWidget : findsNothing);
          final r = (tester.getRect(helplineText), tester.getRect(callButton));
          await tester.pumpWidget(const SizedBox());
          return r;
        }

        final (helpWithout, callWithout) = await measure(false);
        final (helpWith, callWith) = await measure(true);
        // The new button changes nothing above it.
        expect(helpWith, helpWithout);
        expect(callWith, callWithout);
        // ignore: avoid_print
        print(
          'SAFE-15 ${size.width.toInt()}x${size.height.toInt()}: helpline '
          'text bottom ${helpWith.bottom.toStringAsFixed(1)}, call button '
          'bottom ${callWith.bottom.toStringAsFixed(1)} of '
          '${size.height.toInt()} (SafeArea min 16)',
        );
        expect(
          callWith.bottom,
          lessThanOrEqualTo(size.height - 16),
          reason: 'call button fully on screen without scrolling',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('SAFE-16 / SAFE-28 opening the plan is NOT a path choice: no '
      'event, no resolution, mic stays locked; Back returns to the same '
      'crisis screen', (tester) async {
    final env = PlanEnv();
    await env.seed('u1', samplePlan);
    await pumpHost(tester, env);
    await openCrisis(tester, env);
    final crisisBefore = env.safety.crisis;
    expect(crisisBefore, isNotNull);

    await tester.ensureVisible(planButton);
    await tester.tap(planButton);
    await settle(tester);

    // The read-only plan is on top.
    expect(find.byType(SafetyPlanView), findsOneWidget);
    expect(find.byKey(const Key('sp-item-w1')), findsOneWidget);
    expect(find.byKey(const Key('sp-helpline')), findsOneWidget);
    expect(find.byKey(const Key('sp-edit')), findsNothing, reason: 'read only');
    expect(
      find.byKey(const Key('sp-breathing')),
      findsNothing,
      reason: 'no breathing while the crisis flow is open',
    );
    // Nothing happened to the crisis flow.
    expect(identical(env.safety.crisis, crisisBefore), isTrue);
    expect(env.safety.resolutionPending, isFalse);
    expect(env.paths, isEmpty);
    expect(env.events, isEmpty);
    // The avatar call screen's mic lock (_safetyBlocks) reads exactly these.
    expect(
      env.safety.crisis != null ||
          env.safety.resolutionPending ||
          env.safety.breathing != null,
      isTrue,
    );
    expect(env.queue.items, isEmpty);

    // Back: the same crisis screen, still waiting for a path.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(SafetyPlanView), findsNothing);
    expect(find.byType(CrisisScreen), findsOneWidget);
    expect(callButton, findsOneWidget);
    expect(identical(env.safety.crisis, crisisBefore), isTrue);
    expect(env.paths, isEmpty);
    expect(env.events, isEmpty);

    // Back on the crisis screen itself is still blocked.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(CrisisScreen), findsOneWidget);

    // A path still works afterwards (exactly once).
    await tester.ensureVisible(
      find.byKey(const Key('crisis-path-reached_out')),
    );
    await tester.tap(find.byKey(const Key('crisis-path-reached_out')));
    await settle(tester);
    expect(env.paths, [CrisisPath.reachedOut]);
  });

  testWidgets('SAFE-16 the plan view closes with the crisis screen', (
    tester,
  ) async {
    final env = PlanEnv();
    await env.seed('u1', samplePlan);
    await pumpHost(tester, env);
    await openCrisis(tester, env);
    await tester.ensureVisible(planButton);
    await tester.tap(planButton);
    await settle(tester);
    expect(find.byType(SafetyPlanView), findsOneWidget);
    // The crisis flow ends some other way (e.g. a new chat response).
    env.safety.chooseCrisisPath(CrisisPath.misunderstanding);
    await settle(tester);
    expect(find.byType(SafetyPlanView), findsNothing);
    expect(find.byType(CrisisScreen), findsNothing);
  });

  group('SAFE-24 / SAFE-25 DEBUG menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.longPress(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('SAFE-24 debug build: Fill demo, then Clear', (tester) async {
      final env = PlanEnv();
      await pumpHost(tester, env);
      await openMenu(tester);
      expect(find.text(fillDemoSafetyPlanLabel), findsOneWidget);
      expect(find.text(clearSafetyPlanLabel), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('safety-debug-fill-safety-plan')),
      );
      await tester.tap(find.byKey(const Key('safety-debug-fill-safety-plan')));
      await settle(tester);
      expect(env.box.rows.keys, ['u1']);
      expect((await env.repo().load('u1'))!.isEmpty, isFalse);
      // The crisis screen now offers it.
      await openCrisis(tester, env);
      expect(planButton, findsOneWidget);
      env.safety.chooseCrisisPath(CrisisPath.misunderstanding);
      await settle(tester);

      await openMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('safety-debug-clear-safety-plan')),
      );
      await tester.tap(find.byKey(const Key('safety-debug-clear-safety-plan')));
      await settle(tester);
      expect(env.box.rows, isEmpty);
    });

    testWidgets('SAFE-25 release build: no safety plan items (the rest of the '
        'menu is unchanged)', (tester) async {
      final env = PlanEnv();
      await pumpHost(tester, env, planDebugTools: false);
      await openMenu(tester);
      expect(find.byKey(const Key('safety-debug-high')), findsOneWidget);
      expect(find.text(fillDemoSafetyPlanLabel), findsNothing);
      expect(find.text(clearSafetyPlanLabel), findsNothing);
    });

    testWidgets('SAFE-25 release build: no DEBUG menu at all', (tester) async {
      final env = PlanEnv();
      await pumpHost(tester, env, debugMenu: false, planDebugTools: false);
      await tester.longPress(find.text('Settings'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(fillDemoSafetyPlanLabel), findsNothing);
      expect(find.byKey(const Key('safety-debug-high')), findsNothing);
    });

    test('SAFE-25 the debug tools default to kDebugMode', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Tests run in debug mode; a release build compiles kDebugMode false.
      expect(c.read(safetyPlanDebugToolsProvider), isTrue);
    });
  });
}
