/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
import { MemoryPlatformStore, registered, actor, manualContent, testTime } from '../../../test/platform-memory';
import { LifecycleService } from '@/lib/platform/server/lifecycle';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import type { VersionDTO } from '@/lib/platform/types';
import { answerIssues } from '@/lib/platform/answers';
import base from '../../../contracts/v0.5.0/contracts.schema.json';
import extension from '../../../contracts/v0.5.1/contracts.schema.json';

let store: MemoryPlatformStore, service: LifecycleService, org: string, version: VersionDTO;
const patient = actor('patient_a'), otherPatient = actor('patient_b'), pro = actor(), otherPro = actor('clinician_b');
const answers = [{ question_id: 'question_1', type: 'short_text' as const, value: 'My original answer mentions score as ordinary text.' }];
beforeEach(async () => {
  store = new MemoryPlatformStore(); service = new LifecycleService(store, 'test-secret-at-least-thirty-two-characters', () => testTime);
  registered(store, pro.uid); registered(store, otherPro.uid);
  for (const p of [patient, otherPatient]) { registered(store, p.uid, 'pending'); store.seed('accounts', p.uid, { ...store.read<any>('accounts', p.uid), general_access: true }); }
  org = (await service.createOrganization(pro, { name: 'Practice' }, 'organization')).id;
  store.seed('psychologist_profiles', pro.uid, { organization_id: org, discoverable: true, accepting_new_patients: true });
  const content = manualContent(), draft = await service.createDraft(pro, { organization_id: org, content }, 'draft');
  version = await service.publish(pro, draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish');
});
const invite = (uid = patient.uid, key = 'invite') => service.createInvitation(pro, { organization_id: org, intended_uid: uid, expires_at: new Date(+testTime + 86400000).toISOString() }, key);
const onboard = async (p = patient, key = 'invite') => {
  const link = await invite(p.uid, key);
  return await service.redeemInvitation(p, link.token, { consent_version: 'care-consent-v1' }, `redeem_${key}`) as { relationship_id: string };
};
const assigned = async () => {
  const r = await onboard();
  const batch: any = await service.assign(pro, { organization_id: org, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [r.relationship_id] } }, 'assign');
  const detail = await service.patientDetail(patient, batch.assignment_ids[0]);
  if (!('attempt' in detail)) throw new Error('Expected an open attempt');
  return { r, detail };
};
const submitted = async () => {
  const setup = await assigned();
  await service.saveAttempt(patient, setup.detail.attempt.id, { expected_revision: 0, answers }, 'save');
  const ack = await service.saveAttempt(patient, setup.detail.attempt.id, { expected_revision: 1 }, 'submit', true);
  const s = (await service.list(pro, 'submissions', org)).items[0];
  return { ...setup, ack, s };
};

