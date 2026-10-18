import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_source.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/settings/export_screen.dart';
import 'package:koi_mobile/settings/import_screen.dart';
import 'package:koi_mobile/settings/privacy_screen.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/settings/settings_screen.dart';
import 'package:koi_mobile/settings/storage_usage.dart';
import 'package:koi_mobile/settings/widgets/avatar_picker.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/top_nav.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

/// A store whose load and save wait for [loadGate] / [saveGate].
class _GatedStore extends MemorySettingsPrefsStore {
  _GatedStore([super.initial]);
  Completer<void>? loadGate;
  Completer<void>? saveGate;

  @override
  Future<SettingsPrefs> load(String uid) async {
    await loadGate?.future;
    return super.load(uid);
  }

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async {
    await saveGate?.future;
    return super.save(uid, prefs);
  }
}

const String _languageNote =
    ' Language is a saved preference; replies and interface translation are '
    'not guaranteed.';

void main() {
  useRealFonts();

  late _GatedStore store;
  late List<Uri> dialled;

  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsPrefs? stored,
    _GatedStore? custom,
    DateTime? now,
    int? storageBytes,
    AvatarSource avatar = AvatarSource.placeholder,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    store = custom ?? _GatedStore({'u1': ?stored});
    dialled = [];
    // A fresh page each time (a second call must not reuse the old state).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(complete: true),
            settings: store,
          ),
          koiStorageBytesProvider.overrideWith((ref) async => storageBytes),
          avatarSourceProvider.overrideWithValue(avatar),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SettingsTab(
              openTel: (uri) async => dialled.add(uri),
              now: () => now ?? DateTime(2026, 10, 18, 7, 5),
            ),
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

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('settings-status'))).data!;

  group('Settings page at 360dp', () {
    testWidgets('ATC-M1-24 all web sections and rows; no overflow', (tester) async {
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
      // Web 223e97c settings/page.tsx, nothing saved yet.
      for (final t in [
        'Avatar & Name',
        'Koi 🦊',
        'Language',
        'No language preference saved', // :136
        'Clear History',
        'Unavailable until deletion scope is approved', // :143
        'Daily Check-in',
        'No preference saved', // :183
        'Reminder Time',
        'Choose a local preferred time', // :192
        'Encryption',
        'AES-256, on-device',
        'Data Collection',
        'Storage and inference privacy', // :243
        'Export My Data',
        'Wellness export currently unavailable', // :250
        'Import Data',
        'Coming soon; import unavailable', // :257
        'Device Storage Estimate', // :336 "Browser …"
        'Device storage estimate unavailable.', // useStorageEstimate.ts:4
        '—', // :330
        'Version Info',
        'KOI Mobile preview', // :429 "KOI Web preview"
        "What's New",
        'Latest updates & features',
        'Crisis Resources',
        'Support contacts (hours not verified)', // :588
        'Mobile preview', // :674 "Web preview"
        'Made with care · Private by design',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      for (final gone in [
        'Delete all conversations',
        'Every day at 8:00 PM',
        'Tap to change',
        'Anonymous only',
        'Download a copy',
        'Restore from backup',
        'Local Storage',
        '42 KB of 5 MB used',
        '1%',
        'KOI v1.0.0',
        'v1.0.0',
        '24/7 helplines (Pakistan)',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(status(tester), 'No check-in preference saved.$_languageNote');
      await scrollThrough(tester, const Key('settings-scroll'));
    });

    testWidgets('ATC-M1-24 shows the saved values', (tester) async {
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(
          companion: 'raza',
          displayName: 'Rafi',
          language: 'ur',
          notificationsEnabled: false,
          notificationTime: '21:15',
        ),
      );
      expect(find.text('Raza 👨 · Rafi'), findsOneWidget); // page.tsx:78
      expect(descOf(tester, 'row-language', 'Language'), 'Urdu (preference)');
      expect(descOf(tester, 'row-checkin', 'Daily Check-in'), 'Preference off');
      expect(descOf(tester, 'row-reminder', 'Reminder Time'), '21:15');
      expect(
        status(tester),
        'Preference off; no notifications scheduled.$_languageNote',
      );
    });

    testWidgets('ATC-M1-25 check-in on: real saved time in desc and status line', (
      tester,
    ) async {
      const on = SettingsPrefs(
        language: 'en',
        notificationsEnabled: true,
        notificationTime: '21:15',
      );
      await pumpSettings(tester, stored: on, now: DateTime(2026, 1, 1, 20));
      expect(
        descOf(tester, 'row-language', 'Language'),
        'English (preference)',
      );
      expect(
        descOf(tester, 'row-checkin', 'Daily Check-in'),
        'Preferred time: 21:15',
      );
      expect(
        status(tester),
        'Preferred time later today (21:15, device time). No message is '
        'scheduled.$_languageNote',
      );
      await pumpSettings(tester, stored: on, now: DateTime(2026, 1, 1, 21, 15));
      expect(
        status(tester),
        'Preferred time reached (21:15, device time). No message is '
        'scheduled.$_languageNote',
      );
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(notificationsEnabled: true),
      );
      expect(
        descOf(tester, 'row-checkin', 'Daily Check-in'),
        'Preferred time: not set',
      );
      expect(
        status(tester),
        'Choose a preferred time. Message delivery is '
        'unavailable.$_languageNote',
      );
    });

    testWidgets('ATC-M1-25 the status line re-reads the clock every minute', (
      tester,
    ) async {
      var now = DateTime(2026, 1, 1, 21, 14);
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
                'u1': const SettingsPrefs(
                  notificationsEnabled: true,
                  notificationTime: '21:15',
                ),
              }),
            ),
            koiStorageBytesProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: SettingsTab(now: () => now)),
          ),
        ),
      );
      await tester.pump();
      expect(status(tester), startsWith('Preferred time later today'));
      now = DateTime(2026, 1, 1, 21, 15);
      await tester.pump(const Duration(minutes: 1));
      expect(status(tester), startsWith('Preferred time reached'));
    });

    testWidgets('ATC-M1-26 language toggle saves, then says so (web toasts)', (
      tester,
    ) async {
      await pumpSettings(tester);
      // page.tsx:64: anything but 'en' becomes 'en'.
      await tapVisible(tester, find.byKey(const Key('row-language')));
      expect(find.text('Preference saved on this device.'), findsOneWidget);
      expect(
        descOf(tester, 'row-language', 'Language'),
        'English (preference)',
      );
      expect(store.values['u1']!.language, 'en');

      await tapVisible(tester, find.byKey(const Key('row-language')));
      expect(descOf(tester, 'row-language', 'Language'), 'Urdu (preference)');
      expect(store.values['u1']!.language, 'ur');
      expect(find.text('Language changed to Urdu'), findsNothing);
      await drain(tester);
      expect(find.byKey(const Key('settings-toast')), findsNothing);
    });

    testWidgets('ATC-M1-25 daily check-in toggle: desc, status and save', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      expect(find.text('Preference saved on this device.'), findsOneWidget);
      expect(
        descOf(tester, 'row-checkin', 'Daily Check-in'),
        'Preferred time: not set',
      );
      expect(store.values['u1']!.notificationsEnabled, isTrue);
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      expect(descOf(tester, 'row-checkin', 'Daily Check-in'), 'Preference off');
      expect(store.values['u1']!.notificationsEnabled, isFalse);
      expect(status(tester), startsWith('Preference off;'));
      await drain(tester);
    });

    testWidgets('ATC-M1-26 a failed save keeps the old value and says so', (
      tester,
    ) async {
      await pumpSettings(tester, stored: const SettingsPrefs(language: 'ur'));
      store.saveError = StateError('disk full');
      await tapVisible(tester, find.byKey(const Key('row-language')));
      expect(
        find.text('Preference could not be saved. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Preference saved on this device.'), findsNothing);
      expect(descOf(tester, 'row-language', 'Language'), 'Urdu (preference)');
      await drain(tester);
    });

    testWidgets('ATC-M1-26 preference rows do nothing while loading or saving', (
      tester,
    ) async {
      final slow = _GatedStore()..loadGate = Completer<void>();
      await pumpSettings(tester, custom: slow);
      await tapVisible(tester, find.byKey(const Key('row-language')));
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      expect(slow.values, isEmpty); // not loaded yet: disabled
      expect(find.byKey(const Key('settings-toast')), findsNothing);

      slow.loadGate!.complete();
      await tester.pump();
      slow.saveGate = Completer<void>();
      await tapVisible(tester, find.byKey(const Key('row-language')));
      await tapVisible(tester, find.byKey(const Key('row-checkin')));
      slow.saveGate!.complete();
      await tester.pump();
      // Only the first tap saved; the second came while it was saving.
      expect(slow.values['u1']!.language, 'en');
      expect(slow.values['u1']!.notificationsEnabled, isNull);
      await drain(tester);
    });

    testWidgets('ATC-M1-28 Clear History is disabled: no toast, nothing changes', (
      tester,
    ) async {
      await pumpSettings(tester);
      final row = find.byKey(const Key('row-clear'));
      await tapVisible(tester, row);
      expect(find.text('All conversations cleared'), findsNothing);
      expect(
        find.text(
          'History deletion is unavailable until its scope is '
          'approved.',
        ),
        findsNothing, // web's handler can't run on a disabled button
      );
      expect(find.byKey(const Key('settings-toast')), findsNothing);
      expect(store.values, isEmpty);
      final semantics = tester.getSemantics(row);
      expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
    });

    testWidgets('ATC-M1-25 Reminder Time: system time picker saves HH:mm', (
      tester,
    ) async {
      await pumpSettings(tester, now: DateTime(2026, 10, 18, 7, 5));
      await tapVisible(tester, find.byKey(const Key('row-reminder')));
      await tester.pumpAndSettle();
      expect(find.text('Preferred time (device timezone)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.values, isEmpty);

      await tapVisible(tester, find.byKey(const Key('row-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // initial = device time 07:05
      await tester.pumpAndSettle();
      expect(store.values['u1']!.notificationTime, '07:05');
      expect(descOf(tester, 'row-reminder', 'Reminder Time'), '07:05');
      expect(find.text('Preference saved on this device.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('ATC-M1-25 Reminder Time picker opens on the saved time', (tester) async {
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(notificationTime: '21:15'),
      );
      await tapVisible(tester, find.byKey(const Key('row-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(store.values['u1']!.notificationTime, '21:15');
      await drain(tester);
    });

    testWidgets('ATC-M1-26 a new toast restarts the 3s timer', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-language')));
      await tester.pump(const Duration(milliseconds: 2500));
      store.saveError = StateError('disk full');
      await tapVisible(tester, find.byKey(const Key('row-language')));
      await tester.pump(const Duration(milliseconds: 2500));
      expect(
        find.text('Preference could not be saved. Please retry.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('settings-toast')), findsNothing);
    });

    testWidgets('ATC-M14-20 Storage: real KOI data size, never a quota or percent', (
      tester,
    ) async {
      await pumpSettings(tester, storageBytes: 1572864); // 1.5 MiB
      await tester.pump();
      expect(
        find.text(
          'Approximately 1.50 MB of KOI data on this device (saved records '
          'only; app files and caches are not counted).',
        ),
        findsOneWidget,
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('ATC-M12-09 crisis helplines expand and dial the exact tel: links', (
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

    testWidgets('ATC-M1-28 help panels: one open at a time, collapsed panels hidden', (
      tester,
    ) async {
      await pumpSettings(tester);
      double h(String id) =>
          tester.getSize(find.byKey(Key('help-$id-body'))).height;
      expect(h('version'), 0);
      await tapVisible(tester, find.byKey(const Key('help-version')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('version'), greaterThan(0));
      for (final line in [
        'Version: 0.0.1', // pubspec.yaml
        'Release Date: Not published', // page.tsx:460
        'Runtime: Debug build', // tests run in debug mode
        'Platform: Mobile App', // page.tsx:466 "Web App"
      ]) {
        expect(find.text(line, findRichText: true), findsOneWidget);
      }
      expect(find.textContaining('Production'), findsNothing);
      expect(find.textContaining('January 2025'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('help-whatsnew')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('version'), 0);
      expect(h('whatsnew'), greaterThan(0));
      await tapVisible(tester, find.byKey(const Key('help-whatsnew')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h('whatsnew'), 0);
    });

    testWidgets("ATC-M1-28 What's New: web's list, avatar line only when animated", (
      tester,
    ) async {
      const web = [
        'Encrypted local history recovery',
        'Local companion and reminder preferences',
        'Audio and camera remain unavailable',
      ];
      await pumpSettings(tester);
      expect(find.text('Current implemented features'), findsOneWidget);
      for (final t in web) {
        expect(find.textContaining(t), findsOneWidget, reason: t);
      }
      expect(find.textContaining('Enhanced avatar animations'), findsNothing);
      expect(find.textContaining('v1.0.0'), findsNothing);
      expect(find.textContaining('offline support'), findsNothing);

      await pumpSettings(tester, avatar: AvatarSource.local);
      expect(find.textContaining('Enhanced avatar animations'), findsOneWidget);
    });
  });

  group('ATC-M1-27 AvatarPicker (companions, web parity)', () {
    testWidgets('opens, fits 360dp, saves companion + nickname', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AvatarPicker), findsOneWidget);
      expect(find.text('Choose Your Companion'), findsOneWidget);
      expect(
        find.text('Pick the personality that resonates with you'),
        findsOneWidget,
      );
      for (final t in [
        'AISHA',
        'RAZA',
        'KOI',
        '🦊',
        'Companion nickname (optional, stored locally)', // AvatarPicker:187
        'Leave blank for the companion name', // :195
      ]) {
        expect(
          find.descendant(
            of: find.byType(AvatarPicker),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
      expect(find.text('Your Name (Optional)'), findsNothing);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.byKey(const Key('picker-aisha')));
      await tester.enterText(
        find.byKey(const Key('avatar-picker-name')),
        '  Sara ',
      );
      await tapVisible(tester, find.byKey(const Key('avatar-picker-save')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AvatarPicker), findsNothing);
      expect(find.text('Aisha 👩 · Sara'), findsOneWidget);
      expect(find.text('Companion saved on this device.'), findsOneWidget);
      expect(find.text('Companion updated successfully!'), findsNothing);
      expect(store.values['u1']!.companion, 'aisha');
      expect(store.values['u1']!.displayName, 'Sara'); // trimmed
      await drain(tester);
    });

    testWidgets('nickname is limited to 64 characters', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const Key('avatar-picker-name')),
        'x' * 70,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('avatar-picker-name')),
      );
      expect(field.controller!.text.length, 64);
    });

    testWidgets('"Saving..." while saving; a failed save stays open', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('row-avatar')));
      await tester.pump(const Duration(milliseconds: 400));
      await tapVisible(tester, find.byKey(const Key('picker-raza')));
      store
        ..saveGate = Completer<void>()
        ..saveError = StateError('disk full');
      await tapVisible(tester, find.byKey(const Key('avatar-picker-save')));
      expect(find.text('Saving...'), findsOneWidget); // AvatarPicker.tsx:233
      store.saveGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AvatarPicker), findsOneWidget); // still open
      expect(
        find.descendant(
          of: find.byType(AvatarPicker),
          matching: find.text('Companion could not be saved. Please retry.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Save Changes ✓'), findsOneWidget);
      expect(store.values, isEmpty);
      await drain(tester);
      await tapVisible(tester, find.byKey(const Key('avatar-picker-cancel')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Koi 🦊'), findsOneWidget); // unchanged
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

    testWidgets('opens on the current companion and nickname', (tester) async {
      await pumpSettings(
        tester,
        stored: const SettingsPrefs(companion: 'raza', displayName: 'Ali'),
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

  group('ATC-M14-21 sub-pages (nested navigator, top nav stays)', () {
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

  testWidgets('ATC-M0-24 in the shell: Settings tab shows the page under the top nav', (
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
