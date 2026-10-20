/** @jest-environment node */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const { ROOTS, mergeRules, indexes } = require('../../../scripts/web5-artifacts.cjs');
const { validateEvidence } = require('../../lib/platform/server/production-evidence.cjs');
const { configuration } = require('../../lib/platform/server/admin-config.cjs');
const { writeGuard } = require('../../../scripts/web5-provision.cjs');
const project = 'koi-companion-fyp', digest = 'a'.repeat(64);
const proof = () => ({ project, live_release_verified: true, ruleset_name: `projects/${project}/rulesets/reviewed`, rules_sha256: digest, verified_at: new Date().toISOString(), password_provider_enabled: true, rules_tests: { passed: true, source_sha256: digest, denied_roots: [...ROOTS] } });
let folder: string, evidence: string;
beforeEach(() => { folder = fs.mkdtempSync(path.join(os.tmpdir(), 'koi-web5-')); evidence = path.join(folder, 'proof.json'); fs.writeFileSync(evidence, JSON.stringify(proof())); });
afterEach(() => { fs.unlinkSync(evidence); fs.rmdirSync(folder); });
const env = () => ({ KOI_PLATFORM_MODE:'reviewed-production', KOI_PLATFORM_FIREBASE_PROJECT_ID:project, KOI_PLATFORM_RULESET_SHA256:digest, KOI_PLATFORM_RULES_EVIDENCE_PATH:evidence, KOI_PLATFORM_CURSOR_SIGNING_KEY:'fictional-test-key-'.repeat(3), FIREBASE_ADMIN_SDK:JSON.stringify({ type:'service_account',project_id:project,client_email:`restricted-demo@${project}.iam.gserviceaccount.com`,private_key:'fixture-only-not-a-real-key' }), KOI_PLATFORM_BOOTSTRAP_ADMIN_UID:'operator', KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT:`restricted-demo@${project}.iam.gserviceaccount.com`, KOI_WEB5_CLOUD_WRITE_AUTHORIZATION:'PROVISION_FICTIONAL_KOI_DEMO' });
it('accepts only existing-project cloud configuration with matched live rules test evidence', () => {
  expect(configuration(env())).toMatchObject({ project,mode:'reviewed-production' });
  expect(writeGuard({ apply:true,confirmProject:project },env()).project).toBe(project);
  for (const patch of [{ FIRESTORE_EMULATOR_HOST:'127.0.0.1:5480' },{ NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL:'http://127.0.0.1:5499' },{ NEXT_PUBLIC_FIREBASE_PROJECT_ID:'another-project' },{ KOI_PLATFORM_FIREBASE_PROJECT_ID:'another-project' },{ NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR:'true' },{ KOI_PLATFORM_RULES_EVIDENCE_PATH:'' },{ KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT:'emulator-only' },{ KOI_PLATFORM_CURSOR_SIGNING_KEY:'demo-only-platform-cursor-key-never-use-in-production' }]) expect(() => configuration({ ...env(),...patch })).toThrow();
});
it('requires explicit cloud-write confirmation and allowlisted operator, never just configuration', () => {
  expect(() => writeGuard({ apply:false,confirmProject:project },env())).toThrow();
  expect(() => writeGuard({ apply:true,confirmProject:'wrong' },env())).toThrow();
  expect(() => writeGuard({ apply:true,confirmProject:project },{ ...env(), KOI_WEB5_CLOUD_WRITE_AUTHORIZATION:'' })).toThrow();
  expect(() => writeGuard({ apply:true,confirmProject:project },{ ...env(), KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT:'foreign' })).toThrow();
});
it('rejects stale, forged-source, incomplete and unverified rules evidence', () => {
  for(const patch of [{live_release_verified:false},{project:'other'},{rules_sha256:'b'.repeat(64)},{verified_at:new Date(Date.now()-2*86400000).toISOString()},{rules_tests:{passed:true,source_sha256:digest,denied_roots:ROOTS.filter((c:string)=>c!=='clinician_evaluations')}}]) expect(()=>validateEvidence({...proof(),...patch},project,digest)).toThrow();
});
it('preserves the complete original policy while adding backend-only platform namespaces', () => {
  const original=fs.readFileSync(path.join(process.cwd(),'../firestore.rules'),'utf8'), merged=mergeRules(original);
  expect(merged.replace(/\n    \/\/ WEB-5 platform:[\s\S]*?    \/\/ END WEB-5 platform\n/, '')).toBe(original);
  for(const root of ROOTS) expect(merged).toContain(`match /${root}/{platformDocument=**} { allow read, write: if false; }`);
  const foreign={collectionGroup:'existing_custom_data',queryScope:'COLLECTION',fields:[{fieldPath:'owner',order:'ASCENDING'},{fieldPath:'date',order:'DESCENDING'}]};
  const result=indexes({indexes:[foreign],fieldOverrides:[{collectionGroup:'users',fieldPath:'secret',indexes:[]}]});
  expect(result.indexes).toContainEqual(foreign); expect(indexes(result)).toEqual(result); expect(result.fieldOverrides).toHaveLength(1);
});
