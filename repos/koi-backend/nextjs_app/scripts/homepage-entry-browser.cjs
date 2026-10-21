// Existing local Next server only. All auth/API traffic is intercepted; no database or provider access.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const BASE = 'http://127.0.0.1:3107';
const OUT = path.resolve(__dirname, '../.local/homepage-entry');
const titles = ['Continue Anonymously', 'Continue as General User', 'Continue as Patient', 'Continue as Psychologist'];
function token() {
  const time = Math.floor(Date.now() / 1000);
  return [JSON.stringify({ alg: 'none', typ: 'JWT' }), JSON.stringify({ iss: 'https://securetoken.google.com/demo-koi-fixture', aud: 'demo-koi-fixture', auth_time: time, iat: time, exp: time + 3600, user_id: 'entry-fixture', sub: 'entry-fixture', email: 'entry@example.invalid', email_verified: true, firebase: { identities: { email: ['entry@example.invalid'] }, sign_in_provider: 'password' } })].map(value => Buffer.from(value).toString('base64url')).join('.') + '.';
}
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const executablePath = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(fs.existsSync);
  const browser = await chromium.launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  const results = [];
  try {
    for (const width of [390, 768, 1280, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, reducedMotion: 'reduce', serviceWorkers: 'block' });
      const errors = [], forbidden = [];
      const caps = { uid: 'entry-fixture', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: false, create_organization: false, companion_account_sync: false }, professional_organization_ids: [], active_patient_relationships: [] };
      const jwt = token();
      await context.route('**/*', async route => {
        const request = route.request(), url = new URL(request.url());
        const json = value => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(value) });
        if (url.pathname.includes('accounts:signInWithPassword')) return json({ localId: caps.uid, email: 'entry@example.invalid', registered: true, idToken: jwt, refreshToken: 'fixture-only', expiresIn: '3600' });
        if (url.pathname.includes('accounts:lookup')) return json({ users: [{ localId: caps.uid, email: 'entry@example.invalid', emailVerified: true, providerUserInfo: [{ providerId: 'password', email: 'entry@example.invalid', rawId: 'entry@example.invalid' }], createdAt: '0', lastLoginAt: '0' }] });
        if (url.pathname.includes('/token') && /securetoken/.test(url.href)) return json({ access_token: jwt, id_token: jwt, refresh_token: 'fixture-only', expires_in: '3600', user_id: caps.uid });
        if (url.pathname.startsWith('/api/')) {
          if (request.method() !== 'GET' || /chat|crisis|speech|questionnaire-drafts|evaluation/.test(url.pathname)) { forbidden.push(url.pathname); return route.abort(); }
          return json(url.pathname.endsWith('/capabilities') ? caps : { items: [], next_cursor: null });
        }
        if (url.origin === BASE && request.method() === 'GET' && (url.pathname.startsWith('/_next/') || ['/', '/account', '/patient', '/professional', '/icon.svg', '/favicon.ico'].includes(url.pathname))) return route.continue();
        return route.abort();
      });
      const page = await context.newPage();
      page.on('pageerror', error => errors.push(error.message));
      page.setDefaultTimeout(30000);
      await page.goto(BASE + '/?home=1', { waitUntil: 'domcontentloaded', timeout: 120000 });
      const trigger = () => page.getByRole('button', { name: /Explore KOI/ });
      const menu = () => page.getByRole('dialog', { name: 'Choose your KOI experience' });
      await trigger().focus(); await page.keyboard.press('Enter');
      await menu().waitFor();
      assert.deepEqual(await menu().locator('[data-entry]').evaluateAll(elements => elements.map(el => el.getAttribute('aria-label'))), titles);
      await page.waitForFunction(() => document.activeElement?.getAttribute('aria-label') === 'Continue Anonymously');
      const box = await menu().boundingBox();
      assert.ok(box.x >= 0 && box.x + box.width <= width && box.y + box.height <= 900, 'Menu fits viewport');
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'No horizontal overflow');
      await page.screenshot({ path: path.join(OUT, 'menu-' + width + '.png') });
      await page.keyboard.press('Escape');
      assert.equal(await menu().count(), 0);
      assert.equal(await trigger().evaluate(el => el === document.activeElement), true);
      await trigger().click(); await page.mouse.click(8, 600);
      assert.equal(await menu().count(), 0);
      assert.equal(await trigger().evaluate(el => el === document.activeElement), true);
      for (const [entry, heading] of [['general', 'Welcome to KOI Care'], ['patient', 'Patient Access'], ['psychologist', 'Psychologist Access']]) {
        await trigger().click();
        await menu().locator(`a[href="/account?entry=${entry}"]`).click();
        await page.getByRole('heading', { name: heading, exact: true }).waitFor();
        await page.getByText('Public registration is not available yet.', { exact: false }).waitFor();
        await page.reload({ waitUntil: 'domcontentloaded' });
        await page.getByRole('heading', { name: heading, exact: true }).waitFor();
        await page.goBack(); await trigger().waitFor();
        await page.goForward(); await page.getByRole('heading', { name: heading, exact: true }).waitFor();
        await page.goBack(); await trigger().waitFor();
      }
      // Mock-only care sign-in: a General User is shown a useful Patient-access explanation.
      await trigger().click(); await menu().getByRole('link', { name: 'Continue as Patient' }).click();
      await page.getByRole('textbox', { name: 'Email', exact: true }).fill('entry@example.invalid');
      await page.getByLabel('Password', { exact: true }).fill('Frontend-fixture-only');
      await page.getByRole('button', { name: 'Sign in', exact: true }).click();
      await page.getByRole('heading', { name: 'Patient access requires an active care relationship' }).waitFor();
      await page.getByRole('link', { name: 'Continue as General User', exact: true }).click();
      await page.waitForURL('**/patient');
      await page.goto(BASE + '/account?entry=psychologist');
      await page.getByRole('heading', { name: 'Verified psychologist access required' }).waitFor();
      caps.capabilities.professional_workspace = true;
      await page.reload(); await page.waitForURL('**/professional?view=dashboard#practice-dashboard');
      caps.active_patient_relationships = [{ relationship_id: 'entry-rel', organization_id: 'entry-org', psychologist_uid: 'fixture-pro' }];
      await page.goto(BASE + '/account?entry=patient'); await page.waitForURL('**/patient');
      await page.goto(BASE + '/?home=1'); await trigger().click();
      assert.deepEqual(await menu().locator('[data-entry]').evaluateAll(elements => elements.map(el => el.getAttribute('aria-label'))), titles, 'Signed-in multi-capability account sees all four choices');
      await page.setViewportSize({ width, height: 500 });
      const shortBox = await menu().boundingBox();
      assert.ok(shortBox.y + shortBox.height <= 500, 'Short viewports keep menu inside screen');
      await menu().getByRole('link', { name: 'Continue as Psychologist' }).focus();
      const selected = await menu().getByRole('link', { name: 'Continue as Psychologist' }).boundingBox();
      assert.ok(selected.y >= shortBox.y && selected.y + selected.height <= shortBox.y + shortBox.height, 'Focused final choice scrolls into view');
      await page.keyboard.press('Escape');
      caps.capabilities.professional_workspace = false;
      await page.goto(BASE + '/account?entry=psychologist');
      await page.getByRole('heading', { name: 'Verified psychologist access required' }).waitFor();
      await page.getByRole('button', { name: 'Sign out of account' }).click();
      await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
      await page.reload();
      await page.getByRole('heading', { name: 'Psychologist Access', exact: true }).waitFor();
      await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
      assert.equal(await page.getByRole('heading', { name: 'Verified psychologist access required' }).count(), 0, 'Sign-out clears care access');
      assert.deepEqual(forbidden, []); assert.deepEqual(errors, []);
      results.push({ width, fourEntries: true, keyboardAndDismissal: true, historyAndRefresh: true, careSignInFixture: true, serverAccessRouting: true, signOut: true, shortViewport: true, liveWrites: 0 });
      console.log('PASS homepage entry interactions at ' + width + 'px');
      await context.close();
    }
    fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(results, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
