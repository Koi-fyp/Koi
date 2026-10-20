const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ROOTS = Object.freeze(['accounts','registration_challenges','psychologist_verifications','organization_owners','organizations','organization_memberships','psychologist_profiles','patient_relationships','connection_requests','demo_payments','patient_invitations','invitation_token_lookup','instrument_templates','questionnaires','questionnaire_versions','assignments','attempts','submissions','clinician_evaluations','review_records','review_heads','ai_jobs','ai_results','messages','appointments','notifications','professional_notifications','patient_archives','audit_events','idempotency_records','platform_outbox','platform_rate_limits','access_invalidation_outbox','migration_manifests','demo_provision_runs','demo_provision_records','demo_seed_manifests']);
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const patch = () => '\n    // WEB-5 platform: backend-only. Admin SDK authorization is enforced in Next.\n' + ROOTS.map(c => `    match /${c}/{platformDocument=**} { allow read, write: if false; }`).join('\n') + '\n    // END WEB-5 platform\n';
function mergeRules(source) {
  if (!source.includes("rules_version = '2'") || !source.includes('match /databases/{database}/documents {') || source.includes('// WEB-5 platform:')) throw new Error('Rules source requires review');
  const closing = /\r?\n\s*}\s*}\s*$/.exec(source);
  if (!closing) throw new Error('Unexpected rules structure');
  return source.slice(0, closing.index) + patch() + source.slice(closing.index);
}
function indexes(existing = { indexes: [], fieldOverrides: [] }) {
  const base = JSON.parse(fs.readFileSync(path.join(__dirname, '../review/web-2/firestore.indexes.proposed.json'), 'utf8'));
  const extra = { submissions: [['organization_id','relationship_id']], messages: [['organization_id','relationship_id']], appointments: [['organization_id','relationship_id']], professional_notifications: [['organization_id','recipient_uid']], review_records: [['organization_id','psychologist_uid']] };
  for (const [collectionGroup, queries] of Object.entries(extra)) for (const fields of queries) base.indexes.push({ collectionGroup, queryScope: 'COLLECTION', fields: [...fields, '__name__'].map(fieldPath => ({ fieldPath, order: 'ASCENDING' })) });
  // Single-field equality + document-ID order uses normal automatic indexes.
  const all = [...existing.indexes];
  const key = i => JSON.stringify([i.collectionGroup, i.queryScope, i.fields.map(f => [f.fieldPath, f.order ?? f.arrayConfig])]);
  for (const i of base.indexes) if (i.fields.filter(f => f.fieldPath !== '__name__').length >= 2 && !all.some(e => key(e) === key(i))) all.push(i);
  return { ...existing, indexes: all, fieldOverrides: existing.fieldOverrides ?? [] };
}
if (require.main === module) {
  const args = process.argv.slice(2), source = args[0], destination = args[1];
  if (!source || !destination) throw new Error('Usage: node scripts/web5-artifacts.cjs SOURCE.rules NEW_OUTPUT_DIRECTORY [EXISTING_INDEXES.json]');
  if (fs.existsSync(destination)) throw new Error('Output directory already exists; preserve it');
  const content = fs.readFileSync(source, 'utf8');
  const merged = mergeRules(content), ix = indexes(args[2] ? JSON.parse(fs.readFileSync(args[2], 'utf8')) : undefined);
  fs.mkdirSync(destination, { recursive: true });
  fs.writeFileSync(path.join(destination, 'firestore.rules'), merged);
  fs.writeFileSync(path.join(destination, 'platform-deny.patch.rules'), patch());
  fs.writeFileSync(path.join(destination, 'firestore.indexes.json'), JSON.stringify(ix, null, 2) + '\n');
  fs.writeFileSync(path.join(destination, 'firebase.json'), JSON.stringify({ firestore: { rules: 'firestore.rules', indexes: 'firestore.indexes.json' }, emulators: { auth: { host: '127.0.0.1', port: 5199 }, firestore: { host: '127.0.0.1', port: 5180 }, ui: { enabled: false }, singleProjectMode: true } }, null, 2) + '\n');
  fs.writeFileSync(path.join(destination, 'source-manifest.json'), JSON.stringify({ project: 'koi-companion-fyp', source_sha256: sha(content), merged_sha256: sha(merged), platform_roots: ROOTS, live_source_verified: false, note: 'Source provenance and live release must be verified separately. Explicit denies do not override overlapping allow rules. Never deploy the checked-in reference over an unverified live policy.' }, null, 2) + '\n');
  console.log('Prepared additive rules/index artifacts locally; nothing deployed.');
}
module.exports = { ROOTS, sha, patch, mergeRules, indexes };
