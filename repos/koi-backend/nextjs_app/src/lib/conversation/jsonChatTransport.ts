import { ChatError, createChatRequest, parseChatResponse, type ChatRequest, type ChatResponse, type ChatServerEvent, type CompanionState } from './chatContract';
import { SseParser } from './sseParser';

export const DEFAULT_CHAT_TIMEOUT_MS = 160_000;
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
    const headers = new Headers(options.headers); headers.set('Content-Type', 'application/json'); headers.set('Accept', 'text/event-stream');
    // Redirect/poll semantics are unverified. Do not forward the Firebase token implicitly.
    const response = await (options.fetchImpl ?? fetch)(url, { method: 'POST', headers, signal: abort.signal, redirect: 'error',
      body: JSON.stringify(createChatRequest(request.message, request.session_history, {
        exercise_state: request.exercise_state,
        client_event: request.client_event,
        policy_event: request.policy_event,
        crisis_path: request.crisis_path,
      })) });
    abort.signal.throwIfAborted();
    if (response.status >= 300 && response.status < 400) throw new ChatError('redirect', 'The chat service redirected this request. Its safe follow-up protocol is not configured yet.', response.status);
    if (!response.ok) {
      // Never surface/log an arbitrary backend body, which may contain sensitive generation output.
      throw new ChatError(response.status === 401 || response.status === 403 ? 'authentication' : 'http',
        response.status === 401 || response.status === 403 ? 'Your session needs authentication. Please sign in again.' : `The self-hosted companion is unavailable (${response.status}).`, response.status);
    }
    if (response.redirected || (response.url && new URL(response.url).origin !== new URL(url).origin)) {
      throw new ChatError('redirect', 'The chat service redirected this request. Its safe follow-up protocol is not configured yet.');
    }
    if (!(response.headers.get('content-type') ?? '').toLowerCase().includes('text/event-stream')) throw new ChatError('invalid-response', 'The companion did not return a chat event stream.');
    if (!response.body) throw new ChatError('invalid-response', 'The companion returned no stream.');

    reader = response.body.getReader();
    const parser = new SseParser();
    let deltaText = '';
    let latency: number | undefined;
    let terminal = false;
    let finalResponse: ChatResponse | undefined;
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
      if (!['latency', 'companion_state', 'delta', 'ui_action', 'handoff', 'state', 'done'].includes(frame.event)) return;
      const data = object(parseJson(frame));
      switch (frame.event) {
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
          emit({ event: 'delta', data: { text: data.text } });
          break;
        }
        case 'ui_action': {
          const [action] = parseActions([data]);
          emit({ event: 'ui_action', data: action });
          break;
        }
        case 'handoff': emit({ event: 'handoff', data: parseHandoff(data) }); break;
        case 'state': {
          if (typeof data.exercise_state !== 'string' || !data.exercise_state) throw new ChatError('invalid-response', 'The companion sent an invalid exercise state.');
          emit({ event: 'state', data: { exercise_state: data.exercise_state } });
          break;
        }
        case 'done': {
          const state = companionState(data.companion_state);
          if (typeof data.full_text !== 'string' || !data.full_text.trim()
            || typeof data.total_generation_s !== 'number' || !Number.isFinite(data.total_generation_s) || data.total_generation_s < 0) {
            throw new ChatError('invalid-response', 'The companion sent an incomplete final event.');
          }
          if (data.exercise_state !== undefined && data.exercise_state !== null && typeof data.exercise_state !== 'string') throw new ChatError('invalid-response', 'The companion sent invalid final exercise state.');
          const actions = data.ui_actions === undefined ? undefined : parseActions(data.ui_actions);
          const finalHandoff = data.handoff === undefined || data.handoff === null ? data.handoff as null | undefined : parseHandoff(data.handoff);
          // Final text replaces deltas; it is never appended, preventing duplicate content.
          finalResponse = parseChatResponse({ reply: data.full_text, latency_ms: latency ?? data.total_generation_s * 1000, companion_state: state });
          terminal = true;
          const doneEvent: Extract<ChatServerEvent, { event: 'done' }>['data'] = {
            full_text: data.full_text, companion_state: state,
            ui_actions: actions, handoff: finalHandoff, total_generation_s: data.total_generation_s,
          };
          if (Object.prototype.hasOwnProperty.call(data, 'exercise_state')) doneEvent.exercise_state = data.exercise_state as string | null;
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
    if (!terminal || !finalResponse) throw new ChatError('invalid-response', 'The companion stream ended before the turn completed.');
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
