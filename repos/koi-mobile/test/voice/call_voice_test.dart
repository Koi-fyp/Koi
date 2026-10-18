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
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/environment/environment_palette.dart';
import 'package:koi_mobile/environment/environment_providers.dart';
import 'package:koi_mobile/modes/input_mode.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/voice/voice_controller.dart';
import 'package:koi_mobile/voice/voice_providers.dart';
import 'package:koi_mobile/voice/voice_text.dart' show chunkReply;

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

  /// Thrown before any event (the service then saves the fallback reply).
  Object? error;

  @override
  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
    AudioUpload? audio,
  }) async {
    calls++;
    final e = error;
    if (e != null) throw e;
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
    KoiInputMode mode = KoiInputMode.voice,
  }) async {
    prefs.values[ModePrefs.keyFor('u1')] = mode.id;
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
              // Not warm: the warm-up gives up at once (unavailable).
              limit: speechWarm ? const Duration(seconds: 240) : Duration.zero,
            ),
          ),
          clipPlayerFactoryProvider.overrideWithValue(() => player),
          ttsEngineFactoryProvider.overrideWithValue(() => tts),
          modePrefsProvider.overrideWithValue(ModePrefs(prefs)),
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

  testWidgets('ATC-M3-11 speaks only after done, with the server voice and label', (
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

  // Changed in Prompt 29: the device voice only once the speech service is
  // unavailable (its warm-up ended without a 200), not while it warms.
  testWidgets('ATC-M3-12 speech unavailable → device voice and its label; '
      'Aisha voice', (
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

  // Changed in Prompt 29: a failing chunk is skipped (was: device voice).
  testWidgets('ATC-M3-12 server error → chunk skipped: silent, no device voice, '
      'never an error on screen', (tester) async {
    speech.respond = (_) async =>
        FakeSpeechServer.error(503, 'speech-unavailable');
    await pumpCall(tester, companion: 'aisha');
    await send(tester);
    expect(speech.requests.single['voice_id'], 'aisha_en');
    expect(tts.spoken, isEmpty);
    expect(player.played, isEmpty);
    expect(find.textContaining('speech-unavailable'), findsNothing);
    expect(label, findsNothing);
  });

  // Changed in Prompt 29: the fox is text only (was: Raza's voice).
  testWidgets('ATC-M3-12 Koi fox: silent even with Voice saved, no avatar', (
    tester,
  ) async {
    final c = await pumpCall(tester, companion: 'koi');
    expect(find.byType(AvatarView), findsNothing);
    expect(c.read(effectiveInputModeProvider), KoiInputMode.text);
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(label, findsNothing);
  });

  testWidgets('ATC-M3-12 Roman Urdu for an Urdu user is not spoken', (tester) async {
    chat.reply = 'Aap kaise hain?';
    await pumpCall(tester, language: 'ur');
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  testWidgets('ATC-M3-13 crisis handoff during the turn: never spoken', (tester) async {
    chat.during = (h) =>
        h.onHandoff?.call(const Handoff(to: 'crisis', reason: 'test'));
    final container = await pumpCall(tester);
    await send(tester);
    expect(container.read(safetyControllerProvider).crisis, isNotNull);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  Future<void> selectMode(WidgetTester tester, KoiInputMode mode) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AvatarCallScreen),
        matching: find.byKey(const Key('mode-selector-button')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(Key('mode-item-${mode.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Changed in Prompt 29: the Voice on/off pill is replaced by the mode
  // menu; Text / Camera view are the "voice off" modes.
  testWidgets('ATC-M3-14 mode Text: switching stops the reply at once, later '
      'replies are silent, remembered per uid', (tester) async {
    await pumpCall(tester);
    expect(find.byKey(const Key('voice-toggle')), findsNothing);
    await send(tester);
    expect(player.isPlaying, isTrue);

    await selectMode(tester, KoiInputMode.text);
    expect(player.isPlaying, isFalse, reason: 'switching stops at once');
    expect(prefs.values['koi_input_mode_u1'], 'text');

    await send(tester, 'again');
    expect(speech.requests, hasLength(1), reason: 'Text: nothing new');
    expect(tts.spoken, isEmpty);

    await selectMode(tester, KoiInputMode.cameraVoice);
    expect(prefs.values['koi_input_mode_u1'], 'camera-voice');
  });

  testWidgets('ATC-M3-14 Text / Camera view saved: replies stay silent', (
    tester,
  ) async {
    for (final mode in [KoiInputMode.text, KoiInputMode.camera]) {
      speech.requests.clear();
      await pumpCall(tester, mode: mode);
      await send(tester, mode.id);
      expect(speech.requests, isEmpty, reason: mode.label);
      expect(tts.spoken, isEmpty, reason: mode.label);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('ATC-M3-15 a new message stops the reply that is playing', (tester) async {
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

  testWidgets('ATC-M3-15 End call stops the voice', (tester) async {
    await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pump();
    expect(player.isPlaying, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AvatarCallScreen), findsNothing);
  });

  testWidgets('ATC-M3-15 companion switch stops the voice', (tester) async {
    final container = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    container
        .read(selectedAvatarProvider.notifier)
        .select(CompanionAvatar.aisha);
    await tester.pump();
    expect(player.isPlaying, isFalse);
  });

  testWidgets('ATC-M3-15 crisis screen opening stops the voice', (tester) async {
    final container = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    container
        .read(safetyControllerProvider)
        .handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
    await tester.pump();
    expect(player.isPlaying, isFalse);
  });

  testWidgets('ATC-M3-15 breathing screen opening stops the voice', (tester) async {
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

  testWidgets('ATC-M3-15 app going to the background stops the voice', (tester) async {
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

  testWidgets('ATC-M3-15 leaving the call screen (back) stops the voice', (tester) async {
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

  // Changed in Prompt 29: the mode menu (longest label) instead of the
  // voice pill.
  testWidgets('ATC-M3-16 top bar fits 360dp with "Camera view + voice" and the '
      'transcript open', (tester) async {
    await pumpCall(tester, mode: KoiInputMode.cameraVoice);
    await tester.tap(find.byKey(const Key('transcript-toggle')));
    await tester.pump();
    expect(find.text('Hide transcript'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AvatarCallScreen),
        matching: find.text('Camera view + voice'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final status = tester.getRect(find.byKey(const Key('call-status')));
    expect(status.width, greaterThan(40));
  });

  testWidgets('ATC-M3-17 the text Chat screen never speaks', (tester) async {
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

  testWidgets('ATC-M3-35 a fallback ("trouble connecting") reply is never '
      'spoken, even with voice on and the speech server warm', (tester) async {
    chat.error = const ChatApiException('500');
    final c = await pumpCall(tester);
    await send(tester);
    await tester.pump(const Duration(seconds: 1));

    final last = c.read(chatControllerProvider('u1')).messages.last;
    expect(last.isFallback, isTrue);
    expect(last.content, ConversationService.fallbackReply);
    expect(c.read(effectiveInputModeProvider).spokenReplies, isTrue);
    expect(speech.requests, isEmpty);
    expect(player.played, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(label, findsNothing);
  });

  testWidgets('ATC-M21-20 one turn: companion_state reaches the avatar '
      '(setEmotion over the bridge) and the environment tint', (tester) async {
    final c = await pumpCall(tester);
    final view = avatar(tester);
    final sent = <String>[];
    view
      ..attachPage(Object(), run: (js) async => sent.add(js), reload: () {})
      ..markReady();
    sent.clear();
    final env = c.read(environmentControllerProvider);
    expect(env.mood, EnvironmentMood.neutral);

    chat.during = (h) =>
        h.onCompanionState?.call(const CompanionState(AvatarEmotion.joy, 0.8));
    await send(tester);
    await tester.pump(const Duration(seconds: 2));

    // Avatar: Dart state and the JS sent to the page.
    expect(view.emotion, AvatarEmotion.joy);
    expect(
      sent,
      contains(
        'window.AvatarController && '
        'window.AvatarController.setEmotion("joy", 0.8);',
      ),
    );
    // Environment: same turn, same emotion, painted at the call strength.
    expect(env.mood, EnvironmentMood.joy);
    final background = tester
        .widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(AvatarCallScreen),
                matching: find.byKey(const Key('environment-background')),
              )
              .first,
        )
        .color;
    expect(
      background,
      EnvironmentPalette.colorFor(
        EnvironmentMood.joy,
        EnvironmentPalette.callStrength,
      ),
    );
    player.finish();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('ATC-M3-46 a mixed-script reply is silent (no device voice)', (
    tester,
  ) async {
    chat.reply = 'Hello. آپ کیسے ہیں؟';
    await pumpCall(tester, companion: 'aisha');
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(label, findsNothing);
  });

  testWidgets('ATC-M3-47 Roman Urdu is silent for an English-setting user', (
    tester,
  ) async {
    chat.reply = 'Tum theek ho? Mujhe batao kya hua.';
    await pumpCall(tester, language: 'en');
    await send(tester);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  testWidgets('ATC-M3-48 exercise turn (a grounding / plan ui_action, which '
      'mobile does not run yet) is silent', (tester) async {
    for (final name in ['start_grounding', 'start_plan']) {
      speech.requests.clear();
      chat.during = (h) => h.onUiAction?.call(UiAction(name), false);
      final c = await pumpCall(tester);
      await send(tester);
      expect(speech.requests, isEmpty, reason: name);
      expect(tts.spoken, isEmpty, reason: name);
      expect(c.read(chatControllerProvider('u1')).exerciseStarts, 1);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('ATC-M3-48 a HIGH risk result in the turn is silent', (
    tester,
  ) async {
    chat.during = (h) => h.onRisk?.call(
      RiskResult.fromJson(const {'status': 'ok', 'risk_category': 'HIGH'}),
    );
    final c = await pumpCall(tester);
    await send(tester);
    expect(c.read(chatControllerProvider('u1')).textOnlyEvents, 1);
    expect(speech.requests, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  testWidgets('ATC-M3-49 sign-out / another uid stops the voice', (
    tester,
  ) async {
    final c = await pumpCall(tester);
    await send(tester);
    expect(player.isPlaying, isTrue);
    (c.read(authServiceProvider) as FakeAuthService).set(
      user: const KoiUser(uid: 'u2', isAnonymous: true),
    );
    await tester.pump();
    expect(player.isPlaying, isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('ATC-M3-50 the reply goes out in the planned chunks (short '
      'first, then 140–220), one voice', (tester) async {
    player.hold = false;
    chat.reply = List.generate(
      9,
      (i) => 'This is sentence number $i of a longer reply.',
    ).join(' ');
    await pumpCall(tester);
    await send(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final texts = speech.requests.map((r) => r['text']! as String).toList();
    expect(texts, chunkReply(chat.reply));
    expect(texts.first, 'This is sentence number 0 of a longer reply.');
    for (final t in texts.sublist(1, texts.length - 1)) {
      expect(t.length, inInclusiveRange(140, 220));
    }
    expect(speech.requests.map((r) => r['voice_id']).toSet(), {'raza_en'});
  });
}
