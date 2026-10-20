// Read-only Firebase control-plane inspection. Never imports companion/AI code.
const fs = require('node:fs');
const path = require('node:path');
const { sha } = require('./web5-artifacts.cjs');
const PROJECT = 'koi-companion-fyp';
async function audit({ credential, destination, fetchImpl = fetch }) {
  if (fs.existsSync(destination)) throw new Error('Preserve existing evidence; choose a new destination');
  fs.mkdirSync(destination, { recursive: true });
  const result = { project: PROJECT, inspected_at: new Date().toISOString(), live_release_verified: false, writes: 0, ai_requests: 0, blockers: [] };
  if (!credential) result.blockers.push('No Admin SDK credential or Firebase CLI login is available; published rules, indexes, IAM and Auth provider configuration cannot be verified.');
  else {
    if (credential.project_id !== PROJECT || credential.type !== 'service_account' || !credential.private_key || !credential.client_email?.endsWith(`@${PROJECT}.iam.gserviceaccount.com`)) throw new Error('Credential must belong to the existing project');
    const { cert } = require('firebase-admin/app');
    const token = (await cert(credential).getAccessToken()).access_token;
    const get = async url => {
      const u = new URL(url);
      if (u.protocol !== 'https:' || !['firebaserules.googleapis.com','firestore.googleapis.com','identitytoolkit.googleapis.com','firebase.googleapis.com'].includes(u.hostname)) throw new Error('Read target is not allowlisted');
      const response = await fetchImpl(url, { method: 'GET', redirect: 'error', headers: { Authorization: `Bearer ${token}` } });
      if (!response.ok) throw new Error(`Firebase read denied (${response.status})`);
      return response.json();
    };
    try {
      const release = await get(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
      if (!release.rulesetName?.startsWith(`projects/${PROJECT}/rulesets/`)) throw new Error('Release project mismatch');
      const ruleset = await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
      const files = ruleset.source?.files;
      if (files?.length !== 1 || typeof files[0].content !== 'string') throw new Error('Multi-file rules require manual review');
      fs.writeFileSync(path.join(destination, 'published.rules'), files[0].content);
      Object.assign(result, { live_release_verified: true, ruleset_name: release.rulesetName, release_name: release.name, rules_sha256: sha(files[0].content) });
      fs.writeFileSync(path.join(destination, 'release.json'), JSON.stringify(release, null, 2) + '\n');
    } catch { result.blockers.push('Published Firestore release/source unavailable; check rules read IAM.'); }
    for (const [name, url] of Object.entries({ indexes: `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes?pageSize=100`, auth_config: `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`, project: `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}` })) {
      try {
        const body = await get(url);
        if (name === 'auth_config') result.password_provider_enabled = body.signIn?.email?.enabled === true;
        else if (name === 'indexes') { fs.writeFileSync(path.join(destination, 'published-indexes.json'), JSON.stringify(body, null, 2) + '\n'); result.indexes_truncated = !!body.nextPageToken; }
        else result.firebase_project_verified = body.projectId === PROJECT;
      } catch { result.blockers.push(`${name} read unavailable; verify permissions/configuration separately.`); }
    }
  }
  fs.writeFileSync(path.join(destination, 'audit.json'), JSON.stringify(result, null, 2) + '\n');
  return result;
}
async function main() {
  require('@next/env').loadEnvConfig(process.cwd(), false, { info() {}, error() {} });
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Use a clean shell for cloud inspection');
  const file = process.argv[2], destination = process.argv[3] || 'review/web-5/evidence/cloud-inspection';
  const raw = file ? fs.readFileSync(file, 'utf8') : process.env.FIREBASE_ADMIN_SDK;
  const result = await audit({ credential: raw ? JSON.parse(raw) : null, destination });
  console.log(JSON.stringify({ project: result.project, live_release_verified: result.live_release_verified, blockers: result.blockers, writes: 0, ai_requests: 0 }, null, 2));
}
if (require.main === module) main().catch(() => { console.error('Read-only Firebase inspection unavailable; credentials and raw API errors omitted.'); process.exitCode = 1; });
module.exports = { audit, PROJECT };
