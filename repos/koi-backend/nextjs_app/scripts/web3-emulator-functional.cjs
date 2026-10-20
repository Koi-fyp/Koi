// Fictional accounts and data, guarded local emulators only. No live services or provider calls.
const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { mkdirSync, writeFileSync, existsSync } = require('node:fs');
const { chromium } = require('playwright');
const { getPlatformAdmin } = require('../src/lib/platform/server/admin-config.cjs');
const manifest = require('../src/lib/platform/illustrations.json');
let stage = 'configuration';
async function main() {
  const { auth, db, config } = getPlatformAdmin();
  assert.equal(config.mode, 'emulator'); assert.equal(config.project, 'demo-koi-platform-web1');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:5180'); assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:5199');
  const suffix = randomUUID().slice(0, 8), password = randomUUID() + '-Fictional!', checks = [];
  const pass = name => { checks.push(name); process.stdout.write(`PASS ${name}\n`); };
  const users = {}, tokens = {};
  for (const role of ['operator', 'clinician', 'other', 'patient', 'applicant', 'outsider']) users[role] = await auth.createUser({ uid: `w2_${role}_${suffix}`, email: `w2-${role}-${suffix}@example.invalid`, password });
  for (const role of ['clinician', 'other']) for (const state of ['pending', 'verified']) {
    const r = spawnSync(process.execPath, ['scripts/platform-verify-psychologist.cjs', '--uid', users[role].uid, '--state', state, '--evidence-id', 'fictional_review', '--request-id', `${role}_${state}`], { env: { ...process.env, KOI_PLATFORM_BOOTSTRAP_ADMIN_UID: users.operator.uid, KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT: 'emulator-only' }, encoding: 'utf8', timeout: 30000 });
    assert.equal(r.status, 0, 'Restricted verification must succeed');
  }
  for (const role of ['patient', 'applicant', 'outsider']) await db.collection('accounts').doc(users[role].uid).create({ uid: users[role].uid, state: 'registered', general_access: true, registration_method: 'restricted_seeded_verification', registration_evidence_id: 'fictional_emulator_only', registered_at: new Date().toISOString(), authorization_revision: 1 });
  for (const role of ['clinician', 'other', 'patient', 'applicant', 'outsider']) {
    const r = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: users[role].email, password, returnSecureToken: true }) }); assert.equal(r.status, 200); tokens[role] = (await r.json()).idToken;
  }
  const base = 'http://127.0.0.1:3107';
  const api = async (path, method = 'GET', body, role = 'clinician', key = randomUUID()) => {
    const r = await fetch(base + path, { method, headers: { Authorization: `Bearer ${tokens[role]}`, ...(method === 'GET' ? {} : { 'Content-Type': 'application/json', 'Idempotency-Key': key }) }, body: method === 'GET' ? undefined : JSON.stringify(body) });
    const data = await r.json(); return { status: r.status, data, headers: r.headers };
  };
  const ok = async (...args) => { const r = await api(...args); assert(r.status >= 200 && r.status < 300, `API failed in ${stage}: ${r.status} ${r.data.code}`); return r.data; };
  const canonical = x => x && typeof x === 'object' ? Array.isArray(x) ? '[' + x.map(canonical).join(',') + ']' : '{' + Object.keys(x).sort().map(k => JSON.stringify(k) + ':' + canonical(x[k])).join(',') + '}' : JSON.stringify(x);
  const hash = x => createHash('sha256').update(canonical(x)).digest('hex');
  stage = 'WEB-1 baseline authoring';
  const org = await ok('/api/v1/professional/organizations', 'POST', { name: 'Fictional WEB-2 practice' });
  await ok('/api/v1/professional/profile', 'PUT', { organization_id: org.id, display_name: 'Fictional WEB-3 expert', bio: 'Fictional emulator practice', discoverable: true, accepting_new_patients: true, expected_revision: 0 });
  const otherOrg = await ok('/api/v1/professional/organizations', 'POST', { name: 'Fictional other practice' }, 'other');
  const content = { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: 'Fictional care check-in', ur: 'خیالی سوالنامہ' }, locales: ['en', 'ur'], questions: [
    { id: 'text_q', type: 'short_text', required: true, prompt: { en: 'What would you like to discuss?', ur: 'آپ کیا کہنا چاہتے ہیں؟' }, max_length: 1000 },
    { id: 'picture_q', type: 'image_single_choice', required: true, prompt: { en: 'Choose a shape', ur: 'ایک شکل منتخب کریں' }, options: manifest.assets.slice(0, 2).map((a, i) => ({ id: `shape_${i}`, label: { en: i ? 'Square' : 'Circle', ur: i ? 'مربع' : 'دائرہ' }, asset: a.reference })) },
  ] };
  const draft = await ok('/api/v1/professional/questionnaires', 'POST', { organization_id: org.id, content });
  const version = await ok(`/api/v1/professional/questionnaires/${draft.id}/publish`, 'POST', { expected_revision: 1, expected_content_sha256: hash(content) });
  pass('verified clinician creates organization and publishes a text/picture EN/UR questionnaire');
  const output = 'review/web-3/evidence'; mkdirSync(output, { recursive: true });
  const installedChrome = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  const browser = await chromium.launch({ headless: true, executablePath: existsSync(chromium.executablePath()) ? undefined : installedChrome });
  let pageErrors = 0, companionRequests = 0; const contexts = [];
  const context = async () => {
    const c = await browser.newContext({ viewport: { width: 1280, height: 950 }, reducedMotion: 'reduce' }); contexts.push(c);
    await c.route('**/*', route => {
      const u = new URL(route.request().url());
      if (u.pathname === '/api/v1/chat' || u.hostname.includes('modal.run')) { companionRequests++; return route.abort(); }
      if (['127.0.0.1', 'localhost', 'fonts.googleapis.com', 'fonts.gstatic.com'].includes(u.hostname)) return route.continue();
      return route.abort();
    });
    const p = await c.newPage(); p.setDefaultTimeout(60000); p.on('pageerror', () => { pageErrors++; }); p.on('dialog', d => d.accept()); return p;
  };
  const login = async (page, role, path) => {
    await page.goto(base + path, { waitUntil: 'domcontentloaded', timeout: 120000 });
    await page.getByRole('textbox', { name: 'Email', exact: true }).fill(users[role].email);
    await page.getByLabel('Password', { exact: true }).fill(password);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  };
  try {
    stage = 'clinician invitation UI'; const pro = await context();
    await login(pro, 'clinician', `/professional?version=${version.id}`);
    await pro.getByRole('button', { name: 'Manage patients and submissions' }).click({ timeout: 120000 });
    await pro.getByLabel('Intended account UID (optional)').fill(users.patient.uid);
    await pro.getByRole('button', { name: 'Create secure invitation' }).click();
    const link = await pro.getByLabel('Single-use invitation link').inputValue({ timeout: 60000 });
    const token = new URLSearchParams(new URL(link).hash.slice(1)).get('invite'); assert(token);
    const inviteDoc = (await db.collection('patient_invitations').where('token_hash', '==', createHash('sha256').update(token).digest('hex')).get()).docs[0]; assert(inviteDoc);
    assert(!JSON.stringify(inviteDoc.data()).includes(token));
    pass('secure invitation UI returns a fragment link and stores no bearer token');
    stage = 'patient invitation redemption'; const patient = await context();
    await login(patient, 'patient', new URL(link).pathname + new URL(link).hash);
    await patient.getByLabel(/I consent to joining/).check({ timeout: 120000 });
    await patient.getByRole('button', { name: 'Accept invitation' }).click();
    await patient.getByRole('heading', { name: 'Assigned questionnaires' }).waitFor({ timeout: 60000 });
    const caps = await ok('/api/v1/me/capabilities', 'GET', undefined, 'patient'), rel = caps.active_patient_relationships[0]; assert(rel);
    assert.equal((await api(`/api/v1/patient-invitations/${token}/redeem`, 'POST', { consent_version: 'care-consent-v1' }, 'patient')).status, 409);
    pass('General account accepts single-use invitation and gains only relationship capabilities');
    stage = 'assignment UI';
    await pro.getByRole('button', { name: 'Refresh patients and submissions' }).click();
    await pro.getByLabel('Assign to all active patients (snapshot at assignment time)').check();
    await pro.getByLabel('Published questionnaire version ID').fill(version.id);
    await pro.getByRole('button', { name: 'Assign published questionnaire' }).click();
    await pro.getByText('1 independent assignments created.').waitFor({ timeout: 60000 });
    const list = await ok('/api/v1/patient/assignments', 'GET', undefined, 'patient'), assignment = list.items[0]; assert(assignment);
    pass('clinician assigns an immutable version using all-active roster snapshot');
    stage = 'patient runner autosave, resume, restart';
    await patient.getByRole('button', { name: 'Refresh your care' }).click();
    await patient.getByRole('button', { name: 'Open questionnaire' }).click();
    await patient.getByRole('textbox', { name: 'What would you like to discuss?' }).fill('Fictional original response');
    await patient.getByLabel('Circle', { exact: true }).check();
    await patient.getByText('All answers saved', { exact: true }).waitFor({ timeout: 60000 });
    await patient.reload({ waitUntil: 'domcontentloaded' });
    await patient.getByRole('button', { name: 'Open questionnaire' }).click({ timeout: 60000 });
    assert.equal(await patient.getByRole('textbox', { name: 'What would you like to discuss?' }).inputValue(), 'Fictional original response');
    await patient.getByRole('button', { name: 'Restart questionnaire' }).click();
    await patient.waitForFunction(() => document.querySelector('textarea')?.value === '');
    const restarted = await ok(`/api/v1/patient/assignments/${assignment.id}`, 'GET', undefined, 'patient'); assert.deepEqual(restarted.attempt.answers, []);
    await patient.getByRole('combobox').selectOption('ur');
    assert.equal(await patient.getByRole('textbox', { name: 'آپ کیا کہنا چاہتے ہیں؟' }).evaluate(el => el.closest('[dir]').dir), 'rtl');
    await patient.setViewportSize({ width: 390, height: 844 }); await patient.screenshot({ path: `${output}/patient-urdu-mobile.png`, fullPage: true });
    assert(await patient.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await patient.getByRole('combobox').selectOption('en');
    await patient.getByRole('textbox', { name: 'What would you like to discuss?' }).fill('Fictional final response'); await patient.getByLabel('Square', { exact: true }).check();
    await patient.getByText('All answers saved', { exact: true }).waitFor({ timeout: 60000 });
    pass('runner autosaves and resumes across reload, restarts, renders bundled pictures and mobile Urdu RTL');
    stage = 'final confirmation';
    await patient.getByRole('button', { name: 'Review before submitting' }).click();
    await patient.getByRole('button', { name: 'Confirm final submission' }).click();
    await patient.getByRole('heading', { name: 'Questionnaire submitted' }).waitFor({ timeout: 60000 });
    const patientText = await patient.locator('body').innerText(); assert(!/evaluation|interpretation|validated score|AI processing/i.test(patientText));
    await patient.screenshot({ path: `${output}/patient-acknowledgement.png`, fullPage: true });
    const submitted = await ok(`/api/v1/patient/assignments/${assignment.id}`, 'GET', undefined, 'patient');
    assert.deepEqual(Object.keys(submitted).sort(), ['acknowledgement', 'assignment']);
    assert.deepEqual(Object.keys(submitted.acknowledgement).sort(), ['assignment_id', 'attempt_id', 'status', 'submitted_at']);
    const dup = await Promise.all(['a', 'b'].map(k => ok(`/api/v1/patient/attempts/${assignment.attempt_id}/submit`, 'POST', { expected_revision: 0 }, 'patient', `duplicate_${k}`)));
    assert.deepEqual(dup[0], submitted.acknowledgement); assert.deepEqual(dup[1], dup[0]);
    assert.equal((await db.collection('ai_jobs').where('job.organization_id', '==', org.id).get()).size, 1);
    assert.equal((await api(`/api/v1/patient/attempts/${assignment.attempt_id}`, 'PATCH', { expected_revision: 1, answers: [] }, 'patient')).status, 409);
    pass('confirmation locks answers; duplicate concurrent submissions return one acknowledgement/job');
    stage = 'professional review UI';
    await pro.getByRole('button', { name: 'Refresh patients and submissions' }).click(); await pro.getByRole('button', { name: 'Inspect submission' }).click();
    await pro.getByText('No AI interpretation is available. You can review the original answers manually.').waitFor({ timeout: 60000 });
    await pro.getByLabel('Psychologist conclusion').fill('Fictional manual clinician observation'); await pro.getByLabel('Review feedback').fill('Fictional feedback');
    await pro.getByRole('button', { name: 'Approve review' }).click(); await pro.getByText('Review revision saved. Original interpretation preserved.').waitFor({ timeout: 60000 });
    const submissions = await ok(`/api/v1/professional/submissions?organization_id=${org.id}`), sid = submissions.items[0].id;
    let workspace = await ok(`/api/v1/professional/submissions/${sid}/workspace`); assert.equal(workspace.review_revision, 1); assert.deepEqual(workspace.evaluation.validated_scores, []); assert.equal(workspace.job.state, 'queued');
    pass('psychologist manually reviews raw answers while AI is queued and custom scores are absent');
    stage = 'synthetic unavailable AI and immutable original response';
    // Explicit test fixtures only; no worker/provider is implemented or simulated by runtime.
    const original = { ...(await db.collection('clinician_evaluations').doc(workspace.evaluation.id).get()).data(), interpretation: 'FICTIONAL AI fixture: original interpretation', provider_response_sha256: 'a'.repeat(64) };
    await db.collection('clinician_evaluations').doc(workspace.evaluation.id).set(original);
    await db.collection('ai_jobs').doc(workspace.job.id).update({ 'job.state': 'failed', 'job.failure_code': 'provider_unavailable' });
    await pro.getByRole('button', { name: 'Refresh evaluation and reviews' }).click(); await pro.getByText(original.interpretation, { exact: true }).waitFor();
    await pro.getByLabel('Psychologist conclusion').fill('Fictional corrected observation'); await pro.getByRole('button', { name: 'Reject evaluation' }).click();
    await pro.getByText('Revision 2 · reject').waitFor({ timeout: 60000 });
    assert.deepEqual((await db.collection('clinician_evaluations').doc(workspace.evaluation.id).get()).data(), original);
    assert.deepEqual(await ok(`/api/v1/patient/attempts/${assignment.attempt_id}/submit`, 'POST', { expected_revision: 0 }, 'patient'), submitted.acknowledgement);
    await pro.screenshot({ path: `${output}/professional-review.png`, fullPage: true });
    pass('provider failure never affects acknowledgement; review decisions preserve original fixture separately');
    stage = 'patient and organization isolation';
    for (const role of ['patient', 'outsider']) for (const path of [`/api/v1/professional/submissions/${sid}`, `/api/v1/professional/evaluations/${workspace.evaluation.id}`, `/api/v1/professional/submissions/${sid}/workspace`, `/api/v1/professional/evaluations/${workspace.evaluation.id}/reviews`]) assert.equal((await api(path, 'GET', undefined, role)).status, 403);
    assert.equal((await api(`/api/v1/patient/assignments/${assignment.id}`, 'GET', undefined, 'outsider')).status, 404);
    assert.equal((await api(`/api/v1/professional/submissions/${sid}/workspace`, 'GET', undefined, 'other')).status, 404);
    assert.equal((await api('/api/v1/professional/assignments', 'POST', { organization_id: otherOrg.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [rel.relationship_id] } }, 'other')).status, 404);
    assert(!JSON.stringify(await ok('/api/v1/patient/assignments', 'GET', undefined, 'patient')).includes(original.interpretation));
    pass('cross-patient, cross-practice and patient-to-evaluation access is denied');
    stage = 'General application and psychologist acceptance';
    const applicationKey = randomUUID();
    let application = await ok('/api/v1/connection-requests', 'POST', { psychologist_uid: users.clinician.uid, consent_version: 'care-consent-v1' }, 'applicant', applicationKey);
    application = await ok(`/api/v1/connection-requests/${application.id}/transition`, 'POST', { expected_revision: application.revision, to_state: 'awaiting_demo_payment' }, 'applicant');
    application = await ok(`/api/v1/connection-requests/${application.id}/demo-payment`, 'POST', { expected_revision: application.revision }, 'applicant');
    assert.deepEqual((await ok('/api/v1/me/capabilities', 'GET', undefined, 'applicant')).active_patient_relationships, []);
    await pro.getByRole('button', { name: 'Refresh patients and submissions' }).click(); await pro.getByRole('button', { name: 'Accept application' }).click();
    await pro.getByText(`${users.applicant.uid} · accepted`, { exact: true }).waitFor({ timeout: 60000 });
    assert.equal((await ok('/api/v1/me/capabilities', 'GET', undefined, 'applicant')).active_patient_relationships.length, 1);
    const replayedApplication = await ok('/api/v1/connection-requests', 'POST', { psychologist_uid: users.clinician.uid, consent_version: 'care-consent-v1' }, 'applicant', applicationKey);
    assert.equal(replayedApplication.id, application.id); assert.equal(replayedApplication.state, 'requested');
    pass('General application demo step grants no rights; clinician acceptance activates relationship');
    stage = 'repeat assignment and concurrent devices';
    const repeat = await ok('/api/v1/professional/assignments', 'POST', { organization_id: org.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [rel.relationship_id] } });
    const repeatDetail = await ok(`/api/v1/patient/assignments/${repeat.assignment_ids[0]}`, 'GET', undefined, 'patient');
    const validAnswers = [{ question_id: 'text_q', type: 'short_text', value: 'Concurrent fictional answer' }, { question_id: 'picture_q', type: 'image_single_choice', value: 'shape_0' }];
    const race = await Promise.all(['one', 'two'].map(k => api(`/api/v1/patient/attempts/${repeatDetail.attempt.id}`, 'PATCH', { expected_revision: 0, answers: validAnswers }, 'patient', `device_${k}`)));
    assert.deepEqual(race.map(r => r.status).sort(), [200, 409]);
    assert.equal((await api(`/api/v1/patient/attempts/${repeatDetail.attempt.id}`, 'PATCH', { expected_revision: 1, version_id: 'forged', answers: validAnswers }, 'patient')).status, 422);
    pass('repeat assignment has independent attempt; multi-device saves conflict and forged version is rejected');
    const firstSubmitRace = await Promise.all(['one', 'two'].map(k => ok(`/api/v1/patient/attempts/${repeatDetail.attempt.id}/submit`, 'POST', { expected_revision: 1 }, 'patient', `first_submit_${k}`)));
    assert.deepEqual(firstSubmitRace[0], firstSubmitRace[1]);
    assert.equal((await db.collection('ai_jobs').where('job.organization_id', '==', org.id).get()).size, 2);
    pass('concurrent first submission across devices creates one additional job and identical acknowledgements');
    const openBatch = await ok('/api/v1/professional/assignments', 'POST', { organization_id: org.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [rel.relationship_id] } });
    const openDetail = await ok(`/api/v1/patient/assignments/${openBatch.assignment_ids[0]}`, 'GET', undefined, 'patient');
    stage = 'Firestore direct reads, writes and queries';
    const firestore = `http://127.0.0.1:5180/v1/projects/${config.project}/databases/(default)/documents`;
    for (const [collection, id] of [['accounts', users.patient.uid], ['patient_relationships', rel.relationship_id], ['assignments', assignment.id], ['attempts', assignment.attempt_id], ['submissions', sid], ['clinician_evaluations', workspace.evaluation.id], ['review_records', 'forged'], ['ai_jobs', workspace.job.id], ['notifications', 'forged']]) {
      const headers = { Authorization: `Bearer ${tokens.patient}`, 'Content-Type': 'application/json' };
      assert.equal((await fetch(`${firestore}/${collection}/${id}`, { headers })).status, 403);
      assert.equal((await fetch(`${firestore}/${collection}/forged`, { method: 'PATCH', headers, body: JSON.stringify({ fields: { patient_uid: { stringValue: users.patient.uid } } }) })).status, 403);
    }
    for (const allDescendants of [false, true]) assert.equal((await fetch(`${firestore}:runQuery`, { method: 'POST', headers: { Authorization: `Bearer ${tokens.patient}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'clinician_evaluations', allDescendants }] } }) })).status, 403);
    pass('emulator Firestore denies direct reads, writes, collection and collection-group evaluation queries');
    
    stage = 'WEB-3 discovery and human communications';
    const directory = await ok('/api/v1/experts', 'GET', undefined, 'patient'); assert(directory.items.some(p => p.id === users.clinician.uid));
    assert.equal((await fetch(base + '/api/v1/experts')).status, 401);
    assert.equal((await api('/api/v1/professional/analytics?organization_id=' + org.id, 'GET', undefined, 'patient')).status, 403);
    const messageBody = { relationship_id: rel.relationship_id, body: 'Fictional human message' };
    const messageRace = await Promise.all([1,2].map(() => ok('/api/v1/messages', 'POST', messageBody, 'patient', 'same_message'))); assert.deepEqual(messageRace[0], messageRace[1]);
    assert.equal((await api('/api/v1/relationships/' + rel.relationship_id + '/messages', 'GET', undefined, 'other')).status, 404);
    assert.equal((await api('/api/v1/relationships/' + rel.relationship_id + '/messages', 'GET', undefined, 'outsider')).status, 404);
    const appointment = await ok('/api/v1/appointments', 'POST', { relationship_id: rel.relationship_id }, 'patient');
    const proposal = await ok('/api/v1/appointments/' + appointment.id + '/transition', 'POST', { expected_revision: 1, to_state: 'proposed', starts_at: new Date(Date.now()+86400000).toISOString(), ends_at: new Date(Date.now()+90000000).toISOString() });
    const appointmentRace = await Promise.all(['confirmed','cancelled'].map(to_state => api('/api/v1/appointments/' + appointment.id + '/transition', 'POST', { expected_revision: proposal.revision, to_state }, 'patient'))); assert.deepEqual(appointmentRace.map(r=>r.status).sort(), [200,409]);
    const notices = await ok('/api/v1/notifications', 'GET', undefined, 'patient'); assert(notices.items.some(n=>n.kind==='assignment')); assert(!/evaluation|interpretation|submission_id|score/.test(JSON.stringify(notices)));
    const beforeCount = (await db.collection('notifications').where('recipient_uid','==',users.patient.uid).get()).size; await ok('/api/v1/notifications', 'GET', undefined, 'patient'); assert.equal((await db.collection('notifications').where('recipient_uid','==',users.patient.uid).get()).size,beforeCount);
    const analytics = await ok('/api/v1/professional/analytics?organization_id='+org.id); assert.equal(analytics.series[0].submitted, 2); assert.equal(analytics.series[0].enrolled, 3);
    const updates = await ok('/api/v1/professional/submission-notifications?organization_id='+org.id); assert.equal(updates.items.length,2);
    assert.equal((await api('/api/v1/professional/submission-notifications?organization_id='+org.id,'GET',undefined,'patient')).status,403);
    await pro.getByRole('button', { name: 'Refresh patients and submissions' }).click();
    const rosterRow = pro.locator('.professional-row').filter({ has: pro.getByRole('button', { name: 'Open conversation', exact: true }) }).filter({ hasText: users.patient.uid });
    await rosterRow.getByRole('button', { name: 'Open conversation', exact: true }).click();
    await pro.getByText('Fictional human message', { exact: true }).waitFor();
    await pro.getByLabel('Message', { exact: true }).fill('Fictional psychologist reply'); const sent = pro.waitForResponse(r=>r.url().endsWith('/api/v1/messages') && r.request().method()==='POST'); await pro.getByRole('button',{name:'Send message',exact:true}).click(); assert.equal((await sent).status(),201);
    await pro.locator('.professional-question').getByText('Fictional psychologist reply',{exact:true}).waitFor();
    await pro.getByRole('button',{name:'Refresh practice data',exact:true}).click(); await pro.getByText(/3 assignments.*2 submissions, all time.*2 submissions in selected dates/).waitFor();
    await pro.getByRole('button',{name:'Refresh submission updates',exact:true}).click(); await pro.getByRole('button',{name:'Open received submission',exact:true}).first().waitFor();
    await pro.getByRole('button',{name:'Refresh notifications',exact:true}).click();
    await pro.screenshot({path: output+'/professional-community.png',fullPage:true});
    pass('WEB-3 directory, transactional messages, isolated inbox, appointment race, counts and Neo conversation UI');

    stage = 'live relationship revocation and cache clearing';
    await patient.getByRole('button', { name: 'Back to assignments' }).click();
    await patient.getByRole('button', { name: 'View acknowledgement' }).first().waitFor();
    await patient.getByRole('button', { name: 'Open questionnaire' }).click();
    await patient.getByRole('textbox', { name: 'What would you like to discuss?' }).waitFor();
    await ok(`/api/v1/professional/patient-relationships/${rel.relationship_id}/close`, 'POST', { expected_revision: 1 });
    await patient.getByRole('heading', { name: 'Join a practice' }).waitFor({ timeout: 12000 });
    assert.equal(await patient.getByRole('textbox', { name: 'What would you like to discuss?' }).count(), 0);
    assert.equal((await api(`/api/v1/patient/assignments/${assignment.id}`, 'GET', undefined, 'patient')).status, 403);
    assert.equal((await api(`/api/v1/patient/attempts/${openDetail.attempt.id}`, 'PATCH', { expected_revision: 0, answers: validAnswers }, 'patient')).status, 403);
    assert.equal((await api('/api/v1/professional/assignments', 'POST', { organization_id: org.id, questionnaire_version_id: version.id, target: { kind: 'selected', relationship_ids: [rel.relationship_id] } })).status, 403);
    assert.equal((await ok(`/api/v1/professional/submissions/${sid}/workspace`)).submission.id, sid);
    const caches = await patient.evaluate(async () => ({ local: JSON.stringify(localStorage), session: JSON.stringify(sessionStorage), caches: 'caches' in window ? await window.caches.keys() : [] }));
    assert(!caches.local.includes('Fictional final response')); assert(!caches.session.includes('Fictional final response')); assert.equal(caches.caches.length, 0);
    assert.equal((await api('/api/v1/relationships/'+rel.relationship_id+'/messages','GET',undefined,'patient')).status,403);
    await ok('/api/v1/professional/patient-relationships/'+rel.relationship_id+'/archive','POST',{expected_revision:0,archived:true});
    assert.equal((await ok('/api/v1/professional/patient-relationships/'+rel.relationship_id+'/submissions')).items.length,2);
    pass('closure denies subsequent operations and clears an open runner through authorization invalidation');
    stage = 'cross-account browser transition'; await patient.getByRole('button', { name: 'Sign out', exact: true }).click();
    await patient.getByRole('textbox', { name: 'Email', exact: true }).fill(users.outsider.email); await patient.getByLabel('Password', { exact: true }).fill(password); await patient.getByRole('button', { name: 'Sign in', exact: true }).click();
    await patient.getByRole('heading', { name: 'Join a practice' }).waitFor({ timeout: 60000 }); assert(!/Fictional final response|Original provider|FICTIONAL AI/.test(await patient.locator('body').innerText()));
    pass('logout/login into another account exposes no retained patient or evaluation content');
    assert.equal(companionRequests, 0); assert.equal(pageErrors, 0);
    writeFileSync(`${output}/functional-emulator.json`, JSON.stringify({ run_at: new Date().toISOString(), project: config.project, checks, passed: checks.length, page_errors: pageErrors, companion_requests: companionRequests, real: ['Firebase Auth emulator', 'Firestore emulator transactions/rules', 'Next route handlers', 'Chrome browser'], fixtures: ['fictional accounts and registration records', 'explicitly labelled original interpretation/provider-failure fixture for review protection'], provider_calls: 0 }, null, 2) + '\n');
  } catch (error) {
    for (const [index, c] of contexts.entries()) for (const page of c.pages()) {
      await page.screenshot({ path: `${output}/failure-${index}.png`, fullPage: true }).catch(() => {});
      process.stderr.write(`Visible screen ${index}: ${(await page.locator('body').innerText()).slice(0, 1500)}\n`);
    }
    throw error;
  } finally { for (const c of contexts) await c.close(); await browser.close(); }
}
main().catch(error => { process.stderr.write(`WEB-3 emulator failed at ${stage}: ${error.message}\n`); process.exitCode = 1; });
