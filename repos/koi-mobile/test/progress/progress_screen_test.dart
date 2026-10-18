import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/progress/progress_icons.dart';
import 'package:koi_mobile/progress/progress_screen.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/shell/top_nav.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/real_fonts.dart';
import 'progress_stats_test.dart' show msg;

void main() {
  useRealFonts();

  // Wednesday 14 Oct 2026, 15:00 local.
  final now = DateTime(2026, 10, 14, 15);
  DateTime day(int offset, [int hour = 10]) =>
      DateTime(2026, 10, 14 + offset, hour);

  Future<void> pump(
    WidgetTester tester, {
    List<MessageRecord> rows = const [],
    Widget? home,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    final store = MemoryMessageStore();
    for (final r in rows) {
      await store.put(r);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(complete: true),
          ),
          ...chatOverrides(store: store),
        ],
        child: MaterialApp(
          home: home ?? Scaffold(body: ProgressScreen(now: () => now)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> scrollThrough(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.drag(
        find.byKey(const Key('progress-scroll')),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
  }

  String statValue(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .first
      .data!;

  String textIn(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Text),
          matchRoot: true,
        ),
      )
      .first
      .data!;

  Color? heatColor(WidgetTester tester, int row, int col) =>
      (tester.widget<Container>(find.byKey(Key('heat-$row-$col'))).decoration!
              as BoxDecoration)
          .color;

  test('ATC-M0-21 every web icon path parses', () {
    for (final icon in [
      ProgressIcons.flame,
      ProgressIcons.chat,
      ProgressIcons.smile,
      ProgressIcons.lock,
      ProgressIcons.check,
      ProgressIcons.arrow,
      ProgressIcons.sparkles,
      ProgressIcons.puzzle,
      ProgressIcons.download,
      ProgressIcons.share,
      ProgressIcons.calendar,
      ProgressIcons.trendingUp,
      ProgressIcons.brain,
    ]) {
      for (final p in icon) {
        final b = p.getBounds();
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(24));
      }
    }
  });

  testWidgets('ATC-M0-21 no history: zero / empty states, every section, no overflow', (
    tester,
  ) async {
    await pump(tester);
    for (final t in [
      'Your Progress',
      'Every step matters. Keep growing.',
      'TOTAL PIECES COLLECTED',
      'pieces of your story, preserved',
      'Days Streak',
      'Total Sessions',
      'Avg Mood',
      'Mood Trends',
      'No mood check-ins yet',
      'Milestones',
      'First Conversation',
      'Activity Heatmap',
      'Emotional Growth',
      'Share Your Progress',
      'Privacy-first · No personal details shared',
    ]) {
      await tester.ensureVisible(find.text(t));
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(textIn(tester, 'jigsaw-total'), '0');
    expect(statValue(tester, 'stat-streak'), '0');
    expect(statValue(tester, 'stat-sessions'), '0');
    expect(statValue(tester, 'stat-mood'), '–');
    expect(textIn(tester, 'milestones-badge'), '0/4 Complete');
    expect(find.byKey(const Key('milestone-1-reward')), findsNothing);
    expect(textIn(tester, 'share-pieces'), '0');
    expect(textIn(tester, 'share-days'), '0');
    expect(textIn(tester, 'share-streak'), '0');
    // Changed in Prompt 28: the 7 day-label mood bars are replaced by the
    // mood dashboard (empty state above) and the check-in calendar.
    expect(find.byKey(const Key('mood-dashboard')), findsOneWidget);
    // Web's fake values never appear (outside the calendar's day numbers).
    for (final fake in ['247', '12', '47', '7.2', '2/4 Complete']) {
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data == fake &&
              find
                  .ancestor(
                    of: find.byWidget(w),
                    matching: find.byKey(const Key('checkin-calendar')),
                  )
                  .evaluate()
                  .isEmpty,
        ),
        findsNothing,
        reason: fake,
      );
    }
    expect(heatColor(tester, 0, 0), const Color(0xFFF0F0F0));
    await scrollThrough(tester);
  });

  testWidgets('ATC-M0-22 real history: streak, sessions, milestones, heatmap', (
    tester,
  ) async {
    await pump(
      tester,
      rows: [
        // 3-day current streak: Mon, Tue, Wed (today); 6 messages today.
        for (var i = 0; i < 6; i++) msg(day(0, 8 + i)),
        msg(day(-1)),
        msg(day(-2)),
        // Earlier 7-day run: 21–27 Sep.
        for (var i = 0; i < 7; i++) msg(DateTime(2026, 9, 21 + i, 12)),
        msg(day(0, 14), sender: 'ai'),
      ],
    );
    expect(statValue(tester, 'stat-streak'), '3');
    expect(statValue(tester, 'stat-sessions'), '10');
    expect(textIn(tester, 'share-days'), '10');
    expect(textIn(tester, 'share-streak'), '3');
    expect(textIn(tester, 'milestones-badge'), '2/4 Complete');
    expect(find.byKey(const Key('milestone-1-reward')), findsOneWidget);
    expect(find.byKey(const Key('milestone-2-reward')), findsOneWidget);
    expect(find.byKey(const Key('milestone-3-reward')), findsNothing);
    expect(find.text('+5 pieces'), findsOneWidget);
    expect(find.text('+10 pieces'), findsOneWidget);
    // Wed this week: 6 messages → intensity 4 (#2e7d32); Mon → 1.
    expect(heatColor(tester, 2, 7), const Color(0xFF2E7D32));
    expect(heatColor(tester, 0, 7), const Color(0xFFC8E6C9));
    expect(heatColor(tester, 3, 7), const Color(0xFFF0F0F0)); // future
    await scrollThrough(tester);
  });

  testWidgets('ATC-M0-23 jigsaw: expand, 25 locked pieces, 0%, collapse via arrow', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('jigsaw-card')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your Wellness Journey'), findsOneWidget);
    expect(find.text("HOW FAR YOU'VE COME"), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.text('0 of 25 pieces unlocked · Keep growing to reveal more'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('jigsaw-card'))).height,
      greaterThanOrEqualTo(480),
    );
    // Taps inside the expanded content do not collapse it (web
    // stopPropagation); only the arrow does.
    await tester.tap(find.text('Completion Progress'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your Wellness Journey'), findsOneWidget);
    await tester.tap(find.byKey(const Key('jigsaw-collapse')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your Wellness Journey'), findsNothing);
    expect(find.text('TOTAL PIECES COLLECTED'), findsOneWidget);
    await scrollThrough(tester);
  });

  testWidgets('ATC-M0-23 milestone tap toggles its highlight', (tester) async {
    await pump(tester);
    BoxDecoration hl() =>
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const Key('milestone-3-highlight')),
                )
                .decoration!
            as BoxDecoration;
    expect(hl().color, isNull);
    await tapVisible(tester, find.byKey(const Key('milestone-3')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(hl().color, const Color(0x0A000000));
    await tapVisible(tester, find.byKey(const Key('milestone-3')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(hl().color, isNull);
  });

  testWidgets('ATC-M0-23 Download and Share show "coming soon" toasts', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byKey(const Key('share-download')));
    expect(find.text(ProgressScreen.downloadSoon), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('share-share')));
    expect(find.text(ProgressScreen.shareSoon), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
  });

  testWidgets('ATC-M0-24 Progress tab in the shell shows the page under the nav', (
    tester,
  ) async {
    await pump(tester, home: const AppShell(initialTab: KoiTab.progress));
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.byType(KoiTopNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
