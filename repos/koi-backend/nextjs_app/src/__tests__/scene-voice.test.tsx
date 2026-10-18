/** @jest-environment jsdom */
import { act, renderHook } from '@testing-library/react';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
import type { SpeechFrame } from '@/lib/speech/mouthCues';
import type { PlaybackSnapshot, SpeechSource } from '@/lib/speech/SpeechPlayback';
import type { TurnPlayback } from '@/lib/speech/SpeechTurnController';
import { SpeechReplyController, type ReplyOutcome, type ReplyStatus } from '@/lib/speech/speechReplyController';
import type { SpeechClient } from '@/lib/speech/speechClient';
import { useSpokenReplies, type ReplyVoiceController, type SpokenRepliesOptions, type SpokenReplyMessage } from '@/lib/speech/useSpokenReplies';

const TOKEN = 'fake-id-token-not-real';
const REPLY = 'I hear you. Let us take this one step at a time.';
const IDLE: SpeechFrame = { active: false, time: 0, cues: [] };
type Events = NonNullable<SpokenRepliesOptions['serverEvents']>;

function fakeController() {
  let onStatus: (status: ReplyStatus) => void = () => undefined;
  const finishers: Array<(outcome: ReplyOutcome) => void> = [];
  const controller = {
    speakReply: jest.fn(() => new Promise<ReplyOutcome>((resolve) => { finishers.push(resolve); })),
    cancel: jest.fn(), dispose: jest.fn(), getFrame: jest.fn(() => IDLE),
  } satisfies ReplyVoiceController;
  const factory = jest.fn((deps: { onStatus: (status: ReplyStatus) => void }) => { onStatus = deps.onStatus; return controller; });
  return { controller, factory, status: (s: Partial<ReplyStatus>) => onStatus({ state: 'idle', generationId: 'g', chunk: 0, total: 1, reason: null, ...s }),
    finish: (outcome: ReplyOutcome) => finishers[finishers.length - 1](outcome) };
}
const user = (id: string, status = 'completed'): SpokenReplyMessage => ({ id, sender: 'user', status, content: 'private user text' });
const ai = (id: string, content = REPLY, status = 'completed'): SpokenReplyMessage => ({ id, sender: 'ai', status, content });
let ids = 0, gens = 0;
const generationId = () => `gen-${++gens}`;

function setup(overrides: Partial<SpokenRepliesOptions> = {}, fake = fakeController()) {
  const getToken = jest.fn(async () => TOKEN);
  const initialProps: SpokenRepliesOptions = { enabled: true, uid: 'user-a', companion: 'aisha', messages: [], pending: false, serverEvents: [],
    baseUrl: 'https://speech.test', getToken, createController: fake.factory as unknown as SpokenRepliesOptions['createController'], newGenerationId: generationId, ...overrides };
  const hook = renderHook((props: SpokenRepliesOptions) => useSpokenReplies(props), { initialProps });
  let props = initialProps;
  const update = (next: Partial<SpokenRepliesOptions>) => { props = { ...props, ...next }; hook.rerender(props); };
  /** User sends, then the reply finishes (not a delta): the only signal that speaks. */
  const reply = (text = REPLY, id = `ai-${++ids}`) => {
    const history = [...props.messages, user(`u-${id}`, 'pending')];
    update({ messages: history, pending: true, serverEvents: [] });
    update({ messages: [...history.slice(0, -1), user(`u-${id}`), ai(id, text)], pending: false });
  };
  return { ...hook, fake, getToken, update, reply, props: () => props };
}
const flush = () => act(async () => { await Promise.resolve(); await Promise.resolve(); });
const handoff: Events = [{ id: 1, event: { event: 'handoff', data: { to: 'crisis', reason: 'test' } } }];
const highRisk: Events = [{ id: 1, event: { event: 'risk', data: { status: 'ok', risk_category: 'HIGH' } } as unknown as ChatServerEvent }];
const action = (name: string): Events => [{ id: 2, event: { event: 'ui_action', data: { name, args: {} } } }];

