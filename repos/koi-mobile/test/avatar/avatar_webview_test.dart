import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_source.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/avatar/avatar_web_page.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/fake_auth.dart';
import '../support/fake_avatar_page.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  final remote = AvatarSource.parse('https://koi.example.com/avatar-host');
  final callScreen = find.byType(AvatarCallScreen);
  final loading = find.byKey(const Key('avatar-loading'));
  final fallback = find.byKey(const Key('avatar-fallback'));

  late FakeAvatarPages pages;
  late MemorySettingsPrefsStore store;
  late SimulatedAvatarStateSource sim;

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    AvatarSource? source,
    AvatarType stored = AvatarType.male,
    bool simulate = false,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360, 800) * 3;
    addTearDown(tester.view.reset);
    pages = FakeAvatarPages();
    store = MemorySettingsPrefsStore({'u1': SettingsPrefs(avatarType: stored)});
    sim = SimulatedAvatarStateSource();
    final scope = ProviderScope(
      overrides: [
        ...overridesFor(
          FakeAuthService(
            fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
          ),
          onboardingStore(complete: true),
          settings: store,
        ),
        if (source != null) avatarSourceProvider.overrideWithValue(source),
        avatarWebPageFactoryProvider.overrideWithValue(pages.create),
        if (simulate)
          avatarStateSourceFactoryProvider.overrideWithValue(() => sim),
      ],
      child: const MaterialApp(home: AppShell()),
    );
    await tester.pumpWidget(scope);
    await tester.pump(const Duration(seconds: 2));
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> openCall(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('avatar-call-entry')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // route + first load
  }

  Future<void> endCall(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool inputEnabled(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: callScreen,
          matching: find.byKey(const Key('chat-input')),
        ),
      )
      .enabled!;

  testWidgets('no KOI_AVATAR_URL → placeholder image, no WebView made', (
    tester,
  ) async {
    await pumpShell(tester); // default provider: KOI_AVATAR_URL is empty
    await openCall(tester);
    expect(find.byKey(const Key('avatar-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('avatar-webview')), findsNothing);
    expect(pages.all, isEmpty);
    expect(inputEnabled(tester), isTrue);
  });

  testWidgets('remote: loads ?model=, shows loading until AVATAR_READY, then '
      'sends the current emotion', (tester) async {
    await pumpShell(tester, source: remote);
    await openCall(tester);
    final page = pages.last;

    expect(
      page.lastUrl.toString(),
      'https://koi.example.com/avatar-host?model=male',
    );
    expect(loading, findsOneWidget);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(inputEnabled(tester), isTrue);
    expect(page.scripts, isEmpty); // nothing before ready

    page.handlers.onMessage('SOMETHING_ELSE');
    await tester.pump();
    expect(loading, findsOneWidget);

    page.sendReady();
    await tester.pump();
    expect(loading, findsNothing);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(inputEnabled(tester), isTrue);
    expect(page.emotionCalls, [
      'window.AvatarController && '
          'window.AvatarController.setEmotion("neutral", 0.0);',
    ]);
    await endCall(tester);
  });

  testWidgets('conversation state: sent after AVATAR_READY and re-sent with '
      'the emotion after Reconnect', (tester) async {
    await pumpShell(tester, source: remote, simulate: true);
    await openCall(tester);
    final page = pages.last;
    final s = sim.startSession();
    sim.emit(
      AvatarStateUpdate(
        s,
        emotion: AvatarEmotion.joy,
        intensity: 0.5,
        conversationState: AvatarConversationState.listening,
      ),
    );
    await tester.pump();
    expect(page.scripts, isEmpty); // queued until ready

    page.sendReady();
    await tester.pump();
    expect(page.emotionCalls.last, contains('setEmotion("joy", 0.5)'));
    expect(page.stateCalls, [
      'window.AvatarController && '
          'window.AvatarController.setConversationState("listening");',
    ]);

    page.handlers.onMainFrameError();
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatar-reconnect')));
    await tester.pump();
    sim.emit(
      AvatarStateUpdate(s, conversationState: AvatarConversationState.thinking),
    );
    await tester.pump();
    expect(page.stateCalls, hasLength(1)); // not ready: queued
    page.sendReady();
    await tester.pump();
    expect(page.emotionCalls, hasLength(2));
    expect(page.emotionCalls.last, contains('setEmotion("joy", 0.5)'));
    expect(page.stateCalls, hasLength(2));
    expect(page.stateCalls.last, contains('setConversationState("thinking")'));
    await endCall(tester);
  });

  for (final avatar in AvatarType.values) {
    testWidgets('${avatar.name}: Chat card, call placeholder and fallback '
        'show ${avatar.imageAsset}', (tester) async {
      await pumpShell(tester, stored: avatar);
      String assetIn(Finder area) =>
          (tester
                      .widget<Image>(
                        find
                            .descendant(of: area, matching: find.byType(Image))
                            .first,
                      )
                      .image
                  as AssetImage)
              .assetName;

      // Chat card (no call screen yet).
      final card = find.byKey(ValueKey('avatar-image-${avatar.name}'));
      expect(card, findsOneWidget);
      expect(assetIn(card), avatar.imageAsset);

      await openCall(tester);
      final placeholder = find.byKey(const Key('avatar-placeholder'));
      expect(placeholder, findsOneWidget);
      expect(
        (tester.widget<Image>(placeholder).image as AssetImage).assetName,
        avatar.imageAsset,
      );

      final avatarCtl = tester
          .widget<AvatarView>(find.byType(AvatarView))
          .controller;
      avatarCtl.markFailed();
      await tester.pump();
      expect(fallback, findsOneWidget);
      expect(assetIn(fallback), avatar.imageAsset);
      await endCall(tester);
    });
  }

  testWidgets('remote: the WebView may not leave the avatar origin', (
    tester,
  ) async {
    await pumpShell(tester, source: remote);
    await openCall(tester);
    final allow = pages.last.handlers.allowNavigation;
    expect(allow('https://koi.example.com/avatar-host?model=female'), isTrue);
    expect(allow('https://evil.example.com/'), isFalse);
    expect(allow('http://koi.example.com/avatar-host'), isFalse);
    expect(allow('intent://scan#Intent;end'), isFalse);
    await endCall(tester);
  });

  testWidgets('20 s without AVATAR_READY → fallback with the selected avatar '
      '+ Reconnect; Reconnect reloads and re-sends the emotion', (
    tester,
  ) async {
    await pumpShell(tester, source: remote, stored: AvatarType.female);
    await openCall(tester);
    final page = pages.last;

    await tester.pump(const Duration(seconds: 18));
    expect(fallback, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(fallback, findsOneWidget);
    expect(
      find.descendant(
        of: fallback,
        matching: find.byKey(const ValueKey('avatar-image-female')),
      ),
      findsOneWidget,
    );
    expect(find.text('Avatar offline'), findsOneWidget);
    expect(inputEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('avatar-reconnect')));
    await tester.pump();
    expect(page.loads, hasLength(2));
    expect(loading, findsOneWidget);
    page.sendReady();
    await tester.pump();
    expect(fallback, findsNothing);
    expect(page.emotionCalls, hasLength(1));
    expect(pages.all, hasLength(1)); // same WebView, reloaded
    await endCall(tester);
  });

  testWidgets('page load error → fallback', (tester) async {
    await pumpShell(tester, source: remote);
    await openCall(tester);
    pages.last.handlers.onMainFrameError();
    await tester.pump();
    expect(fallback, findsOneWidget);
    await endCall(tester);
  });

  testWidgets('page reloads itself → not ready until the next AVATAR_READY', (
    tester,
  ) async {
    await pumpShell(tester, source: remote, simulate: true);
    await openCall(tester);
    final page = pages.last;
    page.sendReady();
    final s = sim.startSession();
    sim.emit(AvatarStateUpdate(s, emotion: AvatarEmotion.joy, intensity: 0.4));
    await tester.pump();
    expect(page.emotionCalls.last, contains('setEmotion("joy", 0.4)'));

    page.handlers.onPageStarted(); // e.g. the page reloaded after a crash
    await tester.pump();
    expect(loading, findsOneWidget);
    sim.emit(AvatarStateUpdate(s, emotion: AvatarEmotion.fun, intensity: 0.9));
    await tester.pump();
    final before = page.emotionCalls.length;
    page.sendReady();
    await tester.pump();
    expect(page.emotionCalls.length, before + 1);
    expect(page.emotionCalls.last, contains('setEmotion("fun", 0.9)'));
    await endCall(tester);
  });

  testWidgets('conversation updates for an old session are dropped', (
    tester,
  ) async {
    await pumpShell(tester, source: remote, simulate: true);
    await openCall(tester);
    final page = pages.last;
    page.sendReady();
    final old = sim.startSession();
    final current = sim.startSession();
    sim.emit(
      AvatarStateUpdate(old, emotion: AvatarEmotion.angry, intensity: 1),
    );
    await tester.pump();
    expect(page.emotionCalls.where((c) => c.contains('angry')), isEmpty);
    sim.emit(
      AvatarStateUpdate(current, emotion: AvatarEmotion.sorrow, intensity: 0.5),
    );
    await tester.pump();
    expect(page.emotionCalls.last, contains('setEmotion("sorrow", 0.5)'));
    await endCall(tester);
  });

  testWidgets('reopening the call screen: one live WebView, old page ignored', (
    tester,
  ) async {
    await pumpShell(tester, source: remote);
    await openCall(tester);
    final first = pages.last;
    await endCall(tester);
    expect(first.disposed, isTrue);
    expect(pages.live, isEmpty);

    await openCall(tester);
    expect(pages.all, hasLength(2));
    expect(pages.live, hasLength(1));
    final second = pages.last;

    // A late message from the first page changes nothing.
    first.sendReady();
    await tester.pump();
    expect(loading, findsOneWidget);
    expect(first.scripts, isEmpty);

    second.sendReady();
    await tester.pump();
    expect(loading, findsNothing);
    expect(second.emotionCalls, hasLength(1));
    await endCall(tester);
    expect(pages.live, isEmpty);
  });

  /// App to the background and back, through the states Flutter allows.
  void backgroundAndReturn(WidgetTester tester) {
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('back from the background: a lost page is reloaded', (
    tester,
  ) async {
    await pumpShell(tester, source: remote);
    await openCall(tester);
    final page = pages.last;
    page.sendReady();
    await tester.pump();

    backgroundAndReturn(tester);
    await tester.pump();
    expect(page.aliveChecks, 1);
    expect(page.loads, hasLength(1)); // alive: nothing to do

    page.alive = false;
    backgroundAndReturn(tester);
    await tester.pump();
    expect(page.loads, hasLength(2));
    expect(loading, findsOneWidget);
    page.sendReady();
    await tester.pump();
    expect(page.emotionCalls, hasLength(2)); // restored after reload
    expect(tester.takeException(), isNull);
    await endCall(tester);
  });

  group('avatar selection', () {
    testWidgets('stored female → Chat card and call placeholder', (
      tester,
    ) async {
      await pumpShell(tester, stored: AvatarType.female);
      expect(
        find.descendant(
          of: find.byKey(const Key('avatar-card')),
          matching: find.byKey(const ValueKey('avatar-image-female')),
        ),
        findsOneWidget,
      );
      await openCall(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('avatar-view')),
          matching: find.byKey(const ValueKey('avatar-image-female')),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Settings "Avatar" row saves avatarType and updates Chat live',
      (tester) async {
        final container = await pumpShell(tester);
        expect(find.byKey(const ValueKey('avatar-image-male')), findsOneWidget);

        await tester.tap(find.byKey(const Key('nav-tab-settings')));
        await settle(tester);
        final row = find.byKey(const Key('row-avatar-type'));
        await tester.ensureVisible(row);
        await tester.pump();
        expect(
          find.descendant(of: row, matching: find.text('Male')),
          findsOneWidget,
        );
        await tester.tap(row);
        await tester.pump();
        expect(
          find.descendant(of: row, matching: find.text('Female')),
          findsOneWidget,
        );
        expect(find.text('Avatar changed to Female'), findsOneWidget);
        expect(store.values['u1']!.avatarType, AvatarType.female);
        expect(container.read(selectedAvatarProvider), AvatarType.female);
        // Companion choice untouched.
        expect(store.values['u1']!.companion, SettingsPrefs.defaultCompanion);

        await tester.tap(find.byKey(const Key('nav-tab-chat')));
        await settle(tester);
        expect(
          find.descendant(
            of: find.byKey(const Key('avatar-card')),
            matching: find.byKey(const ValueKey('avatar-image-female')),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4)); // toast timer
      },
    );

    testWidgets(
      'remote: changing the avatar during a call reloads with the new '
      '?model= and re-sends the emotion',
      (tester) async {
        final container = await pumpShell(
          tester,
          source: remote,
          stored: AvatarType.female,
        );
        await openCall(tester);
        final page = pages.last;
        expect(page.lastUrl!.queryParameters['model'], 'female');
        page.sendReady();
        await tester.pump();

        container.read(selectedAvatarProvider.notifier).select(AvatarType.male);
        await tester.pump();
        expect(page.loads, hasLength(2));
        expect(page.lastUrl!.queryParameters['model'], 'male');
        expect(loading, findsOneWidget);
        page.sendReady();
        await tester.pump();
        expect(page.emotionCalls, hasLength(2));
        await endCall(tester);
      },
    );
  });

  test('the real page uses the KoiBridge channel name', () {
    expect(koiBridgeChannel, 'KoiBridge');
    expect(AvatarViewController.readyMessage, 'AVATAR_READY');
  });
}
