import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/environment/environment_controller.dart';
import 'package:koi_mobile/environment/environment_debug_menu.dart';
import 'package:koi_mobile/environment/environment_palette.dart';
import 'package:koi_mobile/environment/environment_providers.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/top_nav.dart';
import 'package:koi_mobile/theme/koi_colors.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

AvatarStateUpdate _emotion(AvatarEmotion e, {String session = 'u1'}) =>
    AvatarStateUpdate(session, emotion: e, intensity: 0.7);

/// Progress keeps animating, so pumpAndSettle never returns there.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  useRealFonts();

  group('palette', () {
    test('ATC-M6-01 each companion emotion maps to its own mood and token', () {
      expect(
        {
          for (final e in AvatarEmotion.values)
            e: EnvironmentMood.fromEmotion(e),
        },
        {
          AvatarEmotion.neutral: EnvironmentMood.neutral,
          AvatarEmotion.joy: EnvironmentMood.joy,
          AvatarEmotion.angry: EnvironmentMood.angry,
          AvatarEmotion.sorrow: EnvironmentMood.sorrow,
          AvatarEmotion.fun: EnvironmentMood.fun,
        },
      );
      expect(EnvironmentMood.fromEmotion(null), EnvironmentMood.neutral);
      expect(
        EnvironmentPalette.token(EnvironmentMood.joy),
        KoiColors.neoYellow,
      );
      expect(EnvironmentPalette.token(EnvironmentMood.fun), KoiColors.neoMint);
      expect(
        EnvironmentPalette.token(EnvironmentMood.sorrow),
        KoiColors.neoBlue,
      );
      expect(
        EnvironmentPalette.token(EnvironmentMood.angry),
        KoiColors.neoPurple,
      );
      expect(EnvironmentPalette.token(EnvironmentMood.calm), KoiColors.cyan);
    });

    test('ATC-M6-02 approved strengths and the resulting colours', () {
      expect(EnvironmentPalette.callStrength, 0.25);
      expect(EnvironmentPalette.chatStrength, 0.15);
      String at(double s) => [
        for (final m in EnvironmentMood.values)
          '${m.name} ${_hex(EnvironmentPalette.colorFor(m, s))}',
      ].join(', ');
      expect(
        at(0.25),
        'neutral #FFE5D9, joy #FFE0A3, angry #E0C3D3, sorrow #CBC5DD, '
        'fun #CBE1BF, calm #C1D9D8',
      );
      expect(
        at(0.15),
        'neutral #FFE5D9, joy #FFE2B8, angry #EDD1D6, sorrow #E0D2DC, '
        'fun #E0E2C9, calm #DADED8',
      );
      expect(
        EnvironmentPalette.colorFor(EnvironmentMood.joy, 0),
        KoiColors.background,
      );
    });

    test('ATC-M6-03 text on the background stays >= 4.5:1 on every tint', () {
      const gray600 = Color(0xFF4B5563);
      for (final s in [
        EnvironmentPalette.callStrength,
        EnvironmentPalette.chatStrength,
      ]) {
        for (final m in EnvironmentMood.values) {
          final bg = EnvironmentPalette.colorFor(m, s);
          expect(
            _contrast(gray600, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$m $s',
          );
          expect(
            _contrast(KoiColors.neoBlack, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$m $s',
          );
        }
      }
    });

    test('ATC-M6-01 an unknown backend emotion is neutral', () {
      final state = CompanionState.fromJson({'emotion': 'mystery'});
      final env = EnvironmentController(uid: 'u1')
        ..onAvatarEvent(_emotion(AvatarEmotion.joy))
        ..onAvatarEvent(_emotion(state.emotion));
      expect(env.mood, EnvironmentMood.neutral);
    });
  });

  group('controller', () {
    test('ATC-M6-04 follows the latest emotion of its own conversation only', () {
      final env = EnvironmentController(uid: 'u1');
      expect(env.mood, EnvironmentMood.neutral);
      env.onAvatarEvent(_emotion(AvatarEmotion.sorrow));
      expect(env.mood, EnvironmentMood.sorrow);
      env.onAvatarEvent(_emotion(AvatarEmotion.fun, session: 'other'));
      env.onAvatarEvent(
        const AvatarStateUpdate(
          'u1',
          conversationState: AvatarConversationState.speaking,
        ),
      );
      expect(env.mood, EnvironmentMood.sorrow);
    });

    test('ATC-M6-05 breathing → calm, then back to the last emotion', () {
      final env = EnvironmentController(uid: 'u1')
        ..onAvatarEvent(_emotion(AvatarEmotion.joy));
      env.updateSafety(crisis: false, breathing: true);
      expect(env.mood, EnvironmentMood.calm);
      env.onAvatarEvent(_emotion(AvatarEmotion.angry));
      expect(env.mood, EnvironmentMood.calm);
      env.updateSafety(crisis: false, breathing: false);
      expect(env.mood, EnvironmentMood.angry);
    });

    test('ATC-M6-05 crisis → calm, then neutral until the next emotion', () {
      final env = EnvironmentController(uid: 'u1')
        ..onAvatarEvent(_emotion(AvatarEmotion.joy));
      env.updateSafety(crisis: true, breathing: false);
      expect(env.mood, EnvironmentMood.calm);
      env.updateSafety(crisis: false, breathing: false);
      expect(env.mood, EnvironmentMood.neutral);
      env.onAvatarEvent(_emotion(AvatarEmotion.fun));
      expect(env.mood, EnvironmentMood.fun);
    });

    test('ATC-M6-04 new conversation / reset() → neutral; no notify if unchanged', () {
      final env = EnvironmentController(uid: 'u1');
      var notified = 0;
      env.addListener(() => notified++);
      env.onAvatarEvent(_emotion(AvatarEmotion.joy));
      env.onAvatarEvent(const AvatarSessionStarted('u1'));
      expect(env.mood, EnvironmentMood.neutral);
      env.onAvatarEvent(_emotion(AvatarEmotion.sorrow));
      env.debugPreview(EnvironmentMood.fun);
      env.reset();
      expect(env.mood, EnvironmentMood.neutral);
      expect(env.preview, isNull);
      env.reset();
      expect(notified, 5); // joy, new conversation, sorrow, preview, reset
    });

    test('ATC-M6-05 debug preview wins until cleared', () {
      final env = EnvironmentController(uid: 'u1')
        ..onAvatarEvent(_emotion(AvatarEmotion.joy))
        ..updateSafety(crisis: true, breathing: false)
        ..debugPreview(EnvironmentMood.sorrow);
      expect(env.mood, EnvironmentMood.sorrow);
      env.debugPreview(null);
      expect(env.mood, EnvironmentMood.calm);
    });
  });

  group('provider', () {
    late FakeAuthService auth;
    late ProviderContainer container;

    setUp(() {
      auth = FakeAuthService(
        fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
      );
      container = ProviderContainer(
        overrides: [
          ...overridesFor(auth, onboardingStore(complete: true)),
          ...chatOverrides(),
        ],
      );
      addTearDown(container.dispose);
    });

    EnvironmentController env() =>
        container.read(environmentControllerProvider);

    test('ATC-M6-06 HIGH risk → calm until the resolution is sent, then neutral', () {
      env().onAvatarEvent(_emotion(AvatarEmotion.angry));
      final safety = container.read(safetyControllerProvider)
        ..handleRisk(SimulatedSafetyEvents.high());
      expect(safety.crisis, isNotNull);
      expect(env().mood, EnvironmentMood.calm);
      safety.chooseCrisisPath(CrisisPath.values.first);
      expect(safety.resolutionPending, isTrue);
      expect(env().mood, EnvironmentMood.calm);
      // crisisResolutionSent does not notify: the next turn's events end
      // calm; the turn's state update alone gives neutral.
      safety.crisisResolutionSent();
      env().onAvatarEvent(
        const AvatarStateUpdate(
          'u1',
          conversationState: AvatarConversationState.thinking,
        ),
      );
      expect(env().mood, EnvironmentMood.neutral);
      env().onAvatarEvent(_emotion(AvatarEmotion.fun));
      expect(env().mood, EnvironmentMood.fun);
    });

    test('ATC-M6-06 breathing from the backend → calm, then the emotion again', () {
      env().onAvatarEvent(_emotion(AvatarEmotion.joy));
      final safety = container.read(safetyControllerProvider)
        ..handleUiAction(SimulatedSafetyEvents.startBreathing());
      expect(env().mood, EnvironmentMood.calm);
      safety.dismissBreathing();
      expect(env().mood, EnvironmentMood.joy);
    });

    test('ATC-M6-06 sign-out / another user → a fresh neutral controller', () {
      env().onAvatarEvent(_emotion(AvatarEmotion.joy));
      final first = env();
      auth.set(user: null);
      expect(env().mood, EnvironmentMood.neutral);
      auth.set(user: const KoiUser(uid: 'u2', isAnonymous: true));
      expect(env(), isNot(same(first)));
      expect(env().uid, 'u2');
      expect(env().mood, EnvironmentMood.neutral);
    });
  });

  group('widgets', () {
    Color background(WidgetTester tester, {Finder? within}) => tester
        .widget<ColoredBox>(
          find
              .descendant(
                of: within ?? find.byType(MaterialApp),
                matching: find.byKey(const Key('environment-background')),
              )
              .first,
        )
        .color;

    Future<EnvironmentController> pumpBackground(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      late EnvironmentController env;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overridesFor(
              FakeAuthService(
                fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
              ),
              onboardingStore(complete: true),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: Consumer(
                builder: (context, ref, _) {
                  env = ref.watch(environmentControllerProvider);
                  return const EnvironmentBackground(
                    strength: 0.12,
                    child: SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      return env;
    }

    final joy = EnvironmentPalette.colorFor(EnvironmentMood.joy, 0.12);

    testWidgets('ATC-M6-08 animates over ~1.8 s', (tester) async {
      final env = await pumpBackground(tester, disableAnimations: false);
      expect(background(tester), KoiColors.background);
      env.onAvatarEvent(_emotion(AvatarEmotion.joy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(background(tester), isNot(KoiColors.background));
      expect(background(tester), isNot(joy));
      await tester.pump(const Duration(milliseconds: 900));
      expect(background(tester), joy);
    });

    testWidgets('ATC-M6-08 reduce motion: changes at once', (tester) async {
      final env = await pumpBackground(tester, disableAnimations: true);
      env.onAvatarEvent(_emotion(AvatarEmotion.joy));
      await tester.pump();
      expect(background(tester), joy);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      bool debugMenu = true,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overridesFor(
              FakeAuthService(
                fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
              ),
              onboardingStore(complete: true),
            ),
            ...chatOverrides(),
            safetyDebugMenuEnabledProvider.overrideWithValue(debugMenu),
          ],
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    }

    Color navStrip(WidgetTester tester) =>
        tester.widget<KoiTopNav>(find.byType(KoiTopNav)).background;

    testWidgets('ATC-M6-09 Chat tab: message area and nav strip at 15%; '
        'other tabs keep the nav peach', (tester) async {
      final container = await pumpShell(tester);
      final chatJoy = EnvironmentPalette.colorFor(
        EnvironmentMood.joy,
        EnvironmentPalette.chatStrength,
      );
      container
          .read(environmentControllerProvider)
          .onAvatarEvent(_emotion(AvatarEmotion.joy));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(background(tester), chatJoy);
      expect(navStrip(tester), chatJoy);

      await tester.tap(find.text('Progress'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(navStrip(tester), KoiColors.background);
    });

    testWidgets('ATC-M6-09 call screen tint is 25%', (tester) async {
      final container = await pumpShell(tester);
      container
          .read(environmentControllerProvider)
          .debugPreview(EnvironmentMood.calm);
      final avatar = AvatarViewController();
      addTearDown(avatar.dispose);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => AvatarCallScreen(avatarController: avatar),
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        background(tester, within: find.byType(AvatarCallScreen)),
        EnvironmentPalette.colorFor(
          EnvironmentMood.calm,
          EnvironmentPalette.callStrength,
        ),
      );
    });

    testWidgets('ATC-M6-10 debug menu: "Set environment emotion" previews a palette', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      // The DEBUG button sits on the Progress page.
      await tester.tap(find.text('Progress'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('safety-debug-button')));
      await settle(tester);
      final item = find.byKey(const Key('safety-debug-environment'));
      expect(find.text(environmentDebugLabel), findsOneWidget);
      await tester.ensureVisible(item);
      await tester.tap(item);
      await settle(tester);
      await tester.tap(find.byKey(const Key('environment-debug-sorrow')));
      await settle(tester);
      final env = container.read(environmentControllerProvider);
      expect(env.mood, EnvironmentMood.sorrow);
      await tester.tap(find.text('Chat'));
      await settle(tester);
      expect(
        background(tester),
        EnvironmentPalette.colorFor(
          EnvironmentMood.sorrow,
          EnvironmentPalette.chatStrength,
        ),
      );
    });

    testWidgets('ATC-M6-10 no debug menu (release behaviour): no environment option', (
      tester,
    ) async {
      await pumpShell(tester, debugMenu: false);
      await tester.tap(find.text('Progress'));
      await settle(tester);
      expect(find.byKey(const Key('safety-debug-button')), findsNothing);
      expect(find.byKey(const Key('safety-debug-trigger')), findsNothing);
      expect(find.text(environmentDebugLabel), findsNothing);
    });
  });
}
