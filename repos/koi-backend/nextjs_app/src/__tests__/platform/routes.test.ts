/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/runtime', () => ({ getPlatformRuntime: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { PlatformService } from '@/lib/platform/server/service';
import { PlatformError } from '@/lib/platform/server/errors';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import { GET as capabilities } from '@/app/api/v1/me/capabilities/route';
import { POST as organization } from '@/app/api/v1/professional/organizations/route';
import { POST as create, GET as list } from '@/app/api/v1/professional/questionnaires/route';
import { GET as get, PUT as update } from '@/app/api/v1/professional/questionnaires/[id]/route';
import { POST as publish } from '@/app/api/v1/professional/questionnaires/[id]/publish/route';
import { GET as version } from '@/app/api/v1/professional/questionnaire-versions/[id]/route';
import { actor, manualContent, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';
import type { OrganizationDTO, DraftDTO, VersionDTO } from '@/lib/platform/types';

let store: MemoryPlatformStore, service: PlatformService;
const request = (method = 'GET', body?: unknown, uid = 'clinician_a', key = 'request_1', url = '/api/v1/test') => new NextRequest(`http://localhost${url}`, { method, headers: { Authorization: `Bearer ${uid}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
beforeEach(() => {
  store = new MemoryPlatformStore(); registered(store, 'clinician_a'); service = new PlatformService(store, 'test-key-with-more-than-32-characters', () => testTime);
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service, authenticate: async (req: NextRequest) => {
    const uid = req.headers.get('Authorization')?.slice(7); if (!uid || uid === 'invalid') throw new PlatformError(401, 'unauthenticated'); return actor(uid);
  } });
});
it('runs actual route wrappers: organization -> draft -> publish -> GET version, with frozen DTOs and no-store', async () => {
  const caps = await capabilities(request()); checkSchema('CapabilitiesDTO', await caps.json());
  const orgResponse = await organization(request('POST', { name: 'Fictional practice' })); expect(orgResponse.status).toBe(200);
  const org = await orgResponse.json(); checkSchema<OrganizationDTO>('OrganizationDTO', org);
  const content = manualContent(); const draftResponse = await create(request('POST', { organization_id: org.id, content })); expect(draftResponse.status).toBe(201);
  const draft = await draftResponse.json(); checkSchema<DraftDTO>('QuestionnaireDraftDTO', draft);
  const detail = await get(request(), { params: { id: draft.id } }); expect(await detail.json()).toEqual(draft);
  const page = await list(request('GET', undefined, 'clinician_a', 'unused', `/api/v1/professional/questionnaires?organization_id=${org.id}`)); checkSchema('QuestionnaireDraftListDTO', await page.json());
  const published = await publish(request('POST', { expected_revision: 1, expected_content_sha256: hash(content) }), { params: { id: draft.id } });
  const snapshot = await published.json(); checkSchema<VersionDTO>('QuestionnaireVersionDTO', snapshot);
  expect((await update(request('PUT', { expected_revision: 1, content: { ...content, title: { en: 'Later title' } } }), { params: { id: draft.id } })).status).toBe(200);
  const inspected = await version(request(), { params: { id: snapshot.id } }); expect(await inspected.json()).toEqual(snapshot);
  expect(inspected.headers.get('cache-control')).toBe('private, no-store'); expect(inspected.headers.get('vary')).toBe('Authorization');
});
it('denies unauthenticated, invalid-token, custom guest and general callers without touching platform data', async () => {
  expect((await organization(new NextRequest('http://localhost/api/v1/professional/organizations', { method: 'POST' }))).status).toBe(401);
  expect((await organization(request('POST', { name: 'Practice' }, 'invalid'))).status).toBe(401);
  store.seed('users', 'guest', { role: 'psychologist' });
  store.seed('accounts', 'general', { uid: 'general', state: 'registered', general_access: true, authorization_revision: 1 });
  for (const uid of ['guest', 'general']) {
    const result = await organization(request('POST', { name: 'Practice' }, uid)); expect(result.status).toBe(403); checkSchema('ErrorDTO', await result.json());
  }
  expect(store.count('organizations')).toBe(0);
});
it('rejects malformed bodies, forbidden extra fields, oversized content and invalid query pagination', async () => {
  const malformed = new NextRequest('http://localhost/api/v1/professional/organizations', { method: 'POST', headers: { Authorization: 'Bearer clinician_a', 'Content-Type': 'application/json', 'Idempotency-Key': 'one' }, body: '{invalid' });
  expect((await organization(malformed)).status).toBe(422);
  expect((await organization(request('POST', { name: 'Practice', verified: true }))).status).toBe(422);
  expect((await organization(request('POST', [{ name: 'Practice' }]))).status).toBe(422);
  expect((await organization(request('POST', []))).status).toBe(422);
  expect((await organization(request('POST', { name: 'A'.repeat(512_001) }))).status).toBe(422);
  expect((await organization(request('POST', { name: 'Practice' }, 'clinician_a', ''))).status).toBe(422);
  const org = await (await organization(request('POST', { name: 'Practice' }))).json();
  for (const suffix of ['&limit=0', '&limit=101', '&limit=1&limit=2', '&unexpected=x']) expect((await list(request('GET', undefined, 'clinician_a', 'none', `/api/v1/professional/questionnaires?organization_id=${org.id}${suffix}`))).status).toBe(422);
});
it('denies cross-organization GET/PUT/publish/version and sanitizes SDK exceptions', async () => {
  const org = await service.createOrganization(actor(), { name: 'Practice' }, 'org');
  const content = manualContent(), draft = await service.createDraft(actor(), { organization_id: org.id, content }, 'draft');
  const snapshot = await service.publish(actor(), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish');
  registered(store, 'clinician_b');
  expect((await get(request('GET', undefined, 'clinician_b'), { params: { id: draft.id } })).status).toBe(404);
  expect((await update(request('PUT', { expected_revision: 1, content }, 'clinician_b'), { params: { id: draft.id } })).status).toBe(404);
  expect((await publish(request('POST', { expected_revision: 1, expected_content_sha256: hash(content) }, 'clinician_b'), { params: { id: draft.id } })).status).toBe(404);
  expect((await version(request('GET', undefined, 'clinician_b'), { params: { id: snapshot.id } })).status).toBe(404);
  jest.spyOn(service, 'createOrganization').mockRejectedValueOnce(new Error('PRIVATE_DIAGNOSTIC_TOKEN_EVALUATION'));
  const response = await organization(request('POST', { name: 'Practice' })); const error = await response.json();
  expect(response.status).toBe(503); expect(JSON.stringify(error)).not.toMatch(/PRIVATE|TOKEN|EVALUATION/); checkSchema('ErrorDTO', error);
});
