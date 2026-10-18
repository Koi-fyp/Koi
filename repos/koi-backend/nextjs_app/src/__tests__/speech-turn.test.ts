import { SpeechReplyController, type ReplyStatus, type ReplyTurn } from '@/lib/speech/speechReplyController';
import type { SpeakResult, SpeechApiRequest } from '@/lib/speech/speechClient';
import { SpeechClientError } from '@/lib/speech/speechClient';
import type { TurnPlayback } from '@/lib/speech/SpeechTurnController';
import { SpeechPlayback, type PlaybackSnapshot } from '@/lib/speech/SpeechPlayback';
import { VRMMouthController } from '@/components/avatar/VRMMouthController';

const S1 = 'Take a slow breath with me now.', S2 = 'Did that help a little bit?', S3 = 'We can keep going whenever you like.';
const REPLY = `${S1} ${S2} ${S3}`;
const URDU = 'آپ آج کیسا محسوس کر رہے ہیں؟';

function fakePlayback() {
  let snapshot: PlaybackSnapshot = { state: 'idle', time: 0, duration: 0, error: null };
  const listeners = new Set<() => void>();
  const set = (state: PlaybackSnapshot['state']) => { snapshot = { ...snapshot, state }; listeners.forEach(listener => listener()); };
  const playback = {
    loaded: [] as string[], clears: 0, failPlay: false,
    load(source: { audioBlob?: Blob }) { playback.loaded.push((source.audioBlob as Blob & { label?: string }).label ?? '?'); set('idle'); },
    async play() { set(playback.failPlay ? 'error' : 'playing'); },
    clear() { playback.clears++; set('stopped'); },
    dispose() { listeners.clear(); },
    end() { set('ended'); },
    getFrame: () => ({ active: snapshot.state === 'playing', time: 0.1, cues: [{ start: 0, end: 0.5, value: 'D' as const }] }),
    getSnapshot: () => snapshot,
    subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; },
  };
  return playback;
}
function speech(label: string): SpeakResult {
  const audio = Object.assign(new Blob([new Uint8Array(64)], { type: 'audio/wav' }), { label });
  return { ok: true, speech: { audio, cues: [{ start: 0, end: 0.5, value: 'D' }], duration: 1, synthesisMs: 1, extractionMs: 1, generationId: 'g', voiceId: 'aisha_en', sampleRate: 22050 } };
}
type Call = { request: SpeechApiRequest; signal: AbortSignal; resolve: (result: SpeakResult) => void };
function fakeClient() {
  const calls: Call[] = []; let inFlight = 0, maxInFlight = 0;
  const client = {
    calls, get maxInFlight() { return maxInFlight; },
    speak: jest.fn((request: SpeechApiRequest, { signal }: { signal?: AbortSignal } = {}) => new Promise<SpeakResult>(resolve => {
      inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
      const settle = (result: SpeakResult) => { inFlight--; resolve(result); };
      let settled = false; const once = (result: SpeakResult) => { if (!settled) { settled = true; settle(result); } };
      signal?.addEventListener('abort', () => once({ ok: false, error: new SpeechClientError('aborted') }));
      calls.push({ request, signal: signal!, resolve: once });
    })),
  };
  return client;
}
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
let ids = 0;
function setup(playback: TurnPlayback = fakePlayback() as unknown as TurnPlayback) {
  const client = fakeClient(), statuses: ReplyStatus[] = [], mouth = { setSource: jest.fn() };
  const controller = new SpeechReplyController({ client, playback, mouth, onStatus: status => statuses.push(status),
    newRequestId: () => `123e4567-e89b-42d3-a456-${String(++ids).padStart(12, '0')}` });
  return { client, playback: playback as unknown as ReturnType<typeof fakePlayback>, controller, statuses, mouth };
}
const turn = (overrides: Partial<ReplyTurn> = {}): ReplyTurn => ({ text: REPLY, companion: 'aisha', ownerUid: 'user-1', generationId: 'gen-1', languageHint: 'en', ...overrides });
let logs: jest.SpyInstance[];
beforeEach(() => { jest.useFakeTimers(); logs = (['log', 'info', 'warn', 'error', 'debug'] as const).map(name => jest.spyOn(console, name).mockImplementation(() => {})); });
afterEach(() => { for (const spy of logs) { expect(spy).not.toHaveBeenCalled(); spy.mockRestore(); } jest.useRealTimers(); });

