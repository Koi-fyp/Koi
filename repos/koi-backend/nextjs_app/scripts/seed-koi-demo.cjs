// Explicit local operator action only. No dotenv loading, credential output or production fallback.
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { guard, passwords, IDENTITIES } = require('./koi-demo-guard.cjs');
const canonical = x => x && typeof x === 'object' ? Array.isArray(x) ? '[' + x.map(canonical).join(',') + ']' : '{' + Object.keys(x).sort().map(k => JSON.stringify(k) + ':' + canonical(x[k])).join(',') + '}' : JSON.stringify(x);
const hash = x => createHash('sha256').update(canonical(x)).digest('hex');
async function seed(env = process.env) {
  const { base } = guard(env), secrets = passwords(env);
  if (env !== process.env) throw new Error('explicit_process_environment_required');
  const { auth, db } = require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
  const marker = db.collection('demo_seed_manifests').doc('web4_v1');
  await db.runTransaction(async tx => { const s = await tx.get(marker); if (s.exists && s.data().fixture !== 'KOI_WEB4_FICTIONAL') throw new Error('unexpected_demo_manifest'); if (!s.exists) tx.create(marker, { fixture: 'KOI_WEB4_FICTIONAL', version: 1, created_at: new Date().toISOString() }); });
  const tokens = {};
  for (const [role, identity] of Object.entries(IDENTITIES)) {
    let existing; try { existing = await auth.getUser(identity.uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
    if (existing && (existing.email !== identity.email || existing.displayName !== `Fictional KOI demo ${role}` || existing.disabled)) throw new Error('unexpected_existing_identity');
    if (existing) await auth.updateUser(identity.uid, { password: secrets[role] });
    else await auth.createUser({ ...identity, displayName: `Fictional KOI demo ${role}`, password: secrets[role] });
    if (role !== 'psychologist') await db.runTransaction(async tx => {
      const ref = db.collection('accounts').doc(identity.uid), snap = await tx.get(ref);
      if (snap.exists) { if (snap.data().registration_evidence_id !== 'web4_fictional_operator_seed' || !snap.data().general_access || snap.data().state !== 'registered') throw new Error('unexpected_existing_registration'); return; }
      tx.create(ref, { uid: identity.uid, state: 'registered', general_access: true, registration_method: 'restricted_seeded_verification', registration_evidence_id: 'web4_fictional_operator_seed', registered_at: new Date().toISOString(), authorization_revision: 1 });
      tx.create(db.collection('audit_events').doc(`web4_registration_${role}`), { actor_uid: 'koi_demo_web4_operator', subject_uid: identity.uid, operation: 'emulator_only_fictional_registration', occurred_at: new Date().toISOString() });
    });
    const login = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: identity.email, password: secrets[role], returnSecureToken: true }) });
    if (!login.ok) throw new Error('demo_login_failed'); tokens[role] = (await login.json()).idToken;
  }
  try { await auth.getUser('koi_demo_web4_operator'); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; await auth.createUser({ uid: 'koi_demo_web4_operator', displayName: 'Fictional restricted demo operator' }); }
  for (const state of ['pending', 'verified']) {
    const result = spawnSync(process.execPath, ['scripts/platform-verify-psychologist.cjs', '--uid', IDENTITIES.psychologist.uid, '--state', state, '--evidence-id', 'web4_fictional_operator_seed', '--request-id', `web4_${state}`], { cwd: require('node:path').join(__dirname, '..'), env: { ...env, KOI_PLATFORM_BOOTSTRAP_ADMIN_UID: 'koi_demo_web4_operator', KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT: 'emulator-only' }, encoding: 'utf8', timeout: 30000, windowsHide: true });
    if (result.status !== 0) throw new Error('restricted_demo_verification_failed');
  }
  const api = async (path, method = 'GET', body, role = 'psychologist', key = 'web4_seed') => {
    const response = await fetch(base + path, { method, redirect: 'error', headers: { Authorization: `Bearer ${tokens[role]}`, ...(method === 'GET' ? {} : { 'Content-Type': 'application/json', 'Idempotency-Key': key }) }, body: method === 'GET' ? undefined : JSON.stringify(body) });
    if (!response.ok) throw new Error(`demo_route_failed_${response.status}_${path.split('?')[0]}`);
    return response.json();
  };
  const org = await api('/api/v1/professional/organizations', 'POST', { name: 'Fictional KOI demonstration practice' }, 'psychologist', 'web4_org');
  const profileRef = db.collection('psychologist_profiles').doc(IDENTITIES.psychologist.uid);
  if (!(await profileRef.get()).exists) await api('/api/v1/professional/profile', 'PUT', { organization_id: org.id, display_name: 'Fictional Demo Psychologist', bio: 'Fictional demonstration practice. No real patient data or clinical advice.', discoverable: true, accepting_new_patients: true, expected_revision: 0 }, 'psychologist', 'web4_profile');
  let caps = await api('/api/v1/me/capabilities', 'GET', undefined, 'patient');
  let relation = caps.active_patient_relationships.find(r => r.organization_id === org.id);
  if (!relation) {
    const day = new Date().toISOString().slice(0, 10), expires = new Date(Date.parse(day) + 2 * 86400000).toISOString();
    const invite = await api('/api/v1/professional/patient-invitations', 'POST', { organization_id: org.id, intended_uid: IDENTITIES.patient.uid, expires_at: expires }, 'psychologist', `web4_invite_${day}`);
    await api(`/api/v1/patient-invitations/${invite.token}/redeem`, 'POST', { consent_version: 'care-consent-v1' }, 'patient', `web4_redeem_${day}`);
    caps = await api('/api/v1/me/capabilities', 'GET', undefined, 'patient'); relation = caps.active_patient_relationships.find(r => r.organization_id === org.id);
  }
  if (!relation) throw new Error('demo_relationship_unavailable');
  const assets = require('../src/lib/platform/illustrations.json');
  const content = { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: 'Fictional demo check-in' }, locales: ['en'], questions: [
    { id: 'reflection', type: 'short_text', required: true, prompt: { en: 'What would you like to discuss in this fictional demonstration?' }, max_length: 1000 },
    { id: 'picture', type: 'image_single_choice', required: true, prompt: { en: 'Choose a shape for this demonstration' }, options: assets.assets.slice(0, 2).map((a, i) => ({ id: `shape_${i}`, label: { en: i ? 'Square' : 'Circle' }, asset: a.reference })) },
  ] };
  const draft = await api('/api/v1/professional/questionnaires', 'POST', { organization_id: org.id, content }, 'psychologist', 'web4_draft');
  const version = await api(`/api/v1/professional/questionnaires/${draft.id}/publish`, 'POST', { expected_revision: 1, expected_content_sha256: hash(content) }, 'psychologist', 'web4_publish');
  const assignments = {};
  for (const kind of ['open', 'submitted']) assignments[kind] = (await api('/api/v1/professional/assignments', 'POST', { organization_id: org.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [relation.relationship_id] } }, 'psychologist', `web4_assign_${kind}`)).assignment_ids[0];
  let detail = await api(`/api/v1/patient/assignments/${assignments.submitted}`, 'GET', undefined, 'patient');
  if (detail.attempt) {
    const answers = [{ question_id: 'reflection', type: 'short_text', value: 'Fictional demo response. No real patient information.' }, { question_id: 'picture', type: 'image_single_choice', value: 'shape_0' }];
    if (canonical(detail.attempt.answers) !== canonical(answers)) await api(`/api/v1/patient/attempts/${detail.attempt.id}`, 'PATCH', { expected_revision: detail.attempt.revision, answers }, 'patient', 'web4_save');
    detail = await api(`/api/v1/patient/assignments/${assignments.submitted}`, 'GET', undefined, 'patient');
    await api(`/api/v1/patient/attempts/${detail.attempt.id}/submit`, 'POST', { expected_revision: detail.attempt.revision }, 'patient', 'web4_submit');
  }
  const submission = (await db.collection('submissions').where('assignment_id', '==', assignments.submitted).get()).docs[0];
  if (!submission) throw new Error('demo_submission_missing');
  const workspace = await api(`/api/v1/professional/submissions/${submission.id}/workspace`);
  if (workspace.review_revision === 0) await api('/api/v1/professional/review-decisions', 'POST', { organization_id: org.id, evaluation_id: workspace.evaluation.id, expected_review_revision: 0, conclusion: 'Fictional manual demonstration review. No diagnosis or validated score is supplied.', feedback: 'AI worker is not connected; this is a manual review.', decision: 'approve' }, 'psychologist', 'web4_review');
  const requests = await api('/api/v1/connection-requests', 'GET', undefined, 'general');
  let application = requests.items.find(r => r.psychologist_uid === IDENTITIES.psychologist.uid);
  if (!application) application = await api('/api/v1/connection-requests', 'POST', { psychologist_uid: IDENTITIES.psychologist.uid, consent_version: 'care-consent-v1' }, 'general', 'web4_application');
  if (application.state === 'requested') application = await api(`/api/v1/connection-requests/${application.id}/transition`, 'POST', { expected_revision: application.revision, to_state: 'awaiting_demo_payment' }, 'general', 'web4_application_continue');
  if (application.state === 'awaiting_demo_payment') await api(`/api/v1/connection-requests/${application.id}/demo-payment`, 'POST', { expected_revision: application.revision }, 'general', 'web4_demo_payment');
  const summary = { fixture: 'KOI_WEB4_FICTIONAL', organization_id: org.id, questionnaire_version_id: version.id, relationship_id: relation.relationship_id, assignments, submission_id: submission.id, evaluation_id: workspace.evaluation.id };
  await marker.set({ ...summary, version: 1 }, { merge: true });
  return summary;
}
if (require.main === module) seed().then(s => { process.stdout.write(JSON.stringify({ ...s, emails: Object.fromEntries(Object.entries(IDENTITIES).map(([r, i]) => [r, i.email])), passwords: 'Configured from operator environment; never printed' }, null, 2) + '\n'); }).catch(() => { process.stderr.write('Demo seed failed. Check exact demo guards, password variables, running Next routes and existing demo state. No production fallback.\n'); process.exitCode = 1; });
module.exports = { seed };
