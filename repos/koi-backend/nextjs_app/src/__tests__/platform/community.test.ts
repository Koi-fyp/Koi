/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
import { MemoryPlatformStore, registered, actor, testTime, manualContent } from '../../../test/platform-memory';
import { hash } from '@/lib/platform/server/contract';
import { CommunityService } from '@/lib/platform/server/community';
let store: MemoryPlatformStore, service: CommunityService, relationship: string;
const pro = actor(), patient = actor('patient_a'), stranger = actor('patient_b');
beforeEach(async () => {
  store = new MemoryPlatformStore(); service = new CommunityService(store, 'test-secret-at-least-thirty-two-characters', () => testTime);
  registered(store, pro.uid); registered(store, 'clinician_b');
  for (const p of [patient, stranger]) { registered(store, p.uid, 'pending'); store.seed('accounts', p.uid, { ...store.read<any>('accounts', p.uid), general_access: true }); }
  const org = await service.createOrganization(pro, { name: 'Practice' }, 'org');
  const invite = await service.createInvitation(pro, { organization_id: org.id, intended_uid: patient.uid, expires_at: new Date(+testTime + 86400000).toISOString() }, 'invite');
  const ack: any = await service.redeemInvitation(patient, invite.token, { consent_version: 'care-consent-v1' }, 'redeem'); relationship = ack.relationship_id;
});
it('creates one message and one notification on concurrent duplicate delivery', async () => {
  const body = { relationship_id: relationship, body: 'Hello' };
  const [a, b] = await Promise.all([service.sendMessage(patient, body, 'send'), service.sendMessage(patient, body, 'send')]);
  expect(a).toEqual(b); expect(store.count('messages')).toBe(1); expect(store.count('notifications')).toBe(1);
  const page: any = await service.notifications(pro); expect(page.items).toHaveLength(1); expect(page.items[0].reference).toEqual({ message_id: a.id });
  expect(await service.notifications(patient)).toEqual({ items: [], next_cursor: null });
  await expect(service.sendMessage(patient, { ...body, body: 'Changed' }, 'send')).rejects.toMatchObject({ status: 409 });
});
it('denies cross-patient and cross-practice reads, writes and forged notification IDs', async () => {
  await service.sendMessage(patient, { relationship_id: relationship, body: 'Private' }, 'send');
  const notice: any = await service.notifications(pro);
  for (const a of [stranger, actor('clinician_b')]) {
    await expect(service.conversation(a, relationship, 'messages')).rejects.toMatchObject({ status: 404 });
    await expect(service.sendMessage(a, { relationship_id: relationship, body: 'forged' }, 'send')).rejects.toMatchObject({ status: 404 });
    await expect(service.notifications(a, 25, undefined, notice.items[0].id)).rejects.toMatchObject({ status: 404 });
  }
});
it('revokes existing messages, appointment mutations, receipt replays and notifications on closure', async () => {
  const body = { relationship_id: relationship, body: 'Hello' };
  await service.sendMessage(patient, body, 'send');
  const a = await service.appointment(patient, { relationship_id: relationship }, 'request');
  await service.closeRelationship(pro, relationship, { expected_revision: 1 }, 'close');
  await expect(service.conversation(patient, relationship, 'messages')).rejects.toMatchObject({ status: 403 });
  await expect(service.sendMessage(patient, body, 'send')).rejects.toMatchObject({ status: 403 });
  await expect(service.appointment(patient, { expected_revision: 1, to_state: 'cancelled' }, 'cancel', a.id)).rejects.toMatchObject({ status: 403 });
  expect((await service.notifications(pro) as any).items).toEqual([]);
});
it('requires patient confirmation, rejects conflicting revisions and terminal reopening', async () => {
  const a = await service.appointment(patient, { relationship_id: relationship }, 'request');
  const proposal = { expected_revision: 1, to_state: 'proposed', starts_at: new Date(+testTime + 3600000).toISOString(), ends_at: new Date(+testTime + 7200000).toISOString() };
  await expect(service.appointment(patient, proposal, 'bad', a.id)).rejects.toMatchObject({ status: 409 });
  const b = await service.appointment(pro, proposal, 'propose', a.id);
  await expect(service.appointment(pro, { expected_revision: 2, to_state: 'confirmed' }, 'bad', a.id)).rejects.toMatchObject({ status: 409 });
  const races = await Promise.allSettled(['confirmed', 'cancelled'].map(to_state => service.appointment(patient, { expected_revision: b.revision, to_state }, to_state, a.id)));
  expect(races.filter(r => r.status === 'fulfilled')).toHaveLength(1);
  await expect(service.appointment(pro, { expected_revision: 3, to_state: 'completed' }, 'early', a.id)).rejects.toMatchObject({ status: 409 });
  await service.appointment(patient, { expected_revision: 3, to_state: 'cancelled' }, 'cancel', a.id);
  await expect(service.appointment(pro, { ...proposal, expected_revision: 4 }, 'reopen', a.id)).rejects.toMatchObject({ status: 409 });
});
it('strips nested unexpected data and binds pagination to participants', async () => {
  for (let i = 0; i < 3; i++) await service.sendMessage(pro, { relationship_id: relationship, body: String(i) }, `send_${i}`);
  const first: any = await service.conversation(patient, relationship, 'messages', 1);
  const m = store.read('messages', first.items[0].id); store.seed('messages', m.id, { ...m, clinician_evaluation: { score: 90 } });
  expect(JSON.stringify(await service.conversation(patient, relationship, 'messages'))).not.toContain('score');
  await expect(service.conversation(pro, relationship, 'messages', 1, first.next_cursor)).rejects.toMatchObject({ status: 422 });
  const n: any = await service.notifications(patient); const record = store.read('notifications', n.items[0].id);
  store.seed('notifications', record.id, { ...record, reference: { ...record.reference, score: 90 }, interpretation: 'secret' });
  expect(JSON.stringify(await service.notifications(patient))).not.toMatch(/score|interpretation/);
  const read: any = await service.notifications(patient, 25, undefined, record.id);
  expect(await service.notifications(patient, 25, undefined, record.id)).toEqual(read);
});
it('authorizes profile edits and discovery from server records, enforces accepting applications', async () => {
  const org = store.read<any>('patient_relationships', relationship).organization_id;
  const body = { organization_id: org, display_name: 'Dr Fictional', bio: 'Fictional practice', discoverable: true, accepting_new_patients: false, expected_revision: 0 };
  await service.profile(pro, org, body, 'profile');
  expect((await service.experts(patient) as any).items[0].display_name).toBe('Dr Fictional');
  await expect(service.experts(actor('anonymous'))).rejects.toMatchObject({ status: 403 });
  await expect(service.profile(stranger, org, body, 'profile')).rejects.toMatchObject({ status: 403 });
  await expect(service.profile(actor('clinician_b'), org, body, 'profile')).rejects.toMatchObject({ status: 404 });
  await expect(service.createConnection(stranger, { psychologist_uid: pro.uid, consent_version: 'care-consent-v1' }, 'apply')).rejects.toMatchObject({ status: 403 });
  await service.profile(pro, org, { ...body, accepting_new_patients: true, expected_revision: 1 }, 'accepting');
  const c = await service.createConnection(stranger, { psychologist_uid: pro.uid, consent_version: 'care-consent-v1' }, 'apply');
  expect((await service.notifications(pro) as any).items.some((n: any) => n.kind === 'application_state')).toBe(true);
  await service.transitionConnection(stranger, c.id, { expected_revision: 1, to_state: 'awaiting_demo_payment' }, 'continue');
  await service.transitionConnection(stranger, c.id, { expected_revision: 2 }, 'demo', true);
  await service.transitionConnection(stranger, c.id, { expected_revision: 2 }, 'demo', true);
  expect(store.count('demo_payments')).toBe(1);
  expect((await service.capabilities(stranger)).active_patient_relationships).toHaveLength(0);
  store.seed('psychologist_verifications', pro.uid, { ...store.read<any>('psychologist_verifications', pro.uid), state: 'suspended' });
  expect((await service.experts(patient) as any).items).toHaveLength(0);
});
it('counts authoritative submissions and isolates assignment and professional submission notifications', async () => {
  const org = store.read<any>('patient_relationships', relationship).organization_id, content = manualContent();
  const d = await service.createDraft(pro, { organization_id: org, content }, 'draft');
  const v = await service.publish(pro, d.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish');
  const batch: any = await service.assign(pro, { organization_id: org, questionnaire_version_id: v.id, target: { kind: 'selected', relationship_ids: [relationship] } }, 'assign');
  const inbox: any = await service.notifications(patient); expect(inbox.items).toHaveLength(1); expect(inbox.items[0].kind).toBe('assignment');
  expect(await service.notifications(patient)).toEqual(inbox); expect(store.count('notifications')).toBe(1);
  const detail: any = await service.patientDetail(patient, batch.assignment_ids[0]);
  await service.saveAttempt(patient, detail.attempt.id, { expected_revision: 0, answers: [{ question_id: 'question_1', type: 'short_text', value: 'Fictional' }] }, 'save');
  await service.saveAttempt(patient, detail.attempt.id, { expected_revision: 1 }, 'submit', true);
  await service.saveAttempt(patient, detail.attempt.id, { expected_revision: 1 }, 'duplicate', true);
  const stats = await service.analytics(pro, org); expect(stats.series[0]).toMatchObject({ enrolled: 1, submitted: 1, scoring_version: 'not_applicable' });
  expect(stats.series[0].points).toEqual([{ date: '2026-10-19', submitted: 1 }]);
  expect((await service.submissionNotices(pro, org)).items).toHaveLength(1);
  for (const a of [patient, stranger, actor('clinician_b')]) {
    await expect(service.analytics(a, org)).rejects.toMatchObject({ status: a.uid === 'clinician_b' ? 404 : 403 });
    await expect(service.submissionNotices(a, org)).rejects.toBeDefined();
    await expect(service.patientHistory(a, relationship)).rejects.toMatchObject({ status: 404 });
  }
  expect(JSON.stringify(await service.notifications(patient))).not.toMatch(/submission_id|evaluation|score|interpretation|job/);
  await expect(service.archive(pro, relationship, { expected_revision: 0, archived: true }, 'early')).rejects.toMatchObject({ status: 409 });
  await service.closeRelationship(pro, relationship, { expected_revision: 1 }, 'close');
  await service.archive(pro, relationship, { expected_revision: 0, archived: true }, 'archive');
  expect(await service.archive(pro, relationship)).toMatchObject({ archived: true, revision: 1 });
  expect((await service.patientHistory(pro, relationship)).items).toHaveLength(1);
  expect((await service.analytics(pro, org)).series[0].submitted).toBe(1);
});
