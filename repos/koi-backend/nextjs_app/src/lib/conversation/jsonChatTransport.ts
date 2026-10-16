import { ChatError, createChatRequest, parseChatResponse, type ChatRequest, type ChatResponse } from './chatContract';
export function chatEndpoint(apiBase: string | undefined): string {
  if (!apiBase?.trim()) throw new ChatError('configuration', 'The self-hosted chat API is not configured.');
  let url: URL;
  try { url = new URL(apiBase); } catch { throw new ChatError('configuration', 'The self-hosted chat API URL is invalid.'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new ChatError('configuration', 'The self-hosted chat API URL is invalid.');
  return url.href.replace(/\/$/, '') + '/api/v1/chat';
}
/** Transport only. Authentication is enforced by conversationService before calling this function. */
export async function postJsonChat(request: ChatRequest, options: {
  apiBase: string | undefined; headers: Headers; signal: AbortSignal; timeoutMs?: number; fetchImpl?: typeof fetch;
  onEvent?: (event: string, payload: Record<string, unknown>) => void;
}): Promise<ChatResponse> {
  const url = chatEndpoint(options.apiBase);
  const abort = new AbortController(); let timedOut = false;
  const onAbort = () => abort.abort();
  options.signal.throwIfAborted(); options.signal.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => { timedOut = true; abort.abort(); }, options.timeoutMs ?? 45000);
  try {
    const headers = new Headers(options.headers); headers.set('Content-Type', 'application/json'); headers.set('Accept', 'text/event-stream');
    const response = await (options.fetchImpl ?? fetch)(url, { method: 'POST', headers, signal: abort.signal, redirect: 'follow',
      body: JSON.stringify(createChatRequest(request.message, request.session_history)) });
    abort.signal.throwIfAborted();
    if (!response.ok) {
      // Never surface/log an arbitrary backend body, which may contain sensitive generation output.
      throw new ChatError(response.status === 401 || response.status === 403 ? 'authentication' : 'http',
        response.status === 401 || response.status === 403 ? 'Your session needs authentication. Please sign in again.' : `The self-hosted companion is unavailable (${response.status}).`, response.status);
    }
    if (!response.body) throw new ChatError('invalid-response', 'The companion returned no stream.');
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '', fullText = '', state: Record<string, unknown> | undefined, latency = 0, risk: unknown;
    const consume = (frame: string) => {
      let event = 'message';
      for (const line of frame.split(/\r?\n/)) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        if (!line.startsWith('data:')) continue;
        try {
          const payload = JSON.parse(line.slice(5).trim()) as Record<string, unknown>;
          options.onEvent?.(event, payload);
          if (event === 'companion_state') state = payload;
          else if (event === 'latency' && typeof payload.latency_ms === 'number') latency = payload.latency_ms;
          else if (event === 'delta' && typeof payload.text === 'string') fullText += payload.text;
          else if (event === 'done') { if (typeof payload.full_text === 'string') fullText = payload.full_text; state = (payload.companion_state as Record<string, unknown>) ?? state; risk = payload.risk; }
        } catch { /* Ignore malformed or unknown SSE events. */ }
      }
    };
    while (true) {
      const next = await reader.read(); if (next.done) break;
      buffer += decoder.decode(next.value, { stream: true });
      const frames = buffer.split(/\r?\n\r?\n/); buffer = frames.pop() ?? '';
      frames.forEach(consume);
    }
    if (buffer.trim()) consume(buffer);
    abort.signal.throwIfAborted();
    return parseChatResponse({ reply: fullText, latency_ms: latency, companion_state: state, risk });
  } catch (error) {
    if (options.signal.aborted) throw new DOMException('Request cancelled.', 'AbortError');
    if (timedOut) throw new ChatError('timeout', 'The companion took too long to respond. Please try again.');
    if (error instanceof ChatError) throw error;
    throw new ChatError('network', 'Unable to reach the self-hosted companion. Please try again.');
  } finally { clearTimeout(timer); options.signal.removeEventListener('abort', onAbort); }
}
