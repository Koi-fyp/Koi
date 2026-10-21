/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/runtime', () => ({ getPlatformRuntime: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { LifecycleService } from '@/lib/platform/server/lifecycle';
import { PlatformError } from '@/lib/platform/server/errors';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import { POST as feedback } from '@/app/api/v1/professional/evaluations/[id]/ai-feedback/route';
import { POST as invite } from '@/app/api/v1/professional/patient-invitations/route';
import { POST as redeem } from '@/app/api/v1/patient-invitations/[token]/redeem/route';
import { POST as assign } from '@/app/api/v1/professional/assignments/route';
import { GET as assignments } from '@/app/api/v1/patient/assignments/route';
import { GET as detail } from '@/app/api/v1/patient/assignments/[id]/route';
import { PATCH as save } from '@/app/api/v1/patient/attempts/[id]/route';
import { POST as submit } from '@/app/api/v1/patient/attempts/[id]/submit/route';
import { GET as workspace } from '@/app/api/v1/professional/submissions/[id]/workspace/route';
import { actor, manualContent, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';

let service: LifecycleService, store: MemoryPlatformStore, evaluationId: string, sid: string, assignmentId: string;
const req = (method = 'GET', body?: unknown, uid = 'patient', key = 'request') => new NextRequest('http://localhost/api/v1/test', { method, headers: { Authorization: `Bearer ${uid}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
const pro = actor().uid;
const send = (body: unknown, uid = pro, key = 'feedback-1', id = evaluationId) => feedback(req('POST', body, uid, key), { params: { id } });
const valid = { rating: 4, tags: ['Accurate', 'Helpful follow-ups'], comment: 'Useful clarifying points.' };

beforeEach(async () => {
  store = new MemoryPlatformStore(); registered(store, pro); registered(store, 'patient', 'pending'); registered(store, 'other_psychologist');
  store.seed('accounts', 'patient', { ...store.read<any>('accounts', 'patient'), general_access: true });
  service = new LifecycleService(store, 'test-cursor-key-at-least-thirty-two-characters', () => testTime);
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service, authenticate: async (request: NextRequest) => { const uid = request.headers.get('Authorization')?.slice(7); if (!uid || uid === 'invalid') throw new PlatformError(401, 'unauthenticated'); return actor(uid); } });
  const org = (await service.createOrganization(actor(), { name: 'Practice' }, 'org')).id;
  const content = manualContent(), draft = await service.createDraft(actor(), { organization_id: org, content }, 'draft');
  const vid = (await service.publish(actor(), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish')).id;
  const link = await (await invite(req('POST', { organization_id: org, expires_at: new Date(+testTime + 100000).toISOString() }, pro))).json();
  await redeem(req('POST', { consent_version: 'care-consent-v1' }), { params: { token: link.token } });
  assignmentId = (await (await assign(req('POST', { organization_id: org, questionnaire_version_id: vid, target: { kind: 'all_active' } }, pro))).json()).assignment_ids[0];
  const value = await (await detail(req(), { params: { id: assignmentId } })).json();
  await save(req('PATCH', { expected_revision: 0, answers: [{ question_id: 'question_1', type: 'short_text', value: 'Patient response' }] }), { params: { id: value.attempt.id } });
  await submit(req('POST', { expected_revision: 1 }), { params: { id: value.attempt.id } });
  sid = (await service.list(actor(), 'submissions', org)).items[0].id; evaluationId = `evaluation_${hash(sid)}`;
});

it('stores one owner-only note in ai_feedback_notes with the agreed fields and audits it', async () => {
  const response = await send(valid); expect(response.status).toBe(200);
  expect(response.headers.get('cache-control')).toBe('private, no-store');
  const note = await response.json();
  expect(note).toEqual({ evaluation_id: evaluationId, rating: 4, tags: ['Accurate', 'Helpful follow-ups'], comment: 'Useful clarifying points.', created_at: testTime.toISOString(), psychologist_uid: pro });
  expect(store.count('ai_feedback_notes')).toBe(1); expect(store.count('ai_feedback')).toBe(0);
  expect([...store.data.entries()].some(([k, v]: [string, any]) => k.startsWith('audit_events/') && v.operation === 'createAiFeedbackNote' && v.resource_id === evaluationId)).toBe(true);
});
it('denies patients, guests, unauthenticated callers and other psychologists', async () => {
  expect((await send(valid, 'patient')).status).toBe(403);
  expect((await send(valid, 'guest')).status).toBe(403);
  expect((await send(valid, 'invalid')).status).toBe(401);
  expect((await feedback(new NextRequest('http://localhost/x', { method: 'POST', body: JSON.stringify(valid) }), { params: { id: evaluationId } })).status).toBe(401);
  const other = await send(valid, 'other_psychologist'); expect([403, 404]).toContain(other.status); checkSchema<any>('ErrorDTO', await other.json());
  expect(store.count('ai_feedback_notes')).toBe(0);
});
it.each([
  ['rating 0', { ...valid, rating: 0 }], ['rating 6', { ...valid, rating: 6 }], ['fractional rating', { ...valid, rating: 3.5 }],
  ['unknown tag', { ...valid, tags: ['Great'] }], ['duplicate tag', { ...valid, tags: ['Accurate', 'Accurate'] }],
  ['comment over 500', { ...valid, comment: 'x'.repeat(501) }], ['extra field', { ...valid, score: 9 }], ['array body', []],
])('rejects an invalid body (%s) with 422', async (_name, body) => {
  expect((await send(body)).status).toBe(422); expect(store.count('ai_feedback_notes')).toBe(0);
});
it('is idempotent: a retry and a second send both return the first note and replace nothing', async () => {
  const first = await (await send(valid)).json();
  expect(await (await send(valid)).json()).toEqual(first);
  const second = await send({ rating: 1, tags: ['Unsafe wording'] }, pro, 'feedback-2');
  expect(second.status).toBe(200); expect(await second.json()).toEqual(first);
  expect(store.count('ai_feedback_notes')).toBe(1);
  expect(store.read<any>('ai_feedback_notes', `feedback_${hash([evaluationId, pro])}`).rating).toBe(4);
});
it('never appears in any patient DTO, nor in the professional workspace payload', async () => {
  await send(valid);
  for (const response of [await assignments(req()), await detail(req(), { params: { id: assignmentId } })]) {
    const text = JSON.stringify(await response.json());
    expect(text).not.toMatch(/rating|Helpful follow-ups|Useful clarifying|ai_feedback/);
  }
  expect(JSON.stringify(await (await workspace(req('GET', undefined, pro), { params: { id: sid } })).json())).not.toMatch(/Useful clarifying|ai_feedback/);
});
