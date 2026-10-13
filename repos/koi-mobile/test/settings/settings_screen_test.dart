import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/settings/export_screen.dart';
import 'package:koi_mobile/settings/import_screen.dart';
import 'package:koi_mobile/settings/privacy_screen.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/settings/settings_screen.dart';
import 'package:koi_mobile/settings/widgets/avatar_picker.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/top_nav.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  late MemorySettingsPrefsStore store;
  late List<Uri> dialled;

  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsPrefs? stored,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    store = MemorySettingsPrefsStore({'u1': ?stored});
    dialled = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(
          FakeAuthService(
            fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
          ),
          onboardingStore(complete: true),
          settings: store,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SettingsTab(openTel: (uri) async => dialled.add(uri)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets any open toast time out (3s) so no timer is left pending.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
  }

  /// Scrolls the whole page top to bottom; any overflow fails the test.
  Future<void> scrollThrough(WidgetTester tester, Key scrollKey) async {
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byKey(scrollKey), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  String descOf(WidgetTester tester, String rowKey, String label) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key(rowKey)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(texts, contains(label));
    return texts.last!;
  }

  group('Settings page at 360dp', () {
    testWidgets('all web sections and rows; no overflow', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Settings'), findsOneWidget);
      for (final label in [
        'ACCOUNT',
        'NOTIFICATIONS',
        'PRIVACY',
        'STORAGE',
        'ABOUT & HELP',
      ]) {
        await tester.ensureVisible(find.text(label));
        expect(find.text(label), findsOneWidget);
      }
      for (final t in [
        'Avatar & Name',
        'Koi 🦊', // page.tsx default useState('koi')
        'Language',
        'English',
        'Clear History',
        'Delete all conversations',
        'Daily Check-in',
        'Every day at 8:00 PM',
        'Reminder Time',
        'Tap to change',
        'Encryption',
        'AES-256, on-device',
        'Data Collection',
        'Anonymous only',
        'Export My Data',
        'Download a copy',
        'Import Data',
        'Restore from backup',
        'Local Storage',
        '42 KB of 5 MB used',
        '1%',
        'Version Info',
        'KOI v1.0.0',
        "What's New",
        'Latest updates & features',
        'Crisis Resources',
        '24/7 helplines (Pakistan)',
        'Made with care · Private by design',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await scrollThrough(tester, const Key('settings-scroll'));
    });

    testWidgets('loads stored prefs instead of the web defaults', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(
          companion: 'raza',
          language: 'ur',
          notificationsEnabled: false,
        ),
      );
      expect(find.text('Raza 👨'), findsOneWidget);
      expect(find.text('Urdu'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('language toggle: toast uses the old value; saved', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-language')));
      expect(find.text('Language changed to Urdu'), findsOneWidget);
      expect(descOf(tester, 'row-language', 'Language'), 'Urdu');
      expect(store.values['u1']!.language, 'ur');

      await tapVisible(tester, find.byKey(const Key('row-language')));
      expect(find.text('Language changed to English'), findsOneWidget);
      expect(store.values['u1']!.language, 'en');
      await drain(tester);
      expect(find.byKey(const Key('settings-toast')), findsNothing);
    });

    testWidgets('daily check-in toggle: desc, toast and save', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      expect(find.text('Daily check-in disabled'), findsOneWidget);
      expect(descOf(tester, 'row-checkin', 'Daily Check-in'), 'Disabled');
      expect(store.values['u1']!.notificationsEnabled, isFalse);
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      expect(find.text('Daily check-in enabled'), findsOneWidget);
      expect(store.values['u1']!.notificationsEnabled, isTrue);
      await drain(tester);
    });

    testWidgets('clear history and reminder time only show toasts (as web)', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-clear')));
      expect(find.text('All conversations cleared'), findsOneWidget);
      expect(store.values, isEmpty); // nothing saved or cleared
      await tapVisible(tester, find.byKey(const Key('row-reminder')));
      expect(find.text('Time picker coming soon!'), findsOneWidget);
      expect(find.text('All conversations cleared'), findsNothing);
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('a new toast restarts the 3s timer', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-clear')));
      await tester.pump(const Duration(milliseconds: 2500));
      await tapVisible(tester, find.byKey(const Key('row-reminder')));
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('Time picker coming soon!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('settings-toast')), findsNothing);
    });

    testWidgets('crisis helplines expand and dial the exact tel: links', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('help-crisis')));
      await tester.pump(const Duration(milliseconds: 400));
      for (final (name, tel) in [
        ('Umang (Mental Health)', '0311-7786264'),
        ('Rozan Counselling', '0800-22444'),
        ('Emergency Services', '15 / 1122'),
      ]) {
        expect(find.text(name), findsOneWidget);
        await tapVisible(tester, find.text(tel));
      }
      expect(dialled.map((u) => u.toString()), [
        'tel:03117786264',
        'tel:080022444',
        'tel:15',
      ]);
      await scrollThrough(tester, const Key('settings-scroll'));
    });

    testWidgets('help panels: one open at a time, collapsed panels hidden', (
      tester,
    ) async {
      await pumpSettings(tester);
      double h(String id) =>
          tester.getSize(find.byKey(Key('help-$id-body'))).height;
      expect(h('version'), 0);
      await tapVisible(tester, find.byKey(const Key('help-version')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('version'), greaterThan(0));
      expect(
        find.text('Release Date: January 2025', findRichText: true),
        findsOneWidget,
      );
      // web: "Web App" (settings/page.tsx:439); mobile decision 2026-10-13
      expect(
        find.text('Platform: Mobile App', findRichText: true),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('help-whatsnew')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('version'), 0);
      expect(h('whatsnew'), greaterThan(0));
      await tapVisible(tester, find.byKey(const Key('help-whatsnew')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('whatsnew'), 0);
    });
  });

  group('AvatarPicker (companions, web parity)', () {
    testWidgets('opens, fits 360dp, saves companion + name', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AvatarPicker), findsOneWidget);
      expect(find.text('Choose Your Companion'), findsOneWidget);
      expect(
        find.text('Pick the personality that resonates with you'),
        findsOneWidget,
      );
      for (final t in ['AISHA', 'RAZA', 'KOI', '🦊', 'Your Name (Optional)']) {
        expect(
          find.descendant(
            of: find.byType(AvatarPicker),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.byKey(const Key('picker-aisha')));
      await tester.enterText(
        find.byKey(const Key('avatar-picker-name')),
        'Sara',
      );
      await tapVisible(tester, find.byKey(const Key('avatar-picker-save')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AvatarPicker), findsNothing);
      expect(find.text('Aisha 👩'), findsOneWidget);
      expect(find.text('Companion updated successfully!'), findsOneWidget);
      expect(store.values['u1']!.companion, 'aisha');
      expect(store.values['u1']!.name, 'Sara');
      await drain(tester);
    });

    testWidgets('Cancel, ✕ and the backdrop close without saving', (
      tester,
    ) async {
      await pumpSettings(tester);
      for (final close in [
        'avatar-picker-cancel',
        'avatar-picker-close',
        'avatar-picker-backdrop',
      ]) {
        await tapVisible(tester, find.byKey(const Key('row-avatar')));
        await tester.pump(const Duration(milliseconds: 400));
        await tapVisible(tester, find.byKey(const Key('picker-raza')));
        if (close == 'avatar-picker-backdrop') {
          await tester.tapAt(const Offset(4, 4));
          await tester.pump();
        } else {
          await tapVisible(tester, find.byKey(Key(close)));
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AvatarPicker), findsNothing, reason: close);
        expect(find.text('Koi 🦊'), findsOneWidget, reason: close);
      }
      expect(store.values, isEmpty);
    });

    testWidgets('opens on the current companion', (tester) async {
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(companion: 'raza', name: 'Ali'),
      );
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      final field = tester.widget<TextField>(
        find.byKey(const Key('avatar-picker-name')),
      );
      expect(field.controller!.text, 'Ali');
      final selected = tester.getSemantics(
        find.byKey(const Key('picker-raza')),
      );
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('360dp: Cancel above Save, full width, full-size text', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      final save = find.byKey(const Key('avatar-picker-save'));
      final cancel = find.byKey(const Key('avatar-picker-cancel'));
      await tester.ensureVisible(save);
      await tester.pump();
      expect(
        find.byKey(const Key('avatar-picker-actions-stacked')),
        findsOneWidget,
      );
      final s = tester.getRect(save);
      final c = tester.getRect(cancel);
      expect(c.bottom, lessThan(s.top)); // web order: Cancel, then Save
      expect(s.top - c.bottom, moreOrLessEquals(16)); // gap 1rem
      expect(s.width, c.width);
      // 360 - 2*16 (overlay) - 2*3 (border) - 2*32 (padding) = 258
      expect(s.width, moreOrLessEquals(258));
      final label = tester.getSize(
        find.descendant(of: save, matching: find.text('Save Changes ✓')),
      );
      expect(label.width, greaterThan(115)); // ~124dp, not scaled down
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screen: side by side like web', (tester) async {
      await pumpSettings(tester);
      tester.view.physicalSize = const Size(2400, 2400); // 800x800dp
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('avatar-picker-actions-stacked')),
        findsNothing,
      );
      final s = tester.getRect(find.byKey(const Key('avatar-picker-save')));
      final c = tester.getRect(find.byKey(const Key('avatar-picker-cancel')));
      expect(c.top, s.top);
      expect(s.left - c.right, moreOrLessEquals(16));
      expect(tester.takeException(), isNull);
    });
  });

  group('sub-pages (nested navigator, top nav stays)', () {
    testWidgets('Privacy: content, no overflow, Back to Settings', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-encryption')));
      expect(find.byType(PrivacyScreen), findsOneWidget);
      for (final t in [
        'Privacy Center',
        'Encryption Active',
        'AES-256 • Military-grade',
        '📊 What We Store',
        '📱 On Your Device',
        'Encrypted',
        '☁️ Cloud (Optional)',
        'Anonymous',
        '🚫 Never Stored',
        'Protected',
        '📝 Recent Activity',
        'Conversation saved',
        'Danger Zone',
        'Delete My Account',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.pump(const Duration(seconds: 1));
      await scrollThrough(tester, const Key('privacy-scroll'));
      await tapVisible(tester, find.byKey(const Key('delete-account')));
      expect(find.byType(PrivacyScreen), findsOneWidget); // no-op, as web

      // Let the Android stretch-overscroll from the drags settle first.
      await tester.pump(const Duration(seconds: 2));
      await tester.ensureVisible(find.byKey(const Key('back-to-settings')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('back-to-settings')));
      await tester.pump();
      await tester.pump(); // zero-length route transition finishes
      expect(find.byType(PrivacyScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Data Collection also opens Privacy; system back pops it', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-data')));
      expect(find.byType(PrivacyScreen), findsOneWidget);
      // NavigatorPopHandler learns the nested stack can pop one frame later.
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      await tester.pump(); // zero-length route transition finishes
      expect(find.byType(PrivacyScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Import: coming-soon page, disabled notify, no overflow', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-import')));
      expect(find.byType(ImportScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // fadeUp delays
      for (final t in [
        'Import Data',
        '✨ Coming Soon',
        'PDF Import',
        'JSON Import',
        'Smart Conflict Resolution',
        'Preview Before Import',
        'Get Notified',
        'Notify Me (Coming Soon)',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await scrollThrough(tester, const Key('import-scroll'));
    });

    testWidgets('Export: generate → progress → ready → download toast', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-export')));
      expect(find.byType(ExportScreen), findsOneWidget);
      expect(find.text('Export Wellness Report'), findsOneWidget);
      expect(find.text('Report Includes'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.byKey(const Key('export-generate')));
      expect(find.byKey(const Key('export-progress')), findsOneWidget);
      expect(find.text('📊 Analyzing mood patterns...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1250)); // ~50%
      expect(find.text('💙 Calculating loneliness trends...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('🎉 Almost ready!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2400)); // past 5.1s
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('export-complete')), findsOneWidget);
      expect(find.text('Report Ready!'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.byKey(const Key('export-download')));
      expect(find.text(ExportScreen.downloadUnavailable), findsOneWidget);
      await scrollThrough(tester, const Key('export-scroll'));
      await drain(tester);
    });
  });

  testWidgets('in the shell: Settings tab shows the page under the top nav', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(
          FakeAuthService(
            fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
          ),
          onboardingStore(complete: true),
        ),
        child: const MaterialApp(home: AppShell(initialTab: KoiTab.settings)),
      ),
    );
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('row-export')));
    expect(find.byType(ExportScreen), findsOneWidget);
    expect(find.byType(KoiTopNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
