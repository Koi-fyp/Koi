import { parseMouthCues, type MouthCue } from './mouthCues';
export interface SpeechSample {
  kind: 'manual' | 'rhubarb'; transcript: string; language: 'en' | 'ur' | 'ur-en';
  durationSeconds: number; sha256: string; mouthCues: readonly MouthCue[];
  voice?: string; synthesisSeconds?: number; cueExtractionSeconds?: number;
}
/** Validates local sample metadata; production speech transport is deliberately separate. */
export function parseSpeechSample(input: unknown): SpeechSample {
  if (!input || typeof input !== 'object') throw new Error('Invalid speech sample.');
  const data = input as Record<string, unknown>;
  const legacyManual = data.kind === undefined && typeof data.cueSource === 'string' && data.cueSource.startsWith('Manually authored');
  if (data.kind !== 'rhubarb' && data.kind !== 'manual' && !legacyManual) throw new Error('Missing cue provenance.');
  if (typeof data.transcript !== 'string' || !data.transcript.trim() || typeof data.durationSeconds !== 'number' || !Number.isFinite(data.durationSeconds) || data.durationSeconds <= 0 || typeof data.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(data.sha256)) throw new Error('Invalid audio metadata.');
  const cues = parseMouthCues(data.mouthCues);
  if (!cues.length || cues.some(cue => cue.end > (data.durationSeconds as number) + 0.05)) throw new Error('Cue/audio duration mismatch.');
  const language = data.language ?? (legacyManual ? 'en' : undefined);
  if (!['en', 'ur', 'ur-en'].includes(language as string)) throw new Error('Invalid sample language.');
  const kind = legacyManual ? 'manual' : data.kind as SpeechSample['kind'];
  if (kind === 'rhubarb' && (data.voice !== 'ur_PK-fasih-medium' || !['phonetic', 'pocketSphinx'].includes(data.recognizer as string))) throw new Error('Invalid automatic-cue provenance.');
  const timings: Pick<SpeechSample, 'synthesisSeconds' | 'cueExtractionSeconds'> = {};
  for (const key of ['synthesisSeconds', 'cueExtractionSeconds'] as const) {
    if (data[key] !== undefined) { if (typeof data[key] !== 'number' || !Number.isFinite(data[key]) || (data[key] as number) < 0) throw new Error('Invalid processing time.'); timings[key] = data[key] as number; }
  }
  return { kind, transcript: data.transcript, language: language as SpeechSample['language'], durationSeconds: data.durationSeconds, sha256: data.sha256, mouthCues: cues, voice: typeof data.voice === 'string' ? data.voice : undefined, ...timings };
}
