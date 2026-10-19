// Real local Firebase emulator + browser journey. No mocks, deployment or live project access.
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { mkdirSync, writeFileSync, existsSync } = require('node:fs');
const { join } = require('node:path');
const { chromium } = require('playwright');
const { getPlatformAdmin } = require('../src/lib/platform/server/admin-config.cjs');
let stage = 'emulator configuration';

async function main() {
  const { auth, db, config } = getPlatformAdmin();
  assert.equal(config.mode, 'emulator');
  assert.equal(config.project, 'demo-koi-platform-web1');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:5180');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:5199');
  const suffix = randomUUID().replace(/-/g, '').slice(0, 12);
  stage = 'synthetic emulator identities and restricted seed';
  const password = randomUUID() + '-Local-only!';
  const operator = await auth.createUser({ uid: `operator_${suffix}`, email: `operator-${suffix}@example.invalid`, password });
  const clinician = await auth.createUser({ uid: `clinician_${suffix}`, email: `clinician-${suffix}@example.invalid`, password });
  const other = await auth.createUser({ uid: `other_${suffix}`, email: `other-${suffix}@example.invalid`, password });
  const general = await auth.createUser({ uid: `general_${suffix}`, email: `general-${suffix}@example.invalid`, password });
  const seed = (uid, state, key) => {
    const result = spawnSync(process.execPath, ['scripts/platform-verify-psychologist.cjs', '--uid', uid, '--state', state, '--evidence-id', `synthetic_review_${suffix}`, '--request-id', key], {
      cwd: process.cwd(), env: { ...process.env, KOI_PLATFORM_BOOTSTRAP_ADMIN_UID: operator.uid, KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT: 'emulator-only' }, encoding: 'utf8', timeout: 30000,
    });
    assert.equal(result.status, 0, 'Restricted emulator verification CLI must succeed');
  };
  seed(clinician.uid, 'pending', 'pending'); seed(clinician.uid, 'verified', 'verified');
  seed(other.uid, 'pending', 'pending'); seed(other.uid, 'verified', 'verified');
  await db.collection('accounts').doc(general.uid).create({ uid: general.uid, state: 'registered', general_access: true, registration_method: 'restricted_seeded_verification', registration_evidence_id: 'synthetic_only', registered_at: new Date().toISOString(), authorization_revision: 1 });
  const tokenFor = async email => {
    const response = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
    assert.equal(response.status, 200); return (await response.json()).idToken;
  };
  const tokens = { clinician: await tokenFor(clinician.email), other: await tokenFor(other.email), general: await tokenFor(general.email) };
  const anonymousResponse = await fetch('http://127.0.0.1:5199/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-platform-key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }) });
  assert.equal(anonymousResponse.status, 200); tokens.anonymous = (await anonymousResponse.json()).idToken;
  const base = 'http://127.0.0.1:3107';
  const api = async (path, method = 'GET', body, token = tokens.clinician, key = randomUUID()) => {
    const response = await fetch(base + path, { method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(method === 'GET' ? {} : { 'Content-Type': 'application/json', 'Idempotency-Key': key }) }, body: method === 'GET' ? undefined : JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  };
  const output = join(process.cwd(), 'review/web-1/evidence'); mkdirSync(output, { recursive: true });
  stage = 'launch Chromium';
  const installedChrome = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  const executablePath = process.env.KOI_WEB1_BROWSER_EXECUTABLE || (existsSync(chromium.executablePath()) ? undefined : existsSync(installedChrome) ? installedChrome : undefined);
  const browser = await chromium.launch({ headless: true, executablePath });
  try {
    const context = await browser.newContext({ reducedMotion: 'reduce', viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();
    let companionRequests = 0, pageErrors = 0;
    page.on('pageerror', () => { pageErrors++; });
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/api/v1/chat' || url.hostname.includes('modal.run')) { companionRequests++; return route.abort(); }
      if (['127.0.0.1', 'localhost', 'fonts.googleapis.com', 'fonts.gstatic.com'].includes(url.hostname)) return route.continue();
      return route.abort();
    });
    page.on('dialog', dialog => dialog.accept());
    stage = 'professional page and password sign-in';
    await page.goto(base + '/professional', { waitUntil: 'domcontentloaded', timeout: 120000 });
    await page.getByRole('textbox', { name: 'Email', exact: true }).fill(clinician.email);
    await page.getByLabel('Password', { exact: true }).fill(password);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    await page.getByRole('heading', { name: 'Create your organization' }).waitFor({ timeout: 120000 });
    stage = 'organization creation';
    await page.getByRole('textbox', { name: 'Organization name' }).fill('Fictional WEB-1 practice');
    await page.getByRole('button', { name: 'Create organization', exact: true }).click();
    await page.getByText('Organization created.', { exact: true }).waitFor({ timeout: 60000 });
    stage = 'manual draft with picture';
    await page.getByRole('button', { name: 'New questionnaire' }).click();
    await page.getByRole('textbox', { name: 'Title · English', exact: true }).fill('Fictional shapes questionnaire');
    await page.getByRole('textbox', { name: 'Question 1 · English', exact: true }).fill('What would you like to discuss?');
    await page.getByRole('button', { name: 'Add question', exact: true }).click();
    await page.getByRole('combobox', { name: 'Question 2 type' }).selectOption('image_single_choice');
    await page.getByRole('textbox', { name: 'Question 2 · English', exact: true }).fill('Choose a geometric shape.');
    await page.getByRole('group', { name: 'Question 2 option 1 picture' }).getByRole('button', { name: /Triangle/ }).click();
    await page.getByRole('button', { name: 'Save draft', exact: true }).click();
    await page.getByText('Draft saved. Revision 1.', { exact: true }).waitFor({ timeout: 60000 });
    stage = 'immutable publication';
    await page.getByRole('button', { name: 'Publish saved revision' }).click();
    await page.getByText('Published. This version is immutable.', { exact: true }).waitFor({ timeout: 60000 });
    const region = page.getByRole('region', { name: 'Published questionnaire' });
    const versionLink = await region.getByRole('link', { name: 'Open this published version later' }).getAttribute('href');
    assert(versionLink);
    const versionId = new URL(versionLink, base).searchParams.get('version');
    const firstSnapshot = await api(`/api/v1/professional/questionnaire-versions/${versionId}`); assert.equal(firstSnapshot.status, 200);
    const draftId = firstSnapshot.data.questionnaire_id, organizationId = firstSnapshot.data.organization_id;
    await page.screenshot({ path: join(output, 'published-desktop.png'), fullPage: true });
    stage = 'draft edit, reload and published inspection';
    await page.getByRole('textbox', { name: 'Title · English', exact: true }).fill('Fictional revised draft');
    // Advance only the browser freshness hint; server/emulator clocks and real Auth stay untouched.
    await page.evaluate(() => { window.__web1OriginalDateNow = Date.now; Date.now = () => window.__web1OriginalDateNow() + 250000; });
    await page.getByRole('button', { name: 'Save draft', exact: true }).click();
    await page.getByRole('dialog', { name: 'Confirm your sign-in' }).waitFor({ timeout: 30000 });
    await page.evaluate(() => { Date.now = window.__web1OriginalDateNow; delete window.__web1OriginalDateNow; });
    await page.getByLabel('Confirm password', { exact: true }).fill(password);
    await page.getByRole('button', { name: 'Continue', exact: true }).click();
    await page.getByText('Draft saved. Revision 2.', { exact: true }).waitFor({ timeout: 60000 });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Open draft: Fictional revised draft' }).click({ timeout: 60000 });
    await page.getByRole('spinbutton', { name: 'Published revision to inspect' }).fill('1');
    await page.getByRole('button', { name: 'Inspect published revision' }).click();
    await page.getByRole('region', { name: 'Published questionnaire' }).getByText('Fictional shapes questionnaire', { exact: true }).waitFor({ timeout: 60000 });
    assert.deepEqual((await api(`/api/v1/professional/questionnaire-versions/${versionId}`)).data, firstSnapshot.data);
    // Reopen the bookmark after a page load, not just an in-memory preview.
    await page.goto(base + versionLink, { waitUntil: 'domcontentloaded' });
    await page.getByRole('region', { name: 'Published questionnaire' }).waitFor({ timeout: 60000 });
    stage = 'mobile viewport';
    await page.setViewportSize({ width: 390, height: 844 });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.screenshot({ path: join(output, 'published-mobile.png'), fullPage: true });
    stage = 'authorization, direct rules denial and suspension';
    const rootArrays = await api('/api/v1/professional/organizations', 'POST', [{ name: 'invalid' }]); assert.equal(rootArrays.status, 422);
    assert.equal((await api('/api/v1/professional/organizations', 'POST', { name: 'denied' }, null)).status, 401);
    assert.equal((await api('/api/v1/professional/organizations', 'POST', { name: 'denied' }, tokens.general)).status, 403);
    assert.equal((await api('/api/v1/professional/organizations', 'POST', { name: 'denied' }, tokens.anonymous)).status, 403);
    for (const path of [`/api/v1/professional/questionnaires/${draftId}`, `/api/v1/professional/questionnaire-versions/${versionId}`, `/api/v1/professional/questionnaires?organization_id=${organizationId}`]) assert.equal((await api(path, 'GET', undefined, tokens.other)).status, 404);
    const publishBody = { expected_revision: 1, expected_content_sha256: firstSnapshot.data.content_sha256 };
    const currentDraft = await api(`/api/v1/professional/questionnaires/${draftId}`); assert.equal(currentDraft.status, 200);
    assert.equal((await api('/api/v1/professional/questionnaires', 'POST', { organization_id: organizationId, content: currentDraft.data.content }, tokens.other)).status, 404);
    assert.equal((await api(`/api/v1/professional/questionnaires/${draftId}`, 'PUT', { expected_revision: 2, content: currentDraft.data.content }, tokens.other)).status, 404);
    assert.equal((await api(`/api/v1/professional/questionnaires/${draftId}/publish`, 'POST', publishBody, tokens.other)).status, 404);
    const writes = await Promise.all([api(`/api/v1/professional/questionnaires/${draftId}`, 'PUT', { expected_revision: 2, content: currentDraft.data.content }), api(`/api/v1/professional/questionnaires/${draftId}`, 'PUT', { expected_revision: 2, content: currentDraft.data.content })]);
    assert.deepEqual(writes.map(result => result.status).sort(), [200, 409]);
    const duplicate = await api(`/api/v1/professional/questionnaires/${draftId}/publish`, 'POST', publishBody); assert.equal(duplicate.status, 200); assert.deepEqual(duplicate.data, firstSnapshot.data);
    const rawDenied = await fetch(`http://127.0.0.1:5180/v1/projects/${config.project}/databases/(default)/documents/questionnaire_versions/${versionId}`, { headers: { Authorization: `Bearer ${tokens.clinician}` } }); assert.equal(rawDenied.status, 403);
    seed(clinician.uid, 'suspended', 'suspended');
    assert.equal((await api(`/api/v1/professional/questionnaire-versions/${versionId}`)).status, 403);
    await page.reload({ waitUntil: 'domcontentloaded' }); await page.getByRole('heading', { name: 'Practice access required' }).waitFor({ timeout: 60000 });
    assert.equal(companionRequests, 0); assert.equal(pageErrors, 0);
    const report = { passed: true, project: config.project, runtime: 'Real local Firebase Auth/Firestore emulators + real Next dev server + Chromium; no mocked API/auth/database',
      checks: ['restricted CLI pending-to-verified', 'real password sign-in and ID token verification', 'organization and owner membership', 'manual form including bundled picture choice', 'save and reload', 'immutable publish', 'recent-auth prompt retains unsaved edits and uses real reauthentication', 'later draft edit preserves published snapshot', 'inspect revision after refresh', 'published bookmark', 'mobile viewport no horizontal overflow', 'array-body rejection', 'signed-out, anonymous and General denied', 'cross-practice reads, list, create, update and publish denied', 'concurrent saves yield one success and one conflict', 'duplicate publish stable', 'direct Firestore read denied by emulator rules', 'suspension denies old token and clears workspace'],
      companion_requests: companionRequests, page_errors: pageErrors, published_version_count: (await db.collection('questionnaire_versions').where('organization_id', '==', organizationId).get()).size,
      ai_jobs_created: (await db.collection('ai_jobs').get()).size, screenshots: ['published-desktop.png', 'published-mobile.png'], limitations: 'Local emulators do not verify production IAM, deployed Firebase rules or live backend configuration.' };
    writeFileSync(join(output, 'functional-emulator.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    await context.close();
  } finally { await browser.close(); }
}
main().catch(error => { console.error(JSON.stringify({ passed: false, stage, error_type: error.name, notice: 'No tokens or credential diagnostics emitted.' })); process.exitCode = 1; });
