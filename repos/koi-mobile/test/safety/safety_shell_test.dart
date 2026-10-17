import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/safety/crisis_screen.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/top_nav.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  Future<void> pumpShell(
    WidgetTester tester, {
    KoiTab tab = KoiTab.chat,
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
        child: MaterialApp(home: AppShell(initialTab: tab)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(AppShell, skipOffstage: false)),
  );

  for (final (tab, title) in [
    (KoiTab.progress, 'Your Progress'),
    (KoiTab.settings, 'Settings'),
  ]) {
    testWidgets('long-press on the $title title opens the debug menu', (
      tester,
    ) async {
      await pumpShell(tester, tab: tab);
      final heading = find.descendant(
        of: find.byType(SafetyDebugTrigger),
        matching: find.text(title),
      );
      expect(heading, findsOneWidget);
      await tester.longPress(heading);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('safety-debug-high')), findsOneWidget);
    });

    testWidgets('release mode: no debug menu on the $title title', (
      tester,
    ) async {
      await pumpShell(tester, tab: tab, debugMenu: false);
      expect(find.byType(SafetyDebugTrigger), findsOneWidget);
      expect(find.byKey(const Key('safety-debug-trigger')), findsNothing);
      await tester.longPress(find.text(title).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('safety-debug-high')), findsNothing);
    });
  }

  testWidgets('crisis opens above the call screen and resets the avatar', (
    tester,
  ) async {
    await pumpShell(tester);
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
    await tester.pump(const Duration(seconds: 1));
    avatar
      ..setEmotion(AvatarEmotion.joy, 0.9)
      ..setConversationState(AvatarConversationState.speaking)
      ..setMouthCues(const [MouthCue(start: 0, end: 1, value: 'A')]);

    container(tester)
        .read(safetyControllerProvider)
        .handleRisk(SimulatedSafetyEvents.high());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CrisisScreen), findsOneWidget);
    expect(avatar.conversationState, AvatarConversationState.idle);
    expect(avatar.emotion, AvatarEmotion.neutral);
    expect(avatar.mouthCues, isEmpty);

    // Back cannot close it (nor the call screen beneath it).
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CrisisScreen), findsOneWidget);
    expect(find.byType(AvatarCallScreen), findsOneWidget);
  });
}