describe('spoken replies wiring', () => {
  const visibility = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
  beforeEach(() => { jest.useFakeTimers(); ids = 0; gens = 0; });
  afterEach(() => {
    jest.useRealTimers();
    if (visibility) Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
  });

  it('speaks a completed reply exactly once with text, companion, uid and a new generationId', () => {
    const t = setup();
    t.reply();
    t.update({ messages: [...t.props().messages] });
    expect(t.fake.controller.speakReply).toHaveBeenCalledTimes(1);
    expect(t.fake.controller.speakReply).toHaveBeenCalledWith({ text: REPLY, companion: 'aisha', ownerUid: 'user-a', generationId: 'gen-1', languageHint: 'en' });
    t.reply();
    expect(t.fake.controller.speakReply).toHaveBeenCalledTimes(2);
    expect((t.fake.controller.speakReply.mock.calls[1] as unknown[])[0]).toMatchObject({ generationId: 'gen-2' });
  });

  it('never speaks an incomplete (streaming) reply, history, or a reply that existed before voice was on', () => {
    const t = setup({ messages: [user('u0'), ai('old')] });
    t.update({ messages: [...t.props().messages, user('u1'), ai('a1', 'I hear', 'pending')], pending: true });
    t.update({ messages: [...t.props().messages.slice(0, -1), ai('a1', 'I hear you', 'pending')] });
    expect(t.fake.controller.speakReply).not.toHaveBeenCalled();
    const off = setup({ enabled: false });
    off.reply();
    off.update({ enabled: true });
    expect(off.fake.controller.speakReply).not.toHaveBeenCalled();
  });

  it.each([['Roman Urdu', 'Main theek hoon, aap kaise ho?'], ['mixed script', 'Hello دوست, how are you today?']])('stays silent for %s and says so', (_label, text) => {
    const t = setup();
    t.reply(text);
    expect(t.fake.controller.speakReply).not.toHaveBeenCalled();
    expect(t.result.current.line).toBe('skipped');
  });

  it('makes no controller and no speech call while voice is off, for the fox, or without config', () => {
    for (const overrides of [{ enabled: false }, { companion: 'fox' as const }, { companion: null }, { baseUrl: '' }, { uid: null }]) {
      const t = setup(overrides);
      t.reply();
      expect(t.fake.factory).not.toHaveBeenCalled();
      expect(t.fake.controller.speakReply).not.toHaveBeenCalled();
      expect(t.result.current.speechSource).toBeUndefined();
      t.unmount();
    }
  });

  it.each<[string, Events]>([['a crisis handoff', handoff], ['a high-risk result', highRisk], ['an exercise start', action('start_breathing')]])(
    'does not speak when %s arrived in the same turn', (_label, events) => {
      const t = setup();
      t.update({ messages: [user('u1', 'pending')], pending: true, serverEvents: [] });
      t.update({ serverEvents: events });
      t.update({ messages: [user('u1'), ai('a1')], pending: false });
      expect(t.fake.controller.speakReply).not.toHaveBeenCalled();
    });

  const cancelRules: Array<[string, (t: ReturnType<typeof setup>) => void]> = [
    ['the toggle turned off', (t) => t.update({ enabled: false })],
    ['a new user message sent', (t) => t.update({ messages: [...t.props().messages, user('next', 'pending')], pending: true })],
    ['End session (stop)', (t) => act(() => t.result.current.stop())],
    ['leaving the page (unmount)', (t) => t.unmount()],
    ['the companion changed', (t) => t.update({ companion: 'raza' })],
    ['the companion changed to the fox', (t) => t.update({ companion: 'fox' })],
    ['the signed-in uid changed', (t) => t.update({ uid: 'user-b' })],
    ['sign-out', (t) => t.update({ uid: null })],
    ['a crisis handoff opening', (t) => t.update({ serverEvents: handoff })],
    ['a risk dialog opening', (t) => t.update({ serverEvents: highRisk })],
    ['an exercise start', (t) => t.update({ serverEvents: action('start_grounding') })],
    ['an urgent stop_breathing', (t) => t.update({ serverEvents: action('stop_breathing') })],
    ['an urgent pause_breathing', (t) => t.update({ serverEvents: action('pause_breathing') })],
    ['the page becoming hidden', () => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
      act(() => { document.dispatchEvent(new Event('visibilitychange')); });
    }],
  ];
  it.each(cancelRules)('cancels the controller when %s', (label, trigger) => {
    const t = setup();
    t.reply();
    act(() => t.fake.status({ state: 'playing' }));
    expect(t.result.current.audioPlaying).toBe(true);
    const before = t.fake.controller.cancel.mock.calls.length + t.fake.controller.dispose.mock.calls.length;
    trigger(t);
    expect(t.fake.controller.cancel.mock.calls.length + t.fake.controller.dispose.mock.calls.length).toBeGreaterThan(before);
    expect(t.props().messages.some((m) => m.content === REPLY)).toBe(true);
    if (label !== 'leaving the page (unmount)') { expect(t.result.current.audioPlaying).toBe(false); expect(t.result.current.line).toBe('idle'); }
  });

  it('maps status: Speaking..., then idle on completion, unavailable on error, skipped when silent', async () => {
    const t = setup();
    t.reply();
    act(() => t.fake.status({ state: 'playing' }));
    expect(t.result.current.line).toBe('speaking');
    await act(async () => { t.fake.finish('completed'); });
    expect(t.result.current.line).toBe('idle');
    expect(t.result.current.audioPlaying).toBe(false);
    t.reply();
    act(() => t.fake.status({ state: 'error', reason: 'rate-limited' }));
    await act(async () => { t.fake.finish('error'); });
    expect(t.result.current.line).toBe('unavailable');
    t.reply();
    await act(async () => { t.fake.finish('silent'); });
    expect(t.result.current.line).toBe('skipped');
  });

  it('reports unavailable (not an error) when the controller cannot be built', () => {
    const factory = jest.fn(() => { throw new Error('bad base'); });
    const t = setup({ createController: factory });
    t.reply();
    expect(t.result.current.line).toBe('unavailable');
  });
});