it('adds schemas without modifying any frozen definition', () => {
  for (const [name, definition] of Object.entries(base.definitions)) expect(extension.definitions[name]).toEqual(definition);
});
it('registers patient capability only through a single-use hashed invitation and preserves the account', async () => {
  const link = await invite(); expect(link.token).toMatch(/^[\w-]{43}$/);
  expect(JSON.stringify([...store.data.values()])).not.toContain(link.token);
  expect(await invite()).toEqual(link);
  await expect(service.redeemInvitation(otherPatient, link.token, { consent_version: 'care-consent-v1' }, 'wrong')).rejects.toMatchObject({ status: 404 });
  const body = { consent_version: 'care-consent-v1' }, ack: any = await service.redeemInvitation(patient, link.token, body, 'redeem');
  expect(await service.redeemInvitation(patient, link.token, body, 'redeem')).toEqual(ack);
  await expect(service.redeemInvitation(patient, link.token, body, 'fresh_key')).rejects.toMatchObject({ status: 409 });
  const next = await invite(patient.uid, 'another'); await service.redeemInvitation(patient, next.token, body, 'another');
  expect(store.count('patient_relationships')).toBe(1);
  expect((await service.capabilities(patient)).active_patient_relationships).toHaveLength(1);
  expect(store.read<any>('accounts', patient.uid)).toMatchObject({ state: 'registered', general_access: true });
  expect(store.count('access_invalidation_outbox')).toBe(1);
});
it('rejects unregistered custom guests, anonymous IDs, professional-only accounts and cross-organization invites', async () => {
  store.seed('users', 'guest', { role: 'patient', isAnonymous: false }); const link = await invite();
  for (const p of [actor('guest'), actor('anonymous'), pro]) await expect(service.redeemInvitation(p, link.token, { consent_version: 'care-consent-v1' }, 'key')).rejects.toMatchObject({ status: 403 });
  await expect(service.createInvitation(otherPro, { organization_id: org, expires_at: new Date(+testTime + 10000).toISOString() }, 'cross')).rejects.toMatchObject({ status: 404 });
});
it('expires and revokes invitations and limits brute-force redemption', async () => {
  const link = await invite(); await service.revokeInvitation(pro, link.invitation_id, { expected_revision: 1 }, 'revoke');
  await expect(service.redeemInvitation(patient, link.token, { consent_version: 'care-consent-v1' }, 'key')).rejects.toMatchObject({ status: 409 });
  const expiry = await invite(patient.uid, 'expires'); const stored = store.read<any>('patient_invitations', expiry.invitation_id);
  store.seed('patient_invitations', expiry.invitation_id, { ...stored, expires_at: new Date(+testTime - 1).toISOString() });
  await expect(service.redeemInvitation(patient, expiry.token, { consent_version: 'care-consent-v1' }, 'expired')).rejects.toMatchObject({ status: 409 });
  for (let i = 0; i < 58; i++) await service.redeemInvitation(patient, 'x'.repeat(43), { consent_version: 'care-consent-v1' }, `bad_${i}`).catch(() => {});
  await expect(service.redeemInvitation(patient, 'x'.repeat(43), { consent_version: 'care-consent-v1' }, 'limited')).rejects.toMatchObject({ status: 429 });
});
it('enforces applications, demo step, acceptance and consent without payment granting rights', async () => {
  let r = await service.createConnection(patient, { psychologist_uid: pro.uid, consent_version: 'care-consent-v1' }, 'application');
  expect((await service.list(otherPatient, 'connections')).items).toEqual([]);
  await expect(service.transitionConnection(pro, r.id, { expected_revision: r.revision, to_state: 'accepted' }, 'early')).rejects.toMatchObject({ status: 403 });
  r = await service.transitionConnection(patient, r.id, { expected_revision: r.revision, to_state: 'awaiting_demo_payment' }, 'continue');
  await expect(service.transitionConnection(patient, r.id, { expected_revision: r.revision, to_state: 'pending_psychologist_review' }, 'forged')).rejects.toMatchObject({ status: 403 });
  r = await service.transitionConnection(patient, r.id, { expected_revision: r.revision }, 'demo', true);
  expect((await service.capabilities(patient)).active_patient_relationships).toEqual([]);
  await expect(service.transitionConnection(patient, r.id, { expected_revision: r.revision, to_state: 'accepted' }, 'self')).rejects.toMatchObject({ status: 403 });
  await expect(service.transitionConnection(otherPro, r.id, { expected_revision: r.revision, to_state: 'accepted' }, 'foreign')).rejects.toMatchObject({ status: 404 });
  const body = { expected_revision: r.revision, to_state: 'accepted' };
  const results = await Promise.all([service.transitionConnection(pro, r.id, body, 'accept'), service.transitionConnection(pro, r.id, body, 'accept')]);
  expect(results[0]).toEqual(results[1]); expect(store.count('patient_relationships')).toBe(1);
  expect(await service.createConnection(patient, { psychologist_uid: pro.uid, consent_version: 'care-consent-v1' }, 'application')).toMatchObject({ id: r.id, state: 'requested', revision: 1 });
});
it('snapshots all-active assignment targets and creates independent repeat attempts', async () => {
  const a = await onboard(), body = { organization_id: org, questionnaire_version_id: version.id, target: { kind: 'all_active' } };
  const first: any = await service.assign(pro, body, 'all'); await onboard(otherPatient, 'second');
  expect(await service.assign(pro, body, 'all')).toEqual(first); expect(first.resolved_relationship_ids).toEqual([a.relationship_id]);
  const second: any = await service.assign(pro, body, 'repeat'); expect(second.assignment_ids).toHaveLength(2); expect(store.count('attempts')).toBe(3);
  expect(second.assignment_ids).not.toContain(first.assignment_ids[0]);
  for (const key of [...store.data.keys()].filter(k => k.startsWith('assignments/'))) expect((store.data.get(key) as any).questionnaire_version_id).toBe(version.id);
});
it('rejects inactive, foreign and oversized assignment batches before any writes', async () => {
  const r = await onboard(); await service.closeRelationship(pro, r.relationship_id, { expected_revision: 1 }, 'close');
  const body = { organization_id: org, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [r.relationship_id] } };
  await expect(service.assign(pro, body, 'bad')).rejects.toMatchObject({ status: 403 });
  await expect(service.assign(otherPro, body, 'bad')).rejects.toMatchObject({ status: 404 });
  await expect(service.assign(pro, { ...body, questionnaire_version_id: 'wrong_version' }, 'wrong')).rejects.toMatchObject({ status: 404 });
  await expect(service.assign(pro, { ...body, target: { kind: 'selected', relationship_ids: Array.from({ length: 201 }, (_, i) => `r_${i}`) } }, 'large')).rejects.toMatchObject({ status: 422 });
  expect(store.count('assignments')).toBe(0);
});
it('autosaves, resumes, restarts, checks revisions and rejects other patients', async () => {
  const { detail } = await assigned(), id = detail.attempt.id;
  await expect(service.patientDetail(otherPatient, detail.assignment.id)).rejects.toMatchObject({ status: 404 });
  await expect(service.saveAttempt(otherPatient, id, { expected_revision: 0, answers }, 'other')).rejects.toMatchObject({ status: 404 });
  const body = { expected_revision: 0, answers }, saved = await service.saveAttempt(patient, id, body, 'save');
  expect(await service.saveAttempt(patient, id, body, 'save')).toEqual(saved);
  expect(await service.patientDetail(patient, detail.assignment.id)).toMatchObject({ attempt: { answers, revision: 1 } });
  await expect(service.saveAttempt(patient, id, body, 'stale')).rejects.toMatchObject({ status: 409 });
  await service.saveAttempt(patient, id, { expected_revision: 1, answers: [] }, 'restart');
  expect(await service.patientDetail(patient, detail.assignment.id)).toMatchObject({ attempt: { answers: [], revision: 2 } });
  await expect(service.saveAttempt(patient, id, { expected_revision: 2 }, 'empty_submit', true)).rejects.toMatchObject({ status: 422 });
});
it('serializes concurrent devices and emits one acknowledgement/job with immutable answers', async () => {
  const { detail } = await assigned(), id = detail.attempt.id;
  const saves = await Promise.allSettled(['device_a', 'device_b'].map(key => service.saveAttempt(patient, id, { expected_revision: 0, answers }, key)));
  expect(saves.filter(r => r.status === 'fulfilled')).toHaveLength(1); expect(saves.find(r => r.status === 'rejected')).toMatchObject({ reason: { status: 409 } });
  const results = await Promise.all(['submit_a', 'submit_b'].map(key => service.saveAttempt(patient, id, { expected_revision: 1 }, key, true)));
  expect(results[0]).toEqual(results[1]); expect(Object.keys(results[0] as object).sort()).toEqual(['assignment_id', 'attempt_id', 'status', 'submitted_at']);
  expect(store.count('ai_jobs')).toBe(1); expect(store.count('submissions')).toBe(1);
  await expect(service.saveAttempt(patient, id, { expected_revision: 2, answers: [] }, 'reopen')).rejects.toMatchObject({ status: 409 });
  expect(store.read<any>('attempts', id).answers).toEqual(answers);
});
it('rejects wrong pinned versions and unknown answer IDs/types', async () => {
  const { detail } = await assigned(), id = detail.attempt.id;
  await expect(service.saveAttempt(patient, id, { expected_revision: 0, answers: [{ question_id: 'unknown', type: 'yes_no', value: true }] }, 'unknown')).rejects.toMatchObject({ status: 422 });
  await expect(service.saveAttempt(patient, id, { expected_revision: 0, answers, version_id: 'forged' }, 'forged')).rejects.toMatchObject({ status: 422 });
  store.seed('attempts', id, { ...store.read<any>('attempts', id), version_id: 'wrong' });
  await expect(service.saveAttempt(patient, id, { expected_revision: 0, answers }, 'wrong')).rejects.toMatchObject({ status: 404 });
});
it('keeps patient acknowledgement independent from provider failure and denies all professional routes', async () => {
  const { detail, ack, s } = await submitted(); const workspace = await service.workspace(pro, s.id);
  const job = store.read<any>('ai_jobs', workspace.job.id); store.seed('ai_jobs', workspace.job.id, { ...job, job: { ...job.job, state: 'failed', failure_code: 'provider_unavailable' } });
  expect(await service.saveAttempt(patient, detail.attempt.id, { expected_revision: 0 }, 'retry_after_failure', true)).toEqual(ack);
  for (const p of [patient, otherPatient, actor('guest')]) {
    await expect(service.getSubmission(p, s.id)).rejects.toMatchObject({ status: 403 });
    await expect(service.getEvaluation(p, workspace.evaluation.id)).rejects.toMatchObject({ status: 403 });
    await expect(service.workspace(p, s.id)).rejects.toMatchObject({ status: 403 });
    await expect(service.createReview(p, { organization_id: org, evaluation_id: workspace.evaluation.id, expected_review_revision: 0, conclusion: 'Forged' }, 'forged')).rejects.toMatchObject({ status: 403 });
  }
  await expect(service.workspace(otherPro, s.id)).rejects.toMatchObject({ status: 404 });
});
it('strips unknown top-level fields and fails closed on nested evaluation contamination', async () => {
  const { detail, s } = await submitted();
  const a = store.read<any>('assignments', detail.assignment.id); store.seed('assignments', a.id, { ...a, evaluation: { score: 123 } });
  store.seed('attempts', detail.attempt.id, { ...store.read<any>('attempts', detail.attempt.id), interpretation: 'SECRET' });
  const responses = [await service.patientDetail(patient, a.id), await service.list(patient, 'assignments'), await service.capabilities(patient)];
  const json = JSON.stringify(responses); expect(json).not.toMatch(/evaluation|interpretation|validated_scores|job_id|SECRET/); expect(json).not.toContain('answers');
  const raw = store.read<any>('submissions', s.id); expect(raw.answers).toEqual(answers);
  const repeat: any = await service.assign(pro, { organization_id: org, questionnaire_version_id: version.id, target: { kind: 'all_active' } }, 'repeat');
  store.seed('questionnaire_versions', version.id, { ...version, content: { ...version.content, questions: [{ ...version.content.questions[0], evaluation: { score: 1 } }] } });
  await expect(service.patientDetail(patient, repeat.assignment_ids[0])).rejects.toMatchObject({ status: 422 });
});
it('closure revokes open and submitted reads, writes and replay while retaining professional history', async () => {
  const { detail, s, r } = await submitted();
  await service.closeRelationship(pro, r.relationship_id, { expected_revision: 1 }, 'close');
  expect((await service.list(patient, 'assignments')).items).toEqual([]);
  expect((await service.capabilities(patient)).active_patient_relationships).toEqual([]);
  await expect(service.patientDetail(patient, detail.assignment.id)).rejects.toMatchObject({ status: 403 });
  await expect(service.saveAttempt(patient, detail.attempt.id, { expected_revision: 1 }, 'submit', true)).rejects.toMatchObject({ status: 403 });
  expect(await service.getSubmission(pro, s.id)).toMatchObject({ answers });
  expect(store.read<any>('accounts', patient.uid)).toMatchObject({ state: 'registered', general_access: true });
  const link = await invite(patient.uid, 'after_close');
  await expect(service.redeemInvitation(patient, link.token, { consent_version: 'care-consent-v1' }, 'reopen')).rejects.toMatchObject({ status: 409 });
});
it('appends approve/reject/feedback revisions without touching original AI output', async () => {
  const { s } = await submitted(); let w = await service.workspace(pro, s.id);
  const original = { ...w.evaluation, interpretation: 'Original provider interpretation', provider_response_sha256: 'a'.repeat(64) }; store.seed('clinician_evaluations', original.id, original);
  store.seed('ai_provider_responses', original.id, { original_provider_response: 'UNCHANGED' });
  for (const [i, decision] of ['approve', 'reject', 'feedback'].entries()) {
    const body = { organization_id: org, evaluation_id: original.id, expected_review_revision: i, conclusion: `Review ${i}`, feedback: 'Clinician feedback', decision };
    const result = await service.createReview(pro, body, `review_${i}`, true);
    expect(await service.createReview(pro, body, `review_${i}`, true)).toEqual(result);
    await expect(service.createReview(pro, body, `stale_${i}`, true)).rejects.toMatchObject({ status: 409 });
  }
  expect(store.read<any>('clinician_evaluations', original.id)).toEqual(original); expect(store.read<any>('ai_provider_responses', original.id).original_provider_response).toBe('UNCHANGED');
  expect((await service.workspace(pro, s.id)).review_revision).toBe(3);
  expect((await service.list(pro, 'decisions', '', 25, undefined, original.id)).items).toHaveLength(3);
  await expect(service.list(patient, 'decisions', '', 25, undefined, original.id)).rejects.toMatchObject({ status: 403 });
});
it('binds cursor pagination to actor, scope and authorization revision', async () => {
  await onboard(); await onboard(otherPatient, 'second');
  const page = await service.list(pro, 'relationships', org, 1); expect(page.next_cursor).toBeTruthy();
  await expect(service.list(otherPro, 'relationships', org, 1, page.next_cursor!)).rejects.toMatchObject({ status: 404 });
  await expect(service.list(pro, 'submissions', org, 1, page.next_cursor!)).rejects.toMatchObject({ status: 422 });
  expect((await service.list(pro, 'relationships', org, 1, page.next_cursor!)).items).toHaveLength(1);
  const a = store.read<any>('accounts', pro.uid); store.seed('accounts', pro.uid, { ...a, authorization_revision: 2 });
  await expect(service.list(pro, 'relationships', org, 1, page.next_cursor!)).rejects.toMatchObject({ status: 422 });
});
it('removes patient capabilities when the clinician is suspended', async () => {
  const { detail } = await assigned(); registered(store, pro.uid, 'suspended');
  expect((await service.capabilities(patient)).active_patient_relationships).toEqual([]);
  await expect(service.patientDetail(patient, detail.assignment.id)).rejects.toMatchObject({ status: 403 });
});
it.each(['single_choice', 'multi_choice', 'yes_no', 'likert', 'short_text', 'image_single_choice', 'image_multi_choice'])('checks %s answer semantics', type => {
  const q: any = { id: 'q', type, prompt: { en: 'Question' }, required: true, ...(type === 'short_text' ? { max_length: 5 } : type === 'yes_no' ? {} : { options: [{ id: 'a', label: { en: 'A' } }, { id: 'b', label: { en: 'B' } }] }) };
  const value = type === 'yes_no' ? false : type === 'short_text' ? 'Hello' : type.includes('multi') ? ['a'] : 'a';
  expect(answerIssues([q], [{ question_id: 'q', type: type as any, value }], true)).toEqual([]);
  expect(answerIssues([q], [], true)).not.toEqual([]);
  expect(answerIssues([q], [{ question_id: 'q', type: type as any, value: 123 as any }], true)).not.toEqual([]);
});

