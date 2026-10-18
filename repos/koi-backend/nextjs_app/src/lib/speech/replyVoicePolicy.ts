import { useCallback, useEffect, useState } from 'react';
import { classifyChunk, type ReplyLanguageHint } from './chunkReply';
import type { SpeechCompanionId } from './voiceChoice';
/**
 * Roman Urdu is Latin script, so classifyChunk cannot tell it from English. Heuristic: a Latin-only reply
 * with 2+ of these common Roman Urdu words is treated as Roman Urdu and stays text-only. One hit is ignored
 * because several ("main", "par", "ho", "se") are also English or name fragments.
 */
export const ROMAN_URDU_WORDS: ReadonlySet<string> = new Set(['hai', 'nahi', 'main', 'mein', 'aap', 'tum', 'kya', 'ko', 'ke', 'ka', 'ki',
  'ho', 'hoon', 'mujhe', 'kaam', 'yaar', 'aur', 'se', 'ne', 'par']);
export type ReplyVoicePlan = { speak: true; languageHint: Extract<ReplyLanguageHint, 'en' | 'ur-script'> } | { speak: false; reason: 'empty' | 'mixed' | 'roman-ur' };
/** Whole-reply decision: mixed script and Roman Urdu are never sent, even if single chunks would be speakable. */
export function planReplyVoice(text: string): ReplyVoicePlan {
  const kind = classifyChunk(typeof text === 'string' ? text : '');
  if (kind === 'empty' || kind === 'mixed') return { speak: false, reason: kind };
  if (kind === 'ur-script') return { speak: true, languageHint: 'ur-script' };
  const hits = (text.toLowerCase().match(/[a-z]+/g) ?? []).filter(word => ROMAN_URDU_WORDS.has(word)).length;
  return hits >= 2 ? { speak: false, reason: 'roman-ur' } : { speak: true, languageHint: 'en' };
}
/** Empty means voice is not configured. Read as a literal so Next inlines it at build time. */
export function speechBaseUrl(): string { return (process.env.NEXT_PUBLIC_KOI_SPEECH_BASE ?? '').trim(); }
/** The saved companion's id -> the speech table's id; the Koi fox has no voice. */
export function voiceCompanion(companion: 'aisha' | 'raza' | 'koi' | null | undefined): SpeechCompanionId | null {
  return companion === 'aisha' || companion === 'raza' ? companion : companion === 'koi' ? 'fox' : null;
}
export const hasVoice = (companion: SpeechCompanionId | null | undefined) => companion === 'aisha' || companion === 'raza';
export const voiceStorageKey = (uid: string) => `koi_voice_enabled_${uid}`;
/** Stores a boolean only; storage failures read as off. */
export function readVoiceEnabled(uid: string): boolean {
  try { return globalThis.localStorage?.getItem(voiceStorageKey(uid)) === 'true'; } catch { return false; }
}
export function writeVoiceEnabled(uid: string, enabled: boolean) {
  try { globalThis.localStorage?.setItem(voiceStorageKey(uid), enabled ? 'true' : 'false'); } catch { /* Off is the safe default. */ }
}
/** Per-UID "Spoken replies" preference, off by default and never carried over to another uid. */
export function useVoiceEnabled(uid: string | null | undefined): [boolean, (enabled: boolean) => void] {
  const [stored, setStored] = useState<{ uid: string | null; enabled: boolean }>({ uid: null, enabled: false });
  useEffect(() => { setStored({ uid: uid ?? null, enabled: uid ? readVoiceEnabled(uid) : false }); }, [uid]);
  const set = useCallback((enabled: boolean) => { if (!uid) return; writeVoiceEnabled(uid, enabled); setStored({ uid, enabled }); }, [uid]);
  return [!!uid && stored.uid === uid && stored.enabled, set];
}
