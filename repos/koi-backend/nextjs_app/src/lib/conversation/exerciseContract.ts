export interface BreathingPattern {
  inhale_s: number;
  exhale_s: number;
  cycles: number;
  cue_audio: [string, string];
}

export interface BreathingFrame {
  phase: 'inhale' | 'exhale';
  cycle: number;
  phaseProgress: number;
  overallProgress: number;
  complete: boolean;
}

const MAX_PHASE_SECONDS = 12;
const MAX_CYCLES = 12;

/** Validates known server breathing fields and caps long patterns for a phone-sized UI. */
export function parseBreathingPattern(args: Record<string, unknown>): BreathingPattern | null {
  const inhale = args.inhale_s;
  const exhale = args.exhale_s;
  const cycles = args.cycles;
  const cues = args.cue_audio;
  if (typeof inhale !== 'number' || !Number.isFinite(inhale) || inhale <= 0
    || typeof exhale !== 'number' || !Number.isFinite(exhale) || exhale <= 0
    || typeof cycles !== 'number' || !Number.isFinite(cycles) || cycles <= 0
    || !Array.isArray(cues) || cues.length < 2
    || typeof cues[0] !== 'string' || typeof cues[1] !== 'string') return null;
  const cueIn = cues[0].trim().slice(0, 120);
  const cueOut = cues[1].trim().slice(0, 120);
  if (!cueIn || !cueOut) return null;
  return {
    inhale_s: Math.min(MAX_PHASE_SECONDS, Math.max(1, inhale)),
    exhale_s: Math.min(MAX_PHASE_SECONDS, Math.max(1, exhale)),
    cycles: Math.min(MAX_CYCLES, Math.max(1, Math.floor(cycles))),
    cue_audio: [cueIn, cueOut],
  };
}

/** Pure clock projection. Passing controlled elapsed time makes phase behavior deterministic in tests. */
export function getBreathingFrame(pattern: BreathingPattern, elapsedSeconds: number): BreathingFrame {
  const elapsed = Number.isFinite(elapsedSeconds) ? Math.max(0, elapsedSeconds) : 0;
  const cycleSeconds = pattern.inhale_s + pattern.exhale_s;
  const totalSeconds = cycleSeconds * pattern.cycles;
  const overallProgress = Math.min(1, elapsed / totalSeconds);
  if (elapsed >= totalSeconds) return { phase: 'exhale', cycle: pattern.cycles, phaseProgress: 1, overallProgress: 1, complete: true };
  const cycleOffset = elapsed % cycleSeconds;
  const cycle = Math.floor(elapsed / cycleSeconds) + 1;
  if (cycleOffset < pattern.inhale_s) {
    return { phase: 'inhale', cycle, phaseProgress: cycleOffset / pattern.inhale_s, overallProgress, complete: false };
  }
  return { phase: 'exhale', cycle, phaseProgress: (cycleOffset - pattern.inhale_s) / pattern.exhale_s, overallProgress, complete: false };
}

/** Monotonic, injectable clock for pause/resume/stop without accumulating frame deltas. */
export class BreathingClock {
  private elapsed = 0;
  private startedAt = 0;
  private running = false;

  start(nowMs: number) { this.elapsed = 0; this.startedAt = nowMs; this.running = true; }
  pause(nowMs: number) {
    if (this.running) this.elapsed += Math.max(0, (nowMs - this.startedAt) / 1000);
    this.running = false;
  }
  resume(nowMs: number) { if (!this.running) { this.startedAt = nowMs; this.running = true; } }
  stop() { this.elapsed = 0; this.startedAt = 0; this.running = false; }
  isRunning() { return this.running; }
  elapsedAt(nowMs: number) { return this.elapsed + (this.running ? Math.max(0, (nowMs - this.startedAt) / 1000) : 0); }
}
