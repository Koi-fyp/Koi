import { parseMouthCues, type MouthCue } from './mouthCues';
export type SpeechCompanion = 'aisha' | 'raza';
export type SpeechLanguage = 'ur' | 'en';
// PROPOSED table from voice-lab KOI_AHMAD_TO_WEB_HANDOFF.md. Fixed; never extended from a response.
export const VOICE_ALLOWLIST: Readonly<Record<SpeechCompanion, Readonly<Record<SpeechLanguage, string>>>> = Object.freeze({
  aisha: Object.freeze({ ur: 'ur_PK-aegis_female-medium', en: 'en_US-hfc_female-medium' }),
  raza: Object.freeze({ ur: 'ur_PK-fasih-medium', en: 'en_US-hfc_male-medium' }),
});
export type SpeechGuardCode = 'voice-not-allowed' | 'voice-mismatch' | 'stale' | 'invalid';
export class SpeechGuardError extends Error { constructor(readonly code: SpeechGuardCode, message: string) { super(message); this.name = 'SpeechGuardError'; } }
export function isSpeechCompanion(value: unknown): value is SpeechCompanion { return value === 'aisha' || value === 'raza'; }
/** Only aisha/raza with ur/en have a voice; anything else (koi, fox, missing) gets none. */
export function voiceFor(companion: unknown, language: unknown): string {
  if (!isSpeechCompanion(companion) || (language !== 'ur' && language !== 'en')) throw new SpeechGuardError('voice-not-allowed', 'No voice is available for this companion.');
  return VOICE_ALLOWLIST[companion][language];
}
export function companionForVoice(voiceId: unknown): SpeechCompanion | null {
  for (const companion of ['aisha', 'raza'] as const) if (Object.values(VOICE_ALLOWLIST[companion]).includes(voiceId as string)) return companion;
  return null;
}
export interface SpeechExpectation { companion: SpeechCompanion; language: SpeechLanguage; generationId: string; }
export interface GuardedSpeech { audio: Blob; cues: readonly MouthCue[]; duration: number; voiceId: string; generationId: string; }
const MAX_AUDIO_B64 = 4 * 1024 * 1024, MAX_DURATION = 30;
/** PROPOSED v1 response guard: echoed generation and the companion's own voice, inline audio only. */
export async function parseGuardedSpeech(input: unknown, expected: SpeechExpectation): Promise<GuardedSpeech> {
  const voiceId = voiceFor(expected.companion, expected.language);
  if (!input || typeof input !== 'object') throw new SpeechGuardError('invalid', 'Missing speech response.');
  const data = input as Record<string, unknown>;
  if (data.generation_id !== expected.generationId) throw new SpeechGuardError('stale', 'Speech response is for an earlier reply.');
  // A response in the other companion's voice (or any unlisted voice) must never reach the speaker.
  if (data.voice_id !== voiceId) throw new SpeechGuardError('voice-mismatch', 'Speech response used a different voice.');
  // No URL variant: expiring/remote audio URLs are not accepted, only inline bytes.
  if ('audio_url' in data || 'audio_url_expires_s' in data) throw new SpeechGuardError('invalid', 'Remote speech audio is not accepted.');
  if (data.audio_format !== 'wav_pcm_s16le_mono' || typeof data.audio_b64 !== 'string' || !data.audio_b64 || data.audio_b64.length > MAX_AUDIO_B64
    || typeof data.audio_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(data.audio_sha256)
    || typeof data.duration_s !== 'number' || !Number.isFinite(data.duration_s) || data.duration_s <= 0 || data.duration_s > MAX_DURATION) throw new SpeechGuardError('invalid', 'Invalid speech response.');
  const decode = (b64: string) => { try { return Uint8Array.from(atob(b64), char => char.charCodeAt(0)); } catch { throw new SpeechGuardError('invalid', 'Invalid speech audio.'); } };
  const bytes = decode(data.audio_b64);
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), value => value.toString(16).padStart(2, '0')).join('');
  if (hash !== data.audio_sha256) throw new SpeechGuardError('invalid', 'Speech audio integrity check failed.');
  let cues: readonly MouthCue[];
  try { cues = parseMouthCues(data.mouth_cues); } catch { throw new SpeechGuardError('invalid', 'Invalid speech cues.'); }
  if (!cues.length || cues.some(cue => cue.end > (data.duration_s as number) + 0.05)) throw new SpeechGuardError('invalid', 'Speech cue duration mismatch.');
  return { audio: new Blob([bytes], { type: 'audio/wav' }), cues, duration: data.duration_s, voiceId, generationId: expected.generationId };
}
