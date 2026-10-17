import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../settings/widgets/settings_widgets.dart' show backArrowPaths;
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'breathing_clock.dart';
import 'safety_controller.dart';
import 'safety_debug_menu.dart';

/// Paced breathing (the contract's `start_breathing`), full screen.
///
/// Texts, orb scale (0.82–1.0) and the 1–12 bounds mirror Web's
/// PacedBreathingPanel in ExerciseDirector.tsx (origin/feat/avatar-webview-host);
/// the frame uses the KOI design system (NeoCard, NeoButton, KoiText).
///
/// Pause comes from the user or a `pause_breathing` action; resume only from
/// the user. Finishing calls [SafetyController.completeBreathing]
/// (`playback_done`); Stop or back calls [SafetyController.stopBreathing]
/// (`playback_stopped`).
// TODO(audio): cue_audio is shown as text only; no TTS/audio yet.
// TODO(flow): the post-session mood check and "save as my go-to" (UX Flow:
// Grounding/Breathing) are not built.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key, required this.controller});

  final SafetyController controller;

  // Web text.
  static const String title = 'Paced breathing';
  static const String paused = 'Paused';
  static const String complete = 'Activity complete';
  static const String audioNotice = 'On-screen cues only. No audio is played.';
  static const String pauseLabel = 'Pause';
  static const String resumeLabel = 'Resume';
  static const String stopLabel = 'Stop';
  static String cycleText(int cycle, int cycles) => 'Cycle $cycle of $cycles';

  // CompanionScene.module.css literals.
  static const Color orbInhale = Color(0xFF9CCFC5); // .breathOrb
  static const Color orbExhale = Color(0xFFB6C8DF); // [data-phase='exhale']
  static const Color progressTrack = Color(0xFFE7E1DA);
  static const Color progressFill = Color(0xFF668F83);

  static const double orbSize = 180;

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final BreathingClock _clock = BreathingClock();
  Duration _now = Duration.zero;
  double _elapsed = 0;
  int? _runId;
  bool? _paused;

  SafetyController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    _ticker.start();
    _sync();
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  /// Follows the controller: a new run restarts the clock, pause/resume
  /// freezes/continues it.
  void _sync() {
    final run = _c.breathing;
    if (run == null) return;
    if (run.id != _runId) {
      _runId = run.id;
      _paused = false;
      _clock.start(_now);
      _elapsed = 0;
    }
    if (run.paused != _paused) {
      _paused = run.paused;
      run.paused ? _clock.pause(_now) : _clock.resume(_now);
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration now) {
    _now = now;
    final run = _c.breathing;
    if (run == null || run.complete || !_clock.isRunning) return;
    final seconds = _clock.elapsedSecondsAt(now);
    final frame = BreathingFrame.at(run.pattern, seconds);
    if (frame.complete) {
      _clock.pause(now);
      _elapsed = run.pattern.totalSeconds;
      _c.completeBreathing();
    } else {
      setState(() => _elapsed = seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _c.breathing;
    return PopScope<Object?>(
      canPop: false,
      // Back = Stop while running, close once finished.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _c.dismissBreathing();
      },
      child: Scaffold(
        backgroundColor: KoiColors.background,
        body: SafeArea(
          child: run == null ? const SizedBox.shrink() : _content(run),
        ),
      ),
    );
  }

  Widget _content(BreathingRun run) {
    final pattern = run.pattern;
    final frame = BreathingFrame.at(pattern, _elapsed);
    final cue = run.complete
        ? BreathingScreen.complete
        : run.paused
        ? BreathingScreen.paused
        : frame.phase == BreathingPhase.inhale
        ? pattern.cueIn
        : pattern.cueOut;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('breathing-back'),
            tooltip: 'Back',
            onPressed: _c.dismissBreathing,
            icon: StrokeIcon(
              paths: backArrowPaths,
              size: 24,
              strokeWidth: 2.5,
              color: KoiColors.neoBlack,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 22, 22),
            child: NeoCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Debug builds: long-press for simulated pause/stop/crisis.
                  SafetyDebugTrigger(
                    child: Text(
                      BreathingScreen.title,
                      style: KoiText.display(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      cue,
                      key: const Key('breathing-cue'),
                      textAlign: TextAlign.center,
                      style: KoiText.body(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BreathingScreen.cycleText(
                      frame.cycle.clamp(1, pattern.cycles),
                      pattern.cycles,
                    ),
                    key: const Key('breathing-cycle'),
                    style: KoiText.body(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _orb(frame),
                  const SizedBox(height: 16),
                  _progress(frame.overallProgress),
                  const SizedBox(height: 12),
                  Text(
                    BreathingScreen.audioNotice,
                    textAlign: TextAlign.center,
                    style: KoiText.body(
                      fontSize: 13,
                      color: KoiColors.neoMuted,
                    ),
                  ),
                  if (!run.complete) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        run.paused
                            ? NeoButton(
                                key: const Key('breathing-resume'),
                                onPressed: _c.resumeBreathing,
                                child: const Text(BreathingScreen.resumeLabel),
                              )
                            : NeoButton(
                                key: const Key('breathing-pause'),
                                onPressed: _c.pauseBreathing,
                                child: const Text(BreathingScreen.pauseLabel),
                              ),
                        NeoButton(
                          key: const Key('breathing-stop'),
                          variant: NeoButtonVariant.secondary,
                          onPressed: _c.stopBreathing,
                          child: const Text(BreathingScreen.stopLabel),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _orb(BreathingFrame frame) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: BreathingScreen.orbSize,
      child: Center(
        child: Transform.scale(
          key: const Key('breathing-orb'),
          scale: frame.orbScale,
          child: Container(
            width: BreathingScreen.orbSize,
            height: BreathingScreen.orbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: frame.phase == BreathingPhase.inhale
                  ? BreathingScreen.orbInhale
                  : BreathingScreen.orbExhale,
              border: Border.all(width: 2.5),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _progress(double value) => Semantics(
    label: 'Activity progress',
    value: '${(value * 100).round()}%',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          key: const Key('breathing-progress'),
          value: value,
          backgroundColor: BreathingScreen.progressTrack,
          color: BreathingScreen.progressFill,
        ),
      ),
    ),
  );
}
