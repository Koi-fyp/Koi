import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/checkins/checkin_models.dart';
import 'package:koi_mobile/checkins/checkin_providers.dart';
import 'package:koi_mobile/checkins/checkin_screen.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/checkins/mood_dashboard.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/progress/progress_screen.dart';
import 'package:koi_mobile/safety/breathing_screen.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  late MemoryCheckInBox box;
  late RecordingSyncQueue queue;
  late DateTime now;

  setUp(() {
    box = MemoryCheckInBox();
    queue = RecordingSyncQueue();
    now = DateTime(2026, 10, 19, 9); // Monday morning
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool debugTools = false,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
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
              'u1': const SettingsPrefs(companion: 'raza'),
            }),
          ),
          ...chatOverrides(queue: queue),
          checkInBoxProvider.overrideWithValue(box),
          checkInClockProvider.overrideWithValue(() => now),
          checkInDebugToolsProvider.overrideWithValue(debugTools),
        ],
        child: MaterialApp(
          home: Scaffold(body: ProgressScreen(now: () => now)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return ProviderScope.containerOf(
      tester.element(find.byType(ProgressScreen)),
    );
  }

  /// Seeds check-ins through the real repository (FakeCipher).
  Future<void> seed(
    ProviderContainer c,
    List<(String day, int mood, CheckInEmotion e)> rows,
  ) async {
    final repo = c.read(checkInRepositoryProvider);
    for (final (day, mood, e) in rows) {
      await repo.saveMorningRecord(
        'u1',
        MorningCheckIn(
          day: day,
          timestamp: dayOf(day).add(const Duration(hours: 9)),
          sleep: 3,
          mood: mood,
          connection: 3,
          energy: 3,
          emotion: e,
        ),
      );
    }
    await c.read(checkInControllerProvider('u1')).reload();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  int spotCount(WidgetTester tester) => tester
      .widget<LineChart>(find.byType(LineChart))
      .data
      .lineBarsData
      .single
      .spots
      .length;

  testWidgets('ATC-M7-05 the morning check-in is done in 5 taps (the 5th '
      'saves); companion name + image; celebration and suggestions', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.byKey(const Key('checkin-start')));
    expect(find.text('Raza'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    var taps = 0;
    for (final v in [2, 4, 1, 1]) {
      await tester.tap(find.byKey(Key('rating-$v')));
      taps++;
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('emotion-calm')));
    taps++;
    await settle(tester);
    expect(taps, 5);
    expect(box.rows, hasLength(1));
    expect(find.text(CheckInTexts.celebrate), findsOneWidget);
    // Connection 1 + energy 1 → a social step and rest.
    expect(find.byKey(const Key('activity-social')), findsOneWidget);
    expect(find.byKey(const Key('activity-rest')), findsOneWidget);

    await tester.tap(find.byKey(const Key('activity-mark-rest')));
    await settle(tester);
    expect(find.byKey(const Key('activity-done-rest')), findsOneWidget);
    expect(find.byKey(const Key('activity-mark-social')), findsNothing);
  });

  testWidgets('ATC-M7-06 Skip saves nothing (first page and midway)', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.byKey(const Key('checkin-start')));
    await tester.tap(find.byKey(const Key('checkin-skip')));
    await settle(tester);
    expect(find.byType(CheckInScreen), findsNothing);

    await tapVisible(tester, find.byKey(const Key('checkin-start')));
    await tester.tap(find.byKey(const Key('rating-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rating-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkin-skip')));
    await settle(tester);
    expect(box.rows, isEmpty);
    expect(find.byKey(const Key('mood-empty')), findsOneWidget);
  });

  testWidgets('ATC-M7-07 evening reflection from the card: empty is allowed', (
    tester,
  ) async {
    now = DateTime(2026, 10, 19, 20);
    await pump(tester);
    expect(find.byKey(const Key('checkin-entry-evening')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('checkin-start')));
    expect(find.text(CheckInTexts.evening), findsOneWidget);
    await tester.tap(find.byKey(const Key('reflection-save')));
    await settle(tester);
    expect(box.rows, hasLength(1));
    expect(find.text(CheckInTexts.thanks), findsOneWidget);
  });

  testWidgets('ATC-M7-12 calendar: an emotion icon only on check-in days', (
    tester,
  ) async {
    final c = await pump(tester);
    await seed(c, [
      ('2026-10-03', 4, CheckInEmotion.happy),
      ('2026-10-10', 2, CheckInEmotion.sad),
      ('2026-10-18', 3, CheckInEmotion.calm),
    ]);
    await tester.pump();
    final icons = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('cal-icon-'),
    );
    expect(icons, findsNWidgets(3));
    expect(
      tester.widget<Text>(find.byKey(const Key('cal-icon-2026-10-10'))).data,
      CheckInEmotion.sad.emoji,
    );
    for (final d in ['2026-10-01', '2026-10-11', '2026-10-19', '2026-10-31']) {
      expect(find.byKey(Key('cal-day-$d')), findsOneWidget);
      expect(find.byKey(Key('cal-icon-$d')), findsNothing, reason: d);
    }
    // Previous month: no check-ins, no icons.
    await tapVisible(tester, find.byKey(const Key('cal-prev')));
    expect(icons, findsNothing);
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('ATC-M7-13 card: morning check-in at 14:59, evening at 15:00', (
    tester,
  ) async {
    now = DateTime(2026, 10, 19, 14, 59);
    await pump(tester);
    expect(find.byKey(const Key('checkin-entry-morning')), findsOneWidget);
    now = DateTime(2026, 10, 19, 15);
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.byKey(const Key('checkin-entry-evening')), findsOneWidget);
  });

  testWidgets('ATC-M7-14 debug options absent in release, present in debug', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('checkin-debug')), findsNothing);
    expect(find.text(MoodTexts.addSamples), findsNothing);
    expect(find.text(MoodTexts.clear), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, debugTools: true);
    await tapVisible(tester, find.text(MoodTexts.addSamples));
    expect(box.rows.length, inInclusiveRange(15, 25));
    expect(find.byKey(const Key('mood-trend')), findsOneWidget);
    await tapVisible(tester, find.text(MoodTexts.clear));
    expect(box.rows, isEmpty);
    expect(find.byKey(const Key('mood-empty')), findsOneWidget);
  });

  testWidgets('ATC-M11-03 emotion filter changes the trend line', (
    tester,
  ) async {
    final c = await pump(tester);
    await seed(c, [
      ('2026-10-14', 2, CheckInEmotion.sad),
      ('2026-10-15', 5, CheckInEmotion.happy),
      ('2026-10-17', 1, CheckInEmotion.sad),
    ]);
    await tester.pump();
    expect(spotCount(tester), 3);
    await tapVisible(tester, find.byKey(const Key('emotion-filter-sad')));
    expect(spotCount(tester), 2);
    await tapVisible(tester, find.byKey(const Key('emotion-filter-calm')));
    expect(find.byType(LineChart), findsNothing);
    expect(find.byKey(const Key('mood-empty-filtered')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('emotion-filter-all')));
    expect(spotCount(tester), 3);
    // Pie of the range, summing to 100.
    expect(find.text('😢 Sad · 67%'), findsOneWidget);
    expect(find.text('😊 Happy · 33%'), findsOneWidget);
  });

  testWidgets('ATC-M11-04 heavy card after 3 low check-ins; breathing opens '
      'locally and sends nothing to the chat session', (tester) async {
    final c = await pump(tester);
    await seed(c, [
      ('2026-10-16', 2, CheckInEmotion.sad),
      ('2026-10-17', 1, CheckInEmotion.anxious),
      ('2026-10-18', 2, CheckInEmotion.sad),
    ]);
    await tester.pump();
    expect(find.text(MoodTexts.heavy), findsOneWidget);
    expect(c.read(safetyControllerProvider).crisis, isNull);

    await tapVisible(tester, find.byKey(const Key('heavy-breathing')));
    expect(find.byType(BreathingScreen), findsOneWidget);
    expect(
      c.read(safetyControllerProvider).breathing,
      isNull,
      reason: 'shared controller untouched',
    );
    await tester.tap(find.byKey(const Key('breathing-stop')));
    await settle(tester);
    expect(find.byType(BreathingScreen), findsNothing);
    expect(
      c.read(chatSessionStateProvider).pendingClientEvent,
      ClientEvent.none,
    );
  });

  testWidgets(
    'ATC-M11-05 empty state: no chart, no sample data, Avg Mood "–"',
    (tester) async {
      await pump(tester);
      expect(find.text(MoodTexts.empty), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(PieChart), findsNothing);
      expect(find.byKey(const Key('mood-heavy')), findsNothing);
      expect(box.rows, isEmpty);
      final mood = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('stat-mood')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toList();
      expect(mood, containsAll(['–', '/5']));
    },
  );

  testWidgets('ATC-M11-06 the mood dashboard sits right after the jigsaw', (
    tester,
  ) async {
    await pump(tester);
    final jigsaw = tester.getRect(find.byKey(const Key('jigsaw-card')));
    final dash = tester.getRect(find.byKey(const Key('mood-dashboard')));
    expect(dash.top - jigsaw.bottom, 20);
    expect(dash.left, jigsaw.left);
    expect(dash.width, jigsaw.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ATC-IT-M7-01 a check-in saved through the screen reaches the '
      'dashboard and Avg Mood; only the encrypted record exists, nothing is '
      'queued for Firestore', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byKey(const Key('checkin-start')));
    for (final v in [3, 4, 3, 3]) {
      await tester.tap(find.byKey(Key('rating-$v')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('emotion-happy')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('checkin-close')));
    await settle(tester);

    expect(find.byKey(const Key('mood-trend')), findsOneWidget);
    expect(spotCount(tester), 1);
    expect(find.text('😊 Happy · 100%'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget, reason: 'Avg Mood');
    expect(find.byKey(const Key('cal-icon-2026-10-19')), findsOneWidget);

    expect(queue.items, isEmpty, reason: 'local only: nothing synced');
    final row = (jsonDecode(box.rows.values.single) as Map)
        .cast<String, Object?>();
    expect(row['payload'], startsWith('v1:FAKE:'));
    expect(row['synced'], isFalse);
    final raw = box.rows.values.single;
    expect(raw, isNot(contains('mood_rating')));
    expect(raw, isNot(contains('happy')));
  });
}
