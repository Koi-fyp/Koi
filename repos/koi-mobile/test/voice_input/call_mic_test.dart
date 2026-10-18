import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_controller.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/chat/widgets/chat_widgets.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/theme/koi_colors.dart';
import 'package:koi_mobile/voice/voice_controller.dart';
import 'package:koi_mobile/voice/voice_providers.dart';
import 'package:koi_mobile/voice_input/mic_controller.dart';
import 'package:koi_mobile/voice_input/mic_providers.dart';
import 'package:koi_mobile/voice_input/mic_widgets.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';
import '../voice/fakes.dart';
import 'fake_mic.dart';

/// Text turns reply at once; audio turns send `transcript` first. [fail]
/// makes the next audio turn fail (before any event).
class _ScriptedApi extends ChatApiClient {
  _ScriptedApi() : super(baseUrl: 'https://chat.example.test');

  final List<String?> audioPaths = [];
  final List<String> texts = [];
  Object? fail;

  @override
  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
    AudioUpload? audio,
  }) async {
    String reply;
    if (audio != null) {
      audioPaths.add(audio.path);
      final e = fail;
      fail = null;
      if (e != null) throw e;
      handlers.onEvent?.call('transcript');
      handlers.onTranscript?.call('I feel tired');
      reply = 'That sounds hard.';
    } else {
      texts.add(body['message']! as String);
      reply = 'Typed reply.';
    }
    handlers.onEvent?.call('delta');
    handlers.onDelta?.call(reply);
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

  late _ScriptedApi api;
  late FakeMicRecorder recorder;
  late FakeTtsEngine tts;
  late MemoryKeyValueStore prefs;
  late MemoryMessageStore store;
  late MicDiagnosticsLog diagnostics;
  late Directory dir;

  setUp(() {
    api = _ScriptedApi();
    recorder = FakeMicRecorder();
    tts = FakeTtsEngine()..hold = true;
    prefs = MemoryKeyValueStore();
    store = MemoryMessageStore();
    diagnostics = MicDiagnosticsLog();
    dir = Directory.systemTemp.createTempSync('koi_call_mic');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final mic = find.byKey(const Key('call-mic'));

  Future<ProviderContainer> pumpCall(
    WidgetTester tester, {
    BackendWarmup Function()? warmup,
    bool consented = false,
  }) async {
    if (consented) prefs.values[MicPrefs.consentKey('u1')] = 'true';
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
              'u1': const SettingsPrefs(companion: 'raza'),
            }),
          ),
          ...chatOverrides(api: api, store: store),
          backendWarmupProvider.overrideWith(
            (ref) => warmup?.call() ?? BackendWarmup(chatHealth: null),
          ),
          // Speech service not configured: the device voice speaks.
          speechApiProvider.overrideWithValue(fakeApi(FakeSpeechServer())),
          speechWarmupProvider.overrideWithValue(
            SpeechWarmup(
              health: (_) async => false,
              delay: (_) => Completer<void>().future,
            ),
          ),
          clipPlayerFactoryProvider.overrideWithValue(FakeClipPlayer.new),
          ttsEngineFactoryProvider.overrideWithValue(() => tts),
          voicePrefsProvider.overrideWithValue(VoicePrefs(prefs)),
          micPrefsProvider.overrideWithValue(MicPrefs(prefs)),
          micRecorderFactoryProvider.overrideWithValue(() => recorder),
          micTempDirProvider.overrideWithValue(() async => dir.path),
          micDiagnosticsProvider.overrideWithValue(diagnostics),
          micClockProvider.overrideWithValue(() => tester.binding.clock.now()),
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(mic);
    await settle(tester);
  }

  /// Calls the mic button's handler even when the crisis / breathing screen
  /// covers the call screen, so the gate in code is what is tested.
  Future<void> pressMicUnderOverlay(WidgetTester tester) async {
    tester
        .widget<GestureDetector>(
          find
              .descendant(of: mic, matching: find.byType(GestureDetector))
              .first,
        )
        .onTap!();
    await settle(tester);
  }

  ChatController chat(ProviderContainer c) =>
      c.read(chatControllerProvider('u1'));

  Finder inCall(Finder f) =>
      find.descendant(of: find.byType(AvatarCallScreen), matching: f);

  /// With text in the field, Send is tappable.
  bool sendEnabled(WidgetTester tester) =>
      tester
          .widget<GestureDetector>(inCall(find.byKey(const Key('chat-send'))))
          .onTap !=
      null;

  Future<void> typeAndSend(WidgetTester tester, String text) async {
    await tester.enterText(inCall(find.byKey(const Key('chat-input'))), text);
    await tester.pump();
    await tester.tap(inCall(find.byKey(const Key('chat-send'))));
    await settle(tester);
  }

  testWidgets('ATC-M3-28 consent → record with timer → tap again sends; transcript is '
      'the user message, saved encrypted; clip deleted', (tester) async {
    final c = await pumpCall(tester);
    await tapMic(tester);
    expect(find.text(MicTexts.consent), findsOneWidget);
    expect(recorder.permissionAsks, 0, reason: 'explanation first');

    await tester.tap(find.byKey(const Key('mic-consent-continue')));
    await settle(tester);
    expect(recorder.permissionAsks, 1);
    expect(find.byKey(const Key('mic-recording')), findsOneWidget);
    expect(find.text('Recording 0:00'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    // Typing stays possible; only Send waits.
    await tester.enterText(inCall(find.byKey(const Key('chat-input'))), 'x');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Recording 0:03'), findsOneWidget);
    final path = recorder.current!;

    await tapMic(tester);
    expect(api.audioPaths, [path]);
    expect(chat(c).messages.map((m) => (m.sender, m.content)), [
      ('user', 'I feel tired'),
      ('ai', 'That sounds hard.'),
    ]);
    final rows = await store.byConversation('u1');
    expect(rows.map((r) => r.sender), ['user', 'ai']);
    expect(rows.first.content, isNot(contains('I feel tired')));
    expect(File(path).existsSync(), isFalse);
    expect(find.byKey(const Key('mic-recording')), findsNothing);
    expect(diagnostics.last!.line, contains('status=ok'));
    tts.finish();
    await settle(tester);
  });

  testWidgets('ATC-M3-29 warning colour from 0:25, auto-send at 0:30', (tester) async {
    await pumpCall(tester, consented: true);
    await tapMic(tester);
    Color timerColor() =>
        tester.widget<Text>(find.byKey(const Key('mic-timer'))).style!.color!;
    await tester.pump(const Duration(seconds: 24));
    expect(timerColor(), KoiColors.neoBlack);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Recording 0:25'), findsOneWidget);
    expect(timerColor(), KoiColors.danger);
    expect(api.audioPaths, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(api.audioPaths, hasLength(1));
    expect(diagnostics.last!.line, contains('clip=30.0s'));
    tts.finish();
    await settle(tester);
  });

  testWidgets('ATC-M3-30 permission denied: mic stays off, typed text works', (
    tester,
  ) async {
    recorder.granted = false;
    final c = await pumpCall(tester, consented: true);
    await tapMic(tester);
    expect(find.text(MicTexts.denied), findsOneWidget);
    expect(recorder.started, isEmpty);
    expect(find.byKey(const Key('mic-retry')), findsNothing);

    await tapMic(tester);
    expect(find.text(MicTexts.deniedSettings), findsOneWidget);

    await typeAndSend(tester, 'typed');
    expect(api.texts, ['typed']);
    expect(chat(c).messages.last.content, 'Typed reply.');
    tts.finish();
    await settle(tester);
  });

  testWidgets('ATC-M3-30 Not now: no permission, no recording', (tester) async {
    await pumpCall(tester);
    await tapMic(tester);
    await tester.tap(find.byKey(const Key('mic-consent-not-now')));
    await settle(tester);
    expect(recorder.permissionAsks, 0);
    expect(recorder.started, isEmpty);
    expect(prefs.values[MicPrefs.consentKey('u1')], isNull);
  });

  testWidgets('ATC-M3-31 422 → error line + Retry, no reply invented; Retry resends '
      'the same clip', (tester) async {
    final c = await pumpCall(tester, consented: true);
    await tapMic(tester);
    final path = recorder.current!;
    api.fail = const ChatApiException('422');
    await tapMic(tester);

    expect(find.text(MicTexts.unclear), findsOneWidget);
    expect(find.byKey(const Key('mic-retry')), findsOneWidget);
    expect(chat(c).messages, isEmpty);
    expect(store.rows, isEmpty);
    expect(
      tester
          .widget<TextField>(inCall(find.byKey(const Key('chat-input'))))
          .enabled,
      isTrue,
    );
    expect(File(path).existsSync(), isTrue);
    expect(diagnostics.last!.line, contains('status=422'));

    await tester.tap(find.byKey(const Key('mic-retry')));
    await settle(tester);
    expect(api.audioPaths, [path, path]);
    expect(chat(c).messages.map((m) => m.sender), ['user', 'ai']);
    expect(find.byKey(const Key('mic-notice')), findsNothing);
    expect(File(path).existsSync(), isFalse);
    tts.finish();
    await settle(tester);
  });

  testWidgets('ATC-M3-31 timeout → send-failed line + Retry, typing still works', (
    tester,
  ) async {
    final c = await pumpCall(tester, consented: true);
    await tapMic(tester);
    api.fail = const ChatTimeoutException();
    await tapMic(tester);
    expect(find.text(MicTexts.sendFailed), findsOneWidget);
    expect(find.byKey(const Key('mic-retry')), findsOneWidget);
    expect(chat(c).messages, isEmpty);
    expect(diagnostics.last!.line, contains('status=timeout'));

    await typeAndSend(tester, 'typed instead');
    expect(api.texts, ['typed instead']);
    tts.finish();
    await settle(tester);
  });

  testWidgets('ATC-M3-30 Cancel: nothing sent, clip deleted', (tester) async {
    await pumpCall(tester, consented: true);
    await tapMic(tester);
    final path = recorder.current!;
    await tester.tap(find.byKey(const Key('mic-cancel')));
    await settle(tester);
    expect(api.audioPaths, isEmpty);
    expect(File(path).existsSync(), isFalse);
    expect(find.byKey(const Key('mic-recording')), findsNothing);
    await tester.enterText(inCall(find.byKey(const Key('chat-input'))), 'x');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
  });

  testWidgets('ATC-M3-32 recording stops the voice that is playing', (tester) async {
    await pumpCall(tester, consented: true);
    await typeAndSend(tester, 'hi');
    expect(tts.isSpeaking, isTrue);
    await tapMic(tester);
    expect(tts.isSpeaking, isFalse);
    expect(tts.stops, greaterThan(0));
    expect(recorder.started, hasLength(1));
    await tester.tap(find.byKey(const Key('mic-cancel')));
    await settle(tester);
  });

  testWidgets('ATC-M3-32 no recording while the crisis screen is open', (tester) async {
    final c = await pumpCall(tester);
    c
        .read(safetyControllerProvider)
        .handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
    await tester.pump();
    await pressMicUnderOverlay(tester);
    expect(find.text(MicTexts.consent), findsNothing);
    expect(recorder.started, isEmpty);
  });

  testWidgets('ATC-M3-36 crisis resolution pending (screen closed, '
      'crisis_resolved not sent yet): no recording; allowed once sent', (
    tester,
  ) async {
    final c = await pumpCall(tester, consented: true);
    final safety = c.read(safetyControllerProvider)
      ..handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
    await settle(tester);
    safety.chooseCrisisPath(CrisisPath.reachedOut);
    await settle(tester);
    expect(safety.crisis, isNull, reason: 'crisis screen closed');
    expect(safety.resolutionPending, isTrue);

    await pressMicUnderOverlay(tester);
    expect(recorder.started, isEmpty);
    expect(find.byKey(const Key('mic-recording')), findsNothing);

    // Control: the same tap records once the resolution has been sent.
    safety.crisisResolutionSent();
    await pressMicUnderOverlay(tester);
    expect(recorder.started, hasLength(1));
    await tester.tap(find.byKey(const Key('mic-cancel')));
    await settle(tester);
  });

  testWidgets('ATC-M3-32 no recording during breathing; opening it cancels one', (
    tester,
  ) async {
    final c = await pumpCall(tester, consented: true);
    await tapMic(tester);
    final path = recorder.current!;
    void breathe() => c
        .read(safetyControllerProvider)
        .handleUiAction(
          const UiAction(UiAction.startBreathing, {
            'inhale_s': 4,
            'exhale_s': 6,
            'cycles': 1,
            'cue_audio': ['in', 'out'],
          }),
        );
    breathe();
    await settle(tester);
    expect(find.byKey(const Key('mic-recording')), findsNothing);
    expect(File(path).existsSync(), isFalse);
    expect(api.audioPaths, isEmpty);

    await pressMicUnderOverlay(tester);
    expect(recorder.started, hasLength(1), reason: 'blocked while open');
    c.read(safetyControllerProvider).stopBreathing();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ATC-M3-33 audio waits for chat + crisis /health with the waking line', (
    tester,
  ) async {
    final chatHealth = Completer<bool>();
    final crisisHealth = Completer<bool>();
    await pumpCall(
      tester,
      consented: true,
      warmup: () => BackendWarmup(
        chatHealth: (_) => chatHealth.future,
        crisisHealth: (_) => crisisHealth.future,
      ),
    );
    await tapMic(tester);
    await tapMic(tester);
    expect(find.byType(WakingLine), findsOneWidget);
    expect(api.audioPaths, isEmpty);
    chatHealth.complete(true);
    await settle(tester);
    expect(api.audioPaths, isEmpty);
    crisisHealth.complete(true);
    await settle(tester);
    expect(api.audioPaths, hasLength(1));
    expect(find.byType(WakingLine), findsNothing);
    tts.finish();
    await settle(tester);
  });
}
