import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/safety/breathing_screen.dart';
import 'package:koi_mobile/safety/crisis_screen.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_controller.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';
import 'package:koi_mobile/safety/safety_host.dart';
import 'package:koi_mobile/safety/safety_providers.dart';

import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  final crisisScreen = find.byType(CrisisScreen);
  final breathingScreen = find.byType(BreathingScreen);

  late List<ClientEvent> events;
  late List<CrisisPath> paths;

  /// SafetyHost over a blank page at 360x800dp; returns its controller.
  Future<SafetyController> pumpHost(
    WidgetTester tester, {
    bool debugMenu = true,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    events = [];
    paths = [];
    final c = SafetyController(
      onClientEvent: events.add,
      onCrisisPath: paths.add,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          safetyControllerProvider.overrideWith((ref) => c),
          safetyDebugMenuEnabledProvider.overrideWithValue(debugMenu),
        ],
        child: const MaterialApp(
          home: SafetyHost(
            child: Scaffold(
              body: Center(child: SafetyDebugTrigger(child: Text('Settings'))),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  Future<void> startBreathing(SafetyController c, WidgetTester tester) async {
    c.handleUiAction(SimulatedSafetyEvents.startBreathing());
    await settle(tester);
  }

  /// Every visible text on screen, joined.
  String shownText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join('\n');

  String cue(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('breathing-cue'))).data!;
  String cycle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('breathing-cycle'))).data!;

  group('Crisis screen', () {
    testWidgets('ATC-M12-06 cannot be dismissed by back or tapping outside', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      c.handleRisk(SimulatedSafetyEvents.high());
      await settle(tester);
      expect(crisisScreen, findsOneWidget);

      await back(tester);
      expect(crisisScreen, findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.tapAt(const Offset(356, 796));
      await settle(tester);
      expect(crisisScreen, findsOneWidget);
      expect(c.crisis, isNotNull);
      expect(paths, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ATC-M12-07 shows content, never the category or score, max 3 items', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      c.handleRisk(SimulatedSafetyEvents.high()); // score 0.75, 4 items
      await settle(tester);
      expect(find.text(CrisisScreen.title), findsOneWidget);
      expect(find.text(CrisisScreen.description), findsOneWidget);
      expect(c.crisis!.category, RiskCategory.high); // internal only
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('crisis-item-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('crisis-item-3')), findsNothing);
      expect(find.textContaining('item 4'), findsNothing);
      // Grounded: no source label; standard confidence: no limited note.
      expect(find.text(CrisisScreen.fallbackLabel), findsNothing);
      expect(find.text(CrisisScreen.limitedInformation), findsNothing);
      // No category, no score in any form, no "verified" wording.
      final texts = shownText(tester);
      expect(texts, isNot(contains('HIGH')));
      expect(texts.toLowerCase(), isNot(contains('category')));
      expect(texts.toLowerCase(), isNot(contains('risk')));
      expect(texts, isNot(contains('0.75')));
      expect(texts, isNot(contains('75')));
      expect(texts.toLowerCase(), isNot(contains('score')));
      expect(texts.toLowerCase(), isNot(contains('verified')));
    });

    testWidgets('ATC-M12-07 CRITICAL fallback: neutral label + limited information', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      c.handleRisk(SimulatedSafetyEvents.critical());
      await settle(tester);
      expect(c.crisis!.category, RiskCategory.critical); // internal only
      expect(shownText(tester), isNot(contains('CRITICAL')));
      expect(shownText(tester).toLowerCase(), isNot(contains('category')));
      expect(find.text(CrisisScreen.fallbackLabel), findsOneWidget);
      expect(find.text(CrisisScreen.limitedInformation), findsOneWidget);
      expect(find.textContaining('0.95'), findsNothing);
      // No helpline in the payload → the 1166 default.
      expect(
        find.text('Sehat Tahaffuz 1166 (Humraaz mental health service): 1166'),
        findsOneWidget,
      );
    });

    testWidgets('ATC-M12-08 all three paths close it and report crisis_path', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      for (final path in CrisisPath.values) {
        c.handleRisk(SimulatedSafetyEvents.high());
        await settle(tester);
        expect(crisisScreen, findsOneWidget);
        await tester.tap(find.text(CrisisScreen.pathLabels[path]!));
        await settle(tester);
        expect(crisisScreen, findsNothing, reason: path.wire);
        expect(paths.last, path);
        c.crisisResolutionSent();
      }
      expect(paths, CrisisPath.values);
      expect(find.text('I reached out for support'), findsNothing);
    });

    testWidgets('ATC-M12-08 a repeated handoff never opens a second screen', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      await settle(tester);
      expect(find.text(CrisisScreen.unavailable), findsOneWidget);
      expect(find.byKey(const Key('crisis-call')), findsOneWidget);
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      c.handleRisk(SimulatedSafetyEvents.high());
      await settle(tester);
      expect(find.byType(CrisisScreen, skipOffstage: false), findsOneWidget);
      // The open screen got the turn's content.
      expect(find.text(CrisisScreen.unavailable), findsNothing);
      expect(find.byKey(const Key('crisis-item-0')), findsOneWidget);
    });

    testWidgets('ATC-M12-09 call button dials the payload helpline', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      final opened = <Uri>[];
      final content = InterventionContent.fromJson({
        'source': 'grounded',
        'items': [
          {'text': 'x'},
        ],
        'helpline': {
          'name': 'Test Line',
          'number': '0800-123',
          'verified': false,
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CrisisScreen(
            view: CrisisView(content: content),
            onChoose: (_) {},
            openUrl: (uri) async => opened.add(uri),
          ),
        ),
      );
      expect(find.text('Test Line: 0800-123'), findsOneWidget);
      final call = find.byKey(const Key('crisis-call'));
      expect(call, findsOneWidget);
      expect(find.text('Call 0800-123'), findsOneWidget);
      await tester.ensureVisible(call);
      await tester.tap(call);
      await tester.pump();
      expect(opened, [Uri.parse('tel:0800123')]);
    });

    testWidgets('ATC-M12-09 default helpline call button dials 1166', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CrisisScreen(
            view: const CrisisView(),
            onChoose: (_) {},
            openUrl: (uri) async => opened.add(uri),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Call 1166'));
      await tester.tap(find.text('Call 1166'));
      await tester.pump();
      expect(opened, [Uri.parse('tel:1166')]);
    });
  });

  group('Breathing screen', () {
    testWidgets('ATC-M9-04 timing: cues, cycles and orb scale follow inhale/exhale', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester); // 4s in, 6s out, 6 cycles
      expect(breathingScreen, findsOneWidget);
      expect(find.text(BreathingScreen.title), findsOneWidget);
      expect(find.text(BreathingScreen.audioNotice), findsOneWidget);
      expect(cue(tester), 'Breathe in');
      expect(cycle(tester), 'Cycle 1 of 6');

      double scale() => tester
          .widget<Transform>(find.byKey(const Key('breathing-orb')))
          .transform
          .entry(0, 0);
      // ~0.5 s elapsed in the first inhale (settle): just above 0.82.
      expect(scale(), inInclusiveRange(0.82, 0.86));

      await tester.pump(const Duration(seconds: 4));
      expect(cue(tester), 'Breathe out');
      expect(scale(), inInclusiveRange(0.96, 1.0));
      await tester.pump(const Duration(seconds: 6));
      expect(cue(tester), 'Breathe in');
      expect(cycle(tester), 'Cycle 2 of 6');
      expect(events, isEmpty);
    });

    testWidgets('ATC-M9-04 finishing all cycles reports playback_done once', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      await tester.pump(const Duration(seconds: 59));
      expect(cycle(tester), 'Cycle 6 of 6');
      expect(events, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(cue(tester), BreathingScreen.complete);
      expect(events, [ClientEvent.playbackDone]);
      expect(find.byKey(const Key('breathing-pause')), findsNothing);
      expect(find.byKey(const Key('breathing-stop')), findsNothing);
      // Back closes the finished screen, no second event.
      await back(tester);
      expect(breathingScreen, findsNothing);
      expect(events, [ClientEvent.playbackDone]);
    });

    testWidgets('ATC-M9-05 pause and resume (user) freeze and continue the clock', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      await tester.pump(const Duration(seconds: 2)); // ~2.5 s, inhale
      await tester.tap(find.byKey(const Key('breathing-pause')));
      await tester.pump();
      expect(cue(tester), BreathingScreen.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(cue(tester), BreathingScreen.paused);
      expect(cycle(tester), 'Cycle 1 of 6');

      await tester.tap(find.byKey(const Key('breathing-resume')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(cue(tester), 'Breathe in'); // ~3 s, still inhaling
      await tester.pump(const Duration(seconds: 2));
      expect(cue(tester), 'Breathe out');
      expect(events, isEmpty);
    });

    testWidgets('ATC-M9-05 pause_breathing pauses; only the user resumes', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      c.handleUiAction(const UiAction(UiAction.pauseBreathing));
      await tester.pump();
      expect(cue(tester), BreathingScreen.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(cue(tester), BreathingScreen.paused);
      expect(find.byKey(const Key('breathing-resume')), findsOneWidget);
      expect(events, isEmpty);
    });

    testWidgets('ATC-M9-06 Stop button → playback_stopped, screen closes', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      await tester.tap(find.byKey(const Key('breathing-stop')));
      await settle(tester);
      expect(breathingScreen, findsNothing);
      expect(events, [ClientEvent.playbackStopped]);
      expect(find.text(SafetyController.noticeStopped), findsOneWidget);
    });

    testWidgets('ATC-M9-06 stop_breathing event → playback_stopped, Web notice', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      c.handleUiAction(const UiAction(UiAction.stopBreathing));
      await settle(tester);
      expect(breathingScreen, findsNothing);
      expect(events, [ClientEvent.playbackStopped]);
      expect(find.text(SafetyController.noticeStoppedByKoi), findsOneWidget);
    });

    testWidgets('ATC-M9-06 back while running stops it', (tester) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      await back(tester);
      expect(breathingScreen, findsNothing);
      expect(events, [ClientEvent.playbackStopped]);
    });

    testWidgets('ATC-M12-10 a crisis stops the exercise and shows the crisis screen', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await startBreathing(c, tester);
      await tester.pump(const Duration(seconds: 3));
      c.handleRisk(SimulatedSafetyEvents.critical());
      await settle(tester);
      expect(breathingScreen, findsNothing);
      expect(crisisScreen, findsOneWidget);
      expect(events, [ClientEvent.playbackStopped]);
      expect(find.text(SafetyController.noticeSafetyCheck), findsOneWidget);
      // start_breathing while the crisis flow is open is ignored.
      c.handleUiAction(SimulatedSafetyEvents.startBreathing());
      await settle(tester);
      expect(breathingScreen, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ATC-M12-11 Debug menu', () {
    testWidgets('debug build: long-press opens it and simulates events', (
      tester,
    ) async {
      final c = await pumpHost(tester);
      await tester.longPress(find.text('Settings'));
      await settle(tester);
      for (final k in ['high', 'critical', 'start', 'pause', 'stop']) {
        expect(find.byKey(Key('safety-debug-$k')), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const Key('safety-debug-start')));
      await settle(tester);
      expect(breathingScreen, findsOneWidget);
      // Also reachable from the breathing screen title.
      await tester.longPress(find.text(BreathingScreen.title));
      await settle(tester);
      await tester.tap(find.byKey(const Key('safety-debug-high')));
      await settle(tester);
      expect(crisisScreen, findsOneWidget);
      expect(c.crisis!.category, RiskCategory.high);
    });

    testWidgets('release mode: no debug menu at all', (tester) async {
      await pumpHost(tester, debugMenu: false);
      expect(find.byKey(const Key('safety-debug-trigger')), findsNothing);
      await tester.longPress(find.text('Settings'), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('safety-debug-high')), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    test('the real provider is kDebugMode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // flutter test runs in debug mode; release builds compile this to false.
      expect(container.read(safetyDebugMenuEnabledProvider), isTrue);
    });
  });
}
