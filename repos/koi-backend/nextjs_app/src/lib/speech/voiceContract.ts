export type VoiceErrorCode = 'forbidden' | 'size-limit' | 'busy' | 'invalid-input' | 'processing-failed' | 'unavailable' | 'timeout';
export interface VoiceFailure { error: { code: VoiceErrorCode; message: string }; }
export class VoiceServiceError extends Error { constructor(readonly code: VoiceErrorCode, message: string, readonly status?: number) { super(message); this.name = 'VoiceServiceError'; } }
import { parseMouthCues, type MouthCue } from './mouthCues';
export interface TranscriptionResult { text: string; language: { code: string | null; source: 'requested' | 'detected' }; processing_ms: number; model: { name: string; revision: string; runtime: string; version: string; compute_type: string }; input: { container: string; codec: string; duration_seconds: number; normalized_sample_rate: number; channels: number; level_rms: number; peak: number }; }
export interface SynthesizedSpeech { audio: Blob; cues: readonly MouthCue[]; duration: number; synthesisMs: number; extractionMs: number; }
export function parseTranscription(input: unknown): TranscriptionResult {
 const data = input as TranscriptionResult;
 if (!data || typeof data.text !== 'string' || data.text.length > 10000 || !Number.isFinite(data.processing_ms) || data.processing_ms < 0 || !data.model || !['whisper-tiny', 'whisper-base'].includes(data.model.name) || !data.language || !['requested','detected'].includes(data.language.source) || !(data.language.code === null || typeof data.language.code === 'string') || !data.input || data.input.normalized_sample_rate !== 16000 || data.input.channels !== 1 || !Number.isFinite(data.input.duration_seconds) || data.input.duration_seconds <= 0 || data.input.duration_seconds > 30 || !Number.isFinite(data.input.level_rms) || data.input.level_rms < 0 || data.input.level_rms > 32 || !Number.isFinite(data.input.peak) || data.input.peak < 0 || data.input.peak > 32) throw new Error('Invalid transcription response.');
 return data;
}
export async function parseSynthesizedSpeech(input: unknown): Promise<SynthesizedSpeech> {
 const data = input as Record<string, unknown>;
 if (!data || data.content_type !== 'audio/wav' || data.voice !== 'ur_PK-fasih-medium' || data.language !== 'ur' || typeof data.audio_base64 !== 'string' || data.audio_base64.length > 4 * 1024 * 1024 || typeof data.audio_sha256 !== 'string' || !Number.isFinite(data.duration_seconds) || (data.duration_seconds as number) <= 0 || (data.duration_seconds as number) > 30) throw new Error('Invalid speech response.');
 const bytes = Uint8Array.from(atob(data.audio_base64), char => char.charCodeAt(0));
 const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), value => value.toString(16).padStart(2,'0')).join('');
 if (hash !== data.audio_sha256) throw new Error('Speech audio integrity check failed.');
 const cues = parseMouthCues(data.mouth_cues); if (!cues.length || cues.some(cue => cue.end > (data.duration_seconds as number) + .05)) throw new Error('Speech cue duration mismatch.');
 const timings = data.timings_ms as { synthesis: number; cue_extraction: number };
 if (!timings || !Number.isFinite(timings.synthesis) || !Number.isFinite(timings.cue_extraction)) throw new Error('Invalid speech timing.');
 return { audio: new Blob([bytes], { type:'audio/wav' }), cues, duration: data.duration_seconds as number, synthesisMs: timings.synthesis, extractionMs: timings.cue_extraction };
}
