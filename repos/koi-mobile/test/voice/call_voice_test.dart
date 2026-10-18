import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/voice/voice_controller.dart';
import 'package:koi_mobile/voice/voice_providers.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';
import 'fakes.dart';

/// The chat service: streams [reply] as one delta, runs [during] (risk,
/// handoff, …), waits for [gate] if set, then `done`.
class ScriptedChatApi extends ChatApiClient {
  ScriptedChatApi() : super(baseUrl: 'https://chat.example.test');

  String reply = 'Hello there.';
  void Function(ChatHandlers h)? during;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
    AudioUpload? audio,
  }) async {
    calls++;
    handlers.onEvent?.call('delta');
    handlers.onDelta?.call(reply);
    during?.call(handlers);
    final g = gate;
    if (g != null) await g.future;
    return ChatStreamResult(
      fullText: reply,
      companionState: CompanionState.fallback,
      latencyMs: 1,
      exerciseStateChanged: false,
      exerciseState: null,
    );
  }
}

void main() {
  useRealFonts();

  late ScriptedChatApi chat;
  late FakeSpeechServer speech;
  late FakeClipPlayer player;
  late FakeTtsEngine tts;
  late MemoryKeyValueStore prefs;
  late bool speechWarm;

  setUp(() {
    chat = ScriptedChatApi();
    speech = FakeSpeechServer();
    player = FakeClipPlayer()..hold = true;
    tts = FakeTtsEngine()..hold = true;
    prefs = MemoryKeyValueStore();
    speechWarm = true;
  });

  Future<ProviderContainer> pumpCall(
    WidgetTester tester, {
    String companion = 'raza',
    String? language,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 1);
    tester.view.viewPadding = const FakeViewPadding(top: 108, bottom: 1);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            )..fakeToken = 'fake-test-token',
            onboardingStore(complete: true),
            settings: MemorySettingsPrefsStore({
              'u1': SettingsPrefs(companion: companion, language: language),
            }),
          ),
          ...chatOverrides(api: chat),
          backendWarmupProvider.overrideWith(
            (ref) => BackendWarmup(chatHealth: null),
          ),
          speechApiProvider.overrideWithValue(fakeApi(speech)),
          speechWarmupProvider.overrideWithValue(
            SpeechWarmup(
              health: (_) async => speechWarm,
              // Not warm: no retry timer left behind.
              delay: (_) => Completer<void>().future,
            ),
          ),
          clipPlayerFactoryProvider.overrideWithValue(() => player),
          ttsEngineFactoryProvider.overrideWithValue(() => tts),
          voicePrefsProvider.overrideWithValue(VoicePrefs(prefs)),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await tester.tap(find.byKey(const Key('avatar-call-entry')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return container;
  }

  Future<void> send(WidgetTester tester, [String text = 'hi']) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AvatarCallScreen),
        matching: find.byKey(const Key('chat-input')),
      ),
      text,
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AvatarCallScreen),
        matching: find.byKey(const Key('chat-send')),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  AvatarViewController avatar(WidgetTester tester) =>
      tester.widget<AvatarView>(find.byType(AvatarView)).controller;

  final label = find.byKey(const Key('voice-label'));

  testWidgets('speaks only after done, with the server voice and label', (
    tester,
  ) async {
    chat.gate = Completer<void>();
    await pumpCall(tester);
    await send(tester);
    // Streaming: nothing spoken yet, the avatar shows "thinking".
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(avatar(tester).conversationState, AvatarConversationState.thinking);

    chat.gate!.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(speech.requests.single['text'], 'Hello there.');
    expect(speech.requests.single['voice_id'], 'raza_en');
    expect(player.played, hasLength(1));
    expect(find.text(AvatarCallScreen.serverVoiceLabel), findsOneWidget);
    expect(avatar(tester).conversationState, AvatarConversationState.speaking);

    player.finish();
    await tester.pump(const Duration(milliseconds: 100));
    expect(label, findsNothing);
    expect(avatar(tester).conversationState, AvatarConversationState.idle);
  });

  testWidgets('not warm → device voice and its label; Aisha voice', (
    tester,
  ) async {
    speechWarm = false;
    await pumpCall(tester, companion: 'aisha');
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken.single, ('Hello there.', 'en'));
    expect(find.text(AvatarCallScreen.deviceVoiceLabel), findsOneWidget);
    tts.finish();
    await tester.pump(const Duration(milliseconds: 100));
    expect(label, findsNothing);
  });

  testWidgets('server error → device voice, never an error on screen', (
    tester,
  ) async {
    speech.respond = (_) async =>
        FakeSpeechServer.error(503, 'speech-unavailable');
    await pumpCall(tester, companion: 'aisha');
    await send(tester);
    expect(speech.requests.single['voice_id'], 'aisha_en');
    expect(tts.spoken, hasLength(1));
    expect(find.textContaining('speech-unavailable'), findsNothing);
    expect(find.text(AvatarCallScreen.deviceVoiceLabel), findsOneWidget);
    tts.finish();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Koi fox: voice only (Raza), no avatar', (tester) async {
    await pumpCall(tester, companion: 'koi');
    expect(find.byType(AvatarView), findsNothing);
    await send(tester);
    expect(speech.requests.single['voice_id'], 'raza_en');
    expect(find.text(AvatarCallScreen.serverVoiceLabel), findsOneWidget);
    player.finish();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Roman Urdu for an Urdu user is not spoken', (tester) async {
    chat.reply = 'Aap kaise hain?';
    await pumpCall(tester, language: 'ur');
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  testWidgets('crisis handoff during the turn: never spoken', (tester) async {
    chat.during = (h) =>
        h.onHandoff?.call(const Handoff(to: 'crisis', reason: 'test'));
    final container = await pumpCall(tester);
    await send(tester);
    expect(container.read(safetyControllerProvider).crisis, isNotNull);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  testWidgets('voice toggle: off stops and silences, remembered per uid', (
    tester,
  ) async {
    await pumpCall(tester);
    final toggle = find.byKey(const Key('voice-toggle'));
    expect(find.text('Voice on'), findsOneWidget);
    await send(tester);
    expect(player.isPlaying, isTrue);

    await tester.tap(toggle);
    await tester.pump();
    expect(player.isPlaying, isFalse, reason: 'off stops at once');
    expect(find.text('Voice off'), findsOneWidget);
    expect(prefs.values['koi_voice_enabled_u1'], 'false');

    await send(tester, 'again');
    expect(speech.requests, hasLength(1), reason: 'off: nothing new');
    expect(tts.spoken, isEmpty);

    await tester.tap(toggle);
    await tester.pump();
    expect(prefs.values['koi_voice_enabled_u1'], 'true');
  });

  testWidgets('voice off is restored when the call screen opens', (
    tester,
  ) async {
    prefs.values['koi_voice_enabled_u1'] = 'false';
    await pumpCall(tester);
    expect(find.text('Voice off'), findsOneWidget);
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
    // Voice off: streaming shows speaking, as before Prompt 25.
  });

  testWidgets('a new message stops the reply that is playing', (tester) async {
    await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    chat.gate = Completer<void>();
    await send(tester, 'next');
    expect(player.isPlaying, isFalse);
    expect(label, findsNothing);
    chat.gate!.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(player.played, hasLength(2));
    player.finish();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('End call stops the voice', (tester) async {
    await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pump();
    expect(player.isPlaying, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AvatarCallScreen), findsNothing);
  });

  testWidgets('companion switch stops the voice', (tester) async {
    final container = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    container
        .read(selectedAvatarProvider.notifier)
        .select(CompanionAvatar.aisha);
    await tester.pump();
    expect(player.isPlaying, isFalse);
  });

  testWidgets('crisis screen opening stops the voice', (tester) async {
    final container = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    container
        .read(safetyControllerProvider)
        .handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
    await tester.pump();
    expect(player.isPlaying, isFalse);
  });

  testWidgets('breathing screen opening stops the voice', (tester) async {
    final container = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    container
        .read(safetyControllerProvider)
        .handleUiAction(
          const UiAction(UiAction.startBreathing, {
            'inhale_s': 4,
            'exhale_s': 6,
            'cycles': 1,
            'cue_audio': ['in', 'out'],
          }),
        );
    await tester.pump();
    expect(player.isPlaying, isFalse);
    container.read(safetyControllerProvider).stopBreathing();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('app going to the background stops the voice', (tester) async {
    await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(player.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('leaving the call screen (back) stops the voice', (tester) async {
    await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AvatarCallScreen), findsNothing);
    expect(player.isPlaying, isFalse);
  });

  testWidgets('top bar fits 360dp with voice off and the transcript open', (
    tester,
  ) async {
    prefs.values['koi_voice_enabled_u1'] = 'false';
    await pumpCall(tester);
    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(find.text('Hide transcript'), findsOneWidget);
    expect(find.text('Voice off'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final status = tester.getRect(find.byKey(const Key('call-status')));
    expect(status.width, greaterThan(40));
  });

  testWidgets('the text Chat screen never speaks', (tester) async {
    await pumpCall(tester);
    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('chat-input')), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(chat.calls, 1);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });
}
