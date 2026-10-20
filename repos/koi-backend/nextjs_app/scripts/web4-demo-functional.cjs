const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { mkdirSync, writeFileSync, existsSync } = require('node:fs');
const { chromium } = require('playwright');
const { guard, IDENTITIES, passwords } = require('./koi-demo-guard.cjs');
let stage = 'guards';
async function main() {
  const { base } = guard();
  // Test-only ephemeral password when the operator has not provided one. Never logged/saved.
  if (!process.env.KOI_DEMO_PASSWORD && !process.env.KOI_DEMO_PSYCHOLOGIST_PASSWORD) process.env.KOI_DEMO_PASSWORD = randomUUID() + '-Demo';
  const secret = passwords(), { auth, db } = require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
  const { seed } = require('./seed-koi-demo.cjs'), checks = [], output = 'review/web-4/evidence'; mkdirSync(output, { recursive: true });
  const pass = name => { checks.push(name); console.log(`PASS ${name}`); };
  stage = 'deterministic seed'; const fixture = await seed();
  const count = async () => { const names = ['organizations', 'patient_relationships', 'questionnaires', 'questionnaire_versions', 'assignments', 'attempts', 'submissions', 'ai_jobs', 'review_records', 'connection_requests']; return Object.fromEntries(await Promise.all(names.map(async c => [c, (await db.collection(c).get()).size]))); };
  const before = await count(); assert.deepEqual(await seed(), fixture); assert.deepEqual(await count(), before); pass('repeat seeding preserves identifiers and collection counts');
  const tokens = {};
  for (const [role, identity] of Object.entries(IDENTITIES)) { const r = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: identity.email, password: secret[role], returnSecureToken: true }) }); assert.equal(r.status, 200); tokens[role] = (await r.json()).idToken; }
  const api = async (path, role = 'psychologist', method = 'GET', body) => {
    const r = await fetch(base + path, { method, headers: { Authorization: `Bearer ${tokens[role]}`, 'Content-Type': 'application/json', 'Idempotency-Key': randomUUID() }, ...(body ? { body: JSON.stringify(body) } : {}) }); return { status: r.status, data: await r.json() };
  };
  assert.equal((await api(`/api/v1/patient/assignments/${fixture.assignments.open}`, 'patient')).data.attempt.status, 'not_started');
  assert.equal((await api(`/api/v1/patient/assignments/${fixture.assignments.submitted}`, 'patient')).data.acknowledgement.status, 'submitted');
  for (const path of [`/api/v1/professional/evaluations/${fixture.evaluation_id}`, `/api/v1/professional/submissions/${fixture.submission_id}/workspace`, `/api/v1/professional/analytics?organization_id=${fixture.organization_id}`]) assert.equal((await api(path, 'patient')).status, 403);
  pass('persistent fixtures include open and submitted assignments; patient evaluation HTTP access denied');
  const browser = await chromium.launch({ headless: true, executablePath: existsSync(chromium.executablePath()) ? undefined : 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  const contexts = []; let pageErrors = 0, companionRequests = 0, nonlocalRequests = 0;
  const context = async () => {
    const c = await browser.newContext({ viewport: { width: 1280, height: 950 }, reducedMotion: 'reduce' }); contexts.push(c);
    await c.route('**/*', route => { const u = new URL(route.request().url()); if (u.pathname === '/api/v1/chat' || u.hostname.includes('modal.run')) { companionRequests++; return route.abort(); } if (['127.0.0.1', 'localhost'].includes(u.hostname)) return route.continue(); if (/googleapis.com$|firebaseio.com$|firebaseapp.com$/.test(u.hostname) && !u.hostname.includes('fonts.')) nonlocalRequests++; return route.abort(); });
    const p = await c.newPage(); p.setDefaultTimeout(90000); p.on('pageerror', () => pageErrors++); p.on('dialog', d => d.accept()); return p;
  };
  const login = async (page, role) => {
    stage = role + ' main GUI account sign-in'; await page.bringToFront();
    await page.goto(base + '/?home=1', { waitUntil: 'domcontentloaded' }); await page.getByText('KOI menu', { exact: true }).click();
    assert.equal(await page.getByRole('link', { name: 'Professional Dashboard', exact: true }).count(), 0);
    await page.getByRole('link', { name: 'Account sign-in', exact: true }).click();
    await page.getByLabel('Email', { exact: true }).fill(IDENTITIES[role].email); await page.getByLabel('Password', { exact: true }).fill(secret[role]); await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await page.getByRole('button', { name: 'Sign out of account' }).waitFor();
  };
  try {
    stage = 'main GUI and role navigation'; const pro = await context(), patient = await context(), general = await context();
    await login(pro, 'psychologist'); stage = 'professional dashboard navigation link'; await pro.getByRole('link', { name: 'Professional Dashboard', exact: true }).click(); stage = 'professional dashboard heading'; await pro.getByRole('heading', { name: 'Practice profile and activity' }).waitFor();
    await login(general, 'general'); await general.getByRole('link', { name: 'Find an Expert', exact: true }).waitFor(); assert.equal(await general.getByRole('link', { name: 'Messages', exact: true }).count(), 0);
    await general.goto(base + '/patient?view=messages#care'); await general.getByRole('heading', { name: 'Active care relationship required' }).waitFor();
    await general.goto(base + '/professional'); await general.getByRole('heading', { name: 'Practice access required' }).waitFor();
    await login(patient, 'patient'); await patient.getByRole('link', { name: 'Questionnaires', exact: true }).click(); await patient.getByRole('heading', { name: 'Assigned questionnaires' }).waitFor();
    pass('homepage account entry, capability menus and unauthorized deep-link guards');
    stage = 'manual publish via GUI'; await pro.bringToFront(); await pro.goto(base + '/professional?view=questionnaires');
    await pro.getByRole('button', { name: 'New questionnaire', exact: true }).click(); const title = `Fictional WEB-4 live demo ${randomUUID().slice(0, 8)}`;
    await pro.getByRole('textbox', { name: /^Title .* English$/ }).fill(title); await pro.getByRole('textbox', { name: /^Question 1 .* English$/ }).fill('Fictional WEB-4 reflection');
    await pro.getByRole('button', { name: 'Save draft', exact: true }).click(); await pro.getByText('Draft saved. Revision 1.', { exact: true }).waitFor();
    await pro.getByRole('button', { name: 'Publish saved revision', exact: true }).click(); await pro.getByText('Published. This version is immutable.', { exact: true }).waitFor();
    await pro.getByRole('button', { name: 'Manage patients and submissions' }).click(); await pro.getByLabel('Assign to all active patients (snapshot at assignment time)').check();
    await pro.getByRole('button', { name: 'Assign published questionnaire', exact: true }).click(); await pro.getByText(/independent assignments created/).waitFor();
    pass('real GUI manual creation, immutable publish and assignment');
    stage = 'patient resume and submit'; await patient.bringToFront(); await patient.getByRole('button', { name: 'Refresh your care' }).click();
    const row = () => patient.locator('.professional-row').filter({ has: patient.getByRole('button', { name: 'Open questionnaire', exact: true }) }).filter({ hasText: title });
    await row().getByRole('button', { name: 'Open questionnaire' }).click(); await patient.getByRole('textbox', { name: 'Fictional WEB-4 reflection' }).fill('Fictional WEB-4 browser response'); await patient.getByText('All answers saved', { exact: true }).waitFor();
    await patient.reload({ waitUntil: 'domcontentloaded' }); await row().getByRole('button', { name: 'Open questionnaire' }).click(); assert.equal(await patient.getByRole('textbox', { name: 'Fictional WEB-4 reflection' }).inputValue(), 'Fictional WEB-4 browser response');
    await patient.getByRole('button', { name: 'Review before submitting' }).click(); await patient.getByRole('button', { name: 'Confirm final submission' }).click(); await patient.getByRole('heading', { name: 'Questionnaire submitted' }).waitFor();
    assert(!/evaluation|interpretation|validated score|AI processing/i.test(await patient.locator('body').innerText())); await patient.screenshot({ path: `${output}/patient-ack.png`, fullPage: true }); pass('separate patient profile autosaves, reloads, resumes and receives acknowledgement without results');
    stage = 'protected review and communication'; await pro.bringToFront(); await pro.getByRole('button', { name: 'Refresh patients and submissions' }).click();
    const all = (await api(`/api/v1/professional/submissions?organization_id=${fixture.organization_id}`)).data.items, submitted = all.find(s => s.answers.some(a => a.value === 'Fictional WEB-4 browser response')); assert(submitted);
    const w = (await api(`/api/v1/professional/submissions/${submitted.id}/workspace`)).data; assert.equal(w.job.state, 'queued'); assert.deepEqual(w.evaluation.validated_scores, []);
    await pro.getByRole('button', { name: 'Inspect submission', exact: true }).first().click(); await pro.getByLabel('Psychologist conclusion').waitFor();
    await pro.getByRole('button', { name: 'Open conversation', exact: true }).first().click(); await pro.getByLabel('Message', { exact: true }).fill('Fictional WEB-4 human greeting');
    const sent = pro.waitForResponse(r => r.url().endsWith('/api/v1/messages') && r.request().method() === 'POST'); await pro.getByRole('button', { name: 'Send message', exact: true }).click(); assert.equal((await sent).status(), 201);
    await patient.bringToFront(); await patient.goto(base + '/patient?view=messages#care'); await patient.getByText('Fictional WEB-4 human greeting', { exact: true }).waitFor();
    const requested = patient.waitForResponse(r => r.url().endsWith('/api/v1/appointments') && r.request().method() === 'POST'); await patient.getByRole('button', { name: 'Request appointment' }).click(); const a = await (await requested).json();
    assert.equal((await api(`/api/v1/appointments/${a.id}/transition`, 'psychologist', 'POST', { expected_revision: 1, to_state: 'proposed', starts_at: new Date(Date.now() + 86400000).toISOString(), ends_at: new Date(Date.now() + 90000000).toISOString() })).status, 200);
    await patient.getByRole('button', { name: 'Refresh conversation' }).click(); await patient.getByRole('button', { name: 'Accept proposed time' }).click();
    await patient.getByRole('button', { name: 'Refresh notifications' }).click(); await patient.getByRole('button', { name: 'Mark read' }).first().waitFor();
    await pro.bringToFront(); await pro.getByRole('button', { name: 'Refresh practice data' }).click(); await pro.getByText(/assignments.*submissions, all time/).first().waitFor();
    await pro.screenshot({ path: `${output}/professional-dashboard.png`, fullPage: true }); pass('protected review, human messages, appointment response, notifications and actual fictional-data analytics');
    stage = 'persistent session and mobile navigation'; await patient.bringToFront(); await patient.goto(base + '/account'); await patient.getByRole('link', { name: 'Messages', exact: true }).waitFor(); await patient.reload(); await patient.getByRole('link', { name: 'Messages', exact: true }).waitFor();
    await patient.setViewportSize({ width: 390, height: 844 }); assert(await patient.evaluate(() => document.documentElement.scrollWidth <= innerWidth)); await patient.screenshot({ path: `${output}/patient-account-mobile.png`, fullPage: true });
    await patient.getByRole('button', { name: 'Sign out of account' }).click(); await patient.getByRole('button', { name: 'Sign in', exact: true }).waitFor(); assert.equal(await patient.getByRole('link', { name: 'Messages', exact: true }).count(), 0); pass('Firebase session survives reload; sign-out removes privileged links; mobile account screen fits');
    assert.equal(pageErrors, 0); assert.equal(companionRequests, 0); assert.equal(nonlocalRequests, 0);
    const authFingerprints = {}, listed = await auth.listUsers(1000); for (const i of Object.values(IDENTITIES)) { const u = listed.users.find(u => u.uid === i.uid); assert(u?.passwordHash); authFingerprints[i.uid] = createHash('sha256').update(u.passwordHash).digest('hex'); }
    mkdirSync('.local/koi-demo', { recursive: true }); writeFileSync('.local/koi-demo/persistence-check.json', JSON.stringify({ fixture, authFingerprints, counts: await count() }));
    writeFileSync(`${output}/functional.json`, JSON.stringify({ passed: true, checks, page_errors: pageErrors, companion_requests: companionRequests, nonlocal_requests: nonlocalRequests, fictional: true, real: ['Auth emulator', 'Firestore emulator', 'Next routes', 'Chrome'], provider_calls: 0 }, null, 2) + '\n');
  } catch (e) { let diagnostic = e.message; for (const value of Object.values(secret)) diagnostic = diagnostic.replaceAll(value, '[redacted]'); console.error(diagnostic.slice(0,900)); for (const [i, c] of contexts.entries()) for (const p of c.pages()) await p.screenshot({ path: `${output}/failure-${i}.png`, fullPage: true }).catch(() => {}); throw e; }
  finally { for (const c of contexts) await c.close(); await browser.close(); }
}
main().catch(e => { console.error(`WEB-4 local demo failed at ${stage}: ${e.name}. Credentials omitted.`); process.exitCode = 1; });
