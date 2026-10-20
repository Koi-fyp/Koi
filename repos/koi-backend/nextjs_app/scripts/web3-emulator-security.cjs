// Local-only supplemental direct-rule and anonymous Firebase identity checks.
const assert = require('node:assert/strict');
const { writeFileSync } = require('node:fs');
const { getPlatformAdmin } = require('../src/lib/platform/server/admin-config.cjs');
async function main() {
  const { auth, config } = getPlatformAdmin();
  assert.equal(config.mode, 'emulator'); assert.equal(config.project, 'demo-koi-platform-web1');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:5180');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:5199');
  const users = await auth.listUsers(1000), patient = users.users.find(u => u.uid.startsWith('w2_patient_')); assert(patient, 'Run the functional harness first');
  const signIn = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: await auth.createCustomToken(patient.uid), returnSecureToken: true }) });
  assert.equal(signIn.status, 200); const identity = await signIn.json();
  const headers = { Authorization: `Bearer ${identity.idToken}`, 'Content-Type': 'application/json' };
  const root = `http://127.0.0.1:5180/v1/projects/${config.project}/databases/(default)/documents`, checks = [];
  for (const collection of ['psychologist_profiles', 'messages', 'appointments', 'notifications', 'professional_notifications', 'demo_payments', 'patient_archives']) {
    assert.equal((await fetch(`${root}/${collection}/forged`, { headers })).status, 403);
    assert.equal((await fetch(`${root}/${collection}/forged`, { method: 'PATCH', headers, body: JSON.stringify({ fields: { recipient_uid: { stringValue: patient.uid } } }) })).status, 403);
    for (const allDescendants of [false, true]) assert.equal((await fetch(`${root}:runQuery`, { method: 'POST', headers, body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection, allDescendants }] } }) })).status, 403);
    checks.push(`${collection}: direct read, write, query and collection-group denied`);
  }
  const anonymous = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }) });
  assert.equal(anonymous.status, 200); const anonymousIdentity = await anonymous.json();
  assert.equal((await fetch('http://127.0.0.1:3107/api/v1/experts', { headers: { Authorization: `Bearer ${anonymousIdentity.idToken}` } })).status, 403);
  checks.push('Real Firebase anonymous UID cannot access expert directory');
  writeFileSync('review/web-3/evidence/security-emulator.json', JSON.stringify({ run_at: new Date().toISOString(), checks, direct_rule_assertions: 28, anonymous_api_assertions: 1, passed: true, project: config.project }, null, 2) + '\n');
  process.stdout.write('PASS: 28 direct Firestore denial assertions and Firebase anonymous directory denial\n');
}
main().catch(e => { process.stderr.write(`Local security check failed: ${e.message}\n`); process.exitCode = 1; });
