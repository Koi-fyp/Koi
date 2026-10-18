import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_call_screen.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/modes/input_mode.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/mode_selector.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  group('ATC-M20-10 the four modes', () {
    test('exact labels and flags (mic input, spoken replies, camera view)', () {
      expect(
        {
          for (final m in KoiInputMode.values)
            m.label: (m.micInput, m.spokenReplies, m.cameraView),
        },
        {
          'Text': (false, false, false),
          'Voice': (true, true, false),
          'Camera view': (false, false, true),
          'Camera view + voice': (true, true, true),
        },
      );
      expect(KoiInputMode.values.map((m) => m.id), [
        'text',
        'voice',
        'camera',
        'camera-voice',
      ]);
      expect(KoiInputMode.fromId('video-audio'), isNull);
    });
  });

  group(
    'ATC-M20-11 ModePrefs: per uid, Text by default, one-time migration',
    () {
      KoiInputMode load(Map<String, String> values) =>
          ModePrefs(MemoryKeyValueStore(values)).load('u1');

      test('new user → Text, saved', () async {
        final store = MemoryKeyValueStore();
        expect(ModePrefs(store).load('u1'), KoiInputMode.text);
        await pumpEventQueue();
        expect(store.values, {'koi_input_mode_u1': 'text'});
      });

      test(
        'Prompt 25 voice on → Voice; off → Text; the old key is deleted',
        () async {
          for (final (old, mode) in [
            ('true', KoiInputMode.voice),
            ('false', KoiInputMode.text),
          ]) {
            final store = MemoryKeyValueStore({'koi_voice_enabled_u1': old});
            expect(ModePrefs(store).load('u1'), mode);
            await pumpEventQueue();
            expect(store.values, {'koi_input_mode_u1': mode.id});
          }
        },
      );

      test('never set, but the call screen was used (mic consent / denial) → '
          'Voice', () {
        expect(load({'koi_mic_consent_u1': 'true'}), KoiInputMode.voice);
        expect(load({'koi_mic_denied_u1': '1'}), KoiInputMode.voice);
        // Another uid's traces don't count.
        expect(load({'koi_mic_consent_u2': 'true'}), KoiInputMode.text);
      });

      test('a saved mode wins and the old key is then ignored', () {
        expect(
          load({'koi_input_mode_u1': 'camera', 'koi_voice_enabled_u1': 'true'}),
          KoiInputMode.camera,
        );
      });

      test('per uid: one user\'s choice never applies to another', () async {
        final store = MemoryKeyValueStore();
        final prefs = ModePrefs(store);
        await prefs.save('u1', KoiInputMode.cameraVoice);
        expect(prefs.load('u1'), KoiInputMode.cameraVoice);
        expect(prefs.load('u2'), KoiInputMode.text);
      });
    },
  );

  group('ATC-M20-12 Koi fox is text only', () {
    useRealFonts();

    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      required String companion,
      KoiInputMode saved = KoiInputMode.cameraVoice,
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
              settings: MemorySettingsPrefsStore({
                'u1': SettingsPrefs(companion: companion),
              }),
            ),
            ...chatOverrides(),
            modePrefsProvider.overrideWithValue(
              ModePrefs(
                MemoryKeyValueStore({ModePrefs.keyFor('u1'): saved.id}),
              ),
            ),
          ],
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    }

    testWidgets('other modes disabled with the note; Text in force; the saved '
        'mode is kept and comes back with Raza', (tester) async {
      final c = await pumpShell(tester, companion: 'koi');
      expect(c.read(effectiveInputModeProvider), KoiInputMode.text);
      expect(find.text('Text'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mode-selector-button')));
      await tester.pumpAndSettle();
      expect(find.text(ModeSelector.foxNote), findsOneWidget);
      expect(ModeSelector.foxNote, 'Koi (fox) chats by text only.');
      await tester.tap(find.byKey(const Key('mode-item-voice')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mode-selector-menu')),
        findsOneWidget,
        reason: 'a disabled mode does nothing',
      );
      expect(c.read(effectiveInputModeProvider), KoiInputMode.text);
      expect(
        c.read(inputModeControllerProvider('u1')).mode,
        KoiInputMode.cameraVoice,
        reason: 'saved mode untouched',
      );
      await tester.tapAt(const Offset(180, 700));
      await tester.pumpAndSettle();

      // Call screen: no Mic, no Camera for the fox.
      await tester.tap(find.byKey(const Key('avatar-call-entry')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AvatarCallScreen), findsOneWidget);
      expect(find.byKey(const Key('call-mic')), findsNothing);
      expect(find.byKey(const Key('call-camera')), findsNothing);

      c.read(selectedAvatarProvider.notifier).select(CompanionAvatar.raza);
      await tester.pump();
      expect(c.read(effectiveInputModeProvider), KoiInputMode.cameraVoice);
      expect(find.byKey(const Key('call-mic')), findsOneWidget);
      expect(find.byKey(const Key('call-camera')), findsOneWidget);
    });
  });
}
