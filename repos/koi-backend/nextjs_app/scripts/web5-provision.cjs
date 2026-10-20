// One-time restricted LOCAL operator CLI. It is never imported by the application.
const fs = require('node:fs'), path = require('node:path');
const { PROJECT, identities, provision } = require('./web5-provision-core.cjs');
function writeGuard(args, env) {
  if (args.apply !== true || args.confirmProject !== PROJECT || env.KOI_WEB5_CLOUD_WRITE_AUTHORIZATION !== 'PROVISION_FICTIONAL_KOI_DEMO') throw new Error('Explicit project confirmation and cloud provisioning authorization required');
  if (env.KOI_PLATFORM_MODE !== 'reviewed-production' || env.KOI_PLATFORM_FIREBASE_PROJECT_ID !== PROJECT || ['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_DATABASE_EMULATOR_HOST','STORAGE_EMULATOR_HOST','NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL'].some(k => !!env[k])) throw new Error('Reviewed existing-project cloud configuration required');
  const config = require('../src/lib/platform/server/admin-config.cjs').configuration(env);
  if (!env.KOI_PLATFORM_BOOTSTRAP_ADMIN_UID || config.credential.client_email !== env.KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT || env.KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT === 'emulator-only') throw new Error('Restricted operator/service allowlist required');
  const evidence = require('../src/lib/platform/server/production-evidence.cjs').readEvidence(env.KOI_PLATFORM_RULES_EVIDENCE_PATH, PROJECT, env.KOI_PLATFORM_RULESET_SHA256);
  if (evidence.password_provider_enabled !== true) throw new Error('Email/password Auth provider must be verified enabled');
  return config;
}
async function exportManifest(db, runId, destination) {
  if (fs.existsSync(destination)) throw new Error('Manifest destination exists; preserve it');
  const run = (await db.collection('demo_provision_runs').doc(runId).get()).data();
  if (run?.project !== PROJECT || !run.fictional) throw new Error('Missing fictional run');
  const entries = (await db.collection('demo_provision_records').where('run_id','==',runId).get()).docs;
  const records = entries.map(d => ({ ...d.data(), ledger_path: d.ref.path }));
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const result = { project: PROJECT, run_id: runId, status: run.status, fictional: true, identities: run.identities, manifest_path: `demo_provision_runs/${runId}`, references: { organization_id: run.organization_id ?? null, relationship_id: run.relationship_id ?? null, assignments: run.assignments ?? null }, records, cleanup: ['Obtain separate authorization. Do not run bulk collection deletion.', 'Close only this run relationship and suspend only this run psychologist through authoritative transitions; disable only manifest Auth UIDs.', 'Regenerate a fresh manifest after all demo actions. Original creation ledger covers seeded records, not later GUI operations; inventory all records scoped to this organization/UIDs before deletion.', 'Compare every current document hash with the manifest and verify current run ownership; stop on drift or outside references.', 'Delete only reviewed exact record paths, then their ledger paths and manifest, then the three exact owned fictional Auth UIDs. Preserve users/, conversations/, mood_entries/, wellness_progress/, tasks/ and all other identities.', 'No automatic cleanup or rollback executes from this tool. Retain an approved export if any records must be retained.'] };
  fs.writeFileSync(destination, JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
  return result;
}
async function main() {
  const raw = process.argv.slice(2), args = {};
  for (let i=0;i<raw.length;i++) { const k=raw[i]; if (['--apply','--manifest-only'].includes(k)) args[k]=true; else if (['--run-id','--confirm-project','--output'].includes(k) && raw[i+1]) args[k]=raw[++i]; else throw new Error('Invalid argument'); }
  const runId=args['--run-id'], roles=identities(runId);
  if (!args['--apply'] && !args['--manifest-only']) { console.log(JSON.stringify({ plan_only:true,project:PROJECT,run_id:runId,identities:roles,cloud_writes:0 },null,2)); return; }
  const destination=args['--output']; if (!destination || fs.existsSync(destination)) throw new Error('Choose a new private manifest output path');
  if (args['--manifest-only']) {
    if (process.env.KOI_PLATFORM_MODE !== 'reviewed-production' || process.env.KOI_PLATFORM_FIREBASE_PROJECT_ID !== PROJECT) throw new Error('Existing-project cloud read configuration required');
    const {db}=require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
    await exportManifest(db,runId,destination); console.log('Read-only fictional run manifest exported.'); return;
  }
  const config=writeGuard({apply:true,confirmProject:args['--confirm-project']},process.env);
  const passwords=Object.fromEntries(Object.keys(roles).map(role=>[role,process.env[`KOI_WEB5_${role.toUpperCase()}_PASSWORD`]]));
  const {auth,db}=require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
  const {loadPlatform}=require('./web5-load-platform.cjs'); const {CommunityService,firestoreStore}=loadPlatform();
  const result=await provision({auth,store:firestoreStore(db),serviceFactory:store=>new CommunityService(store,config.cursorKey),runId,actorUid:process.env.KOI_PLATFORM_BOOTSTRAP_ADMIN_UID,serviceIdentity:config.credential.client_email,passwords});
  await exportManifest(db,runId,destination);
  console.log(JSON.stringify({project:PROJECT,run_id:runId,status:result.status,emails:Object.fromEntries(Object.entries(roles).map(([r,i])=>[r,i.email])),manifest:destination,ai_calls:0},null,2));
}
if(require.main===module) main().catch(()=>{console.error('Fictional provisioning stopped. Inspect private configuration/run ledger; credentials, tokens, passwords and raw SDK errors omitted. No automatic rollback or fallback.');process.exitCode=1;});
module.exports={writeGuard,exportManifest};
