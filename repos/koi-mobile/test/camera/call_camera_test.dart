import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/camera/camera_session.dart';
import 'package:koi_mobile/camera/camera_widgets.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/modes/input_mode.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/voice/voice_controller.dart';
import 'package:koi_mobile/voice/voice_providers.dart';
import 'package:koi_mobile/voice_input/mic_controller.dart';
import 'package:koi_mobile/voice_input/mic_providers.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';
import '../voice/fakes.dart';
import '../voice_input/fake_mic.dart';
import 'fake_camera.dart';

/// Records every chat request: the JSON body and the audio upload, if any.
class _RecordingApi extends ChatApiClient {
  _RecordingApi() : super(baseUrl: 'https://chat.example.test');

  final List<Map<String, Object?>> bodies = [];
  final List<AudioUpload> uploads = [];

  @override
  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
    AudioUpload? audio,
  }) async {
    bodies.add(body);
    if (audio != null) {
      uploads.add(audio);
      handlers.onEvent?.call('transcript');
      handlers.onTranscript?.call('Hello');
    }
    handlers.onEvent?.call('delta');
    handlers.onDelta?.call('Hi.');
    return ChatStreamResult(
      fullText: 'Hi.',
      companionState: CompanionState.fallback,
      latencyMs: 1,
      exerciseStateChanged: false,
      exerciseState: null,
    );
  }
}

