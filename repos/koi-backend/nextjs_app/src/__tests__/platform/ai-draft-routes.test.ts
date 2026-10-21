/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/runtime', () => ({ getPlatformRuntime: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { PlatformService } from '@/lib/platform/server/service';
import { PlatformError } from '@/lib/platform/server/errors';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import { POST as aiDraft } from '@/app/api/v1/professional/questionnaire-drafts/ai/route';
import { POST as confirmReview } from '@/app/api/v1/professional/questionnaires/[id]/confirm-review/route';
import { POST as create } from '@/app/api/v1/professional/questionnaires/route';
import { PUT as update } from '@/app/api/v1/professional/questionnaires/[id]/route';
import { POST as publish } from '@/app/api/v1/professional/questionnaires/[id]/publish/route';
import { POST as organization } from '@/app/api/v1/professional/organizations/route';
import { actor, manualContent, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';

const URL_BASE = 'https://ai.example.test';
const aiContent = () => ({ ...manualContent(), origin: 'ai_drafted' as const });
const upstreamOk = () => ({ web_content: aiContent(), draft: { ignored: true }, provenance: { provider: 'fictional', model_id: 'model-1', prompt_version: 'p3', sources: ['Source A', { title: 'Source B' }] } });
const valid = { topic: 'Sleep habits', audience: 'Adults', language: 'en', count: 8 };
let store: MemoryPlatformStore, service: PlatformService, fetchMock: jest.Mock;
const respond = (status: number, body: unknown) => Promise.resolve(new Response(typeof body === 'string' ? body : JSON.stringify(body), { status }));
const request = (url: string, body?: unknown, uid = 'clinician_a', key = 'request_1', method = 'POST') => new NextRequest(`http://localhost${url}`, { method, headers: { Authorization: `Bearer ${uid}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
const call = (body?: unknown, uid?: string) => aiDraft(request('/api/v1/professional/questionnaire-drafts/ai', body, uid));
beforeEach(() => {
  process.env.KOI_AI_BASE = URL_BASE;
  store = new MemoryPlatformStore(); registered(store, 'clinician_a'); service = new PlatformService(store, 'test-key-with-more-than-32-characters', () => testTime);
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service, authenticate: async (req: NextRequest) => {
    const uid = req.headers.get('Authorization')?.slice(7); if (!uid || uid === 'invalid') throw new PlatformError(401, 'unauthenticated'); return actor(uid);
  } });
  fetchMock = jest.fn(() => respond(200, upstreamOk())); (global as any).fetch = fetchMock;
});
afterEach(() => { delete process.env.KOI_AI_BASE; jest.useRealTimers(); jest.restoreAllMocks(); });

it('forwards the caller token and target, then returns validated content, provenance and the notice', async () => {
  const response = await call(valid); expect(response.status).toBe(200);
  const data = await response.json();
  expect(Object.keys(data).sort()).toEqual(['content', 'notice', 'provenance']);
  checkSchema('CustomQuestionnaireContent', data.content); expect(data.content.origin).toBe('ai_drafted');
  expect(data.provenance).toEqual({ provider: 'fictional', model_id: 'model-1', prompt_version: 'p3', sources: ['Source A', 'Source B'] });
  expect(data.notice).toBe('AI draft, not validated; the psychologist must review every question');
  expect(response.headers.get('cache-control')).toBe('private, no-store');
  expect(fetchMock).toHaveBeenCalledTimes(1);
  const [url, init] = fetchMock.mock.calls[0];
  expect(url).toBe(`${URL_BASE}/api/v1/ai/questionnaires/generate`);
  expect(init.headers.Authorization).toBe('Bearer clinician_a'); expect(init.signal).toBeInstanceOf(AbortSignal);
  expect(JSON.parse(init.body)).toEqual({ ...valid, target: 'web_platform_0_5' });
  expect(store.count('questionnaires')).toBe(0);
});
it('denies guest, patient, unverified psychologist and unauthenticated callers before any upstream call', async () => {
  store.seed('users', 'guest', { role: 'psychologist' });
  store.seed('accounts', 'patient', { uid: 'patient', state: 'registered', general_access: true, authorization_revision: 1 });
  registered(store, 'pending_pro', 'pending');
  for (const uid of ['guest', 'patient', 'pending_pro']) { const r = await call(valid, uid); expect(r.status).toBe(403); checkSchema('ErrorDTO', await r.json()); }
  expect((await call(valid, 'invalid')).status).toBe(401);
  expect((await aiDraft(new NextRequest('http://localhost/x', { method: 'POST' }))).status).toBe(401);
  expect(fetchMock).not.toHaveBeenCalled();
});
it('requires a recent sign-in and the Idempotency-Key', async () => {
  const stale = new PlatformService(store, 'test-key-with-more-than-32-characters', () => new Date(+testTime + 600_000));
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service: stale, authenticate: async () => actor('clinician_a') });
  expect((await call(valid)).status).toBe(401);
  expect((await aiDraft(request('/x', valid, 'clinician_a', ''))).status).toBe(422);
  expect(fetchMock).not.toHaveBeenCalled();
});
it('returns 503 ai_unavailable when KOI_AI_BASE is unset or not a URL', async () => {
  delete process.env.KOI_AI_BASE; let r = await call(valid);
  expect(r.status).toBe(503); expect((await r.json()).code).toBe('ai_unavailable');
  process.env.KOI_AI_BASE = 'not a url'; r = await call(valid); expect(r.status).toBe(503);
  process.env.KOI_AI_BASE = 'file:///etc'; r = await call(valid); expect(r.status).toBe(503);
  expect(fetchMock).not.toHaveBeenCalled();
});
it.each([
  ['missing topic', { audience: 'a', language: 'en', count: 3 }], ['blank topic', { ...valid, topic: '   ' }], ['topic too long', { ...valid, topic: 'x'.repeat(201) }],
  ['non-string audience', { ...valid, audience: 5 }], ['bad language', { ...valid, language: 'fr' }], ['count 0', { ...valid, count: 0 }], ['count 21', { ...valid, count: 21 }],
  ['count fraction', { ...valid, count: 2.5 }], ['count string', { ...valid, count: '8' }], ['extra field', { ...valid, target: 'other' }], ['bad question_types', { ...valid, question_types: ['essay'] }],
  ['empty question_types', { ...valid, question_types: [] }], ['array body', [valid]], ['null body', null],
])('rejects invalid body: %s', async (_name, body) => {
  expect((await call(body)).status).toBe(422); expect(fetchMock).not.toHaveBeenCalled();
});
it('trims strings and forwards the optional fields', async () => {
  await call({ ...valid, topic: '  Sleep  ', purpose: ' screening ', tone: 'warm', question_types: ['likert', 'yes_no'] });
  expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toMatchObject({ topic: 'Sleep', purpose: 'screening', tone: 'warm', question_types: ['likert', 'yes_no'], target: 'web_platform_0_5' });
});
describe('upstream error mapping', () => {
  it.each([[401, 403, 'forbidden'], [403, 403, 'forbidden'], [429, 429, 'rate_limited'], [500, 502, 'ai_provider_error'], [503, 502, 'ai_provider_error'], [404, 502, 'ai_provider_error']])('%i -> %i %s', async (up, status, code) => {
    fetchMock.mockImplementation(() => respond(up, { code: 'secret_internal', detail: 'SECRET-BODY stack trace' }));
    const r = await call(valid); const text = await r.text();
    expect(r.status).toBe(status); expect(JSON.parse(text).code).toBe(code); expect(text).not.toContain('SECRET'); expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it('422 keeps the AI service error code but nothing else', async () => {
    fetchMock.mockImplementation(() => respond(422, { code: 'unsafe_topic', message: 'SECRET-BODY' }));
    const r = await call(valid); const text = await r.text();
    expect(r.status).toBe(422); expect(JSON.parse(text).code).toBe('unsafe_topic'); expect(text).not.toContain('SECRET');
    fetchMock.mockImplementation(() => respond(422, 'not json')); expect((await (await call(valid)).json()).code).toBe('invalid_request');
  });
  it('maps network failure and the 60-second timeout to 502 ai_provider_error without retrying', async () => {
    fetchMock.mockImplementation(() => Promise.reject(new Error('connect ECONNREFUSED secret-host')));
    let r = await call(valid); expect(r.status).toBe(502); expect(await r.text()).not.toContain('secret-host');
    jest.useFakeTimers(); fetchMock.mockClear();
    fetchMock.mockImplementation((_u: string, init: RequestInit) => new Promise((_res, rej) => init.signal!.addEventListener('abort', () => rej(new DOMException('aborted', 'AbortError')))));
    const pending = call(valid); await jest.advanceTimersByTimeAsync(59_000); expect(fetchMock).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1_500); r = await pending; expect(r.status).toBe(502); expect((await r.json()).code).toBe('ai_provider_error'); expect(fetchMock).toHaveBeenCalledTimes(1);
  });
  it.each([
    ['schema-invalid', { ...upstreamOk(), web_content: { kind: 'nope' } }], ['missing content', { provenance: upstreamOk().provenance }],
    ['origin manual', { ...upstreamOk(), web_content: manualContent() }],
    ['empty text', { ...upstreamOk(), web_content: { ...aiContent(), title: { en: '' } } }], ['bad provenance', { ...upstreamOk(), provenance: { provider: 3 } }],
    ['extra property in content', { ...upstreamOk(), web_content: { ...aiContent(), injected: true } }],
  ])('rejects invalid upstream content: %s', async (_n, body) => {
    fetchMock.mockImplementation(() => respond(200, body)); const r = await call(valid);
    expect(r.status).toBe(502); expect((await r.json()).code).toBe('ai_provider_error');
  });
});
it('never logs bodies or tokens', async () => {
  const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map(m => jest.spyOn(console, m).mockImplementation(() => {}));
  await call({ ...valid, topic: 'PRIVATE-TOPIC' });
  fetchMock.mockImplementation(() => respond(500, 'SECRET-BODY')); await call({ ...valid, topic: 'PRIVATE-TOPIC' });
  fetchMock.mockImplementation(() => Promise.reject(new Error('boom'))); await call({ ...valid, topic: 'PRIVATE-TOPIC' });
  for (const spy of spies) expect(spy).not.toHaveBeenCalled();
});

describe('AI-drafted lifecycle: save yes, publish no until the server-side review confirmation', () => {
  let org: string, id: string;
  const setup = async () => {
    org = (await (await organization(request('/api/v1/professional/organizations', { name: 'Fictional practice' }))).json()).id;
    const r = await create(request('/api/v1/professional/questionnaires', { organization_id: org, content: aiContent() })); expect(r.status).toBe(201);
    id = (await r.json()).id;
  };
  const params = () => ({ params: { id } });
  it('saves ai_drafted, blocks publish, refuses a browser-side origin flip, then confirms and publishes', async () => {
    await setup();
    expect(store.read<any>('questionnaires', id).content.origin).toBe('ai_drafted');
    const blocked = await publish(request(`/p`, { expected_revision: 1, expected_content_sha256: hash(aiContent()) }, 'clinician_a', 'pub_1'), params());
    expect(blocked.status).toBe(422); expect(store.count('questionnaire_versions')).toBe(0);
    expect((await update(request('/u', { expected_revision: 1, content: manualContent() }, 'clinician_a', 'upd_1', 'PUT'), params())).status).toBe(422);
    expect((await update(request('/u', { expected_revision: 1, content: { ...aiContent(), title: { en: 'Edited' } } }, 'clinician_a', 'upd_2', 'PUT'), params())).status).toBe(200);
    expect(store.read<any>('questionnaires', id).content.origin).toBe('ai_drafted');
    // stale revision cannot be confirmed
    expect((await confirmReview(request('/c', { expected_revision: 1 }, 'clinician_a', 'conf_0'), params())).status).toBe(409);
    const confirmed = await confirmReview(request('/c', { expected_revision: 2 }, 'clinician_a', 'conf_1'), params());
    expect(confirmed.status).toBe(200); const draft = await confirmed.json();
    expect(draft.revision).toBe(3); expect(draft.content.origin).toBe('manual'); expect(draft.content.title.en).toBe('Edited');
    const audit = [...store.data.entries()].filter(([k, v]) => k.startsWith('audit_events/') && (v as any).operation === 'confirmAiDraftReview');
    expect(audit).toHaveLength(1); expect(audit[0][1]).toMatchObject({ actor_uid: 'clinician_a', organization_id: org, resource_id: id });
    // idempotent replay returns the same result and writes nothing new
    const replay = await confirmReview(request('/c', { expected_revision: 2 }, 'clinician_a', 'conf_1'), params()); expect(await replay.json()).toEqual(draft);
    expect([...store.data.entries()].filter(([k, v]) => k.startsWith('audit_events/') && (v as any).operation === 'confirmAiDraftReview')).toHaveLength(1);
    // a second confirmation with a new key finds a manual draft
    expect((await confirmReview(request('/c', { expected_revision: 3 }, 'clinician_a', 'conf_2'), params())).status).toBe(409);
    const published = await publish(request('/p', { expected_revision: 3, expected_content_sha256: hash(draft.content) }, 'clinician_a', 'pub_2'), params());
    expect(published.status).toBe(200);
  });
  it('confirm: strict body, own draft only, authority and fresh sign-in required', async () => {
    await setup(); registered(store, 'clinician_b');
    for (const body of [{}, { expected_revision: 0 }, { expected_revision: '1' }, { expected_revision: 1, origin: 'manual' }, [1]]) expect((await confirmReview(request('/c', body, 'clinician_a', 'k_' + Math.random().toString(36).slice(2)), params())).status).toBe(422);
    expect((await confirmReview(request('/c', { expected_revision: 1 }, 'clinician_b', 'other_1'), params())).status).toBe(404);
    store.seed('accounts', 'patient', { uid: 'patient', state: 'registered', general_access: true, authorization_revision: 1 });
    expect((await confirmReview(request('/c', { expected_revision: 1 }, 'patient', 'other_2'), params())).status).toBe(403);
    expect((await confirmReview(request('/c', { expected_revision: 1 }, 'invalid', 'other_3'), params())).status).toBe(401);
    expect(store.read<any>('questionnaires', id).content.origin).toBe('ai_drafted');
  });
});