it('rejects unknown consent revisions before onboarding', async () => {
  const link = await invite();
  await expect(service.redeemInvitation(patient, link.token, { consent_version: 'unreviewed_consent' }, 'unknown')).rejects.toMatchObject({ status: 422 });
  await expect(service.createConnection(patient, { psychologist_uid: pro.uid, consent_version: 'unreviewed_consent' }, 'unknown')).rejects.toMatchObject({ status: 422 });
  expect(store.count('patient_relationships')).toBe(0);
});

it('rejects forged evaluation identities and cross-organization review head references', async () => {
  const { s } = await submitted(); const w = await service.workspace(pro, s.id);
  const e = store.read<any>('clinician_evaluations', w.evaluation.id);
  store.seed('clinician_evaluations', e.id, { ...e, id: 'foreign_evaluation' });
  await expect(service.getEvaluation(pro, e.id)).rejects.toMatchObject({ status: 404 });
  store.seed('clinician_evaluations', e.id, e);
  store.seed('review_heads', e.id, { organization_id: 'foreign_org', evaluation_id: e.id, revision: 0 });
  await expect(service.createReview(pro, { organization_id: org, evaluation_id: e.id, expected_review_revision: 0, conclusion: 'Forged head' }, 'forged_head')).rejects.toMatchObject({ status: 404 });
  expect(store.count('review_records')).toBe(0);
});