describe('SpeechReplyController ordering', () => {
  it('requests chunk n+1 while chunk n plays, in order, with at most one request in flight', async () => {
    const { client, playback, controller, statuses, mouth } = setup();
    const done = controller.speakReply(turn());
    await flush();
    expect(client.calls.map(call => call.request.text)).toEqual([S1]);
    expect(client.calls[0].request).toMatchObject({ voice_id: 'aisha_en', language: 'en' });
    expect(mouth.setSource).toHaveBeenCalledWith(controller);
    client.calls[0].resolve(speech('c1')); await flush();
    expect(playback.loaded).toEqual(['c1']);
    expect(controller.getFrame().active).toBe(true);
    expect(client.calls.map(call => call.request.text)).toEqual([S1, S2]);
    client.calls[1].resolve(speech('c2')); await flush();
    expect(client.calls).toHaveLength(2);
    expect(playback.loaded).toEqual(['c1']);
    playback.end(); await flush();
    expect(playback.loaded).toEqual(['c1', 'c2']);
    expect(client.calls.map(call => call.request.text)).toEqual([S1, S2, S3]);
    client.calls[2].resolve(speech('c3')); await flush();
    playback.end(); await flush();
    playback.end(); await flush();
    expect(await done).toBe('completed');
    expect(playback.loaded).toEqual(['c1', 'c2', 'c3']);
    expect(client.maxInFlight).toBe(1);
    expect(new Set(client.calls.map(call => call.request.generation_id)).size).toBe(3);
    expect(statuses.map(status => status.state)).toEqual(expect.arrayContaining(['requesting', 'playing', 'idle']));
    expect(statuses.at(-1)).toMatchObject({ state: 'idle', reason: null, generationId: 'gen-1' });
    expect(mouth.setSource).toHaveBeenLastCalledWith(undefined);
    expect(controller.getFrame().active).toBe(false);
  });
  it('picks the Urdu voice for Urdu-script chunks and skips mixed chunks as unspeakable', async () => {
    const { client, controller, statuses, playback } = setup();
    const done = controller.speakReply(turn({ text: `${URDU} I am here with you okay ${URDU}`, companion: 'raza', languageHint: 'ur-script' }));
    await flush();
    expect(client.calls[0].request).toMatchObject({ voice_id: 'raza_ur', language: 'ur' });
    client.calls[0].resolve(speech('ur')); await flush(); playback.end();
    expect(await done).toBe('completed');
    expect(client.calls).toHaveLength(1);
    expect(statuses).toContainEqual(expect.objectContaining({ state: 'skipped', chunk: 1, reason: 'unspeakable' }));
  });
});

describe('SpeechReplyController silence', () => {
  it.each([
    ['fox', turn({ companion: 'fox' })], ['an unknown companion', turn({ companion: 'koi' })],
    ['a Roman Urdu hint', turn({ text: 'Aap kaisa mehsoos kar rahe hain? Main yahan hoon.', languageHint: 'roman-ur' })],
    ['empty text', turn({ text: '  ... ' })],
  ])('stays text-only for %s', async (_name, input) => {
    const { client, controller, playback } = setup();
    expect(await controller.speakReply(input)).toBe('silent');
    expect(client.speak).not.toHaveBeenCalled(); expect(playback.loaded).toEqual([]);
  });
});

