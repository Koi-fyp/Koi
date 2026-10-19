/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
import { MemoryPlatformStore, registered, actor, manualContent, testTime } from '../../../test/platform-memory';
import { PlatformService, membershipId } from '@/lib/platform/server/service';
import { checkSchema, hash } from '@/lib/platform/server/contract';
import { canonicalJson } from '@/lib/platform/canonical';
import { illustrations } from '@/lib/platform/content';
import type { QuestionType } from '@/lib/platform/types';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const secret = 'test-cursor-key-with-at-least-32-characters';
let store: MemoryPlatformStore, service: PlatformService;
beforeEach(() => { store = new MemoryPlatformStore(); service = new PlatformService(store, secret, () => testTime); registered(store, actor().uid); });
const org = () => service.createOrganization(actor(), { name: 'Fictional practice' }, 'org_key');

it('creates one organization/membership under concurrent calls; ignores a forged client role', async () => {
  const [a, b] = await Promise.all([org(), service.createOrganization(actor(), { name: 'Fictional practice' }, 'org_second_key')]);
  expect(a).toEqual(b); expect(store.count('organizations')).toBe(1); expect(store.count('organization_memberships')).toBe(1);
  expect(store.read('organization_memberships', membershipId(actor().uid, a.id)).uid).toBe(actor().uid);
  store.seed('users', 'guest', { role: 'psychologist', emailVerified: true });
  await expect(service.createOrganization(actor('guest'), { name: 'Forged' }, 'key')).rejects.toMatchObject({ status: 403 });
  expect((await service.capabilities(actor('guest'))).capabilities.professional_workspace).toBe(false);
});
it.each(['pending', 'rejected', 'suspended'])('denies %s psychologists', async state => {
  registered(store, actor().uid, state);
  await expect(org()).rejects.toMatchObject({ status: 403 }); expect(store.count('organizations')).toBe(0);
});
it('requires fresh authentication and an active registered account', async () => {
  await expect(service.createOrganization({ ...actor(), authTime: actor().authTime - 301 }, { name: 'Practice' }, 'key')).rejects.toMatchObject({ status: 401 });
  const account = store.read('accounts', actor().uid); store.seed('accounts', actor().uid, { ...account, state: 'suspended' });
  await expect(org()).rejects.toMatchObject({ status: 403 });
});
it('saves, reopens, publishes and inspects an immutable snapshot after later draft edits', async () => {
  const practice = await org(), content = manualContent();
  const draft = await service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1');
  expect(await service.getDraft(actor(), draft.id)).toEqual(draft);
  const body = { expected_revision: 1, expected_content_sha256: hash(content) };
  const published = await service.publish(actor(), draft.id, body, 'publish_1');
  expect(await service.publish(actor(), draft.id, body, 'publish_2')).toEqual(published);
  const edited = await service.updateDraft(actor(), draft.id, { expected_revision: 1, content: { ...content, title: { en: 'Edited form' } } }, 'edit_1');
  expect(edited.revision).toBe(2); expect(await service.getVersion(actor(), published.id)).toEqual(published);
  expect(await service.publish(actor(), draft.id, body, 'publish_after_edit')).toEqual(published);
  expect(store.writes.filter(w => w.collection === 'questionnaire_versions')).toEqual([{ collection: 'questionnaire_versions', id: published.id, operation: 'create' }]);
  expect([...store.data.entries()].filter(([key]) => key.startsWith('audit_events/')).every(([, row]: [string, any]) => row.organization_id === practice.id)).toBe(true);
});
it('conflicts safely for concurrent edits, altered idempotency payloads and wrong publish hashes', async () => {
  const practice = await org(), content = manualContent();
  const draft = await service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1');
  expect(await service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1')).toEqual(draft);
  await expect(service.createDraft(actor(), { organization_id: practice.id, content: { ...content, title: { en: 'Different' } } }, 'create_1')).rejects.toMatchObject({ status: 409 });
  const results = await Promise.allSettled([service.updateDraft(actor(), draft.id, { expected_revision: 1, content }, 'edit_1'), service.updateDraft(actor(), draft.id, { expected_revision: 1, content }, 'edit_2')]);
  expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
  expect(results.find(r => r.status === 'rejected')).toMatchObject({ reason: { status: 409 } });
  await expect(service.publish(actor(), draft.id, { expected_revision: 2, expected_content_sha256: 'a'.repeat(64) }, 'publish_1')).rejects.toMatchObject({ status: 409 });
  expect(store.count('questionnaire_versions')).toBe(0);
});
it('denies cross-practice IDs, forged scope and revoked membership, including idempotent replays', async () => {
  const practice = await org(), content = manualContent();
  const draft = await service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1');
  const version = await service.publish(actor(), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish_1');
  registered(store, 'clinician_b');
  await expect(service.getDraft(actor('clinician_b'), draft.id)).rejects.toMatchObject({ status: 404 });
  await expect(service.getVersion(actor('clinician_b'), version.id)).rejects.toMatchObject({ status: 404 });
  await expect(service.createDraft(actor('clinician_b'), { organization_id: practice.id, content }, 'forged')).rejects.toMatchObject({ status: 404 });
  await expect(service.updateDraft(actor('clinician_b'), draft.id, { expected_revision: 1, content }, 'forged')).rejects.toMatchObject({ status: 404 });
  await expect(service.publish(actor('clinician_b'), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'forged')).rejects.toMatchObject({ status: 404 });
  const id = membershipId(actor().uid, practice.id); store.seed('organization_memberships', id, { ...store.read<any>('organization_memberships', id), state: 'revoked' });
  await expect(service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1')).rejects.toMatchObject({ status: 403 });
  expect((await service.capabilities(actor())).capabilities.professional_workspace).toBe(false);
});
it('paginates within owner scope and rejects foreign, expired and changed-authority cursors', async () => {
  const practice = await org(), content = manualContent();
  for (const key of ['one', 'two', 'three']) await service.createDraft(actor(), { organization_id: practice.id, content }, key);
  const first = await service.listDrafts(actor(), practice.id, 1);
  const second = await service.listDrafts(actor(), practice.id, 1, first.next_cursor!);
  expect(first.items[0].id).not.toBe(second.items[0].id);
  await expect(service.listDrafts(actor(), practice.id, 1, first.next_cursor + 'x')).rejects.toMatchObject({ status: 422 });
  const later = new PlatformService(store, secret, () => new Date(+testTime + 901_000));
  await expect(later.listDrafts(actor(), practice.id, 1, first.next_cursor!)).rejects.toMatchObject({ status: 422 });
  const account = store.read('accounts', actor().uid); store.seed('accounts', actor().uid, { ...account, authorization_revision: 2 });
  await expect(service.listDrafts(actor(), practice.id, 1, first.next_cursor!)).rejects.toMatchObject({ status: 422 });
  registered(store, 'clinician_b');
  await expect(service.listDrafts(actor('clinician_b'), practice.id, 1, first.next_cursor!)).rejects.toMatchObject({ status: 404 });
});
it.each(['single_choice', 'multi_choice', 'yes_no', 'likert', 'short_text', 'image_single_choice', 'image_multi_choice'] as QuestionType[])('supports %s without any AI/provider dependency', async type => {
  const practice = await org(), content = manualContent() as any;
  const question: any = { id: 'q_1', type, required: true, prompt: { en: 'Choose an answer' } };
  if (type === 'short_text') question.max_length = 100;
  else if (type !== 'yes_no') question.options = [0, 1].map(i => ({ id: `option_${i}`, label: { en: `Option ${i}` }, ...(type.startsWith('image_') ? { asset: illustrations[i].reference } : {}) }));
  if (type.includes('multi')) { question.min_selections = 1; question.max_selections = 2; }
  content.questions = [question];
  const draft = await service.createDraft(actor(), { organization_id: practice.id, content }, 'create_1');
  expect((await service.publish(actor(), draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, 'publish_1')).content.questions[0].type).toBe(type);
  expect(store.count('ai_jobs')).toBe(0);
});
it('rejects unknown fields, duplicate IDs, missing translations, bad bounds and unapproved picture references', async () => {
  const practice = await org(), content: any = manualContent();
  for (const invalidContent of [
    { ...content, score: 4 }, { ...content, locales: ['en', 'ur'] }, { ...content, questions: [content.questions[0], content.questions[0]] },
    { ...content, questions: [{ id: 'q', type: 'image_single_choice', required: true, prompt: { en: 'Picture' }, options: [0, 1].map(i => ({ id: `o_${i}`, label: { en: 'A' }, asset: { ...illustrations[i].reference, sha256: 'a'.repeat(64) } })) }] },
    { ...content, questions: [{ id: 'q', type: 'multi_choice', required: true, prompt: { en: 'Pick' }, options: [0, 1].map(i => ({ id: `o_${i}`, label: { en: 'A' } })), min_selections: 2, max_selections: 1 }] },
  ]) await expect(service.createDraft(actor(), { organization_id: practice.id, content: invalidContent }, 'invalid')).rejects.toMatchObject({ status: 422 });
  expect(store.count('questionnaires')).toBe(0);
});
it('pins original bundled asset bytes and canonical JSON semantics', () => {
  checkSchema('IllustrationManifest', { manifest_version: 1, assets: illustrations });
  expect(() => checkSchema('Id', ['valid_id'])).toThrow('invalid_request');
  for (const asset of illustrations) expect(createHash('sha256').update(readFileSync(join(process.cwd(), 'public', asset.web_path))).digest('hex')).toBe(asset.reference.sha256);
  expect(canonicalJson({ z: 2, a: { c: 3, b: 1 } })).toBe('{"a":{"b":1,"c":3},"z":2}');
  expect(() => canonicalJson('\ud800')).toThrow();
});
