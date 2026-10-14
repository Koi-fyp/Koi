import { ChatError, createChatRequest, parseChatResponse, type ChatAdapter, type ChatResponse } from '@/lib/conversation/chatContract';
// This module is outside production src/app and refuses use outside development.
export const MOCK_SAMPLES = ['Sample joy', 'Sample angry', 'Sample sorrow', 'Sample fun', 'Sample neutral', 'Sample failure', 'Sample slow'] as const;
const emotions = ['joy', 'angry', 'sorrow', 'fun', 'neutral'] as const;
export function createMockChatAdapter(): ChatAdapter {
  if (process.env.NODE_ENV !== 'development') throw new Error('Mock chat is development-only.');
  return { async send(request, options) {
    const valid = createChatRequest(request.message, request.session_history);
    if (!(MOCK_SAMPLES as readonly string[]).includes(valid.message)) throw new ChatError('invalid-response', 'Use only the scripted development samples.');
    options.signal.throwIfAborted();
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { options.signal.removeEventListener('abort', cancel); resolve(); }, valid.message === 'Sample slow' ? 1500 : 300);
      const cancel = () => { clearTimeout(timer); options.signal.removeEventListener('abort', cancel); reject(new DOMException('Request cancelled.', 'AbortError')); };
      options.signal.addEventListener('abort', cancel, { once: true });
    });
    options.signal.throwIfAborted();
    if (valid.message === 'Sample failure') throw new ChatError('network', 'Development simulation: companion unavailable.');
    const emotion = emotions.find((name) => valid.message === `Sample ${name}`) ?? 'neutral';
    const response: ChatResponse = { reply: `Development-only scripted response: ${emotion}. Context includes ${valid.session_history.length} prior messages. No AI inference was performed.`, companion_state: { emotion, intensity: emotion === 'neutral' ? 0 : 0.7 }, latency_ms: 300 };
    return parseChatResponse(response);
  } };
}
