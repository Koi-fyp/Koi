/** @jest-environment node */
import { postJsonChat } from '@/lib/conversation/jsonChatTransport';
import { createChatRequest, type ChatAdapter, type ChatRequest, type ChatSendOptions, type ChatServerEvent } from '@/lib/conversation/chatContract';
import { ConversationSession } from '@/lib/conversation/ConversationSession';

describe('ConversationSession.sendVoice', () => {
  it('sends the clip without text, then shows and keeps the transcript as the user message', async () => {
    const seen: ChatRequest[] = [];
    let finish!: () => void; let emit!: ChatSendOptions['onEvent'];
    const adapter: ChatAdapter = { send: (request, options) => { seen.push(request); emit = options.onEvent; return new Promise(resolve => {
      finish = () => resolve({ reply: 'That sounds hard.', latency_ms: 10, companion_state: { emotion: 'sorrow', intensity: 0.4 } }); }); } };
    const session = new ConversationSession(adapter);
    const audio = new Blob([new Uint8Array(8)], { type: 'audio/webm' });
    const turn = session.sendVoice(audio);
    expect(seen[0]).toMatchObject({ message: '', audio });
    const user = () => session.getSnapshot().messages.find(message => message.sender === 'user')!;
    expect(user()).toMatchObject({ input: 'voice', content: '', status: 'pending' });
    emit!({ event: 'transcript', data: { text: 'I had a long day' } });
    expect(user().content).toBe('I had a long day');
    finish(); await turn;
    expect(user()).toMatchObject({ content: 'I had a long day', status: 'completed' });
    // The transcript, not the audio, becomes context for the next turn.
    void session.send('and I could not sleep');
    expect(seen[1].session_history).toEqual([{ role: 'user', content: 'I had a long day' }, { role: 'assistant', content: 'That sounds hard.' }]);
    expect(seen[1].audio).toBeUndefined();
  });

  it('ignores an empty clip and marks a failed voice turn without inventing text', async () => {
    const adapter: ChatAdapter = { send: jest.fn(async () => { throw new Error('offline'); }) };
    const session = new ConversationSession(adapter);
    await session.sendVoice(new Blob([]));
    expect(adapter.send).not.toHaveBeenCalled();
    await session.sendVoice(new Blob([new Uint8Array(4)]));
    expect(session.getSnapshot().messages[0]).toMatchObject({ input: 'voice', content: '', status: 'failed' });
  });
});

const API = 'https://koi.example.test';
function sse(frames: Array<[string, unknown]>): Response {
  const text = frames.map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`).join('');
  return new Response(text, { status: 200, headers: { 'content-type': 'text/event-stream' } });
}
const DONE: [string, unknown] = ['done', { full_text: 'I hear you.', companion_state: { emotion: 'neutral', intensity: 0 }, total_generation_s: 1.2 }];

describe('voice turn contract', () => {
  it('requires an empty message for a voice turn and a non-empty one for text', () => {
    expect(createChatRequest('', [], {}, { voice: true })).toMatchObject({ message: '' });
    expect(() => createChatRequest('hello', [], {}, { voice: true })).toThrow('Send either text or a voice message.');
    expect(() => createChatRequest('  ', [])).toThrow('Enter a message first.');
  });
});

describe('postJsonChat voice transport', () => {
  it('sends a multipart payload + audio file, never JSON headers, and surfaces the transcript event', async () => {
    const fetchImpl = jest.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => sse([['transcript', { text: 'I feel tired today', language: 'en' }], DONE]));
    const events: ChatServerEvent[] = [];
    const audio = new Blob([new Uint8Array([1, 2, 3, 4])], { type: 'audio/webm;codecs=opus' });
    const result = await postJsonChat({ message: '', session_history: [{ role: 'user', content: 'hi' }], audio }, {
      apiBase: API, headers: new Headers({ Authorization: 'Bearer t' }), signal: new AbortController().signal, fetchImpl: fetchImpl as unknown as typeof fetch,
      onEvent: (event) => events.push(event),
    });
    expect(result.reply).toBe('I hear you.');
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe(`${API}/api/v1/chat`);
    const headers = new Headers(init!.headers);
    expect(headers.get('content-type')).toBeNull(); // the browser adds the multipart boundary
    expect(headers.get('accept')).toBe('text/event-stream');
    expect(headers.get('authorization')).toBe('Bearer t');
    const form = init!.body as FormData;
    expect(form).toBeInstanceOf(FormData);
    expect(JSON.parse(form.get('payload') as string)).toEqual({ message: '', session_history: [{ role: 'user', content: 'hi' }] });
    const file = form.get('audio') as File;
    expect(file.name).toBe('voice.webm');
    expect(file.size).toBe(4);
    expect([...form.keys()].sort()).toEqual(['audio', 'payload']);
    expect(events[0]).toEqual({ event: 'transcript', data: { text: 'I feel tired today', language: 'en' } });
  });

  it('keeps text turns as plain JSON', async () => {
    const fetchImpl = jest.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => sse([DONE]));
    await postJsonChat({ message: 'hello', session_history: [] }, {
      apiBase: API, headers: new Headers(), signal: new AbortController().signal, fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    const init = fetchImpl.mock.calls[0][1]!;
    expect(new Headers(init.headers).get('content-type')).toBe('application/json');
    expect(JSON.parse(init.body as string)).toEqual({ message: 'hello', session_history: [] });
  });
});
