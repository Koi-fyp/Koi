import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/progress/progress_screen.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/modes/input_mode.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/settings/settings_screen.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/mode_selector.dart';
import 'package:koi_mobile/theme/koi_colors.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  // Real DM Sans metrics, so the fit checks measure actual label widths.
  useRealFonts();

  // Default = Infinix X663: 1080x2400 px at density 480 → 360x800 dp.
  late MemoryKeyValueStore prefs;
  setUp(() => prefs = MemoryKeyValueStore());

  Future<void> pumpShell(WidgetTester tester, {double widthDp = 360}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(widthDp * 3, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(complete: true),
            // Raza: all modes (Koi's fox is text only).
            settings: MemorySettingsPrefsStore({
              'u1': const SettingsPrefs(companion: 'raza'),
            }),
          ),
          modePrefsProvider.overrideWithValue(ModePrefs(prefs)),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  BoxDecoration? tabDecoration(WidgetTester tester, String tab) {
    final c = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(Key('nav-tab-$tab')),
            matching: find.byType(Container),
          )
          .first,
    );
    return c.decoration as BoxDecoration?;
  }

  testWidgets('ATC-M0-03 fits a 360dp phone with no overflow', (tester) async {
    await pumpShell(tester);
    expect(tester.takeException(), isNull);
    for (final k in ['nav-pill-brand', 'nav-pill-tabs']) {
      final r = tester.getRect(find.byKey(Key(k)));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    }
  });

  // AUTH-ENTRY (approved 2026-10-20): anonymous users now have 4 tabs
  // (Care = information page), so at 360dp the row scales down a little,
  // like it already did for General / Patient users. It must still fit.
  testWidgets('ATC-M0-03 360dp: 4 tabs fit with no overflow', (tester) async {
    await pumpShell(tester);
    expect(tester.takeException(), isNull);
    for (final t in ['chat', 'progress', 'care', 'settings']) {
      expect(find.byKey(Key('nav-tab-$t')), findsOneWidget, reason: t);
    }
    // Natural DM Sans Bold 14px width of "Progress" is ~59.6dp.
    expect(tester.getRect(find.text('Progress')).width, lessThan(60.1));
    final r = tester.getRect(find.byKey(const Key('nav-pill-tabs')));
    expect(r.right, lessThanOrEqualTo(360));
  });

  testWidgets('ATC-M0-03 320dp: tab row scales down instead of overflowing', (
    tester,
  ) async {
    await pumpShell(tester, widthDp: 320);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Progress')).width, lessThan(59));
    final r = tester.getRect(find.byKey(const Key('nav-pill-tabs')));
    expect(r.right, lessThanOrEqualTo(320));
  });

  testWidgets('ATC-M0-04 pills: white, 3px black border, pill radius, cyan 5px shadow', (
    tester,
  ) async {
    await pumpShell(tester);
    for (final k in ['nav-pill-brand', 'nav-pill-tabs']) {
      final pill = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key(k)),
              matching: find.byType(Container),
            )
            .first,
      );
      final d = pill.decoration as BoxDecoration;
      expect(d.color, KoiColors.neoWhite);
      expect((d.border as Border).top.width, 3);
      expect(d.borderRadius, BorderRadius.circular(9999));
      expect(d.boxShadow!.single.color, const Color(0xFF06B6D4));
      expect(d.boxShadow!.single.offset, const Offset(5, 5));
      expect(d.boxShadow!.single.blurRadius, 0);
    }
    expect(find.text('K'), findsOneWidget);
    expect(find.text('KOI'), findsOneWidget);
  });

  testWidgets('ATC-M0-04 tabs: labels, black active pill, tapping switches screens', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    expect(tabDecoration(tester, 'chat')!.color, KoiColors.neoBlack);
    expect(tabDecoration(tester, 'progress'), isNull);
    expect(
      tester.widget<Text>(find.text('Chat')).style!.color,
      KoiColors.neoWhite,
    );
    expect(
      tester.widget<Text>(find.text('Progress')).style!.color,
      const Color(0xFF4B5563),
    );

    await tester.tap(find.byKey(const Key('nav-tab-progress')));
    await tester.pump();
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(tabDecoration(tester, 'progress')!.color, KoiColors.neoBlack);
    expect(tabDecoration(tester, 'chat'), isNull);

    await tester.tap(find.byKey(const Key('nav-tab-settings')));
    await tester.pump();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // The web logo links to the root, which sends a signed-in user to chat.
    await tester.tap(find.byKey(const Key('nav-logo')));
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  // Changed in Prompt 29: the four modes are live (were Text + 3 LOCKED),
  // labels are Prompt 29's, the menu is web w-64 and the button shows the
  // mode only (web hides "Mode: " below sm).
  testWidgets('ATC-M20-03 mode selector: tap opens, 4 live modes with the exact '
      'labels, a tap selects, saves per uid and closes', (tester) async {
    await pumpShell(tester);
    expect(find.text('Text'), findsOneWidget);
    expect(find.bySemanticsLabel('Mode: Text'), findsOneWidget);
    expect(find.byKey(const Key('mode-selector-menu')), findsNothing);

    await tester.tap(find.byKey(const Key('mode-selector-button')));
    await tester.pumpAndSettle();
    final menu = find.byKey(const Key('mode-selector-menu'));
    expect(menu, findsOneWidget);
    expect(tester.getSize(menu).width, ModeSelector.menuWidth);
    const labels = ['Text', 'Voice', 'Camera view', 'Camera view + voice'];
    expect(KoiInputMode.values.map((m) => m.label), labels);
    for (final m in KoiInputMode.values) {
      expect(
        find.descendant(
          of: find.byKey(Key('mode-item-${m.id}')),
          matching: find.text(m.label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('LOCKED'), findsNothing);
    expect(find.text(ModeSelector.foxNote), findsNothing);
    final rect = tester.getRect(menu);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));

    await tester.tap(find.byKey(const Key('mode-item-camera-voice')));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('mode-selector-button')),
        matching: find.text('Camera view + voice'),
      ),
      findsOneWidget,
    );
    expect(prefs.values['koi_input_mode_u1'], 'camera-voice');
    expect(tester.takeException(), isNull, reason: 'long label fits 360dp');

    // A tap outside closes it too.
    await tester.tap(find.byKey(const Key('mode-selector-button')));
    await tester.pumpAndSettle();
    expect(menu, findsOneWidget);
    await tester.tapAt(const Offset(180, 700));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
  });

  testWidgets('ATC-M20-03 the longest label fits the top nav at 320dp too', (
    tester,
  ) async {
    prefs.values['koi_input_mode_u1'] = 'camera-voice';
    await pumpShell(tester, widthDp: 320);
    expect(tester.takeException(), isNull);
    final r = tester.getRect(find.byKey(const Key('mode-selector-button')));
    expect(r.right, lessThanOrEqualTo(320));
  });
}
