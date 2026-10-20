// Real anonymous emulator sign-in and original onboarding; never sends chat/provider traffic.
const assert = require('node:assert/strict');
const { existsSync, writeFileSync } = require('node:fs');
const { chromium } = require('playwright');
let stage = 'startup';
async function main() {
  const { base } = require('./koi-demo-guard.cjs').guard();
  const browser = await chromium.launch({ headless: true, executablePath: existsSync(chromium.executablePath()) ? undefined : 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  let companionCalls = 0, liveFirebaseCalls = 0, page;
  try {
    page = await browser.newPage({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce' });
    page.setDefaultTimeout(60000);
    await page.route('**/*', route => {
      const u = new URL(route.request().url());
      if (u.pathname === '/api/v1/chat' || u.hostname.includes('modal.run')) { companionCalls++; return route.abort(); }
      if (['127.0.0.1', 'localhost'].includes(u.hostname)) return route.continue();
      if (/googleapis.com$|firebaseio.com$|firebaseapp.com$/.test(u.hostname) && !u.hostname.includes('fonts.')) liveFirebaseCalls++;
      return route.abort();
    });
    stage = 'anonymous sign-in';
    // Bare / follows the original post-sign-in redirect. ?home=1 deliberately
    // remains on the landing page even after a companion session is established.
    await page.goto(base + '/');
    await page.getByRole('button', { name: /Get Started/ }).first().click();
    await page.waitForURL('**/onboarding');
    await page.getByRole('button', { name: /I Understand/ }).click();
    stage = 'original companion selection and consent';
    await page.getByRole('button', { name: /Continue with Raza/ }).click();
    for (const checkbox of await page.getByRole('checkbox').all()) await checkbox.check();
    await page.getByRole('button', { name: /I Agree/ }).click();
    await page.getByRole('button', { name: /Continue/ }).click();
    await page.getByRole('button', { name: /Let's Go/ }).click();
    // Deny-all demo rules intentionally prevent companion profile cloud writes.
    // The original flow exposes a local-save continuation; use it if needed.
    stage = 'local saved-companion continuation';
    await Promise.race([
      page.waitForURL('**/chat'),
      page.getByRole('link', { name: 'Continue with saved companion' }).waitFor().then(() => page.getByRole('link', { name: 'Continue with saved companion' }).click()),
    ]);
    await page.waitForURL('**/chat');
    stage = 'mobile companion navigation';
    const mode = await page.getByRole('button', { name: /^Mode:/ }).boundingBox();
    assert(mode && mode.x >= 0 && mode.x + mode.width <= 390, 'existing mode selector must remain visible');
    await page.locator('summary[aria-label="KOI menu"]').click();
    await page.getByRole('link', { name: 'Account sign-in', exact: true }).waitFor();
    assert.equal(await page.getByRole('link', { name: 'Professional Dashboard', exact: true }).count(), 0);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'mobile navigation must fit');
    await page.screenshot({ path: 'review/web-4/evidence/companion-mobile-final.png', fullPage: true });
    assert.equal(companionCalls, 0); assert.equal(liveFirebaseCalls, 0);
    writeFileSync('review/web-4/evidence/companion-smoke-final.json', JSON.stringify({ passed: true, real_anonymous_emulator_login: true, original_onboarding_local_save: true, mobile_navigation: true, existing_mode_selector_visible: true, companion_provider_calls: companionCalls, live_firebase_calls: liveFirebaseCalls, limits: 'Chat replies and live voice/3D provider output are not exercised. Existing transport/avatar regression suites remain required.' }, null, 2) + '\n');
    console.log('PASS original anonymous onboarding and mobile companion account entry; no provider or live Firebase traffic');
  } catch (error) {
    if (page) {
      await page.screenshot({ path: 'review/web-4/evidence/companion-smoke-failure.png', fullPage: true }).catch(() => {});
      console.error((await page.locator('body').innerText().catch(() => '')).slice(0, 1500));
    }
    throw error;
  } finally { await browser.close(); }
}
main().catch(e => { console.error(`Companion smoke failed at ${stage}: ${e.name}: ${e.message.slice(0, 500)}`); process.exitCode = 1; });