describe('SpeechReplyController cancellation', () => {
  it('cancel() aborts the request, stops audio, neutralises the mouth and ignores late responses', async () => {
    const { client, playback, controller, statuses, mouth } = setup();
    const done = controller.speakReply(turn());
    await flush(); client.calls[0].resolve(speech('c1')); await flush();
    expect(client.calls[1].signal.aborted).toBe(false);
    controller.cancel();
    expect(client.calls[1].signal.aborted).toBe(true);
    expect(playback.getSnapshot().state).toBe('stopped');
    expect(mouth.setSource).toHaveBeenLastCalledWith(undefined);
    expect(controller.getFrame().active).toBe(false);
    expect(await done).toBe('cancelled');
    client.calls[1].resolve(speech('late')); await flush();
    expect(playback.loaded).toEqual(['c1']);
    expect(statuses.at(-1)).toMatchObject({ state: 'idle', reason: 'cancelled' });
  });
  it('a new generationId cancels the previous reply; the same one is deduplicated', async () => {
    const { client, controller } = setup();
    const first = controller.speakReply(turn());
    expect(controller.speakReply(turn())).toBe(first);
    await flush();
    const second = controller.speakReply(turn({ generationId: 'gen-2', text: S2 }));
    expect(await first).toBe('cancelled');
    expect(client.calls[0].signal.aborted).toBe(true);
    await flush();
    expect(client.calls.map(call => call.request.text)).toEqual([S1, S2]);
    client.calls[1].resolve(speech('x')); await flush();
    expect(controller.getStatus()).toMatchObject({ state: 'playing', generationId: 'gen-2' });
    void second;
  });
  it.each([
    ['owner change via setOwner', (c: SpeechReplyController) => c.setOwner('user-2')],
    ['owner change via a new turn', (c: SpeechReplyController) => { void c.speakReply(turn({ ownerUid: 'user-2' })); }],
    ['companion change via setCompanion', (c: SpeechReplyController) => c.setCompanion('raza')],
    ['companion change to fox', (c: SpeechReplyController) => c.setCompanion('fox')],
    ['an aborted external signal', (_c: SpeechReplyController, abort: AbortController) => abort.abort()],
  ])('cancels automatically on %s', async (_name, change) => {
    const { client, controller, playback } = setup(), abort = new AbortController();
    const done = controller.speakReply(turn(), { signal: abort.signal });
    await flush(); client.calls[0].resolve(speech('c1')); await flush();
    change(controller, abort);
    expect(await done).toBe('cancelled');
    expect(client.calls[1].signal.aborted).toBe(true);
    expect(playback.clears).toBeGreaterThan(0);
  });
  it('keeps playing when owner and companion are unchanged', async () => {
    const { client, controller } = setup();
    controller.speakReply(turn()); await flush();
    controller.setOwner('user-1'); controller.setCompanion('aisha');
    expect(client.calls[0].signal.aborted).toBe(false);
  });
});

