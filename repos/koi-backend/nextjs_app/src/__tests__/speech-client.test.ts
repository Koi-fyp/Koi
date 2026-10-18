import { adaptSpeechResponse, createSpeechClient, SPEECH_SERVER_ERROR_CODES, wavDurationSeconds, type SpeechApiRequest } from '@/lib/speech/speechClient';
import { chunkReply, classifyChunk, speakable, MAX_CHUNK_CHARS } from '@/lib/speech/chunkReply';
import { chooseVoice } from '@/lib/speech/voiceChoice';

const GEN = '123e4567-e89b-42d3-a456-426614174000';
const URDU = 'آپ آج کیسا محسوس کر رہے ہیں؟';
const ENGLISH = 'I am here with you, take your time.';
const TOKEN = 'fake-id-token-not-real';
const BASE = 'https://speech.example.test';

function wavBytes(seconds: number, rate = 22050, { riff = 'RIFF', channels = 1 } = {}) {
  const dataSize = Math.round(seconds * rate) * 2 * channels, bytes = new Uint8Array(44 + dataSize), view = new DataView(bytes.buffer);
  const put = (at: number, text: string) => { for (let i = 0; i < 4; i++) bytes[at + i] = text.charCodeAt(i); };
  put(0, riff); view.setUint32(4, 36 + dataSize, true); put(8, 'WAVE'); put(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, channels, true); view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2 * channels, true); view.setUint16(32, 2 * channels, true); view.setUint16(34, 16, true);
  put(36, 'data'); view.setUint32(40, dataSize, true);
  return bytes;
}
const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString('base64');
function body(overrides: Record<string, unknown> = {}, voice = 'aisha_ur') {
  return { generation_id: GEN, voice_id: voice, audio_format: 'wav', sample_rate: 22050, audio_b64: b64(wavBytes(1)),
    mouth_cues: [{ start: 0, end: 0.4, value: 'D' }, { start: 0.4, end: 0.9, value: 'X' }], duration_s: 1, timings_ms: { synthesis: 900, cue_extraction: 300 }, ...overrides };
}
const request = (overrides: Partial<SpeechApiRequest> = {}): SpeechApiRequest => ({ text: URDU, voice_id: 'aisha_ur', language: 'ur', generation_id: GEN, ...overrides });
const response = (status: number, payload: unknown) => ({ ok: status >= 200 && status < 300, status, text: async () => typeof payload === 'string' ? payload : JSON.stringify(payload) }) as unknown as Response;
function setup(...replies: Array<Response | Error>) {
  const fetchImpl = jest.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => { const next = replies.shift(); if (!next || next instanceof Error) throw next ?? new TypeError('no reply'); return next; });
  const getToken = jest.fn(async () => TOKEN);
  return { fetchImpl, getToken, client: createSpeechClient({ baseUrl: `${BASE}/`, getToken, fetchImpl: fetchImpl as unknown as typeof fetch }) };
}
let logs: jest.SpyInstance[];
beforeEach(() => { logs = (['log', 'info', 'warn', 'error', 'debug'] as const).map(name => jest.spyOn(console, name).mockImplementation(() => {})); });
afterEach(() => { for (const spy of logs) { expect(spy).not.toHaveBeenCalled(); spy.mockRestore(); } });

describe('speech client request', () => {
  it('POSTs the contract body with a bearer token and adapts the response to playback types', async () => {
    const { client, fetchImpl } = setup(response(200, body()));
    const result = await client.speak(request());
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.speech).toMatchObject({ duration: 1, synthesisMs: 900, extractionMs: 300, generationId: GEN, voiceId: 'aisha_ur', sampleRate: 22050 });
    expect(result.speech.audio.type).toBe('audio/wav');
    expect(result.speech.cues.map(cue => cue.value)).toEqual(['D', 'X']);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe(`${BASE}/api/v1/speech`);
    expect(init).toMatchObject({ method: 'POST', credentials: 'omit', headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } });
    expect(JSON.parse(init!.body as string)).toEqual({ text: URDU, voice_id: 'aisha_ur', language: 'ur', generation_id: GEN });
  });
  it.each([
    ['mixed script', request({ text: `${URDU} hello` })],
    ['latin text on an Urdu voice', request({ text: ENGLISH })],
    ['Urdu text on an English voice', request({ voice_id: 'raza_en', language: 'en' })],
    ['language not matching voice', request({ language: 'en' })],
    ['over 450 chars', request({ text: 'ا'.repeat(MAX_CHUNK_CHARS + 1) })],
    ['empty text', request({ text: '   ' })],
    ['unknown voice', request({ voice_id: 'ur_PK-fasih-medium' as never })],
    ['non-uuid generation id', request({ generation_id: 'gen-1' })],
  ])('rejects %s locally without a token or network call', async (_name, bad) => {
    const { client, fetchImpl, getToken } = setup();
    expect(await client.speak(bad)).toMatchObject({ ok: false, error: { code: 'invalid-request' } });
    expect(getToken).not.toHaveBeenCalled(); expect(fetchImpl).not.toHaveBeenCalled();
  });
  it('maps a failing token source to unauthenticated without calling fetch', async () => {
    const fetchImpl = jest.fn();
    const client = createSpeechClient({ baseUrl: BASE, getToken: () => Promise.reject(new Error('signed out')), fetchImpl });
    expect(await client.speak(request())).toMatchObject({ ok: false, error: { code: 'unauthenticated' } });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  it('requires an https (or localhost) base URL without credentials or query', () => {
    expect(() => createSpeechClient({ baseUrl: 'http://speech.example.test', getToken: async () => TOKEN })).toThrow();
    expect(() => createSpeechClient({ baseUrl: 'https://user:pw@speech.example.test', getToken: async () => TOKEN })).toThrow();
    expect(() => createSpeechClient({ baseUrl: 'http://localhost:8000', getToken: async () => TOKEN })).not.toThrow();
  });
});

