import type { ChunkClass } from './chunkReply';
import type { SpeechVoiceId } from './speechClient';
export type SpeechCompanionId = 'aisha' | 'raza' | 'fox';
/** Fixed table: aisha/raza get the voice matching the chunk's script; fox, unknown or unspeakable chunks stay silent. */
export function chooseVoice(companion: unknown, chunkClass: ChunkClass): SpeechVoiceId | null {
  if (companion !== 'aisha' && companion !== 'raza') return null;
  if (chunkClass === 'ur-script') return companion === 'aisha' ? 'aisha_ur' : 'raza_ur';
  if (chunkClass === 'latin') return companion === 'aisha' ? 'aisha_en' : 'raza_en';
  return null;
}
