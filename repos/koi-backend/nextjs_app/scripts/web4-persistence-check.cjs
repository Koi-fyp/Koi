const assert = require('node:assert/strict');
const { readFileSync, writeFileSync } = require('node:fs');
const { createHash } = require('node:crypto');
async function main() {
  require('./koi-demo-guard.cjs').guard();
  const { auth, db } = require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
  const expected = JSON.parse(readFileSync('.local/koi-demo/persistence-check.json', 'utf8'));
  const users = (await auth.listUsers(1000)).users;
  for (const [uid, digest] of Object.entries(expected.authFingerprints)) {
    const user = users.find(u => u.uid === uid); assert(user?.passwordHash);
    assert.equal(createHash('sha256').update(user.passwordHash).digest('hex'), digest);
  }
  const manifest = (await db.collection('demo_seed_manifests').doc('web4_v1').get()).data();
  for (const [key, value] of Object.entries(expected.fixture)) assert.deepEqual(manifest[key], value);
  for (const [collection, count] of Object.entries(expected.counts)) assert.equal((await db.collection(collection).get()).size, count, collection);
  writeFileSync('review/web-4/evidence/persistence.json', JSON.stringify({ passed: true, scope: 'Auth password hash fingerprints, deterministic fixture references and all ten domain collection counts match across actual emulator export/restart/import', fictional: true }, null, 2) + '\n');
  console.log('PASS Auth and Firestore persistence after export/restart/import; no credentials printed');
}
main().catch(() => { console.error('Persistence check failed; private details omitted.'); process.exitCode = 1; });