describe('speech client response validation', () => {
  const broken = (bytes: Uint8Array) => b64(bytes);
  it.each([
    ['bad base64', { audio_b64: '@@@@not-base64' }],
    ['base64 with bad padding', { audio_b64: 'UklGRg=' }],
    ['bad wav header', { audio_b64: broken(wavBytes(1, 22050, { riff: 'RIFX' })) }],
    ['stereo wav', { audio_b64: broken(wavBytes(1, 22050, { channels: 2 })) }],
    ['sample rate not matching wav', { sample_rate: 16000 }],
    ['wav length not matching duration_s', { duration_s: 2, mouth_cues: [{ start: 0, end: 1.5, value: 'D' }] }],
    ['overlapping cues', { mouth_cues: [{ start: 0, end: 0.5, value: 'D' }, { start: 0.4, end: 0.8, value: 'E' }] }],
    ['unordered cues', { mouth_cues: [{ start: 0.5, end: 0.8, value: 'D' }, { start: 0, end: 0.4, value: 'E' }] }],
    ['non-finite cue', { mouth_cues: [{ start: 0, end: Number.NaN, value: 'D' }] }],
    ['unknown cue shape', { mouth_cues: [{ start: 0, end: 0.5, value: 'Z' }] }],
    ['no cues', { mouth_cues: [] }],
    ['cue past duration', { mouth_cues: [{ start: 0, end: 1.2, value: 'D' }] }],
    ['wrong voice_id', { voice_id: 'raza_ur' }],
    ['wrong generation_id', { generation_id: '123e4567-e89b-42d3-a456-426614174999' }],
    ['non-wav format', { audio_format: 'mp3' }],
    ['non-finite duration', { duration_s: 'Infinity' }],
    ['bad timings', { timings_ms: { synthesis: -1 } }],
    ['remote audio url', { audio_url: 'https://cdn.example.test/a.wav' }],
  ])('rejects %s', async (_name, overrides) => {
    const { client } = setup(response(200, body(overrides)));
    expect(await client.speak(request())).toMatchObject({ ok: false, error: { code: 'invalid-response' } });
  });
  it('rejects non-JSON and non-200 success bodies', async () => {
    expect(await setup(response(200, '<html>')).client.speak(request())).toMatchObject({ ok: false, error: { code: 'invalid-response' } });
    expect(await setup(response(204, body())).client.speak(request())).toMatchObject({ ok: false, error: { code: 'invalid-response' } });
  });
  it('accepts an English reply for an English voice and reads the wav duration from the data chunk', () => {
    const adapted = adaptSpeechResponse(body({}, 'raza_en'), request({ text: ENGLISH, voice_id: 'raza_en', language: 'en' }));
    expect(adapted?.voiceId).toBe('raza_en');
    expect(wavDurationSeconds(wavBytes(0.5, 24000), 24000)).toBeCloseTo(0.5, 5);
  });
});

