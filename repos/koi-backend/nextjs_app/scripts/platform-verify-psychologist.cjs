// Restricted admin CLI; no public HTTP endpoint imports this module. Never prints credentials/tokens.
const { createHash } = require('node:crypto');
const idPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
class BootstrapError extends Error {}
const fail = code => { throw new BootstrapError(code); };

async function seedVerification({ store, uid, state, evidenceId, requestId, actorUid, serviceIdentity, now = () => new Date() }) {
  if (typeof uid !== 'string' || !uid || uid.length > 128 || /[\/\u0000-\u001f]/.test(uid) || !actorUid || !serviceIdentity || typeof evidenceId !== 'string' || typeof requestId !== 'string' || !idPattern.test(evidenceId) || !idPattern.test(requestId) || !['pending', 'verified', 'rejected', 'suspended'].includes(state)) fail('invalid_arguments');
  const digest = sha([uid, state, evidenceId]);
  const receiptId = 'bootstrap_' + sha([actorUid, uid, requestId]);
  const auditId = 'audit_' + receiptId;
  const at = now().toISOString();
  return store.transaction(async tx => {
    const account = await tx.get('accounts', uid);
    const current = await tx.get('psychologist_verifications', uid);
    const receipt = await tx.get('idempotency_records', receiptId);
    if (receipt) {
      if (receipt.request_hash !== digest || receipt.actor_uid !== actorUid) fail('idempotency_conflict');
      return { state: receipt.state, revision: receipt.revision, replayed: true };
    }
    const allowed = { pending: ['verified', 'rejected'], verified: ['suspended'], rejected: ['pending'], suspended: ['pending'] };
    if ((!current && state !== 'pending') || (current && !allowed[current.state]?.includes(state))) fail('invalid_transition');
    if (account && (account.uid !== uid || account.state !== 'registered')) fail('account_unavailable');
    if (current && current.uid !== uid) fail('identity_mismatch');
    const revision = (current?.revision ?? 0) + 1;
    tx.set('accounts', uid, account ? { ...account, authorization_revision: account.authorization_revision + 1 } : {
      uid, state: 'registered', general_access: false, registration_method: 'restricted_seeded_verification',
      registration_evidence_id: evidenceId, registered_at: at, authorization_revision: 1,
    });
    tx.set('psychologist_verifications', uid, { uid, state, revision, changed_at: at, changed_by: actorUid, audit_id: auditId });
    tx.create('audit_events', auditId, { actor_uid: actorUid, service_identity: serviceIdentity, subject_uid: uid, operation: 'psychologist_verification', previous_state: current?.state ?? null, state, evidence_id: evidenceId, occurred_at: at });
    tx.create('idempotency_records', receiptId, { actor_uid: actorUid, request_hash: digest, state, revision, created_at: at });
    return { state, revision, replayed: false };
  });
}

async function main() {
  const args = process.argv.slice(2);
  const values = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--uid', '--state', '--evidence-id', '--request-id'].includes(args[i]) || !args[i + 1] || values[args[i]]) fail('invalid_arguments');
    values[args[i]] = args[i + 1];
  }
  const { getPlatformAdmin } = require('../src/lib/platform/server/admin-config.cjs');
  const { auth, db, config } = getPlatformAdmin();
  const actorUid = process.env.KOI_PLATFORM_BOOTSTRAP_ADMIN_UID;
  const allowedService = process.env.KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT;
  const serviceIdentity = config.mode === 'emulator' ? 'emulator-only' : config.credential?.client_email;
  if (!actorUid || !allowedService || serviceIdentity !== allowedService) fail('admin_identity_not_allowlisted');
  const [operator, target] = await Promise.all([auth.getUser(actorUid), auth.getUser(values['--uid'])]);
  if (operator.disabled || target.disabled || !target.providerData.some(p => p.providerId === 'password')) fail('existing_password_identity_required');
  const store = { transaction: run => db.runTransaction(tx => run({
    get: async (collection, id) => { const snap = await tx.get(db.collection(collection).doc(id)); return snap.exists ? snap.data() : null; },
    set: (collection, id, data) => { tx.set(db.collection(collection).doc(id), data); },
    create: (collection, id, data) => { tx.create(db.collection(collection).doc(id), data); },
  })) };
  const result = await seedVerification({ store, uid: values['--uid'], state: values['--state'], evidenceId: values['--evidence-id'], requestId: values['--request-id'], actorUid, serviceIdentity });
  process.stdout.write(JSON.stringify({ operation: 'psychologist_verification', ...result }) + '\n');
}
if (require.main === module) main().catch(error => {
  process.stderr.write((error instanceof BootstrapError ? error.message : 'bootstrap_unavailable_check_private_configuration') + '\n');
  process.exitCode = 1;
});
module.exports = { seedVerification, BootstrapError };
