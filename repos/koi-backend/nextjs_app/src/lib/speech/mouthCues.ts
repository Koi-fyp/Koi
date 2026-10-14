export const MOUTH_PRESETS = ['aa', 'ih', 'ou', 'ee', 'oh'] as const;
export type MouthPreset = typeof MOUTH_PRESETS[number];
export type RhubarbShape = 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'X';
export interface MouthCue { readonly start: number; readonly end: number; readonly value: RhubarbShape; }
// Approximations: VRM vowels cannot represent consonant pressure, teeth or tongue position.
export const RHUBARB_TO_VRM: Record<RhubarbShape, MouthPreset | null> = {
  A: null, B: 'ih', C: 'ee', D: 'aa', E: 'oh', F: 'ou', G: 'ih', H: 'ee', X: null,
};
export function parseMouthCues(input: unknown): readonly MouthCue[] {
  if (!Array.isArray(input)) throw new Error('Mouth cues must be an array.');
  let previousEnd = 0;
  return Object.freeze(input.map((item: unknown) => {
    if (!item || typeof item !== 'object') throw new Error('Invalid mouth cue.');
    const { start, end, value } = item as Record<string, unknown>;
    if (typeof start !== 'number' || typeof end !== 'number' || !Number.isFinite(start) || !Number.isFinite(end) || start < previousEnd || end <= start) throw new Error('Mouth cues must be finite, ordered and non-overlapping.');
    previousEnd = end;
    return Object.freeze({ start, end, value: typeof value === 'string' && Object.hasOwn(RHUBARB_TO_VRM, value) ? value as RhubarbShape : 'X' });
  }));
}
export interface SpeechFrame { readonly active: boolean; readonly time: number; readonly cues: readonly MouthCue[]; }
export interface SpeechTimeline { getFrame(): SpeechFrame; }
export function cueAt(cues: readonly MouthCue[], time: number): MouthCue | undefined {
  if (!Number.isFinite(time) || time < 0) return;
  let low = 0, high = cues.length - 1;
  while (low <= high) { const mid = (low + high) >>> 1, cue = cues[mid];
    if (time < cue.start) high = mid - 1; else if (time >= cue.end) low = mid + 1; else return cue;
  }
}
export function mouthAt(frame: SpeechFrame): { preset: MouthPreset | null; weight: number; cue: RhubarbShape | null } {
  const cue = frame.active ? cueAt(frame.cues, frame.time) : undefined;
  const preset = cue ? RHUBARB_TO_VRM[cue.value] : null;
  // Media-time envelope, not accumulated animation time: identical position => identical weights.
  const ramp = cue ? Math.min(0.04, (cue.end - cue.start) / 2) : 0;
  const t = cue && preset ? Math.max(0, Math.min(1, (frame.time - cue.start) / ramp, (cue.end - frame.time) / ramp)) : 0;
  return { preset, weight: 0.7 * t * t * (3 - 2 * t), cue: cue?.value ?? null };
}
