/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/runtime', () => ({ getPlatformRuntime: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { LifecycleService } from '@/lib/platform/server/lifecycle';
import { PlatformError } from '@/lib/platform/server/errors';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import { POST as invite } from '@/app/api/v1/professional/patient-invitations/route';
import { POST as redeem } from '@/app/api/v1/patient-invitations/[token]/redeem/route';
import { POST as assign } from '@/app/api/v1/professional/assignments/route';
import { GET as assignments } from '@/app/api/v1/patient/assignments/route';
import { GET as detail } from '@/app/api/v1/patient/assignments/[id]/route';
import { PATCH as save } from '@/app/api/v1/patient/attempts/[id]/route';
import { POST as submit } from '@/app/api/v1/patient/attempts/[id]/submit/route';
import { GET as workspace } from '@/app/api/v1/professional/submissions/[id]/workspace/route';
import { POST as close } from '@/app/api/v1/professional/patient-relationships/[id]/close/route';
import { GET as events } from '@/app/api/v1/me/access-events/route';
import { actor, manualContent, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';
let service: LifecycleService, store: MemoryPlatformStore, org: string, vid: string;
const req = (method = 'GET', body?: unknown, uid = 'patient', key = 'request', query = '') => new NextRequest(`http://localhost/api/v1/test${query}`, { method, headers: { Authorization: `Bearer ${uid}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
beforeEach(async () => {
  store = new MemoryPlatformStore(); registered(store, actor().uid); registered(store, 'patient', 'pending'); store.seed('accounts', 'patient', { ...store.read<any>('accounts', 'patient'), general_access: true });
  service = new LifecycleService(store, 'test-cursor-key-at-least-thirty-two-characters', () => testTime);
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service, authenticate: async (request: NextRequest) => { const uid = request.headers.get('Authorization')?.slice(7); if (!uid || uid === 'invalid') throw new PlatformError(401, 'unauthenticated'); return actor(uid); } });
  org = (await service.createOrganization(actor(), { name: 'Practice' }, 'org')).id;
  const content = manualContent(), draft = await service.createDraft(actor(), { organization_id: org, content }, 'draft');
  vid = (await service.publish(actor(), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish')).id;
});
it('executes actual HTTP handlers from invitation through acknowledgement, protected review and revocation', async () => {
  const invitation = await invite(req('POST', { organization_id: org, expires_at: new Date(+testTime + 100000).toISOString() }, actor().uid)); expect(invitation.status).toBe(201); const link = await invitation.json(); checkSchema<any>('InvitationCreatedDTO', link);
  const relationship = await redeem(req('POST', { consent_version: 'care-consent-v1' }), { params: { token: link.token } }); expect(relationship.status).toBe(200); const r = await relationship.json();
  const batch = await assign(req('POST', { organization_id: org, questionnaire_version_id: vid, target: { kind: 'all_active' } }, actor().uid)); expect(batch.status).toBe(200); const ids = await batch.json();
  const list = await assignments(req()); checkSchema<any>('PatientAssignmentListDTO', await list.json());
  const d = await detail(req(), { params: { id: ids.assignment_ids[0] } }); const value = await d.json(); checkSchema<any>('PatientAssignmentDetailDTO', value);
  expect((await save(req('PATCH', { expected_revision: 0, answers: [{ question_id: 'question_1', type: 'short_text', value: 'Patient response' }] }), { params: { id: value.attempt.id } })).status).toBe(200);
  const response = await submit(req('POST', { expected_revision: 1 }), { params: { id: value.attempt.id } }); expect(response.status).toBe(200); const ack = await response.json(); checkSchema<any>('PatientSubmitAckDTO', ack);
  const duplicate = await submit(req('POST', { expected_revision: 1 }, 'patient', 'duplicate'), { params: { id: value.attempt.id } }); expect(await duplicate.json()).toEqual(ack); expect(store.count('ai_jobs')).toBe(1);
  const sid = (await service.list(actor(), 'submissions', org)).items[0].id;
  expect((await workspace(req(), { params: { id: sid } })).status).toBe(403);
  const pro = await workspace(req('GET', undefined, actor().uid), { params: { id: sid } }); checkSchema<any>('SubmissionWorkspaceDTO', await pro.json());
  expect((await close(req('POST', { expected_revision: 1 }, actor().uid), { params: { id: r.relationship_id } })).status).toBe(200);
  const denied = await detail(req(), { params: { id: ids.assignment_ids[0] } }); expect(denied.status).toBe(403); checkSchema<any>('ErrorDTO', await denied.json());
  for (const r of [d, list, response, denied]) { expect(r.headers.get('cache-control')).toBe('private, no-store'); expect(r.headers.get('vary')).toBe('Authorization'); }
});
it('rejects malformed/array requests and unauthorized mutations; sanitizes provider diagnostics', async () => {
  expect((await assignments(new NextRequest('http://localhost/api/v1/patient/assignments'))).status).toBe(401);
  for (const body of [[], { expected_revision: 0, score: 9 }]) expect((await save(req('PATCH', body), { params: { id: 'attempt' } })).status).toBe(422);
  for (const query of ['?limit=101', '?limit=1&limit=2', '?organization_id=foreign', '?cursor=bad']) expect((await assignments(req('GET', undefined, 'patient', 'key', query))).status).toBe(422);
  jest.spyOn(service, 'list').mockRejectedValueOnce(new Error('PRIVATE_AI_SCORE_KEY'));
  const response = await assignments(req()); expect(response.status).toBe(503); expect(JSON.stringify(await response.json())).not.toContain('PRIVATE');
});
it('streams authorization hints only, never content, and closes on cancellation', async () => {
  const controller = new AbortController();
  const response = await events(new NextRequest('http://localhost/api/v1/me/access-events', { headers: { Authorization: 'Bearer patient' }, signal: controller.signal }));
  expect(response.headers.get('content-type')).toBe('text/event-stream');
  const reader = response.body!.getReader(), chunk = await reader.read(), text = new TextDecoder().decode(chunk.value);
  expect(text).toContain('authorization_changed'); expect(text).not.toMatch(/answers|score|interpretation|patient_uid|job/);
  const data = JSON.parse(text.split('data: ')[1].trim()); checkSchema<any>('AccessChangedEventDTO', data);
  controller.abort(); await reader.cancel();
});