describe('SpeechReplyController skipping', () => {
  it('skips a chunk slower than 12 s with a timeout status and moves on', async () => {
    const { client, controller, statuses, playback } = setup();
    controller.speakReply(turn()); await flush();
    await jest.advanceTimersByTimeAsync(11_999);
    expect(statuses.some(status => status.state === 'skipped')).toBe(false);
    await jest.advanceTimersByTimeAsync(1); await flush();
    expect(client.calls[0].signal.aborted).toBe(true);
    expect(statuses).toContainEqual(expect.objectContaining({ state: 'skipped', chunk: 0, reason: 'timeout' }));
    expect(client.calls[1].request.text).toBe(S2);
    client.calls[1].resolve(speech('c2')); await flush();
    expect(playback.loaded).toEqual(['c2']);
  });
  it('skips a failed chunk and a chunk whose audio fails to play', async () => {
    const { client, controller, statuses, playback } = setup();
    const done = controller.speakReply(turn()); await flush();
    client.calls[0].resolve({ ok: false, error: new SpeechClientError('language-mismatch', 422) }); await flush();
    expect(statuses).toContainEqual(expect.objectContaining({ state: 'skipped', chunk: 0, reason: 'language-mismatch' }));
    playback.failPlay = true;
    client.calls[1].resolve(speech('c2')); await flush();
    expect(statuses).toContainEqual(expect.objectContaining({ state: 'skipped', chunk: 1, reason: 'playback-failed' }));
    playback.failPlay = false;
    client.calls[2].resolve(speech('c3')); await flush(); playback.end(); await flush();
    expect(await done).toBe('completed');
  });
  it('ends the turn with an error status when unauthenticated', async () => {
    const { client, controller, statuses } = setup();
    const done = controller.speakReply(turn()); await flush();
    client.calls[0].resolve({ ok: false, error: new SpeechClientError('unauthenticated', 401) });
    expect(await done).toBe('error');
    expect(statuses.at(-1)).toMatchObject({ state: 'error', reason: 'unauthenticated' });
    expect(client.calls).toHaveLength(1);
  });
  it('never touches the reply text and never puts it in a status', async () => {
    const { client, controller, statuses } = setup();
    const input = Object.freeze(turn());
    controller.speakReply(input); await flush();
    client.calls[0].resolve({ ok: false, error: new SpeechClientError('speech-unavailable', 503) }); await flush();
    controller.cancel();
    expect(input.text).toBe(REPLY);
    const serialized = JSON.stringify(statuses);
    for (const sentence of [S1, S2, S3]) expect(serialized).not.toContain(sentence);
  });
});

describe('SpeechReplyController with real playback and mouth', () => {
  class FakeAudio extends EventTarget {
    preload = ''; currentTime = 0; duration = 1; paused = true; ended = false; seeking = false; private source = '';
    get src() { return this.source; } set src(value: string) { this.source = value; }
    removeAttribute() { this.source = ''; } load() {}
    async play() { this.paused = false; this.dispatchEvent(new Event('playing')); }
    pause() { this.paused = true; }
    finish() { this.paused = true; this.ended = true; this.dispatchEvent(new Event('ended')); }
  }
  let created: string[], revoked: string[];
  beforeEach(() => {
    created = []; revoked = [];
    Object.assign(URL, { createObjectURL: () => { const url = `blob:speech-${created.length + 1}`; created.push(url); return url; }, revokeObjectURL: (url: string) => { revoked.push(url); } });
  });
  it('releases each chunk object URL after it ends and on cancel, and restores a neutral mouth', async () => {
    let audio!: FakeAudio;
    const playback = new SpeechPlayback(() => { audio = new FakeAudio(); return audio as unknown as HTMLAudioElement; });
    const manager = { getExpression: jest.fn(() => ({}) as never), setValue: jest.fn() };
    const mouthController = new VRMMouthController(manager);
    const client = fakeClient();
    const controller = new SpeechReplyController({ client, playback, mouth: mouthController, newRequestId: () => '123e4567-e89b-42d3-a456-426614174000' });
    controller.speakReply(turn()); await flush();
    client.calls[0].resolve(speech('c1')); await flush();
    expect(created).toEqual(['blob:speech-1']);
    audio.currentTime = 0.1; mouthController.update();
    expect(mouthController.getSnapshot()).toMatchObject({ active: true, preset: 'aa' });
    client.calls[1].resolve(speech('c2')); await flush();
    audio.finish(); await flush();
    expect(revoked).toContain('blob:speech-1');
    expect(created).toEqual(['blob:speech-1', 'blob:speech-2']);
    controller.cancel();
    expect(revoked).toContain('blob:speech-2');
    expect(mouthController.getSnapshot()).toMatchObject({ active: false, preset: null, weight: 0 });
    expect(manager.setValue).toHaveBeenLastCalledWith(expect.any(String), 0);
    controller.dispose();
    expect(playback.getSnapshot().state).toBe('disposed');
  });
});
