import { parseMouthCues, RHUBARB_TO_VRM, type MouthCue } from './mouthCues';
import type { SynthesizedSpeech } from './voiceContract';
import { classifyChunk, MAX_CHUNK_CHARS } from './chunkReply';
export const SPEECH_VOICE_IDS = ['raza_ur', 'aisha_ur', 'raza_en', 'aisha_en'] as const;
export type SpeechVoiceId = typeof SPEECH_VOICE_IDS[number];
export type SpeechApiLanguage = 'ur' | 'en';
export const SPEECH_SERVER_ERROR_CODES = ['invalid-request', 'unauthenticated', 'text-too-long', 'audio-too-long', 'voice-not-allowed', 'language-mismatch', 'rate-limited', 'speech-unavailable'] as const;
export type SpeechServerErrorCode = typeof SPEECH_SERVER_ERROR_CODES[number];
export type SpeechClientErrorCode = SpeechServerErrorCode | 'network' | 'aborted' | 'invalid-response';
/** Carries a code and HTTP status only: never request text, audio or the token. */
export class SpeechClientError extends Error {
  constructor(readonly code: SpeechClientErrorCode, readonly status?: number) { super(`Speech request failed (${code}).`); this.name = 'SpeechClientError'; }
}
export interface SpeechApiRequest { text: string; voice_id: SpeechVoiceId; language: SpeechApiLanguage; generation_id: string; }
/** The new /api/v1/speech response adapted into the existing playback-facing SynthesizedSpeech shape. */
export interface AdaptedSpeech extends SynthesizedSpeech { generationId: string; voiceId: SpeechVoiceId; sampleRate: number; }
export type SpeakResult = { ok: true; speech: AdaptedSpeech } | { ok: false; error: SpeechClientError };
export interface SpeechClient { speak(request: SpeechApiRequest, options?: { signal?: AbortSignal }): Promise<SpeakResult>; }
export interface SpeechClientOptions { baseUrl: string; getToken: () => Promise<string>; fetchImpl?: typeof fetch; }
// Audio cap matches SpeechPlayback's owned-blob limit, so anything accepted here can actually be loaded.
const MAX_AUDIO_BYTES = 2 * 1024 * 1024, MAX_BODY_CHARS = 4 * 1024 * 1024, MAX_DURATION_S = 30, MAX_CUES = 4000, TOLERANCE_S = 0.05;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;
export function isSpeechVoiceId(value: unknown): value is SpeechVoiceId { return SPEECH_VOICE_IDS.includes(value as SpeechVoiceId); }
export function languageForVoice(voiceId: SpeechVoiceId): SpeechApiLanguage { return voiceId.endsWith('_ur') ? 'ur' : 'en'; }
const failure = (code: SpeechClientErrorCode, status?: number): SpeakResult => ({ ok: false, error: new SpeechClientError(code, status) });
/** Mirrors the server rules locally so a request that would 422 is never sent. */
function validRequest(request: SpeechApiRequest): boolean {
  if (!request || typeof request.text !== 'string' || !isSpeechVoiceId(request.voice_id) || request.language !== languageForVoice(request.voice_id)
    || typeof request.generation_id !== 'string' || !UUID.test(request.generation_id)) return false;
  if (!request.text.trim() || request.text.length > MAX_CHUNK_CHARS) return false;
  return classifyChunk(request.text) === (request.language === 'ur' ? 'ur-script' : 'latin');
}
function endpointFor(baseUrl: string): string {
  const url = new URL(baseUrl);
  const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && local)) || url.username || url.password || url.search || url.hash) throw new Error('Speech base URL must be a plain https origin.');
  return `${url.origin}${url.pathname.replace(/\/+$/, '')}/api/v1/speech`;
}
function decodeBase64(value: unknown): Uint8Array | null {
  if (typeof value !== 'string' || !value || value.length % 4 || value.length > Math.ceil(MAX_AUDIO_BYTES / 3) * 4 || !BASE64.test(value)) return null;
  try { return Uint8Array.from(atob(value), char => char.charCodeAt(0)); } catch { return null; }
}
/** RIFF/WAVE, PCM s16 mono at the declared rate; returns the duration implied by the data chunk. */
export function wavDurationSeconds(bytes: Uint8Array, sampleRate: number): number | null {
  if (bytes.length < 44) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (at: number) => String.fromCharCode(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
  if (tag(0) !== 'RIFF' || tag(8) !== 'WAVE') return null;
  let offset = 12, fmt: { format: number; channels: number; rate: number; blockAlign: number; bits: number } | undefined;
  while (offset + 8 <= bytes.length) {
    const id = tag(offset), size = view.getUint32(offset + 4, true), body = offset + 8;
    if (body + size > bytes.length) return null;
    if (id === 'fmt ') {
      if (size < 16) return null;
      fmt = { format: view.getUint16(body, true), channels: view.getUint16(body + 2, true), rate: view.getUint32(body + 4, true), blockAlign: view.getUint16(body + 12, true), bits: view.getUint16(body + 14, true) };
    } else if (id === 'data') {
      if (!fmt || fmt.format !== 1 || fmt.channels !== 1 || fmt.bits !== 16 || fmt.blockAlign !== 2 || fmt.rate !== sampleRate || !size || size % 2) return null;
      return size / (fmt.rate * fmt.blockAlign);
    }
    offset = body + size + (size & 1);
  }
  return null;
}
function strictCues(input: unknown, duration: number): readonly MouthCue[] | null {
  // parseMouthCues maps unknown shapes to X; the new contract rejects them instead.
  if (!Array.isArray(input) || !input.length || input.length > MAX_CUES
    || input.some(cue => !cue || typeof cue !== 'object' || typeof cue.value !== 'string' || !Object.hasOwn(RHUBARB_TO_VRM, cue.value))) return null;
  let cues: readonly MouthCue[];
  try { cues = parseMouthCues(input); } catch { return null; }
  return cues[cues.length - 1].end <= duration + TOLERANCE_S ? cues : null;
}
/** Adapter: new response field names and voice ids -> the existing SynthesizedSpeech playback types. */
export function adaptSpeechResponse(input: unknown, request: SpeechApiRequest): AdaptedSpeech | null {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const data = input as Record<string, unknown>;
  // Inline bytes only: remote/expiring audio URLs would bypass the same-origin playback rule.
  if ('audio_url' in data) return null;
  if (data.generation_id !== request.generation_id || data.voice_id !== request.voice_id || data.audio_format !== 'wav') return null;
  const { sample_rate: rate, duration_s: duration, timings_ms: timings } = data;
  if (typeof rate !== 'number' || !Number.isInteger(rate) || rate < 8000 || rate > 48000) return null;
  if (typeof duration !== 'number' || !Number.isFinite(duration) || duration <= 0 || duration > MAX_DURATION_S) return null;
  if (!timings || typeof timings !== 'object' || Array.isArray(timings)
    || Object.values(timings).some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) return null;
  const bytes = decodeBase64(data.audio_b64);
  if (!bytes || bytes.length > MAX_AUDIO_BYTES) return null;
  const wavDuration = wavDurationSeconds(bytes, rate);
  if (wavDuration === null || Math.abs(wavDuration - duration) > TOLERANCE_S) return null;
  const cues = strictCues(data.mouth_cues, duration);
  if (!cues) return null;
  const ms = timings as Record<string, number>;
  return { audio: new Blob([bytes as BlobPart], { type: 'audio/wav' }), cues, duration, synthesisMs: ms.synthesis ?? 0, extractionMs: ms.cue_extraction ?? 0,
    generationId: request.generation_id, voiceId: request.voice_id, sampleRate: rate };
}
function codeForStatus(status: number): SpeechClientErrorCode {
  if (status === 401 || status === 403) return 'unauthenticated';
  if (status === 413) return 'text-too-long';
  if (status === 429) return 'rate-limited';
  return status >= 500 ? 'speech-unavailable' : 'invalid-request';
}
function serverCode(body: unknown): SpeechServerErrorCode | null {
  const code = (body as { error?: { code?: unknown } } | null)?.error?.code;
  return SPEECH_SERVER_ERROR_CODES.includes(code as SpeechServerErrorCode) ? code as SpeechServerErrorCode : null;
}
/** Unwired client for POST {base}/api/v1/speech. Never logs; one retry on a network error only. */
export function createSpeechClient({ baseUrl, getToken, fetchImpl }: SpeechClientOptions): SpeechClient {
  const endpoint = endpointFor(baseUrl);
  const send: typeof fetch = fetchImpl ?? ((input, init) => globalThis.fetch(input, init));
  return {
    async speak(request, { signal } = {}) {
      if (!validRequest(request)) return failure('invalid-request');
      if (signal?.aborted) return failure('aborted');
      let token: string;
      try { token = await getToken(); } catch { return failure('unauthenticated'); }
      if (typeof token !== 'string' || !token) return failure('unauthenticated');
      if (signal?.aborted) return failure('aborted');
      const init: RequestInit = {
        method: 'POST', signal, credentials: 'omit', cache: 'no-store', redirect: 'error',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ text: request.text, voice_id: request.voice_id, language: request.language, generation_id: request.generation_id }),
      };
      let response: Response | undefined;
      for (let attempt = 0; !response; attempt++) {
        try { response = await send(endpoint, init); }
        catch { if (signal?.aborted) return failure('aborted'); if (attempt >= 1) return failure('network'); }
      }
      const { status, ok } = response;
      let body: unknown;
      try { const raw = await response.text(); if (raw.length > MAX_BODY_CHARS) throw new Error('too large'); body = JSON.parse(raw); }
      catch { return signal?.aborted ? failure('aborted') : failure(ok ? 'invalid-response' : codeForStatus(status), status); }
      if (!ok) return failure(serverCode(body) ?? codeForStatus(status), status);
      if (status !== 200) return failure('invalid-response', status);
      const speech = adaptSpeechResponse(body, request);
      return speech ? { ok: true, speech } : failure('invalid-response', status);
    },
  };
}
