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
    await tester.pump();
    expect(find.text(OfflineBanner.text), findsNothing);
  });

  test('time format follows the 12/24h setting, 2-digit like web', () {
    final t = DateTime(2026, 10, 13, 8, 5);
    expect(formatTime(t, use24h: false), '08:05 AM');
    expect(formatTime(DateTime(2026, 1, 1, 0, 7), use24h: false), '12:07 AM');
    expect(formatTime(DateTime(2026, 1, 1, 13, 0), use24h: true), '13:00');
  });
}
