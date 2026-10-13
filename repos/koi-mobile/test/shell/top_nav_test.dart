import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/screens/placeholders.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/mode_selector.dart';
import 'package:koi_mobile/theme/koi_colors.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  // Real DM Sans metrics, so the fit checks measure actual label widths.
  useRealFonts();

  // Default = Infinix X663: 1080x2400 px at density 480 → 360x800 dp.
  Future<void> pumpShell(WidgetTester tester, {double widthDp = 360}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(widthDp * 3, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(
          FakeAuthService(
            fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
          ),
          onboardingStore(complete: true),
        ),
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

  testWidgets('fits a 360dp phone with no overflow', (tester) async {
    await pumpShell(tester);
    expect(tester.takeException(), isNull);
    for (final k in ['nav-pill-brand', 'nav-pill-tabs']) {
      final r = tester.getRect(find.byKey(Key(k)));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    }
  });

  testWidgets('360dp: tab labels render at full size (no scaling)', (
    tester,
  ) async {
    await pumpShell(tester);
    // Natural DM Sans Bold 14px width of "Progress" is ~59.6dp.
    expect(tester.getRect(find.text('Progress')).width, closeTo(59.6, 0.5));
  });

  testWidgets('320dp: tab row scales down instead of overflowing', (
    tester,
  ) async {
    await pumpShell(tester, widthDp: 320);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Progress')).width, lessThan(59));
    final r = tester.getRect(find.byKey(const Key('nav-pill-tabs')));
    expect(r.right, lessThanOrEqualTo(320));
  });

  testWidgets('pills: white, 3px black border, pill radius, cyan 5px shadow', (
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

  testWidgets('tabs: labels, black active pill, tapping switches screens', (
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
    expect(find.byType(ProgressPlaceholder), findsOneWidget);
    expect(tabDecoration(tester, 'progress')!.color, KoiColors.neoBlack);
    expect(tabDecoration(tester, 'chat'), isNull);

    await tester.tap(find.byKey(const Key('nav-tab-settings')));
    await tester.pump();
    expect(find.byType(SettingsPlaceholder), findsOneWidget);

    // The web logo links to the root, which sends a signed-in user to chat.
    await tester.tap(find.byKey(const Key('nav-logo')));
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('mode selector: tap opens, 3 locked modes, Text selectable', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.text('Mode: Text'), findsOneWidget);
    expect(find.byKey(const Key('mode-selector-menu')), findsNothing);

    await tester.tap(find.byKey(const Key('mode-selector-button')));
    await tester.pumpAndSettle();
    final menu = find.byKey(const Key('mode-selector-menu'));
    expect(menu, findsOneWidget);
    expect(tester.getSize(menu).width, 224);
    for (final m in ModeSelector.modes) {
      expect(find.byKey(Key('mode-item-${m.name}')), findsOneWidget);
    }
    expect(find.text('LOCKED'), findsNWidgets(3));
    final rect = tester.getRect(menu);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));

    // Disabled mode: no change, menu stays open.
    await tester.tap(find.byKey(const Key('mode-item-Audio')));
    await tester.pumpAndSettle();
    expect(find.text('Mode: Text'), findsOneWidget);
    expect(menu, findsOneWidget);

    // Enabled mode closes it.
    await tester.tap(find.byKey(const Key('mode-item-Text')));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);

    // A tap outside closes it too.
    await tester.tap(find.byKey(const Key('mode-selector-button')));
    await tester.pumpAndSettle();
    expect(menu, findsOneWidget);
    await tester.tapAt(const Offset(180, 700));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
  });
}
