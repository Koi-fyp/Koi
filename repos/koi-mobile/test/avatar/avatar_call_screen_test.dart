import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/widgets/chat_widgets.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  const callInput = Key('chat-input');
  final callScreen = find.byType(AvatarCallScreen);
  final panel = find.byKey(const Key('transcript-panel'));

  /// The shell at [size] dp, optionally with a keyboard of [keyboard] dp.
  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 1);
    tester.view.viewPadding = const FakeViewPadding(top: 108, bottom: 1);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(complete: true),
            // Raza → the male avatar (Koi would show no avatar).
            settings: MemorySettingsPrefsStore({
              'u1': const SettingsPrefs(companion: 'raza'),
            }),
          ),
          ...chatOverrides(),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  /// Opens the call screen with the Chat button (or, with [avatar], pushes
  /// it directly so the test can drive the avatar), one frame at a time.
  Future<void> openCall(
    WidgetTester tester, {
    AvatarViewController? avatar,
  }) async {
    if (avatar == null) {
      await tester.tap(find.byKey(const Key('avatar-call-entry')));
    } else {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => AvatarCallScreen(avatarController: avatar),
            ),
          );
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // route transition
  }

  /// skipOffstage: false because a pushed route's first frame is built
  /// offstage, and that is the frame where it must still be disabled.
  bool inputEnabled(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byType(AvatarCallScreen, skipOffstage: false),
          matching: find.byKey(callInput, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .enabled!;

  bool? toggled(WidgetTester tester, String key) => tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties
      .toggled;

  /// Lets any open toast time out (3s) so no timer is left pending.
  Future<void> drainToasts(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 4));

  testWidgets('Chat has the entry button; it opens the call screen', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.byKey(const Key('avatar-call-entry')), findsOneWidget);
    await openCall(tester);

    expect(callScreen, findsOneWidget);
    expect(find.byKey(const Key('avatar-view')), findsOneWidget);
    expect(find.byKey(const Key('avatar-placeholder')), findsOneWidget);
    for (final k in ['call-mic', 'call-camera', 'call-text', 'call-end']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(
      find.descendant(of: callScreen, matching: find.byType(InputBar)),
      findsOneWidget,
    );
    expect(panel, findsNothing); // transcript starts closed
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout at 360dp: avatar is the main area, controls at bottom', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCall(tester);

    final avatar = tester.getRect(find.byKey(const Key('avatar-view')));
    final screen = tester.getRect(callScreen);
    expect(avatar.height, greaterThan(screen.height * 0.5));
    expect(avatar.width, greaterThan(300)); // 360 minus gutters + shadow
    expect(avatar.left, greaterThanOrEqualTo(0));
    expect(avatar.right, lessThanOrEqualTo(360));
    final end = tester.getRect(find.byKey(const Key('call-end')));
    expect(end.bottom, lessThanOrEqualTo(800));
    expect(end.top, greaterThan(avatar.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 800), Size(360, 640)]) {
    testWidgets('keyboard open at ${size.width.toInt()}x'
        '${size.height.toInt()}dp: no overflow, input + controls visible', (
      tester,
    ) async {
      // 911px IME at 360x800 (phone adb metrics) ≈ 304dp.
      await pumpShell(tester, size: size, keyboard: 304);
      await openCall(tester);
      await tester.tap(find.byKey(const Key('transcript-toggle')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final input = tester.getRect(
        find.descendant(of: callScreen, matching: find.byKey(callInput)),
      );
      final end = tester.getRect(find.byKey(const Key('call-end')));
      expect(end.bottom, lessThanOrEqualTo(size.height - 304));
      expect(find.text('Mic'), findsNothing); // labels hidden for room
      expect(input.bottom, lessThanOrEqualTo(end.top));
      expect(
        tester.getSize(find.byKey(const Key('avatar-view'))).height,
        greaterThan(0),
      );
    });
  }

  testWidgets('input and send work before the avatar is ready', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('avatar-call-entry')));
    await tester.pump(); // first frame of the call screen

    expect(inputEnabled(tester), isTrue);
    // InputBar.disabled would block send (_submit and the send button).
    expect(
      tester
          .widget<InputBar>(
            find.descendant(
              of: find.byType(AvatarCallScreen, skipOffstage: false),
              matching: find.byType(InputBar, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .disabled,
      isFalse,
    );
    expect(find.text('Connecting…', skipOffstage: false), findsOneWidget);

    await tester.pump(); // placeholder calls onReady right away
    await tester.pump(const Duration(seconds: 1));
    expect(inputEnabled(tester), isTrue);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('transcript toggle shows the shared conversation', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCall(tester);

    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(find.text(AvatarCallScreen.emptyTranscript), findsOneWidget);

    // Send through the same chat controller the Chat screen uses.
    await tester.enterText(
      find.descendant(of: callScreen, matching: find.byKey(callInput)),
      'Hi avatar',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: callScreen,
        matching: find.byKey(const Key('chat-send')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(of: panel, matching: find.text('Hi avatar')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text(ConversationService.fallbackReply),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('transcript-close')));
    await tester.pump();
    expect(panel, findsNothing);

    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(panel, findsOneWidget);
    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(panel, findsNothing);

    // Ending the call: the same messages are on the Chat screen.
    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pumpAndSettle(); // exit transition, route removed
    expect(callScreen, findsNothing);
    expect(find.text('Hi avatar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android back closes the transcript first, then returns to Chat',
    (tester) async {
      await pumpShell(tester);
      await openCall(tester);
      await tester.tap(find.byKey(const Key('transcript-toggle')));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(panel, findsNothing);
      expect(callScreen, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(callScreen, findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
    },
  );

  testWidgets('End call returns to Chat even with the transcript open', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCall(tester);
    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pumpAndSettle();
    expect(callScreen, findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('avatar failed: the user can still type and send (chat never '
      'depends on the avatar)', (tester) async {
    final avatar = AvatarViewController();
    addTearDown(avatar.dispose);
    await pumpShell(tester);
    await openCall(tester, avatar: avatar);
    avatar.markFailed();
    await tester.pump();
    expect(find.byKey(const Key('avatar-fallback')), findsOneWidget);

    final input = find.descendant(
      of: callScreen,
      matching: find.byKey(callInput),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Still here?');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: callScreen,
        matching: find.byKey(const Key('chat-send')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(
      find.descendant(of: panel, matching: find.text('Still here?')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text(ConversationService.fallbackReply),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('avatar-fallback')), findsOneWidget);
    expect(inputEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallback: static Male.png + Reconnect; input stays enabled', (
    tester,
  ) async {
    final avatar = AvatarViewController();
    addTearDown(avatar.dispose);
    await pumpShell(tester);
    await openCall(tester, avatar: avatar);
    expect(inputEnabled(tester), isTrue);

    avatar.markFailed(); // what a WebView load error will call
    await tester.pump();

    final fallback = find.byKey(const Key('avatar-fallback'));
    expect(fallback, findsOneWidget);
    expect(find.byKey(const Key('avatar-placeholder')), findsNothing);
    final image = tester.widget<Image>(
      find.descendant(of: fallback, matching: find.byType(Image)),
    );
    expect((image.image as AssetImage).assetName, 'assets/images/Male.png');
    expect(find.text(AvatarView.reconnectLabel), findsOneWidget);
    expect(find.text('Avatar offline'), findsOneWidget);
    expect(inputEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('avatar-reconnect')));
    await tester.pump(); // loading
    await tester.pump(); // placeholder ready again
    expect(fallback, findsNothing);
    expect(find.byKey(const Key('avatar-placeholder')), findsOneWidget);
    expect(avatar.isReady, isTrue);
    expect(inputEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallback fits with the keyboard open (button only)', (
    tester,
  ) async {
    final avatar = AvatarViewController();
    addTearDown(avatar.dispose);
    await pumpShell(tester, size: const Size(360, 640), keyboard: 304);
    await openCall(tester, avatar: avatar);
    avatar.markFailed();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('avatar-reconnect')), findsOneWidget);
  });

  testWidgets('placeholder shows the current emotion', (tester) async {
    final avatar = AvatarViewController();
    addTearDown(avatar.dispose);
    await pumpShell(tester);
    await openCall(tester, avatar: avatar);
    final label = find.byKey(const Key('avatar-emotion-label'));
    expect(
      find.descendant(of: label, matching: find.text('neutral')),
      findsOneWidget,
    );

    avatar.setEmotion(AvatarEmotion.joy, 0.8);
    await tester.pump();
    expect(
      find.descendant(of: label, matching: find.text('joy')),
      findsOneWidget,
    );
  });

  testWidgets('controls: Camera greyed out, tap = coming-soon toast only; '
      'Mic enabled (Prompt 26); text stays on; no camera preview', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCall(tester);
    final inputBar = find.descendant(
      of: callScreen,
      matching: find.byType(InputBar),
    );
    double opacity(String key) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byKey(const Key('call-button-opacity')),
          ),
        )
        .opacity;
    bool? enabled(String key) => tester
        .widget<Semantics>(
          find
              .descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .enabled;

    expect(toggled(tester, 'call-text'), isTrue);
    expect(opacity('call-camera'), 0.4);
    expect(enabled('call-camera'), isFalse);
    expect(toggled(tester, 'call-camera'), isNull);
    expect(opacity('call-mic'), 1);
    expect(enabled('call-mic'), isNull);
    expect(toggled(tester, 'call-mic'), isFalse);
    expect(opacity('call-text'), 1);
    expect(opacity('call-end'), 1);

    await tester.tap(find.byKey(const Key('call-camera')));
    await tester.pump();
    expect(find.text(AvatarCallScreen.cameraSoon), findsOneWidget);
    expect(toggled(tester, 'call-text'), isTrue);
    expect(inputBar, findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    expect(find.byType(PlatformViewSurface), findsNothing);

    await tester.tap(find.byKey(const Key('call-text')));
    await tester.pump();
    expect(toggled(tester, 'call-text'), isTrue);
    expect(tester.takeException(), isNull);
    await drainToasts(tester);
  });
}
