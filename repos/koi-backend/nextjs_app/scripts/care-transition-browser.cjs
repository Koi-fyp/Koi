// Frontend-only fixtures against the existing Next server. No emulator reads/writes.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const BASE = 'http://127.0.0.1:3107';
const OUT = path.resolve(__dirname, '../.local/care-transitions');
function token() {
  const time = Math.floor(Date.now() / 1000);
  return [JSON.stringify({ alg: 'none', typ: 'JWT' }), JSON.stringify({ iss: 'https://securetoken.google.com/demo-koi-fixture', aud: 'demo-koi-fixture', auth_time: time, iat: time, exp: time + 3600, user_id: 'transition-fixture', sub: 'transition-fixture', email: 'transition@example.invalid', email_verified: true, firebase: { identities: { email: ['transition@example.invalid'] }, sign_in_provider: 'password' } })].map(value => Buffer.from(value).toString('base64url')).join('.') + '.';
}
const relation = id => ({ relationship_id: id, organization_id: 'org-' + id, psychologist_uid: 'pro-' + id });
const assignment = { id: 'assignment-a', relationship_id: 'a', organization_id: 'org-a', questionnaire_version_id: 'version-a', attempt_id: 'attempt-a', title: { en: 'Fixture care form' }, state: 'in_progress', created_at: '2026-10-21T00:00:00Z' };
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const executablePath = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(fs.existsSync);
  const browser = await chromium.launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  const results = [];
  try {
    for (const width of [390, 768, 1280, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, reducedMotion: 'reduce', serviceWorkers: 'block' });
      // Supply the existing invalidation stream with a browser-local ReadableStream.
      // No streaming request reaches the emulator, Firebase or a companion endpoint.
      await context.addInitScript(() => {
        const original = window.fetch.bind(window), controllers = [];
        let revision = 1;
        const event = () => new TextEncoder().encode('event: authorization_changed\ndata: ' + JSON.stringify({ authorization_revision: revision++ }) + '\n\n');
        window.__emitCareChange = () => controllers.forEach(controller => { try { controller.enqueue(event()); } catch {} });
        window.fetch = async (input, options) => {
          if (new URL(typeof input === 'string' ? input : input.url, location.href).pathname !== '/api/v1/me/access-events') return original(input, options);
          let timer;
          return new Response(new ReadableStream({ start(controller) {
            controllers.push(controller); controller.enqueue(event());
            timer = setInterval(() => { try { controller.enqueue(new TextEncoder().encode(': heartbeat\n\n')); } catch { clearInterval(timer); } }, 1000);
            options.signal.addEventListener('abort', () => { clearInterval(timer); try { controller.close(); } catch {} });
          }, cancel() { clearInterval(timer); } }), { headers: { 'Content-Type': 'text/event-stream' } });
        };
      });
      const errors = [], forbidden = [], transport = [];
      const caps = { uid: 'transition-fixture', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: false, create_organization: false, companion_account_sync: true }, professional_organization_ids: [], active_patient_relationships: [] };
      // A fresh synthetic General User: no previous relationship or application.
      let application = null;
      const expert = { id: 'pro-a', display_name: 'Dr Fictional Practitioner', bio: 'Fixture practice profile. English and Urdu consultations.', accepting_new_patients: true };
      const jwt = token(); let saved = [], revision = 1;
      await context.route('**/*', async route => {
        const request = route.request(), url = new URL(request.url());
        const json = value => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(value) });
        if (url.pathname.includes('accounts:signInWithPassword')) return json({ localId: caps.uid, email: 'transition@example.invalid', registered: true, idToken: jwt, refreshToken: 'fixture-only', expiresIn: '3600' });
        if (url.pathname.includes('accounts:lookup')) return json({ users: [{ localId: caps.uid, email: 'transition@example.invalid', emailVerified: true, providerUserInfo: [{ providerId: 'password', email: 'transition@example.invalid', rawId: 'transition@example.invalid' }], createdAt: '0', lastLoginAt: '0' }] });
        if (url.pathname.includes('/token') && /securetoken/.test(url.href)) return json({ access_token: jwt, id_token: jwt, refresh_token: 'fixture-only', expires_in: '3600', user_id: caps.uid });
        if (url.pathname.startsWith('/api/')) {
          transport.push({ path: url.pathname, method: request.method() });
          if (request.method() === 'POST' && url.pathname === '/api/v1/connection-requests') {
            assert.deepEqual(request.postDataJSON(), { psychologist_uid: expert.id, consent_version: 'care-consent-v1' });
            application = { id: 'application-a', organization_id: 'org-a', applicant_uid: caps.uid, psychologist_uid: expert.id, state: 'requested', demo_payment_state: 'demo_pending', revision: 1, created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z' };
            return json(application);
          }
          if (request.method() === 'POST' && ['/api/v1/connection-requests/application-a/transition', '/api/v1/connection-requests/application-a/demo-payment'].includes(url.pathname)) {
            const body = request.postDataJSON(); assert.equal(body.expected_revision, application.revision);
            if (url.pathname.endsWith('/transition')) { assert.equal(body.to_state, 'awaiting_demo_payment'); assert.equal(application.state, 'requested'); application.state = body.to_state; }
            else { assert.equal(application.state, 'awaiting_demo_payment'); application.state = 'pending_psychologist_review'; application.demo_payment_state = 'demo_completed'; }
            application.revision++; return json(application);
          }
          if (request.method() === 'PATCH' && url.pathname === '/api/v1/patient/attempts/attempt-a') { const body = request.postDataJSON(); saved = body.answers; return json({ revision: ++revision }); }
          if (request.method() !== 'GET' || /chat|crisis|speech|professional|evaluation/.test(url.pathname)) { forbidden.push(url.pathname); return route.abort(); }
          if (url.pathname.endsWith('/capabilities')) return json(caps);
          if (url.pathname === '/api/v1/experts') return json({ items: [expert], next_cursor: null });
          if (url.pathname === '/api/v1/experts/pro-a') return json(expert);
          if (url.pathname.endsWith('/connection-requests')) return json({ items: application ? [application] : [], next_cursor: null });
          if (url.pathname.endsWith('/patient/assignments')) return json({ items: caps.active_patient_relationships.some(r => r.relationship_id === 'a') ? [assignment] : [], next_cursor: null });
          if (url.pathname.endsWith('/assignments/assignment-a')) return json({ assignment, questionnaire: { version_id: 'version-a', schema_version: '0.5.0', title: assignment.title, locales: ['en'], questions: [{ id: 'q', type: 'short_text', prompt: { en: 'Fixture response' }, max_length: 200, required: true }] }, attempt: { id: 'attempt-a', assignment_id: assignment.id, patient_uid: caps.uid, version_id: 'version-a', status: 'in_progress', answers: saved, revision, server_updated_at: '2026-10-21T00:00:00Z' } });
          if (url.pathname.endsWith('/notifications')) return json({ items: application ? [{ id: 'notice-a', event_id: 'event-a', kind: 'application_state', reference: { connection_request_id: application.id }, created_at: '2026-10-21T00:00:00Z' }] : [], next_cursor: null });
          return json({ items: [], next_cursor: null });
        }
        if (url.origin === BASE && request.method() === 'GET' && (url.pathname.startsWith('/_next/') || ['/patient', '/account', '/icon.svg', '/favicon.ico'].includes(url.pathname))) return route.continue();
        return route.abort();
      });
      const page = await context.newPage(); page.setDefaultTimeout(30000);
      page.on('pageerror', error => errors.push(error.message)); page.on('dialog', dialog => dialog.accept());
      await page.goto(BASE + '/account?entry=general', { waitUntil: 'domcontentloaded', timeout: 120000 });
      await page.getByRole('textbox', { name: 'Email', exact: true }).fill('transition@example.invalid');
      await page.getByLabel('Password', { exact: true }).fill('Frontend-fixture-only');
      await page.getByRole('button', { name: 'Sign in', exact: true }).click();
      const nav = page.getByRole('navigation', { name: 'Care navigation' });
      await page.getByText('General User Dashboard', { exact: true }).waitFor();
      assert.deepEqual(await nav.getByRole('link').allTextContents(), ['Care Home', 'Find a Psychologist', 'My Applications', 'Become a Psychologist', 'Notifications', 'Account & Access']);
      assert.equal(await nav.getByRole('link', { name: 'Questionnaires', exact: true }).count(), 0);
      await page.screenshot({ path: path.join(OUT, 'general-' + width + '.png') });
      await nav.getByRole('link', { name: 'Become a Psychologist' }).click();
      await page.getByRole('heading', { name: 'Professional registration is not available yet' }).waitFor();
      assert.equal(await page.getByRole('link', { name: 'Professional sign-in / access' }).getAttribute('href'), '/account?entry=psychologist');
      await nav.getByRole('link', { name: 'Find a Psychologist' }).click();
      await page.getByRole('button', { name: 'Choose for application' }).click();
      await page.getByRole('heading', { level: 1, name: 'My Applications' }).waitFor();
      await page.waitForFunction(() => document.activeElement?.id === 'practice-application');
      const applicationPanel = page.locator('#practice-application'), history = page.locator('#applications').locator('..');
      await applicationPanel.getByRole('heading', { name: expert.display_name }).waitFor();
      const formBox = await applicationPanel.boundingBox();
      assert.ok(formBox.y >= -2 && formBox.y < 850, 'The selected application form is immediately visible');
      assert.equal(await page.getByRole('textbox', { name: /account ID/i }).count(), 0);
      assert.equal(await page.getByRole('textbox', { name: 'Invitation code' }).count(), 0, 'Invitation input is secondary and collapsed');
      const consent = () => applicationPanel.getByRole('checkbox', { name: /^I consent to joining this practice/ });
      const send = () => applicationPanel.getByRole('button', { name: 'Send Application' });
      assert.equal(await send().isDisabled(), true);
      await consent().check(); await page.reload();
      await applicationPanel.getByRole('heading', { name: expert.display_name }).waitFor();
      assert.equal(await consent().isChecked(), false, 'Refresh restores the profile but requires fresh consent');
      assert.ok(page.url().includes('psychologist=pro-a'));
      await nav.getByRole('link', { name: 'Notifications', exact: true }).click();
      await page.goBack(); await applicationPanel.getByRole('heading', { name: expert.display_name }).waitFor();
      await page.goForward(); await page.getByRole('heading', { name: 'Notifications', exact: true, level: 1 }).waitFor();
      await nav.getByRole('link', { name: 'My Applications' }).click();
      await consent().check();
      await page.screenshot({ path: path.join(OUT, 'application-' + width + '.png') });
      await send().click();
      await applicationPanel.getByRole('heading', { name: 'Application recorded' }).waitFor();
      await history.getByText('Application submitted', { exact: true }).waitFor();
      await history.getByRole('button', { name: 'Continue application' }).click();
      await history.getByText('Demo step required', { exact: true }).waitFor();
      await history.getByRole('button', { name: 'Complete demo step' }).click();
      await history.getByText('Waiting for practice review', { exact: true }).waitFor();
      application.state = 'accepted'; await page.evaluate(() => window.__emitCareChange());
      await history.getByText('Application accepted previously', { exact: true }).waitFor();
      assert.equal(await page.getByText('General User Dashboard', { exact: true }).count(), 1, 'Accepted application alone is insufficient');
      caps.active_patient_relationships = [relation('a'), relation('b')]; await page.evaluate(() => window.__emitCareChange());
      await page.getByRole('heading', { name: 'My Care / Overview', exact: true }).waitFor();
      await page.getByRole('heading', { name: 'Your care is active' }).waitFor();
      assert.equal(await page.getByRole('textbox', { name: 'Invitation code' }).count(), 0);
      assert.equal(await page.getByRole('heading', { name: 'Applications', exact: true }).count(), 0);
      assert.equal(await nav.getByRole('link', { name: 'Find a Psychologist' }).count(), 0, 'Discovery stays inside a closed secondary section');
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      await page.screenshot({ path: path.join(OUT, 'patient-' + width + '.png') });
      await nav.getByRole('link', { name: 'Questionnaires', exact: true }).click();
      await page.getByRole('button', { name: 'Resume questionnaire' }).click();
      await page.getByRole('textbox', { name: 'Fixture response' }).fill('Keep my current response');
      caps.active_patient_relationships = [relation('a')]; await page.evaluate(() => window.__emitCareChange());
      await page.waitForFunction(() => document.querySelector('input[aria-label="Fixture response"],textarea[aria-label="Fixture response"]')?.value === 'Keep my current response');
      await page.getByRole('textbox', { name: 'Fixture response' }).waitFor();
      assert.ok(page.url().includes('view=questionnaires'), 'A retained relationship does not interrupt the attempt');
      caps.active_patient_relationships = []; await page.evaluate(() => window.__emitCareChange());
      await page.getByText('General User Dashboard', { exact: true }).waitFor();
      await page.getByText('Your previous care relationship has ended. You can continue using KOI Care to find a psychologist.', { exact: true }).waitFor();
      assert.equal(await page.getByRole('textbox', { name: 'Fixture response', includeHidden: true }).count(), 0);
      await history.getByText('Application accepted previously', { exact: true }).waitFor();
      assert.equal(application.state, 'accepted');
      await nav.getByRole('link', { name: 'My Applications' }).click();
      await page.goBack(); await page.getByRole('heading', { name: 'Care Home', exact: true }).waitFor();
      await page.goForward(); await page.getByRole('heading', { name: 'My Applications', exact: true }).waitFor();
      await page.reload(); await page.getByText('General User Dashboard', { exact: true }).waitFor();
      assert.equal(await nav.getByRole('link', { name: 'Messages', exact: true }).count(), 0);
      await nav.getByRole('link', { name: 'Notifications', exact: true }).click();
      await page.getByText(/Application update/).waitFor();
      caps.active_patient_relationships = [relation('a')]; await page.evaluate(() => window.__emitCareChange());
      await page.getByText('Patient Dashboard', { exact: true }).waitFor();
      await nav.getByRole('link', { name: 'My Care / Overview' }).click();
      await page.reload(); await page.getByText('Patient Dashboard', { exact: true }).waitFor();
      assert.deepEqual(forbidden, []); assert.deepEqual(errors, []);
      assert.ok(transport.every(row => !/evaluation|review|questionnaire-drafts|chat|crisis/.test(row.path)));
      results.push({ width, general: true, professionalEntry: true, directorySelection: true, visibleApplication: true, consent: true, selectionRefresh: true, submitted: true, demoPayment: true, acceptedAloneStaysGeneral: true, promotion: true, remainingRelationshipKeepsDraft: true, demotion: true, acceptedHistory: true, refreshAndHistory: true, privacy: true, liveWrites: 0 });
      console.log('PASS care transition browser checks at ' + width + 'px');
      await context.close();
    }
    fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(results, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
