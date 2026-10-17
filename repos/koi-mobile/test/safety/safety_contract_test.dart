import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/safety/breathing_clock.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_controller.dart';
import 'package:koi_mobile/safety/safety_debug_menu.dart';

Map<String, Object?> breathingArgs({
  Object? inhale = 4,
  Object? exhale = 6,
  Object? cycles = 6,
  Object? cues = const ['Breathe in', 'Breathe out'],
}) => {
  'pattern': 'slow_6_per_min',
  'inhale_s': inhale,
  'exhale_s': exhale,
  'cycles': cycles,
  'cue_audio': cues,
  'minutes_note': 'about one minute',
};

void main() {
  group('RiskResult / InterventionContent', () {
    test('parses the contract fields and ignores unknown ones', () {
      final r = RiskResult.fromJson({
        'status': 'ok',
        'risk_category': 'HIGH',
        'crisis_score': 0.8,
        'confidence': 'reduced',
        'confidence_reasons': ['reduced_modality_set'],
        'modalities_used': ['text'],
        'trigger_flags': ['vocal_contradiction'],
        'model': {'version': 'pilot-0.1', 'calibrated': false},
        'intervention_content': {
          'source': 'fallback',
          'language': 'en',
          'items': [
            {
              'text': 'a',
              'chunk_id': 'c1',
              'source_corpus': 's',
              'evidence_role': 'e',
              'review_status': 'r',
            },
          ],
          'helpline': {'name': 'N', 'number': '1166', 'verified': false},
        },
        'something_new': 1,
      });
      expect(r.riskCategory, RiskCategory.high);
      expect(r.crisisScore, 0.8);
      expect(r.isReducedConfidence, isTrue);
      expect(r.showsCrisisFlow, isTrue);
      expect(r.model!.version, 'pilot-0.1');
      final c = r.interventionContent!;
      expect(c.source, InterventionSource.fallback);
      expect(c.language, 'en');
      expect(c.items.single.chunkId, 'c1');
      expect(c.items.single.reviewStatus, 'r');
      expect(c.helpline!.number, '1166');
      expect(c.helpline!.verified, isFalse);
    });

    test('only HIGH and CRITICAL open the crisis flow; unavailable never', () {
      for (final (cat, shows) in [
        ('LOW', false),
        ('MODERATE', false),
        ('HIGH', true),
        ('CRITICAL', true),
        ('weird', false),
      ]) {
        expect(
          RiskResult.fromJson({'risk_category': cat}).showsCrisisFlow,
          shows,
          reason: cat,
        );
      }
      expect(
        RiskResult.fromJson({'status': 'unavailable', 'risk_category': 'HIGH'})
            .showsCrisisFlow,
        isFalse,
      );
    });

    test('keeps at most 3 items and rejects invalid content', () {
      final four = InterventionContent.fromJson({
        'source': 'grounded',
        'items': [
          for (var i = 0; i < 4; i++) {'text': 't$i'},
        ],
      })!;
      expect(four.items.map((i) => i.text), ['t0', 't1', 't2']);
      expect(
        InterventionContent.fromJson({
          'source': 'verified_fallback',
          'items': [
            {'text': 'x'},
          ],
        }),
        isNull,
      );
      expect(
        InterventionContent.fromJson({'source': 'grounded', 'items': []}),
        isNull,
      );
      expect(
        InterventionContent.fromJson({
          'source': 'grounded',
          'items': [
            {'text': '  '},
          ],
        }),
        isNull,
      );
    });

    test('helpline falls back to the 1166 default', () {
      const view = CrisisView();
      expect(view.helpline.number, '1166');
      expect(
        view.helpline.name,
        'Sehat Tahaffuz 1166 (Humraaz mental health service)',
      );
    });

    test('CRITICAL content that is not fallback is not shown', () {
      final risk = RiskResult.fromJson({
        'risk_category': 'CRITICAL',
        'intervention_content': {
          'source': 'grounded',
          'items': [
            {'text': 'x'},
          ],
        },
      });
      expect(CrisisView.fromRisk(risk).content, isNull);
      expect(
        CrisisView.fromRisk(SimulatedSafetyEvents.critical()).content,
        isNotNull,
      );
    });
  });

  group('BreathingPattern', () {
    test('parses the contract example', () {
      final p = BreathingPattern.fromArgs(breathingArgs())!;
      expect(p.inhaleS, 4);
      expect(p.exhaleS, 6);
      expect(p.cycles, 6);
      expect(p.cueIn, 'Breathe in');
      expect(p.cueOut, 'Breathe out');
      expect(p.pattern, 'slow_6_per_min');
      expect(p.minutesNote, 'about one minute');
    });

    test('bounds timings to 1–12 s and 1–12 cycles like Web', () {
      final low = BreathingPattern.fromArgs(
        breathingArgs(inhale: 0.5, exhale: 0.2, cycles: 0.4),
      )!;
      expect([low.inhaleS, low.exhaleS, low.cycles], [1, 1, 1]);
      final high = BreathingPattern.fromArgs(
        breathingArgs(inhale: 30, exhale: 13, cycles: 99),
      )!;
      expect([high.inhaleS, high.exhaleS, high.cycles], [12, 12, 12]);
      expect(BreathingPattern.fromArgs(breathingArgs(cycles: 6.9))!.cycles, 6);
    });

    test('rejects missing timings or cues; trims cues', () {
      expect(BreathingPattern.fromArgs(breathingArgs(inhale: null)), isNull);
      expect(BreathingPattern.fromArgs(breathingArgs(exhale: 0)), isNull);
      expect(BreathingPattern.fromArgs(breathingArgs(cycles: '6')), isNull);
      expect(BreathingPattern.fromArgs(breathingArgs(cues: ['in'])), isNull);
      expect(
        BreathingPattern.fromArgs(breathingArgs(cues: ['in', ' '])),
        isNull,
      );
      final p = BreathingPattern.fromArgs(
        breathingArgs(cues: ['  in  ', 'x' * 200]),
      )!;
      expect(p.cueIn, 'in');
      expect(p.cueOut.length, 120);
    });
  });

  group('BreathingFrame / BreathingClock', () {
    final p = BreathingPattern.fromArgs(breathingArgs(cycles: 2))!;

    test('phases, cycles and orb scale over time', () {
      var f = BreathingFrame.at(p, 0);
      expect((f.phase, f.cycle, f.orbScale), (BreathingPhase.inhale, 1, 0.82));
      f = BreathingFrame.at(p, 2);
      expect(f.phaseProgress, 0.5);
      f = BreathingFrame.at(p, 4);
      expect((f.phase, f.cycle, f.orbScale), (BreathingPhase.exhale, 1, 1.0));
      f = BreathingFrame.at(p, 10);
      expect((f.phase, f.cycle), (BreathingPhase.inhale, 2));
      expect(f.overallProgress, 0.5);
      f = BreathingFrame.at(p, 20);
      expect((f.complete, f.cycle, f.overallProgress), (true, 2, 1.0));
    });

    test('pause/resume does not count paused time', () {
      final c = BreathingClock()..start(Duration.zero);
      c.pause(const Duration(seconds: 3));
      expect(c.elapsedSecondsAt(const Duration(seconds: 30)), 3);
      c.resume(const Duration(seconds: 30));
      expect(c.elapsedSecondsAt(const Duration(seconds: 32)), 5);
    });
  });

  group('SafetyController', () {
    late List<ClientEvent> events;
    late List<CrisisPath> paths;
    late SafetyController c;

    setUp(() {
      events = [];
      paths = [];
      c = SafetyController(onClientEvent: events.add, onCrisisPath: paths.add);
    });

    void start() => c.handleUiAction(SimulatedSafetyEvents.startBreathing());

    test('start, pause (event), resume (user), complete → playback_done', () {
      start();
      expect(c.breathingActive, isTrue);
      c.handleUiAction(const UiAction(UiAction.pauseBreathing));
      expect(c.breathing!.paused, isTrue);
      c.resumeBreathing();
      expect(c.breathing!.paused, isFalse);
      c.completeBreathing();
      c.completeBreathing();
      expect(events, [ClientEvent.playbackDone]);
      expect(c.breathing!.complete, isTrue);
      c.dismissBreathing();
      expect(c.breathing, isNull);
      expect(events, [ClientEvent.playbackDone]);
    });

    test('stop by user or by KOI → playback_stopped + Web notice', () {
      start();
      c.stopBreathing();
      expect(events, [ClientEvent.playbackStopped]);
      expect(c.notice, SafetyController.noticeStopped);
      start();
      c.handleUiAction(const UiAction(UiAction.stopBreathing));
      expect(events, [
        ClientEvent.playbackStopped,
        ClientEvent.playbackStopped,
      ]);
      expect(c.notice, SafetyController.noticeStoppedByKoi);
    });

    test('an invalid start_breathing shows the Web notice', () {
      c.handleUiAction(
        UiAction(UiAction.startBreathing, breathingArgs(inhale: null)),
      );
      expect(c.breathing, isNull);
      expect(c.notice, SafetyController.noticeInvalidPattern);
    });

    test('crisis interrupts a running exercise', () {
      start();
      c.handleRisk(SimulatedSafetyEvents.high());
      expect(c.breathing, isNull);
      expect(c.crisis, isNotNull);
      expect(events, [ClientEvent.playbackStopped]);
      expect(c.notice, SafetyController.noticeSafetyCheck);
      // No exercise while the crisis flow is open.
      start();
      expect(c.breathing, isNull);
    });

    test('a finished exercise is closed by crisis without an event', () {
      start();
      c.completeBreathing();
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      expect(events, [ClientEvent.playbackDone]);
    });

    test('repeated handoffs never open a second crisis screen', () {
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      expect(c.crisisCount, 1);
      expect(c.crisis!.content, isNull);
      // The turn's risk result arrives after the handoff: fills it in.
      c.handleRisk(SimulatedSafetyEvents.high());
      expect(c.crisis!.content, isNotNull);
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      c.handleRisk(SimulatedSafetyEvents.critical());
      expect(c.crisisCount, 1);
      expect(c.crisis!.category, RiskCategory.high);
    });

    test('non-crisis handoff, LOW and unavailable results change nothing', () {
      c.handleHandoff(const Handoff(to: 'other', reason: 'r'));
      c.handleRisk(RiskResult.fromJson({'risk_category': 'LOW'}));
      c.handleRisk(RiskResult.fromJson({'status': 'unavailable'}));
      expect(c.crisis, isNull);
    });

    test('choosing a path closes it and waits for crisis_resolved', () {
      c.handleRisk(SimulatedSafetyEvents.high());
      c.chooseCrisisPath(CrisisPath.saidButDidNot);
      expect(c.crisis, isNull);
      expect(paths, [CrisisPath.saidButDidNot]);
      expect(paths.single.wire, 'said_but_did_not');
      // In-flight turns still carry handoff: crisis until it is sent.
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      expect(c.crisis, isNull);
      c.crisisResolutionSent();
      c.handleHandoff(const Handoff(to: 'crisis', reason: 'r'));
      expect(c.crisis, isNotNull);
    });

    test('wire names match the contract', () {
      expect(CrisisPath.values.map((p) => p.wire), [
        'reached_out',
        'said_but_did_not',
        'misunderstanding',
      ]);
      expect(ClientEvent.values.map((e) => e.wire), [
        'none',
        'playback_done',
        'playback_stopped',
        'start_breathing',
        'start_grounding',
        'start_plan',
      ]);
      expect(crisisResolvedPolicyEvent, 'crisis_resolved');
    });
  });
}
