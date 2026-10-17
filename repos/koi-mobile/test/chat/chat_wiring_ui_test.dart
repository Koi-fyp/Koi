import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_source.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/widgets/chat_widgets.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

/// Holds every chat response until the test releases it (no network).
class _HeldAdapter implements HttpClientAdapter {
  final List<StreamController<Uint8List>> streams = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final c = StreamController<Uint8List>();
    streams.add(c);
    return ResponseBody(c.stream, 200);
  }

  void finish(String sse) {
    final c = streams.removeAt(0);
    c.add(Uint8List.fromList(utf8.encode(sse)));
    c.close();
  }

  @override
  void close({bool force = false}) {}
}

const _turn =
    'event: companion_state\ndata: {"emotion":"joy","intensity":0.6}\n\n'
    'event: delta\ndata: {"text":"Hi"}\n\n'
    'event: done\ndata: {"full_text":"Hi"}\n\n';

void main() {
  useRealFonts();

  Future<(_HeldAdapter, BackendWarmup, ProviderContainer)> pump(
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final adapter = _HeldAdapter();
    final warmup = BackendWarmup(chatHealth: null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            )..fakeToken = 'fake-test-token',
            onboardingStore(complete: true),
          ),
          ...chatOverrides(
            api: ChatApiClient(
              baseUrl: 'http://127.0.0.1:9',
              dio: Dio()..httpClientAdapter = adapter,
            ),
          ),
          backendWarmupProvider.overrideWith((ref) => warmup),
          avatarSourceProvider.overrideWithValue(AvatarSource.placeholder),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    return (adapter, warmup, container);
  }

  testWidgets('waking line after 3 s; typing allowed, Send off; cleared '
      'on the first event', (tester) async {
    final (adapter, _, _) = await pump(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('chat-waking')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(WakingLine.text), findsOneWidget);

    // Typing still works; sending a second message does not.
    final field = tester.widget<TextField>(find.byKey(const Key('chat-input')));
    expect(field.enabled, isTrue);
    await tester.enterText(find.byKey(const Key('chat-input')), 'next');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    expect(adapter.streams, hasLength(1));

    adapter.finish(_turn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('chat-waking')), findsNothing);
    expect(find.text('Hi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('call-screen source: session start, then the chat stream', (
    tester,
  ) async {
    final (adapter, _, container) = await pump(tester);
    final source = container.read(avatarStateSourceFactoryProvider)();
    final events = <AvatarStateEvent>[];
    // Not cancelled: inside testWidgets (Flutter 3.47) cancelling a
    // broadcast-stream subscription leaves the test unable to finish.
    source.events.listen(events.add);
    await tester.pump();
    expect(events.single, isA<AvatarSessionStarted>());
    expect(events.single.sessionId, 'u1');

    await tester.enterText(find.byKey(const Key('chat-input')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump(const Duration(milliseconds: 100));
    adapter.finish(_turn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final updates = events.whereType<AvatarStateUpdate>().toList();
    expect(
      updates.map((u) => (u.emotion, u.conversationState)),
      containsAllInOrder([
        (null, AvatarConversationState.thinking),
        (AvatarEmotion.joy, null),
        (null, AvatarConversationState.speaking),
        (null, AvatarConversationState.idle),
      ]),
    );
  });

  testWidgets('SafetyController callbacks feed the chat session', (
    tester,
  ) async {
    final (_, _, container) = await pump(tester);
    final session = container.read(chatSessionStateProvider);
    final safety = container.read(safetyControllerProvider);
    safety.onClientEvent!(ClientEvent.playbackDone);
    safety.onCrisisPath!(CrisisPath.misunderstanding);
    expect(session.pendingClientEvent, ClientEvent.playbackDone);
    expect(session.pendingCrisisPath, CrisisPath.misunderstanding);
  });

  testWidgets('DEBUG menu copies the last chat diagnostics line', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const line =
        '[KOI] chat: 09:05:07 status=303 hops=1 elapsed=1.0s backend_events=';
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showSafetyDebugMenu(
                context,
                ref.read(safetyControllerProvider),
                lastChatDiagnostics: () => line,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(copyChatDiagnosticsLabel),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(copyChatDiagnosticsLabel));
    await tester.pumpAndSettle();
    expect(copied, line);
  });
}
