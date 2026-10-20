// Not imported by any public route. No provider/companion code or credentials here.
const { createHash } = require('node:crypto');
const { seedVerification } = require('./platform-verify-psychologist.cjs');
const PROJECT = 'koi-companion-fyp';
const canonical = v => v && typeof v === 'object' ? Array.isArray(v) ? '[' + v.map(canonical).join(',') + ']' : '{' + Object.keys(v).sort().map(k => JSON.stringify(k)+':'+canonical(v[k])).join(',') + '}' : JSON.stringify(v);
const hash = v => createHash('sha256').update(canonical(v)).digest('hex');
function identities(runId) {
  if (!/^[a-z0-9][a-z0-9_-]{7,31}$/.test(runId)) throw new Error('Use a unique 8-32 character fictional run ID');
  return Object.fromEntries(['psychologist','general','patient'].map(role => [role, { uid: `koi_exam_${runId}_${role}`, email: `koi-exam-${role}-${runId}@example.invalid`, displayName: `Fictional KOI examiner ${runId} ${role}` }]));
}
function trackedStore(base, runId) {
  return { transaction: work => base.transaction(async tx => {
    const pending = new Map();
    const read = method => (...args) => { if (pending.size) throw new Error('Service read after write refused'); return tx[method](...args); };
    const write = operation => (collection, id, value) => {
      if (['users','conversations','mood_entries','wellness_progress','tasks','demo_provision_runs','demo_provision_records'].includes(collection)) throw new Error('Provisioning namespace denied');
      const key = `${collection}/${id}`, prior = pending.get(key);
      pending.set(key, { collection, id, value, operation: prior?.operation ?? operation });
    };
    const result = await work({ get: read('get'), query: read('query'), drafts: read('drafts'), create: write('create'), set: write('set') });
    const prepared = [];
    for (const item of pending.values()) {
      const recordId = hash([runId, item.collection, item.id]);
      const current = await tx.get(item.collection, item.id), receipt = await tx.get('demo_provision_records', recordId);
      if (current && (!receipt || receipt.run_id !== runId || receipt.path !== `${item.collection}/${item.id}`)) throw new Error('Existing unowned record refused');
      prepared.push({ ...item, recordId, receipt });
    }
    for (const item of prepared) {
      tx[item.operation](item.collection, item.id, item.value);
      tx.set('demo_provision_records', item.recordId, { run_id: runId, project: PROJECT, path: `${item.collection}/${item.id}`, fictional: true, created_by_run: true, content_sha256: hash(item.value) });
    }
    return result === undefined ? null : result;
  }) };
}
async function provision({ auth, store: base, serviceFactory, runId, actorUid, serviceIdentity, passwords, now = () => new Date() }) {
  const roles = identities(runId), at = now().toISOString();
  if (!actorUid || Object.values(roles).some(i => i.uid === actorUid) || !serviceIdentity?.endsWith(`@${PROJECT}.iam.gserviceaccount.com`)) throw new Error('Restricted operator identity required');
  for (const role of Object.keys(roles)) if (typeof passwords[role] !== 'string' || passwords[role].length < 12 || passwords[role].length > 128) throw new Error('Operator passwords must contain 12-128 characters');
  if ((await auth.getUser(actorUid)).disabled) throw new Error('Operator disabled');
  let manifest = await base.transaction(tx => tx.get('demo_provision_runs', runId));
  if (manifest && (manifest.project !== PROJECT || !manifest.fictional || manifest.actor_uid !== actorUid || manifest.service_identity !== serviceIdentity || canonical(manifest.identities) !== canonical(roles))) throw new Error('Foreign run manifest refused');
  if (!manifest) {
    for (const identity of Object.values(roles)) for (const lookup of [() => auth.getUser(identity.uid), () => auth.getUserByEmail(identity.email)]) {
      try { await lookup(); throw new Error('Existing Auth identity refused'); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
    }
    manifest = { project: PROJECT, run_id: runId, fictional: true, actor_uid: actorUid, service_identity: serviceIdentity, created_at: at, status: 'started', identities: roles };
    await base.transaction(async tx => { if (await tx.get('demo_provision_runs', runId)) throw new Error('Concurrent provision refused'); tx.create('demo_provision_runs', runId, manifest); return true; });
  }
  for (const [role, identity] of Object.entries(roles)) {
    let user;
    try { user = await auth.getUser(identity.uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; user = await auth.createUser({ ...identity, password: passwords[role], emailVerified: false }); }
    if (user.email !== identity.email || user.displayName !== identity.displayName || user.disabled || !user.providerData.some(p => p.providerId === 'password')) throw new Error('Unexpected fictional identity state');
    // No updateUser call: neither real nor existing fictional passwords are overwritten.
  }
  if (manifest.status === 'complete') return manifest;
  const store = trackedStore(base, runId), service = serviceFactory(store), actor = role => ({ uid: roles[role].uid, authTime: +now()/1000 });
  for (const role of ['general','patient']) await store.transaction(async tx => {
    const uid = roles[role].uid, old = await tx.get('accounts', uid);
    if (old) { if (old.registration_evidence_id !== `fictional_${runId}` || old.state !== 'registered' || !old.general_access) throw new Error('Registration conflict'); return; }
    tx.create('accounts', uid, { uid, state: 'registered', general_access: true, registration_method: 'restricted_seeded_verification', registration_evidence_id: `fictional_${runId}`, registered_at: at, authorization_revision: 1 });
    tx.create('audit_events', `exam_${runId}_${role}`, { actor_uid: actorUid, service_identity: serviceIdentity, subject_uid: uid, operation: 'restricted_fictional_demo_registration', occurred_at: at });
  });
  for (const state of ['pending','verified']) await seedVerification({ store, uid: roles.psychologist.uid, state, evidenceId: `fictional_${runId}`, requestId: `${runId}_${state}`, actorUid, serviceIdentity, now });
  const pro = actor('psychologist'), patient = actor('patient'), general = actor('general');
  const organization = await service.createOrganization(pro, { name: `Fictional examiner practice ${runId}` }, `${runId}_org`);
  await service.profile(pro, organization.id, { organization_id: organization.id, display_name: `Fictional Examiner Psychologist ${runId}`, bio: 'Fictional examiner demonstration only. No real patient or clinical advice.', discoverable: true, accepting_new_patients: true, expected_revision: 0 }, `${runId}_profile`);
  let caps = await service.capabilities(patient), relationship = caps.active_patient_relationships.find(r => r.organization_id === organization.id);
  if (!relationship) {
    const invitation = await service.createInvitation(pro, { organization_id: organization.id, intended_uid: patient.uid, expires_at: new Date(Date.parse(manifest.created_at) + 86400000).toISOString() }, `${runId}_invite`);
    await service.redeemInvitation(patient, invitation.token, { consent_version: 'care-consent-v1' }, `${runId}_redeem`);
    caps = await service.capabilities(patient); relationship = caps.active_patient_relationships.find(r => r.organization_id === organization.id);
  }
  const assets = require('../src/lib/platform/illustrations.json').assets;
  const content = { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: `Fictional examiner check-in ${runId}` }, locales: ['en'], questions: [
    { id: 'reflection', type: 'short_text', required: true, prompt: { en: 'Fictional demonstration: what would you like to discuss?' }, max_length: 1000 },
    { id: 'picture', type: 'image_single_choice', required: true, prompt: { en: 'Choose a fictional demonstration shape' }, options: assets.slice(0,2).map((a,i) => ({ id: `shape_${i}`, label: { en: i ? 'Square' : 'Circle' }, asset: a.reference })) },
  ] };
  const draft = await service.createDraft(pro, { organization_id: organization.id, content }, `${runId}_draft`);
  const version = await service.publish(pro, draft.id, { expected_revision: 1, expected_content_sha256: hash(content) }, `${runId}_publish`);
  const assignments = {};
  for (const kind of ['open','submitted']) assignments[kind] = (await service.assign(pro, { organization_id: organization.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [relationship.relationship_id] } }, `${runId}_assign_${kind}`)).assignment_ids[0];
  let detail = await service.patientDetail(patient, assignments.submitted);
  if (detail.attempt) {
    const answers = [{ question_id: 'reflection', type: 'short_text', value: 'Fictional examiner response only.' }, { question_id: 'picture', type: 'image_single_choice', value: 'shape_0' }];
    await service.saveAttempt(patient, detail.attempt.id, { expected_revision: detail.attempt.revision, answers }, `${runId}_save`);
    detail = await service.patientDetail(patient, assignments.submitted);
    await service.saveAttempt(patient, detail.attempt.id, { expected_revision: detail.attempt.revision }, `${runId}_submit`, true);
  }
  const submissions = await service.list(pro, 'submissions', organization.id);
  const submission = submissions.items.find(s => s.assignment_id === assignments.submitted);
  const workspace = await service.workspace(pro, submission.id);
  if (workspace.review_revision === 0) await service.createReview(pro, { organization_id: organization.id, evaluation_id: workspace.evaluation.id, expected_review_revision: 0, conclusion: 'Fictional manual examiner review. No diagnosis or validated score.', feedback: 'AI worker is pending; no model was invoked.', decision: 'approve' }, `${runId}_review`, true);
  let request = await service.createConnection(general, { psychologist_uid: pro.uid, consent_version: 'care-consent-v1' }, `${runId}_application`);
  if (request.state === 'requested') request = await service.transitionConnection(general, request.id, { expected_revision: request.revision, to_state: 'awaiting_demo_payment' }, `${runId}_continue`);
  if (request.state === 'awaiting_demo_payment') await service.transitionConnection(general, request.id, { expected_revision: request.revision }, `${runId}_payment`, true);
  const complete = { ...manifest, status: 'complete', completed_at: now().toISOString(), organization_id: organization.id, relationship_id: relationship.relationship_id, questionnaire_version_id: version.id, assignments, submission_id: submission.id, evaluation_id: workspace.evaluation.id };
  await base.transaction(async tx => { const current = await tx.get('demo_provision_runs', runId); if (current?.actor_uid !== actorUid) throw new Error('Run changed'); tx.set('demo_provision_runs', runId, complete); return true; });
  return complete;
}
module.exports = { PROJECT, hash, identities, trackedStore, provision };
