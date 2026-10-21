import 'server-only';
import { checkDraftContent } from '../server/contract';
import { invalid } from '../server/errors';
import type { ManualContent } from '../types';
import { RouteError } from './route-kit';

export const AI_NOTICE = 'AI draft, not validated; the psychologist must review every question';
export const AI_TIMEOUT_MS = 60_000;
const FIELDS = ['topic', 'audience', 'language', 'count', 'purpose', 'tone', 'question_types'];
const LANGUAGES = ['en', 'ur', 'roman_ur'];
const TYPES = ['single_choice', 'multi_choice', 'yes_no', 'likert', 'short_text', 'image_single_choice', 'image_multi_choice'];

export interface AiDraftRequest { topic: string; audience: string; language: 'en' | 'ur' | 'roman_ur'; count: number; purpose?: string; tone?: string; question_types?: string[] }
export interface AiProvenance { provider: string; model_id: string; prompt_version: string; sources: string[] }

const text = (value: unknown, required: boolean): string | undefined => {
  if (value === undefined && !required) return undefined;
  if (typeof value !== 'string') throw invalid();
  const trimmed = value.trim();
  if (!trimmed.length || trimmed.length > 200) throw invalid();
  return trimmed;
};
/** Strict validation: unknown fields, wrong types, empty or over-long strings, bad count and language all fail. */
export function parseRequest(body: unknown): AiDraftRequest {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw invalid();
  const input = body as Record<string, unknown>;
  if (Object.keys(input).some(key => !FIELDS.includes(key))) throw invalid();
  if (typeof input.language !== 'string' || !LANGUAGES.includes(input.language)) throw invalid();
  if (!Number.isInteger(input.count) || (input.count as number) < 1 || (input.count as number) > 20) throw invalid();
  const out: AiDraftRequest = { topic: text(input.topic, true)!, audience: text(input.audience, true)!, language: input.language as AiDraftRequest['language'], count: input.count as number };
  const purpose = text(input.purpose, false), tone = text(input.tone, false);
  if (purpose !== undefined) out.purpose = purpose;
  if (tone !== undefined) out.tone = tone;
  if (input.question_types !== undefined) {
    const types = input.question_types;
    if (!Array.isArray(types) || !types.length || types.length > TYPES.length || types.some(t => typeof t !== 'string' || !TYPES.includes(t)) || new Set(types).size !== types.length) throw invalid();
    out.question_types = types as string[];
  }
  return out;
}

/** Server-side base URL; unset or malformed means the feature is simply not configured. */
export function aiBase(): string {
  const raw = process.env.KOI_AI_BASE?.trim();
  if (!raw) throw new RouteError(503, 'ai_unavailable');
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') throw new Error('scheme');
    return raw.replace(/\/+$/, '');
  } catch { throw new RouteError(503, 'ai_unavailable'); }
}

const safeCode = (data: any): string => {
  const candidate = data?.code ?? data?.error?.code ?? data?.detail?.code;
  return typeof candidate === 'string' && /^[a-z0-9_]{1,64}$/.test(candidate) ? candidate : 'invalid_request';
};
const sourceLabel = (item: any): string | null => {
  const value = typeof item === 'string' ? item : item && typeof item === 'object' ? [item.title, item.name, item.id, item.url].find(v => typeof v === 'string') : null;
  return typeof value === 'string' && value.trim() ? value.trim().slice(0, 300) : null;
};
const label = (value: unknown): string => {
  if (typeof value !== 'string' || !value.trim() || value.length > 200) throw new RouteError(502, 'ai_provider_error');
  return value.trim();
};
function provenance(raw: any): AiProvenance {
  if (!raw || typeof raw !== 'object') throw new RouteError(502, 'ai_provider_error');
  const sources = Array.isArray(raw.sources) ? raw.sources.slice(0, 20).map(sourceLabel).filter((s: string | null): s is string => !!s) : [];
  return { provider: label(raw.provider), model_id: label(raw.model_id), prompt_version: label(raw.prompt_version), sources };
}

/** Calls the AI service with the caller's own Firebase ID token. One attempt, 60 s, no retries. */
export async function generate(request: AiDraftRequest, authorization: string, fetcher: typeof fetch = fetch): Promise<{ content: ManualContent; provenance: AiProvenance }> {
  const base = aiBase();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);
  let response: Response, data: any = null;
  try {
    response = await fetcher(`${base}/api/v1/ai/questionnaires/generate`, {
      method: 'POST', cache: 'no-store', redirect: 'error', signal: controller.signal,
      headers: { Authorization: authorization, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ ...request, target: 'web_platform_0_5' }),
    });
    const textBody = await response.text();
    if (textBody.length > 1_000_000) throw new Error('too large');
    try { data = JSON.parse(textBody); } catch { data = null; }
  } catch { throw new RouteError(502, 'ai_provider_error'); }
  finally { clearTimeout(timer); }
  if (response.status === 401 || response.status === 403) throw new RouteError(403, 'forbidden');
  if (response.status === 422) throw new RouteError(422, safeCode(data));
  if (response.status === 429) throw new RouteError(429, 'rate_limited');
  if (!response.ok) throw new RouteError(502, 'ai_provider_error');
  try {
    const content = data?.web_content;
    checkDraftContent(content);
    if (content.origin !== 'ai_drafted' || content.validation_status !== 'not_validated') throw new Error('origin');
    return { content, provenance: provenance(data?.provenance) };
  } catch { throw new RouteError(502, 'ai_provider_error'); }
}
