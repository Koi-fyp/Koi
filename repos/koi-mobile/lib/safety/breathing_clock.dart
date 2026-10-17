import 'safety_contract.dart';

enum BreathingPhase { inhale, exhale }

/// Where a breathing run is at a given elapsed time. Port of Web's
/// `getBreathingFrame` (feat/avatar-webview-host
/// lib/conversation/exerciseContract.ts).
class BreathingFrame {
  const BreathingFrame({
    required this.phase,
    required this.cycle,
    required this.phaseProgress,
    required this.overallProgress,
    required this.complete,
  });

  final BreathingPhase phase;

  /// 1-based.
  final int cycle;

  /// 0.0–1.0 within the current inhale or exhale.
  final double phaseProgress;

  /// 0.0–1.0 over the whole run.
  final double overallProgress;
  final bool complete;

  /// Orb scale, as in Web's PacedBreathingPanel: 0.82 → 1.0 while breathing
  /// in, 1.0 → 0.82 while breathing out.
  double get orbScale => phase == BreathingPhase.inhale
      ? 0.82 + phaseProgress * 0.18
      : 1 - phaseProgress * 0.18;

  static BreathingFrame at(BreathingPattern pattern, double elapsedSeconds) {
    final elapsed = elapsedSeconds.isFinite && elapsedSeconds > 0
        ? elapsedSeconds
        : 0.0;
    final cycleSeconds = pattern.cycleSeconds;
    final total = pattern.totalSeconds;
    final overall = (elapsed / total).clamp(0.0, 1.0);
    if (elapsed >= total) {
      return BreathingFrame(
        phase: BreathingPhase.exhale,
        cycle: pattern.cycles,
        phaseProgress: 1,
        overallProgress: 1,
        complete: true,
      );
    }
    final offset = elapsed % cycleSeconds;
    final cycle = (elapsed / cycleSeconds).floor() + 1;
    if (offset < pattern.inhaleS) {
      return BreathingFrame(
        phase: BreathingPhase.inhale,
        cycle: cycle,
        phaseProgress: offset / pattern.inhaleS,
        overallProgress: overall,
        complete: false,
      );
    }
    return BreathingFrame(
      phase: BreathingPhase.exhale,
      cycle: cycle,
      phaseProgress: (offset - pattern.inhaleS) / pattern.exhaleS,
      overallProgress: overall,
      complete: false,
    );
  }
}

/// Pause/resume clock that never accumulates frame deltas. Port of Web's
/// `BreathingClock`; time is passed in so tests are deterministic.
class BreathingClock {
  Duration _elapsed = Duration.zero;
  Duration _startedAt = Duration.zero;
  bool _running = false;

  bool get isRunning => _running;

  void start(Duration now) {
    _elapsed = Duration.zero;
    _startedAt = now;
    _running = true;
  }

  void pause(Duration now) {
    if (_running) _elapsed += _since(now);
    _running = false;
  }

  void resume(Duration now) {
    if (_running) return;
    _startedAt = now;
    _running = true;
  }

  double elapsedSecondsAt(Duration now) {
    final total = _elapsed + (_running ? _since(now) : Duration.zero);
    return total.inMicroseconds / Duration.microsecondsPerSecond;
  }

  Duration _since(Duration now) =>
      now > _startedAt ? now - _startedAt : Duration.zero;
}
