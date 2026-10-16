import { ChatError, createChatRequest, parseChatResponse, type ChatAdapter, type ChatResponse } from '@/lib/conversation/chatContract';
// This module is outside production src/app and refuses use outside development.
export const MOCK_SAMPLES = ['Sample joy', 'Sample angry', 'Sample sorrow', 'Sample fun', 'Sample neutral', 'Sample failure', 'Sample slow'] as const;
const emotions = ['joy', 'angry', 'sorrow', 'fun', 'neutral'] as const;
export function createMockChatAdapter(configuration: { reviewedVoice?: boolean } = {}): ChatAdapter {
  if (process.env.NODE_ENV !== 'development') throw new Error('Mock chat is development-only.');
  return { async send(request, options) {
    const valid = createChatRequest(request.message, request.session_history);
    if ((!configuration.reviewedVoice && !(MOCK_SAMPLES as readonly string[]).includes(valid.message)) || valid.message.length > 300) throw new ChatError('invalid-response', 'Use only the scripted development samples.');
    options.signal.throwIfAborted();
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { options.signal.removeEventListener('abort', cancel); resolve(); }, valid.message === 'Sample slow' ? 1500 : 300);
      const cancel = () => { clearTimeout(timer); options.signal.removeEventListener('abort', cancel); reject(new DOMException('Request cancelled.', 'AbortError')); };
      options.signal.addEventListener('abort', cancel, { once: true });
    });
    options.signal.throwIfAborted();
    if (valid.message === 'Sample failure') throw new ChatError('network', 'Development simulation: companion unavailable.');
    const emotion = configuration.reviewedVoice ? 'joy' : emotions.find((name) => valid.message === `Sample ${name}`) ?? 'neutral';
    const response: ChatResponse = { reply: configuration.reviewedVoice ? "\u06cc\u06c1 \u0635\u0631\u0641 \u0627\u06cc\u06a9 \u0645\u0642\u0627\u0645\u06cc \u0622\u0632\u0645\u0627\u0626\u0634\u06cc \u062c\u0648\u0627\u0628 \u06c1\u06d2\u06d4" : `Development-only scripted response: ${emotion}. Context includes ${valid.session_history.length} prior messages. No AI inference was performed.`, companion_state: { emotion, intensity: emotion === 'neutral' ? 0 : 0.7 }, latency_ms: 300 };
    return parseChatResponse(response);
  } };
}
