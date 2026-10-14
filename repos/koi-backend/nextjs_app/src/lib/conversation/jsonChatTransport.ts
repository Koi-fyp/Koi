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
}): Promise<ChatResponse> {
  const url = chatEndpoint(options.apiBase);
  const abort = new AbortController(); let timedOut = false;
  const onAbort = () => abort.abort();
  options.signal.throwIfAborted(); options.signal.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => { timedOut = true; abort.abort(); }, options.timeoutMs ?? 45000);
  try {
    const headers = new Headers(options.headers); headers.set('Content-Type', 'application/json'); headers.set('Accept', 'application/json');
    const response = await (options.fetchImpl ?? fetch)(url, { method: 'POST', headers, signal: abort.signal, redirect: 'error',
      body: JSON.stringify(createChatRequest(request.message, request.session_history)) });
    abort.signal.throwIfAborted();
    if (!response.ok) {
      // Never surface/log an arbitrary backend body, which may contain sensitive generation output.
      throw new ChatError(response.status === 401 || response.status === 403 ? 'authentication' : 'http',
        response.status === 401 || response.status === 403 ? 'Your session needs authentication. Please sign in again.' : `The self-hosted companion is unavailable (${response.status}).`, response.status);
    }
    if (!(response.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) throw new ChatError('invalid-response', 'The companion endpoint must return JSON.');
    let body: unknown;
    try { body = await response.json(); } catch { abort.signal.throwIfAborted(); throw new ChatError('invalid-response', 'The companion returned invalid JSON.'); }
    abort.signal.throwIfAborted(); return parseChatResponse(body);
  } catch (error) {
    if (options.signal.aborted) throw new DOMException('Request cancelled.', 'AbortError');
    if (timedOut) throw new ChatError('timeout', 'The companion took too long to respond. Please try again.');
    if (error instanceof ChatError) throw error;
    throw new ChatError('network', 'Unable to reach the self-hosted companion. Please try again.');
  } finally { clearTimeout(timer); options.signal.removeEventListener('abort', onAbort); }
}
