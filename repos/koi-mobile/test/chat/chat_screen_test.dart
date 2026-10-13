import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/chat/widgets/chat_widgets.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  Future<
    ({
      MemoryMessageStore store,
      RecordingSyncQueue queue,
      FakeOnlineStatus online,
    })
  >
  pumpChat(WidgetTester tester, {bool online = true}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    final store = MemoryMessageStore();
    final queue = RecordingSyncQueue();
    final status = FakeOnlineStatus(online: online);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(complete: true),
          ),
          ...chatOverrides(online: status, store: store, queue: queue),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    return (store: store, queue: queue, online: status);
  }

  testWidgets('empty chat: avatar panel, hero, CTA, input; no overflow', (
    tester,
  ) async {
    await pumpChat(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byKey(const Key('avatar-card')), findsOneWidget);
    expect(find.text('Try other avatars too!'), findsOneWidget);
    expect(find.byType(HeroText), findsOneWidget);
    expect(find.text(InputBar.placeholder), findsOneWidget);
    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });

  testWidgets('sending: user bubble, then the fallback reply; panel hides', (
    tester,
  ) async {
    final env = await pumpChat(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'Hello KOI');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Hello KOI'), findsOneWidget);
    expect(find.text(ConversationService.fallbackReply), findsOneWidget);
    expect(
      find.byKey(const Key('avatar-card')),
      findsNothing,
    ); // hidden sm:flex
    expect(tester.takeException(), isNull);

    // Stored + queued encrypted (FakeCipher output), never plaintext.
    expect(env.queue.items, hasLength(2));
    for (final i in env.queue.items) {
      expect(i.data['content'], startsWith('v1:FAKE:'));
      expect(i.data.toString(), isNot(contains('Hello KOI')));
    }
  });

  testWidgets('send button disabled until there is text', (tester) async {
    final env = await pumpChat(tester);
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    expect(env.queue.items, isEmpty);
  });

  testWidgets('offline banner shows while offline', (tester) async {
    final env = await pumpChat(tester, online: false);
    expect(find.text(OfflineBanner.text), findsOneWidget);
    env.online.set(true);
    // The StreamProvider update is delivered through Riverpod's scheduler;
    // allow it one extra frame.
    await tester.pump();
    await tester.pump();
    expect(find.text(OfflineBanner.text), findsNothing);
  });

  group('fits the real 360dp phone (Infinix X663)', () {
    // adb: 1080x2400 @ 480dpi (3.0) → 360x800dp; status bar 108px, gesture
    // nav 1px, keyboard (IME visibleFrame) 911px.
    void phone(WidgetTester tester, {bool keyboard = false}) {
      tester.view.padding = const FakeViewPadding(top: 108, bottom: 1);
      tester.view.viewPadding = const FakeViewPadding(top: 108, bottom: 1);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 911 : 0);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('normal view: no overflow, whole panel + input on screen', (
      tester,
    ) async {
      await pumpChat(tester);
      phone(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      final screen = tester.getRect(find.byType(ChatScreen));
      expect(find.byKey(const Key('avatar-card')), findsOneWidget);
      for (final key in ['avatar-card', 'avatar-cta', 'chat-input']) {
        final r = tester.getRect(find.byKey(Key(key)));
        expect(r.bottom, lessThanOrEqualTo(screen.bottom), reason: key);
        expect(r.top, greaterThanOrEqualTo(screen.top), reason: key);
      }
    });

    testWidgets('keyboard open: no overflow, input stays visible', (
      tester,
    ) async {
      await pumpChat(tester);
      phone(tester, keyboard: true);
      await settle(tester);
      expect(tester.takeException(), isNull);
      final input = tester.getRect(find.byKey(const Key('chat-input')));
      expect(input.bottom, lessThanOrEqualTo(800 - 911 / 3));
    });

    testWidgets('keyboard open with a long multi-line draft: no overflow', (
      tester,
    ) async {
      await pumpChat(tester);
      phone(tester, keyboard: true);
      await tester.enterText(
        find.byKey(const Key('chat-input')),
        List.filled(12, 'a fairly long line of draft text').join('\n'),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long messages with the keyboard open: no overflow, newest '
        'reply visible', (tester) async {
      await pumpChat(tester);
      phone(tester, keyboard: true);
      await tester.enterText(
        find.byKey(const Key('chat-input')),
        List.filled(40, 'a very long message').join(' '),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send')));
      await settle(tester);
      await tester.pumpAndSettle(); // let scroll-to-bottom finish
      expect(tester.takeException(), isNull);

      // The reply sits below a bubble taller than the list; it must be
      // scrolled into view (an estimated maxScrollExtent overshot it).
      final reply = find.text(ConversationService.fallbackReply);
      expect(reply, findsOneWidget);
      final list = tester.getRect(find.byKey(const Key('message-list')));
      final r = tester.getRect(reply);
      expect(r.top, greaterThanOrEqualTo(list.top));
      expect(r.bottom, lessThanOrEqualTo(list.bottom));
    });

    testWidgets('a short conversation starts at the top of the list (web)', (
      tester,
    ) async {
      await pumpChat(tester);
      phone(tester);
      await tester.enterText(find.byKey(const Key('chat-input')), 'Hi');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send')));
      await settle(tester);
      await tester.pumpAndSettle();
      final screen = tester.getRect(find.byType(ChatScreen));
      final first = tester.getRect(find.byKey(const Key('bubble-user')));
      // padding-top 16 + bubble padding 8
      expect(first.top - screen.top, moreOrLessEquals(24, epsilon: 1));
    });

    testWidgets('"Try other avatars too!" is tappable and focuses the input '
        '(web: inputRef.current?.focus())', (tester) async {
      await pumpChat(tester);
      phone(tester);
      await settle(tester);
      await tester.tap(find.byKey(const Key('avatar-cta')));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('chat-input')),
      );
      expect(field.focusNode!.hasFocus, isTrue);

      // Keyboard dismissed with Back keeps focus; tapping again must
      // re-show the keyboard instead of doing nothing.
      tester.testTextInput.log.clear();
      await tester.tap(find.byKey(const Key('avatar-cta')));
      await tester.pump();
      expect(
        tester.testTextInput.log.map((c) => c.method),
        contains('TextInput.show'),
      );
    });

    testWidgets('keyboard open: avatar panel hides so the chat fits', (
      tester,
    ) async {
      await pumpChat(tester);
      phone(tester, keyboard: true);
      await settle(tester);
      expect(find.byKey(const Key('avatar-card')), findsNothing);
      expect(find.byType(HeroText), findsOneWidget);
      phone(tester);
      await settle(tester);
      expect(find.byKey(const Key('avatar-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('time format follows the 12/24h setting, 2-digit like web', () {
    final t = DateTime(2026, 10, 13, 8, 5);
    expect(formatTime(t, use24h: false), '08:05 AM');
    expect(formatTime(DateTime(2026, 1, 1, 0, 7), use24h: false), '12:07 AM');
    expect(formatTime(DateTime(2026, 1, 1, 13, 0), use24h: true), '13:00');
  });
}