describe('speech client errors and retry', () => {
  const statusFor: Record<string, number> = { 'invalid-request': 400, unauthenticated: 401, 'text-too-long': 413, 'audio-too-long': 413, 'voice-not-allowed': 403, 'language-mismatch': 422, 'rate-limited': 429, 'speech-unavailable': 503 };
  it.each(SPEECH_SERVER_ERROR_CODES.map(code => [code]))('maps server code %s and never retries', async (code) => {
    const { client, fetchImpl } = setup(response(statusFor[code], { error: { code } }), response(200, body()));
    const result = await client.speak(request());
    expect(result).toMatchObject({ ok: false, error: { code, status: statusFor[code] } });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
  it.each([[401, 'unauthenticated'], [429, 'rate-limited'], [503, 'speech-unavailable'], [418, 'invalid-request']])('falls back to status %s -> %s without a known code', async (status, code) => {
    const { client, fetchImpl } = setup(response(status, '<html>gateway</html>'));
    expect(await client.speak(request())).toMatchObject({ ok: false, error: { code } });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
  it('retries exactly once on a network error', async () => {
    const recovered = setup(new TypeError('offline'), response(200, body()));
    expect((await recovered.client.speak(request())).ok).toBe(true);
    expect(recovered.fetchImpl).toHaveBeenCalledTimes(2);
    const down = setup(new TypeError('offline'), new TypeError('offline'), response(200, body()));
    expect(await down.client.speak(request())).toMatchObject({ ok: false, error: { code: 'network' } });
    expect(down.fetchImpl).toHaveBeenCalledTimes(2);
  });
  it('does not retry an aborted request', async () => {
    const abort = new AbortController();
    const fetchImpl = jest.fn(async () => { abort.abort(); throw new DOMException('aborted', 'AbortError'); });
    const client = createSpeechClient({ baseUrl: BASE, getToken: async () => TOKEN, fetchImpl });
    expect(await client.speak(request(), { signal: abort.signal })).toMatchObject({ ok: false, error: { code: 'aborted' } });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
  it('never puts the text or token into an error', async () => {
    const { client } = setup(response(422, { error: { code: 'language-mismatch' } }));
    const result = await client.speak(request());
    if (!('error' in result)) throw new Error('expected a failure');
    expect(`${result.error.message} ${result.error.stack}`).not.toContain(URDU);
    expect(`${result.error.message} ${result.error.stack}`).not.toContain(TOKEN);
  });
});

describe('chunkReply', () => {
  it('splits Urdu on the Urdu full stop and question mark', () => {
    const text = 'آپ آج کیسا محسوس کر رہے ہیں؟ میں یہاں آپ کے ساتھ ہوں۔ آہستہ آہستہ سانس لیں۔';
    expect(chunkReply(text)).toEqual(['آپ آج کیسا محسوس کر رہے ہیں؟', 'میں یہاں آپ کے ساتھ ہوں۔', 'آہستہ آہستہ سانس لیں۔']);
    expect(chunkReply(text).map(classifyChunk)).toEqual(['ur-script', 'ur-script', 'ur-script']);
  });
  it('splits English on . ? ! and keeps decimals whole', () => {
    expect(chunkReply('Take a slow breath with me now. Did that help a little bit? You scored 3.5 out of five today!'))
      .toEqual(['Take a slow breath with me now.', 'Did that help a little bit?', 'You scored 3.5 out of five today!']);
  });
  it('merges fragments under 20 chars into a same-script neighbour, never across scripts', () => {
    expect(chunkReply('Okay. Let us try something gentle together.')).toEqual(['Okay. Let us try something gentle together.']);
    expect(chunkReply('That is fine. Ok!')).toEqual(['That is fine. Ok!']);
    expect(chunkReply('Okay. آپ آج کیسا محسوس کر رہے ہیں؟')).toEqual(['Okay.', 'آپ آج کیسا محسوس کر رہے ہیں؟']);
  });
  it('splits anything over the limit at a space', () => {
    const long = Array.from({ length: 120 }, (_, i) => `word${i}`).join(' ');
    const chunks = chunkReply(long);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.every(chunk => chunk.length <= MAX_CHUNK_CHARS)).toBe(true);
    expect(chunks.join(' ')).toBe(long);
    expect(chunkReply(long, { maxChars: 100 }).every(chunk => chunk.length <= 100)).toBe(true);
    expect(chunkReply(long, { maxChars: 10_000 }).every(chunk => chunk.length <= MAX_CHUNK_CHARS)).toBe(true);
  });
  it('classifies mixed and empty text', () => {
    expect(classifyChunk(`${URDU} okay`)).toBe('mixed');
    expect(classifyChunk('... 123 !?')).toBe('empty');
    expect(classifyChunk('؟۔ ۱۲۳')).toBe('empty');
    expect(chunkReply('   \n ')).toEqual([]);
  });
  it('speakable rejects mixed, empty and anything hinted as Roman Urdu', () => {
    expect(speakable(URDU, 'ur-script')).toBe(true);
    expect(speakable(ENGLISH, 'en')).toBe(true);
    expect(speakable(ENGLISH, 'unknown')).toBe(true);
    expect(speakable('Aap kaisa mehsoos kar rahe hain?', 'roman-ur')).toBe(false);
    expect(speakable(URDU, 'roman-ur')).toBe(false);
    expect(speakable(`${URDU} okay`, 'ur-script')).toBe(false);
    expect(speakable('...', 'en')).toBe(false);
  });
});

describe('chooseVoice', () => {
  it.each([
    ['aisha', 'ur-script', 'aisha_ur'], ['aisha', 'latin', 'aisha_en'], ['raza', 'ur-script', 'raza_ur'], ['raza', 'latin', 'raza_en'],
    ['aisha', 'mixed', null], ['raza', 'empty', null], ['fox', 'ur-script', null], ['fox', 'latin', null], ['koi', 'latin', null], [undefined, 'latin', null],
  ] as const)('%s + %s -> %s', (companion, kind, voice) => { expect(chooseVoice(companion, kind)).toBe(voice); });
});
