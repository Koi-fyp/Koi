/** @jest-environment node */
const { guard, passwords, IDENTITIES } = require('../../../scripts/koi-demo-guard.cjs');
const valid = { KOI_PLATFORM_MODE: 'emulator', KOI_PLATFORM_FIREBASE_PROJECT_ID: 'demo-koi-platform-web1', FIRESTORE_EMULATOR_HOST: '127.0.0.1:5180', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:5199' };
it('pins exact emulator project and hosts before any SDK initialization', () => {
  expect(guard(valid).project).toBe('demo-koi-platform-web1');
  for (const [key, value] of Object.entries({ KOI_PLATFORM_MODE: 'reviewed-production', KOI_PLATFORM_FIREBASE_PROJECT_ID: 'demo-another', FIRESTORE_EMULATOR_HOST: 'localhost:5180', FIREBASE_AUTH_EMULATOR_HOST: 'example.com:5199' })) expect(() => guard({ ...valid, [key]: value })).toThrow();
});
it('rejects production credentials and conflicting ambient project configuration', () => {
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_ADMIN_SDK', 'FIREBASE_TOKEN', 'GOOGLE_OAUTH_ACCESS_TOKEN', 'GOOGLE_CREDENTIALS', 'FIREBASE_SERVICE_ACCOUNT', 'KOI_PLATFORM_RULESET_SHA256', 'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_PROJECT_ID', 'FIREBASE_CONFIG']) expect(() => guard({ ...valid, [key]: 'forbidden' })).toThrow();
});
it('requires operator passwords without a hardcoded fallback and exports only fictional identities', () => {
  expect(() => passwords({})).toThrow(); expect(() => passwords({ KOI_DEMO_PASSWORD: 'short' })).toThrow();
  const value = require('node:crypto').randomUUID(); expect(passwords({ KOI_DEMO_PASSWORD: value })).toEqual({ psychologist: value, general: value, patient: value });
  const override = require('node:crypto').randomUUID(); expect(passwords({ KOI_DEMO_PASSWORD: value, KOI_DEMO_PATIENT_PASSWORD: override }).patient).toBe(override);
  expect(Object.values(IDENTITIES)).toHaveLength(3); for (const i of Object.values(IDENTITIES) as any[]) expect(i.email).toMatch(/@koi-demo\.example$/);
});
