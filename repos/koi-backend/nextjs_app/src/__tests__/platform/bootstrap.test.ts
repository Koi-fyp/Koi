/** @jest-environment node */
import { MemoryPlatformStore, testTime } from '../../../test/platform-memory';
const { seedVerification } = require('../../../scripts/platform-verify-psychologist.cjs');
const { configuration } = require('../../../src/lib/platform/server/admin-config.cjs');
it('seeds only through explicit admin transitions with audited identity and idempotence', async () => {
  const store = new MemoryPlatformStore();
  const base = { store, uid: 'clinician_a', evidenceId: 'identity_review_1', actorUid: 'admin_uid', serviceIdentity: 'allowlisted-service', now: () => testTime };
  await expect(seedVerification({ ...base, state: 'verified', requestId: 'invalid' })).rejects.toThrow('invalid_transition');
  await seedVerification({ ...base, state: 'pending', requestId: 'pending_1' });
  const result = await seedVerification({ ...base, state: 'verified', requestId: 'verified_1' });
  expect(result).toEqual({ state: 'verified', revision: 2, replayed: false });
  expect(await seedVerification({ ...base, state: 'verified', requestId: 'verified_1' })).toMatchObject({ replayed: true });
  expect(store.read('accounts', 'clinician_a')).toMatchObject({ state: 'registered', general_access: false, authorization_revision: 2 });
  expect(store.count('audit_events')).toBe(2);
  await seedVerification({ ...base, state: 'suspended', requestId: 'suspend_1' });
  expect(store.read('psychologist_verifications', 'clinician_a')).toMatchObject({ state: 'suspended', changed_by: 'admin_uid' });
  await expect(seedVerification({ ...base, state: 'verified', requestId: 'not_pending' })).rejects.toThrow('invalid_transition');
  expect(store.count('organizations')).toBe(0);
});
it('rejects missing evidence, identity and a changed idempotency payload', async () => {
  const store = new MemoryPlatformStore();
  const base = { store, uid: 'clinician_a', evidenceId: 'evidence_1', requestId: 'request_1', actorUid: 'admin_uid', serviceIdentity: 'allowlisted-service', state: 'pending' };
  await expect(seedVerification({ ...base, evidenceId: undefined })).rejects.toThrow('invalid_arguments');
  await expect(seedVerification({ ...base, serviceIdentity: '' })).rejects.toThrow('invalid_arguments');
  await seedVerification(base); await expect(seedVerification({ ...base, evidenceId: 'changed' })).rejects.toThrow('idempotency_conflict');
});
it('requires explicit isolated emulator configuration or reviewed/pinned production configuration', () => {
  expect(() => configuration({})).toThrow();
  expect(() => configuration({ KOI_PLATFORM_FIREBASE_PROJECT_ID: 'koi-companion-fyp' })).toThrow();
  const demo = { KOI_PLATFORM_FIREBASE_PROJECT_ID: 'demo-koi-platform', KOI_PLATFORM_MODE: 'emulator', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' };
  expect(configuration(demo).mode).toBe('emulator');
  expect(() => configuration({ ...demo, KOI_PLATFORM_FIREBASE_PROJECT_ID: 'koi-companion-fyp' })).toThrow();
  expect(() => configuration({ ...demo, FIRESTORE_EMULATOR_HOST: 'remote.invalid:8080' })).toThrow();
  expect(() => configuration({ KOI_PLATFORM_FIREBASE_PROJECT_ID: 'project-a', KOI_PLATFORM_MODE: 'reviewed-production', KOI_PLATFORM_RULESET_SHA256: 'a'.repeat(64), FIREBASE_ADMIN_SDK: JSON.stringify({ project_id: 'project-b' }), KOI_PLATFORM_CURSOR_SIGNING_KEY: 'cursor-key-with-more-than-32-characters' })).toThrow('mismatch');
});
