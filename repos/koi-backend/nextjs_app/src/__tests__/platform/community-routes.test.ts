/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/runtime', () => ({ getPlatformRuntime: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { CommunityService } from '@/lib/platform/server/community';
import { PlatformError } from '@/lib/platform/server/errors';
import { GET as experts } from '@/app/api/v1/experts/route';
import { PUT as profile } from '@/app/api/v1/professional/profile/route';
import { POST as message } from '@/app/api/v1/messages/route';
import { GET as messages } from '@/app/api/v1/relationships/[id]/messages/route';
import { POST as appointment } from '@/app/api/v1/appointments/route';
import { POST as transition } from '@/app/api/v1/appointments/[id]/transition/route';
import { GET as notifications } from '@/app/api/v1/notifications/route';
import { POST as read } from '@/app/api/v1/notifications/[id]/read/route';
import { GET as analytics } from '@/app/api/v1/professional/analytics/route';
import { actor, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';
let service: CommunityService, org: string, relationship: string;
const req = (method = 'GET', body?: unknown, uid = 'patient', query = '', key = 'request') => new NextRequest(`http://localhost/api/v1/test${query}`, { method, headers: { Authorization: `Bearer ${uid}`, 'Content-Type': 'application/json', 'Idempotency-Key': key }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
beforeEach(async () => {
  const store = new MemoryPlatformStore(); registered(store, actor().uid); registered(store, 'patient', 'pending'); store.seed('accounts', 'patient', { ...store.read<any>('accounts', 'patient'), general_access: true });
  service = new CommunityService(store, 'test-cursor-key-at-least-thirty-two-characters', () => testTime);
  (getPlatformRuntime as jest.Mock).mockReturnValue({ service, authenticate: async (request: NextRequest) => { const uid = request.headers.get('Authorization')?.slice(7); if (!uid || uid === 'invalid') throw new PlatformError(401, 'unauthenticated'); return actor(uid); } });
  org = (await service.createOrganization(actor(), { name: 'Practice' }, 'org')).id;
  const invitation = await service.createInvitation(actor(), { organization_id: org, expires_at: new Date(+testTime + 100000).toISOString() }, 'invite');
  relationship = (await service.redeemInvitation(actor('patient'), invitation.token, { consent_version: 'care-consent-v1' }, 'redeem') as any).relationship_id;
});
it('executes profile, directory, message, appointment and inbox HTTP handlers with strict DTOs', async () => {
  expect((await profile(req('PUT', { organization_id: org, display_name: 'Fictional', bio: 'Fictional practice', discoverable: true, accepting_new_patients: true, expected_revision: 0 }, actor().uid))).status).toBe(200);
  const directory = await experts(req()); expect((await directory.json()).items).toHaveLength(1); expect(directory.headers.get('Cache-Control')).toBe('private, no-store');
  const m = await message(req('POST', { relationship_id: relationship, body: 'Hello' })); expect(m.status).toBe(201);
  const page = await messages(req(), { params: { id: relationship } }); expect((await page.json()).items).toHaveLength(1);
  const noticePage = await notifications(req('GET', undefined, actor().uid)); const n = (await noticePage.json()).items[0];
  const readAck = await read(req('POST', {}, actor().uid), { params: { id: n.id } }); expect((await readAck.json()).read_at).toBe(testTime.toISOString());
  const a = await appointment(req('POST', { relationship_id: relationship })); expect(a.status).toBe(201); const id = (await a.json()).id;
  expect((await transition(req('POST', { expected_revision: 1, to_state: 'cancelled' }), { params: { id } })).status).toBe(200);
  expect((await analytics(req('GET', undefined, 'patient', `?organization_id=${org}`))).status).toBe(403);
});
it('rejects unknown queries, forged identity fields and malformed credentials without leaking error details', async () => {
  expect((await experts(new NextRequest('http://localhost/api/v1/experts'))).status).toBe(401);
  expect((await experts(req('GET', undefined, 'invalid'))).status).toBe(401);
  expect((await experts(req('GET', undefined, 'patient', '?limit=1&limit=2'))).status).toBe(422);
  expect((await experts(req('GET', undefined, 'patient', '?organization_id=forged'))).status).toBe(422);
  expect((await message(req('POST', { relationship_id: relationship, body: 'Hello', sender_uid: actor().uid }))).status).toBe(422);
  (getPlatformRuntime as jest.Mock).mockImplementation(() => { throw new Error('secret provider token and score'); });
  const result = await experts(req()); expect(result.status).toBe(503); expect(JSON.stringify(await result.json())).not.toMatch(/secret|score|provider/);
});
