import { ChatError, createChatRequest, parseChatResponse, parseRiskResult, type ChatRequest, type ChatResponse, type ChatServerEvent, type CompanionState, type RiskResult } from './chatContract';
import { SseParser } from './sseParser';

// The published Modal chat Function has a 600 second execution timeout. Modal
// may return several request-result 303s while that single invocation runs.
export const DEFAULT_CHAT_TIMEOUT_MS = 600_000;
export const MAX_MODAL_REDIRECTS = 20;
export function chatEndpoint(apiBase: string | undefined): string {
  if (!apiBase?.trim()) throw new ChatError('configuration', 'The self-hosted chat API is not configured.');
  let url: URL;
  try { url = new URL(apiBase); } catch { throw new ChatError('configuration', 'The self-hosted chat API URL is invalid.'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new ChatError('configuration', 'The self-hosted chat API URL is invalid.');
  const basePath = url.pathname.replace(/\/+$/, '');
  if (basePath.endsWith('/api/v1') || basePath.endsWith('/api/v1/chat')) {
    throw new ChatError('configuration', 'Set NEXT_PUBLIC_KOI_API_BASE to the API base URL, without /api/v1 or /api/v1/chat.');
  }
  return url.href.replace(/\/$/, '') + '/api/v1/chat';
}

export function chatHealthEndpoint(apiBase: string | undefined): string {
  const endpoint = new URL(chatEndpoint(apiBase));
  return new URL('/health', endpoint.origin).href;
}

/**
 * Follow only Modal's documented request-result redirect: HTTP 303 to the
 * same URL/path with a query identifying the original invocation. The POST
 * is never repeated; 303 changes the follow-up to GET. Browser fetch exposes
 * cross-origin manual redirects as opaque, in which case we fail closed.
 */
async function fetchWithModalResultRedirects(
  url: string,
  init: RequestInit,
  fetchImpl: typeof fetch,
): Promise<Response> {
  const original = new URL(url);
  let nextUrl = original;
  let method = init.method ?? 'GET';
  let body = init.body;
  const headers = new Headers(init.headers);

  for (let redirects = 0; ; redirects++) {
    const response = await fetchImpl(nextUrl.href, { ...init, method, body, headers, redirect: 'manual' });

    if (response.type === 'opaqueredirect' || response.status === 0) {
      throw new ChatError('redirect', 'Modal returned a cross-origin redirect that this browser cannot safely inspect. A CORS-compatible same-origin API path is required.');
    }

    if (response.status !== 303) {
      if (response.redirected) {
        const finalUrl = new URL(response.url || nextUrl.href);
        if (finalUrl.origin !== original.origin || finalUrl.pathname !== original.pathname) {
          throw new ChatError('redirect', 'The chat service redirected outside its trusted endpoint.');
        }
      }
      return response;
    }

    if (redirects >= MAX_MODAL_REDIRECTS) {
      throw new ChatError('redirect', 'The chat service exceeded Modal’s redirect limit. Please try again later.');
    }

    const location = response.headers.get('location');
    if (!location) throw new ChatError('redirect', 'The chat service returned an incomplete Modal redirect.');
    const target = new URL(location, nextUrl);
    if (target.protocol !== original.protocol || target.origin !== original.origin
      || target.pathname !== original.pathname || target.username || target.password || target.hash) {
      throw new ChatError('redirect', 'The chat service redirected outside its trusted endpoint.');
    }

    try { await response.body?.cancel(); } catch { /* A redirect body is not part of the response. */ }
    nextUrl = target;
    method = 'GET';
    body = undefined;
    headers.delete('Content-Type');
  }
}

/** A best-effort GET /health probe; success does not guarantee the next chat is warm. */
export async function probeChatHealth(apiBase: string | undefined, options: {
  signal?: AbortSignal; timeoutMs?: number; fetchImpl?: typeof fetch;
} = {}): Promise<boolean> {
  const url = chatHealthEndpoint(apiBase);
  const abort = new AbortController();
  let timedOut = false;
  const onAbort = () => abort.abort();
  options.signal?.throwIfAborted();
  options.signal?.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => { timedOut = true; abort.abort(); }, options.timeoutMs ?? DEFAULT_CHAT_TIMEOUT_MS);
  try {
    const response = await fetchWithModalResultRedirects(url, {
      method: 'GET', headers: { Accept: 'application/json' }, signal: abort.signal,
    }, options.fetchImpl ?? fetch);
    if (!response.ok || !(response.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) return false;
    const body: unknown = await response.json();
    return !!body && typeof body === 'object' && (body as { status?: unknown }).status === 'ok';
  } catch (error) {
    if (options.signal?.aborted) throw new DOMException('Health probe cancelled.', 'AbortError');
    if (timedOut) throw new ChatError('timeout', 'The self-hosted companion health check took too long.');
    if (error instanceof ChatError) throw error;
    throw new ChatError('network', 'Unable to check the self-hosted companion.');
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener('abort', onAbort);
  }
}
function audioFileName(type: string): string {
  return type.includes('ogg') ? 'voice.ogg' : type.includes('mp4') ? 'voice.m4a' : 'voice.webm';
}
/** Transport only. Authentication is enforced by conversationService before calling this function. */
export async function postJsonChat(request: ChatRequest, options: {
  apiBase: string | undefined; headers: Headers; signal: AbortSignal; timeoutMs?: number; fetchImpl?: typeof fetch;
  onEvent?: (event: ChatServerEvent) => void;
}): Promise<ChatResponse> {
  const url = chatEndpoint(options.apiBase);
  const abort = new AbortController(); let timedOut = false;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  const onAbort = () => { abort.abort(); void reader?.cancel().catch(() => {}); };
  options.signal.throwIfAborted(); options.signal.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => { timedOut = true; abort.abort(); }, options.timeoutMs ?? DEFAULT_CHAT_TIMEOUT_MS);
  try {
    const headers = new Headers(options.headers); headers.set('Accept', 'text/event-stream');
    const payload = JSON.stringify(createChatRequest(request.message, request.session_history, {
      exercise_state: request.exercise_state,
      client_event: request.client_event,
      policy_event: request.policy_event,
      crisis_path: request.crisis_path,
    }, { voice: !!request.audio }));
    // A voice turn is multipart: the JSON payload plus the recorded clip. The browser sets the boundary header.
    let body: BodyInit = payload;
    if (request.audio) {
      const form = new FormData();
      form.append('payload', payload);
      form.append('audio', request.audio, audioFileName(request.audio.type));
      body = form;
      headers.delete('Content-Type');
    } else headers.set('Content-Type', 'application/json');
    // Authentication is scoped to the configured API origin; the helper only
    // reuses it after validating a same-origin, same-path Modal result URL.
    const response = await fetchWithModalResultRedirects(url, { method: 'POST', headers, signal: abort.signal, body }, options.fetchImpl ?? fetch);
    abort.signal.throwIfAborted();
    if (response.status >= 300 && response.status < 400) throw new ChatError('redirect', 'The chat service returned an unsupported redirect.', response.status);
    if (!response.ok) {
      // Never surface/log an arbitrary backend body, which may contain sensitive generation output.
      throw new ChatError(response.status === 401 || response.status === 403 ? 'authentication' : 'http',
        response.status === 401 || response.status === 403 ? 'Your session needs authentication. Please sign in again.' : `The self-hosted companion is unavailable (${response.status}).`, response.status);
    }
    if (response.redirected && response.url
      && (new URL(response.url).origin !== new URL(url).origin || new URL(response.url).pathname !== new URL(url).pathname)) {
      throw new ChatError('redirect', 'The chat service redirected this request. Its safe follow-up protocol is not configured yet.');
    }
    if (!(response.headers.get('content-type') ?? '').toLowerCase().includes('text/event-stream')) throw new ChatError('invalid-response', 'The companion did not return a chat event stream.');
    if (!response.body) throw new ChatError('invalid-response', 'The companion returned no stream.');

    reader = response.body.getReader();
    const parser = new SseParser();
    let deltaText = '';
    let presentedDeltaText = '';
    let exerciseSentenceMode = request.exercise_state !== undefined && request.exercise_state !== null
      || request.client_event?.startsWith('start_') === true;
    let latency: number | undefined;
    let terminal = false;
    let finalResponse: ChatResponse | undefined;
    let generationError = false;
    let latestRisk: RiskResult | undefined;
    const parseJson = (frame: { event: string; data: string }): unknown => {
      try { return JSON.parse(frame.data); }
      catch { throw new ChatError('invalid-response', `The companion sent malformed ${frame.event} event data.`); }
    };
    const object = (value: unknown): Record<string, unknown> => {
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ChatError('invalid-response', 'The companion sent an invalid event.');
      return value as Record<string, unknown>;
    };
    const companionState = (value: unknown): CompanionState => {
      const data = object(value);
      const emotions = ['neutral', 'joy', 'angry', 'sorrow', 'fun'];
      if (typeof data.emotion !== 'string' || !emotions.includes(data.emotion)
        || typeof data.intensity !== 'number' || !Number.isFinite(data.intensity) || data.intensity < 0 || data.intensity > 1) {
        throw new ChatError('invalid-response', 'The companion sent an invalid expression state.');
      }
      return { emotion: data.emotion as CompanionState['emotion'], intensity: data.intensity };
    };
    const riskResult = (value: unknown): RiskResult => parseRiskResult(value) ?? { status: 'unavailable' };
    const sameRisk = (left: RiskResult, right: RiskResult) => JSON.stringify(left) === JSON.stringify(right);
    const parseHandoff = (value: unknown): { to: 'crisis'; reason: string } => {
      const data = object(value);
      if (data.to !== 'crisis' || typeof data.reason !== 'string') throw new ChatError('invalid-response', 'The companion sent an invalid handoff event.');
      return { to: 'crisis', reason: data.reason };
    };
    const parseActions = (value: unknown): Array<{ name: string; args: Record<string, unknown> }> => {
      if (!Array.isArray(value)) throw new ChatError('invalid-response', 'The companion sent invalid UI actions.');
      return value.map((item) => {
        const action = object(item);
        if (typeof action.name !== 'string' || !action.name || !action.args || typeof action.args !== 'object' || Array.isArray(action.args)) {
          throw new ChatError('invalid-response', 'The companion sent an invalid UI action.');
        }
        return { name: action.name, args: action.args as Record<string, unknown> };
      });
    };
    const emit = (event: ChatServerEvent) => { abort.signal.throwIfAborted(); options.onEvent?.(event); };
    const consume = (frame: { event: string; data: string }) => {
      if (terminal) throw new ChatError('invalid-response', 'The companion sent events after completing the turn.');
      if (!['latency', 'transcript', 'risk', 'companion_state', 'delta', 'ui_action', 'handoff', 'state', 'error', 'done'].includes(frame.event)) return;
      const data = object(parseJson(frame));
      switch (frame.event) {
        case 'transcript': {
          if (typeof data.text !== 'string' || !data.text.trim() || (data.language !== undefined && typeof data.language !== 'string')) throw new ChatError('invalid-response', 'The companion sent an invalid transcript event.');
          emit({ event: 'transcript', data: { text: data.text, ...(typeof data.language === 'string' ? { language: data.language } : {}) } });
          break;
        }
        case 'risk': {
          latestRisk = riskResult(data);
          emit({ event: 'risk', data: latestRisk });
          break;
        }
        case 'latency': {
          if (typeof data.latency_ms !== 'number' || !Number.isFinite(data.latency_ms) || data.latency_ms < 0) throw new ChatError('invalid-response', 'The companion sent invalid latency metadata.');
          latency = data.latency_ms;
          emit({ event: 'latency', data: { latency_ms: latency } });
          break;
        }
        case 'companion_state': emit({ event: 'companion_state', data: companionState(data) }); break;
        case 'delta': {
          if (typeof data.text !== 'string') throw new ChatError('invalid-response', 'The companion sent an invalid text delta.');
          deltaText += data.text;
          const separator = exerciseSentenceMode && presentedDeltaText && data.text
            && !/^\s/.test(data.text) && !/\s$/.test(presentedDeltaText) ? ' ' : '';
          const presentedText = separator + data.text;
          presentedDeltaText += presentedText;
          emit({ event: 'delta', data: { text: presentedText } });
          break;
        }
        case 'ui_action': {
          const [action] = parseActions([data]);
          if (['start_breathing', 'start_grounding', 'start_plan'].includes(action.name)) exerciseSentenceMode = true;
          emit({ event: 'ui_action', data: action });
          break;
        }
        case 'handoff': emit({ event: 'handoff', data: parseHandoff(data) }); break;
        case 'state': {
          if (data.exercise_state !== null && (typeof data.exercise_state !== 'string' || !data.exercise_state)) throw new ChatError('invalid-response', 'The companion sent an invalid exercise state.');
          emit({ event: 'state', data: { exercise_state: data.exercise_state as string | null } });
          break;
        }
        case 'error': {
          if ((data.code !== 'no_reply' && data.code !== 'generation_failed') || typeof data.detail !== 'string' || data.detail.length > 240) throw new ChatError('invalid-response', 'The companion returned a generation error.');
          generationError = true;
          // Backend detail is diagnostic metadata and is never displayed or retained.
          emit({ event: 'error', data: { code: data.code } });
          break;
        }
        case 'done': {
          const state = companionState(data.companion_state);
          if (typeof data.full_text !== 'string'
            || typeof data.total_generation_s !== 'number' || !Number.isFinite(data.total_generation_s) || data.total_generation_s < 0) {
            throw new ChatError('invalid-response', 'The companion sent an incomplete final event.');
          }
          if (!data.full_text.trim() && !generationError) throw new ChatError('invalid-response', 'The companion sent an empty reply without a terminal error.');
          if (data.exercise_state !== undefined && data.exercise_state !== null && typeof data.exercise_state !== 'string') throw new ChatError('invalid-response', 'The companion sent invalid final exercise state.');
          const actions = data.ui_actions === undefined ? undefined : parseActions(data.ui_actions);
          const finalHandoff = data.handoff === undefined || data.handoff === null ? data.handoff as null | undefined : parseHandoff(data.handoff);
          if (Object.prototype.hasOwnProperty.call(data, 'risk')) {
            const finalRisk = riskResult(data.risk);
            if (latestRisk && !sameRisk(latestRisk, finalRisk)) throw new ChatError('invalid-response', 'The companion returned inconsistent safety metadata.');
            if (!latestRisk) { latestRisk = finalRisk; emit({ event: 'risk', data: finalRisk }); }
          }
          // Final text replaces deltas; it is never appended, preventing duplicate content.
          const reconciledText = exerciseSentenceMode && data.full_text === deltaText ? presentedDeltaText : data.full_text;
          if (!generationError) finalResponse = parseChatResponse({ reply: reconciledText, latency_ms: latency ?? data.total_generation_s * 1000, companion_state: state });
          terminal = true;
          const doneEvent: Extract<ChatServerEvent, { event: 'done' }>['data'] = {
            full_text: data.full_text, companion_state: state,
            ui_actions: actions, handoff: finalHandoff, total_generation_s: data.total_generation_s,
          };
          if (Object.prototype.hasOwnProperty.call(data, 'exercise_state')) doneEvent.exercise_state = data.exercise_state as string | null;
          if (latestRisk) doneEvent.risk = latestRisk;
          emit({ event: 'done', data: doneEvent });
          break;
        }
        default:
          // Unknown named events remain harmless and forward-compatible.
          break;
      }
    };
    while (true) {
      const next = await reader.read(); if (next.done) break;
      abort.signal.throwIfAborted();
      parser.push(next.value).forEach(consume);
    }
    parser.finish().forEach(consume);
    abort.signal.throwIfAborted();
    if (!terminal) throw new ChatError('invalid-response', 'The companion stream ended before the turn completed.');
    if (generationError) throw new ChatError('generation', 'KOI could not complete this reply. Please try again.');
    if (!finalResponse) throw new ChatError('invalid-response', 'The companion stream ended before the turn completed.');
    return finalResponse;
  } catch (error) {
    if (options.signal.aborted) throw new DOMException('Request cancelled.', 'AbortError');
    if (timedOut) throw new ChatError('timeout', 'The companion took too long to respond. Please try again.');
    if (error instanceof ChatError) throw error;
    throw new ChatError('network', 'Unable to reach the self-hosted companion. Please try again.');
  } finally {
    clearTimeout(timer);
    options.signal.removeEventListener('abort', onAbort);
    if (reader) {
      try { await reader.cancel(); } catch { /* The stream may already have closed. */ }
      reader.releaseLock();
    }
  }
}