void main() {
  useRealFonts();

  late FakeLocalCamera camera;
  late _RecordingApi api;
  late FakeSpeechServer speech;
  late FakeMicRecorder recorder;
  late MemoryKeyValueStore prefs;
  late FakeAuthService auth;
  late Directory dir;

  setUp(() {
    camera = FakeLocalCamera();
    api = _RecordingApi();
    speech = FakeSpeechServer();
    recorder = FakeMicRecorder();
    prefs = MemoryKeyValueStore({MicPrefs.consentKey('u1'): 'true'});
    auth = FakeAuthService(
      fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
    )..fakeToken = 'fake-test-token';
    dir = Directory.systemTemp.createTempSync('koi_call_camera');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final cameraButton = find.byKey(const Key('call-camera'));

  Future<ProviderContainer> pumpCall(
    WidgetTester tester, {
    KoiInputMode mode = KoiInputMode.cameraVoice,
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
            auth,
            onboardingStore(complete: true),
            settings: MemorySettingsPrefsStore({
              'u1': const SettingsPrefs(companion: 'raza'),
            }),
          ),
          ...chatOverrides(api: api),
          backendWarmupProvider.overrideWith(
            (ref) => BackendWarmup(chatHealth: null),
          ),
          speechApiProvider.overrideWithValue(fakeApi(speech)),
          speechWarmupProvider.overrideWithValue(
            SpeechWarmup(health: (_) async => true),
          ),
          clipPlayerFactoryProvider.overrideWithValue(FakeClipPlayer.new),
          ttsEngineFactoryProvider.overrideWithValue(FakeTtsEngine.new),
          modePrefsProvider.overrideWithValue(ModePrefs(prefs)),
          micPrefsProvider.overrideWithValue(MicPrefs(prefs)),
          micRecorderFactoryProvider.overrideWithValue(() => recorder),
          micTempDirProvider.overrideWithValue(() async => dir.path),
          micClockProvider.overrideWithValue(() => tester.binding.clock.now()),
          localCameraFactoryProvider.overrideWithValue(() => camera),
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

  Future<void> startCamera(WidgetTester tester) async {
    await tester.tap(cameraButton);
    await settle(tester);
    expect(camera.isOpen, isTrue);
    expect(find.text(CameraTexts.on), findsOneWidget);
  }

  Finder inCall(Finder f) =>
      find.descendant(of: find.byType(AvatarCallScreen), matching: f);

  Future<void> selectMode(WidgetTester tester, KoiInputMode mode) async {
    await tester.tap(inCall(find.byKey(const Key('mode-selector-button'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(Key('mode-item-${mode.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Calls the camera button's handler even when an overlay covers it.
  Future<void> pressCameraUnderOverlay(WidgetTester tester) async {
    tester
        .widget<GestureDetector>(
          find
              .descendant(
                of: cameraButton,
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!();
    await settle(tester);
  }

  testWidgets('ATC-M20-15 starts only on a tap: "Camera on", the exact '
      'disclosure, one tap off (button or the preview\'s Turn off)', (
    tester,
  ) async {
    await pumpCall(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(camera.opens, 0, reason: 'never without a tap');
    expect(find.byKey(const Key('camera-pip')), findsNothing);
    expect(
      find.text(
        'This camera view is for you only. KOI does not record, store, send '
        'or analyze your video.',
      ),
      findsOneWidget,
    );

    await startCamera(tester);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    await tester.tap(cameraButton);
    await settle(tester);
    expect(camera.isOpen, isFalse);
    expect(find.text(CameraTexts.on), findsNothing);

    await startCamera(tester);
    await tester.tap(find.byKey(const Key('camera-off')));
    await settle(tester);
    expect(camera.isOpen, isFalse);
    expect(camera.opens, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(camera.opens, 2, reason: 'stays off');
  });

  group('ATC-M20-16 the camera is released on every exit path', () {
    final paths =
        <String, Future<void> Function(WidgetTester, ProviderContainer)>{
          'mode change (Camera view + voice → Voice)': (t, c) =>
              selectMode(t, KoiInputMode.voice),
          'mode change (Camera view + voice → Camera view)': (t, c) =>
              selectMode(t, KoiInputMode.camera),
          'End call': (t, c) async {
            await t.tap(find.byKey(const Key('call-end')));
            await t.pump();
          },
          'leaving the screen (back)': (t, c) async {
            t.state<NavigatorState>(find.byType(Navigator).first).pop();
            await t.pump();
            await t.pump(const Duration(seconds: 1));
          },
          'sign-out / another uid': (t, c) async {
            auth.set(user: const KoiUser(uid: 'u2', isAnonymous: true));
            await t.pump();
          },
          'app to the background': (t, c) async {
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            await t.pump();
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await t.pump();
          },
          'crisis screen opens': (t, c) async {
            c
                .read(safetyControllerProvider)
                .handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
            await t.pump();
          },
          'breathing overlay opens': (t, c) async {
            c
                .read(safetyControllerProvider)
                .handleUiAction(
                  const UiAction(UiAction.startBreathing, {
                    'inhale_s': 4,
                    'exhale_s': 6,
                    'cycles': 1,
                    'cue_audio': ['in', 'out'],
                  }),
                );
            await t.pump();
          },
        };
    for (final MapEntry(key: name, value: exit) in paths.entries) {
      testWidgets(name, (tester) async {
        final c = await pumpCall(tester);
        await startCamera(tester);
        await exit(tester, c);
        await settle(tester);
        expect(camera.isOpen, isFalse, reason: name);
        expect(camera.closes, greaterThanOrEqualTo(1));
        expect(camera.opens, 1, reason: 'not restarted');
        final safety = c.read(safetyControllerProvider);
        if (safety.breathing != null) safety.stopBreathing();
        await tester.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('no start while the crisis screen is open or its resolution '
        'is pending', (tester) async {
      final c = await pumpCall(tester);
      final safety = c.read(safetyControllerProvider)
        ..handleHandoff(const Handoff(to: 'crisis', reason: 'test'));
      await settle(tester);
      await pressCameraUnderOverlay(tester);
      expect(camera.opens, 0);
      safety.chooseCrisisPath(CrisisPath.reachedOut);
      await settle(tester);
      expect(safety.resolutionPending, isTrue);
      await pressCameraUnderOverlay(tester);
      expect(camera.opens, 0);
      // Control: allowed once the resolution has been sent.
      safety.crisisResolutionSent();
      await pressCameraUnderOverlay(tester);
      expect(camera.opens, 1);
    });
  });

  testWidgets('ATC-M20-17 permission denied: message, typing and the mic '
      'still work', (tester) async {
    camera.error = CameraException('CameraAccessDenied', 'denied');
    await pumpCall(tester);
    await tester.tap(cameraButton);
    await settle(tester);
    expect(find.text(CameraTexts.denied), findsOneWidget);
    expect(camera.isOpen, isFalse);

    await tester.enterText(inCall(find.byKey(const Key('chat-input'))), 'hi');
    await tester.pump();
    await tester.tap(inCall(find.byKey(const Key('chat-send'))));
    await settle(tester);
    expect(api.bodies, hasLength(1));

    await tester.tap(find.byKey(const Key('call-mic')));
    await settle(tester);
    expect(recorder.started, hasLength(1));
    await tester.tap(find.byKey(const Key('call-mic')));
    await settle(tester);
    expect(api.uploads, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'ATC-M20-18 with the camera on, no request carries video: chat '
    'bodies are text JSON, the only upload is the mic WAV, speech gets text',
    (tester) async {
      await pumpCall(tester);
      await startCamera(tester);

      await tester.enterText(inCall(find.byKey(const Key('chat-input'))), 'hi');
      await tester.pump();
      await tester.tap(inCall(find.byKey(const Key('chat-send'))));
      await settle(tester);
      await tester.tap(find.byKey(const Key('call-mic')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('call-mic')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(camera.isOpen, isTrue, reason: 'camera stayed on throughout');
      expect(api.bodies, hasLength(2));
      final media = RegExp(
        r'video|image|camera|frame|jpe?g|png|webm|mp4|base64',
        caseSensitive: false,
      );
      for (final body in [...api.bodies, ...speech.requests]) {
        final text = jsonEncode(body);
        expect(media.hasMatch(text), isFalse, reason: text);
        // Only strings, numbers, bools, null and nested maps/lists of them.
        expect(() => jsonDecode(text), returnsNormally);
      }
      expect(api.uploads, hasLength(1));
      final upload = api.uploads.single;
      expect(upload.filename, 'voice.wav');
      expect(upload.path, startsWith(dir.path));
      expect(upload.path, endsWith('.wav'));
    },
  );
}