describe('spoken replies with the real SpeechReplyController and a fake client', () => {
  function fakePlayback(): TurnPlayback & { loaded: SpeechSource[] } {
    let state: PlaybackSnapshot['state'] = 'idle';
    const listeners = new Set<() => void>();
    const loaded: SpeechSource[] = [];
    return {
      loaded,
      load(source) { loaded.push(source); state = 'loading'; },
      async play() { state = 'playing'; listeners.forEach((l) => l()); },
      clear() { state = 'stopped'; listeners.forEach((l) => l()); }, dispose() { state = 'disposed'; },
      getSnapshot: () => ({ state, time: 0.2, duration: 1, error: null }),
      subscribe(listener) { listeners.add(listener); return () => { listeners.delete(listener); }; },
      getFrame: () => ({ active: state === 'playing', time: 0.2, cues: [{ start: 0, end: 1, value: 'A' }] }),
    };
  }
  const speech = { audio: new Blob(['x'], { type: 'audio/wav' }), cues: [{ start: 0, end: 1, value: 'A' as const }], duration: 1, synthesisMs: 1, extractionMs: 1,
    generationId: 'x', voiceId: 'aisha_en' as const, sampleRate: 16000 };

  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('speaks through the fake client, cancels to a neutral mouth, and keeps text and token out of the console', async () => {
    const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map((name) => jest.spyOn(console, name));
    try {
      const client: Pick<SpeechClient, 'speak'> = { speak: jest.fn(async () => ({ ok: true as const, speech })) };
      const playback = fakePlayback();
      const createController: SpokenRepliesOptions['createController'] = ({ onStatus }) => new SpeechReplyController({ client, playback, onStatus, newRequestId: () => 'req' });
      const t = setup({ createController });
      t.reply();
      await flush(); await flush();
      expect(client.speak).toHaveBeenCalledTimes(1);
      expect((client.speak as jest.Mock).mock.calls[0][0]).toMatchObject({ text: REPLY, voice_id: 'aisha_en', language: 'en' });
      expect(t.result.current.speechSource?.getFrame().active).toBe(true);
      expect(t.result.current.audioPlaying).toBe(true);
      t.update({ messages: [...t.props().messages, user('next', 'pending')], pending: true });
      expect(t.result.current.speechSource?.getFrame()).toEqual(expect.objectContaining({ active: false }));
      expect(t.props().messages.some((m) => m.content === REPLY)).toBe(true);
      for (const spy of spies) for (const call of spy.mock.calls) {
        const out = call.map(String).join(' ');
        expect(out).not.toContain(REPLY); expect(out).not.toContain(TOKEN); expect(out).not.toContain('private user text');
      }
    } finally { spies.forEach((spy) => spy.mockRestore()); }
  });

  it('never calls the client while voice is off', async () => {
    const client = { speak: jest.fn() };
    const createController: SpokenRepliesOptions['createController'] = ({ onStatus }) => new SpeechReplyController({ client, playback: fakePlayback(), onStatus });
    const t = setup({ enabled: false, createController });
    t.reply(); await flush();
    expect(client.speak).not.toHaveBeenCalled();
  });
});
