#!/usr/bin/env node
// UI fix verification (2026-10-19). Prints PASS/FAIL per assertion.
// Usage: node scripts/verify-ui-fix.cjs [--items=1,1b,2,3,4] [--base=http://localhost:3000]
// Needs a running dev server. Without a saved state it completes the app's own
// anonymous sign-in once (via the landing CTA) and stores it under artifacts/ui-fix/.
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require('playwright');

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')));
const BASE = args.base || 'http://localhost:3000';
const ITEMS = (args.items || '1,1b,2,3,4').split(',');
const OUT = path.resolve(__dirname, '..', 'artifacts', 'ui-fix');
const STATE = path.join(OUT, '.auth-state.json');
const STATE_META = path.join(OUT, '.auth-state-meta.json');
const VIEWPORTS = { '1280x800': { width: 1280, height: 800 }, '390x844': { width: 390, height: 844 } };
const results = [];

function record(item, name, pass, detail = '') {
  results.push({ item, name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} [${item}] ${name}${detail ? ` — ${detail}` : ''}`);
}

function watchErrors(page) {
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text().slice(0, 200)}`); });
  page.on('pageerror', (e) => errors.push(`pageerror: ${String(e).slice(0, 200)}`));
  return errors;
}

// Observes the DOM from the first byte so a landing flash cannot slip between polls.
const OBSERVER = () => {
  window.__koiSeen = { hero: false, spinner: false, spinnerFirst: null };
  const check = () => {
    const hero = !!document.querySelector('h1.neo-hero-text');
    const spinner = !!document.querySelector('[data-testid="auth-pending-spinner"]');
    if (spinner && window.__koiSeen.spinnerFirst === null && !window.__koiSeen.hero) window.__koiSeen.spinnerFirst = true;
    if (hero && window.__koiSeen.spinnerFirst === null) window.__koiSeen.spinnerFirst = false;
    window.__koiSeen.hero ||= hero; window.__koiSeen.spinner ||= spinner;
  };
  new MutationObserver(check).observe(document, { subtree: true, childList: true });
  document.addEventListener('DOMContentLoaded', check);
};

async function boxInfo(locator, vpWidth) {
  const box = await locator.boundingBox();
  if (!box) return { ok: false, detail: 'no box' };
  const ok = box.width > 0 && box.height > 0 && box.x >= -0.5 && box.x + box.width <= vpWidth + 0.5;
  return { ok, detail: `x=${box.x.toFixed(0)} w=${box.width.toFixed(0)} h=${box.height.toFixed(0)}` };
}

async function noHorizontalScroll(page) {
  return page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
}

async function ensureSignedInState(browser) {
  if (fs.existsSync(STATE)) return JSON.parse(fs.readFileSync(STATE_META, 'utf8'));
  const ctx = await browser.newContext({ viewport: VIEWPORTS['1280x800'] });
  const page = await ctx.newPage();
  let signUpRequested = false;
  page.on('request', (r) => { if (/identitytoolkit\.googleapis\.com\/v1\/accounts:signUp/.test(r.url())) signUpRequested = true; });
  await page.goto(`${BASE}/`, { waitUntil: 'load', timeout: 180000 });
  await page.getByRole('button', { name: /Start Talking/ }).click();
  await page.waitForURL(/\/onboarding|\/chat/, { timeout: 60000 });
  const landedAt = new URL(page.url()).pathname;
  for (let i = 0; i < 20 && !/\/chat/.test(page.url()); i++) {
    await page.waitForTimeout(800);
    const boxes = page.locator('[role=checkbox][aria-checked=false]');
    for (let k = 0; k < 5 && await boxes.count(); k++) { await boxes.first().click(); await page.waitForTimeout(200); }
    const cont = page.getByRole('button', { name: 'Continue' });
    const next = page.locator('button:visible:not([role=checkbox]):not([role=switch]):enabled');
    if (await cont.count() && await cont.first().isVisible()) await cont.first().click();
    else if (await next.count()) await next.last().click();
  }
  await page.waitForURL(/\/chat/, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await ctx.storageState({ path: STATE, indexedDB: true });
  const meta = { createdAt: new Date().toISOString(), signUpRequested, landedAt };
  fs.writeFileSync(STATE_META, JSON.stringify(meta));
  await ctx.close();
  return { ...meta, live: true };
}

async function item1(browser, signIn) {
  for (const [vp, size] of Object.entries(VIEWPORTS)) {
    const ctx = await browser.newContext({ viewport: size });
    const page = await ctx.newPage();
    const errors = watchErrors(page);
    let signUpRequested = false;
    // The real sign-in runs once (state creation); later CTA clicks are recorded and aborted.
    await page.route(/identitytoolkit\.googleapis\.com\/v1\/accounts:signUp/, (route) => { signUpRequested = true; return route.abort(); });
    await page.goto(`${BASE}/`, { waitUntil: 'load', timeout: 180000 });
    await page.waitForSelector('h1.neo-hero-text', { timeout: 30000 }).catch(() => {});
    const parts = {
      header: page.locator('nav').first(),
      'hero heading': page.locator('h1.neo-hero-text'),
      'primary CTA': page.getByRole('button', { name: /Start Talking/ }),
      footer: page.locator('footer'),
    };
    for (const [name, loc] of Object.entries(parts)) {
      await loc.scrollIntoViewIfNeeded().catch(() => {});
      const info = await boxInfo(loc, size.width);
      record('1', `${vp} ${name} visible inside viewport`, info.ok, info.detail);
    }
    for (const [name, selector, expected] of [['feature cards', '#features .reveal', 4], ['FAQ items', '.faq-item', 7]]) {
      const loc = page.locator(selector);
      const count = await loc.count();
      let allOk = count === expected;
      for (let i = 0; i < count; i++) {
        await loc.nth(i).scrollIntoViewIfNeeded();
        await page.waitForTimeout(150);
        const info = await boxInfo(loc.nth(i), size.width);
        const opacity = await loc.nth(i).evaluate((el) => Number(getComputedStyle(el).opacity));
        allOk = allOk && info.ok;
        if (name === 'feature cards') { await page.waitForTimeout(500); allOk = allOk && await loc.nth(i).evaluate((el) => Number(getComputedStyle(el).opacity)) > 0.5; }
        else allOk = allOk && opacity > 0;
      }
      record('1', `${vp} ${name} (${count}) visible inside viewport`, allOk);
    }
    record('1', `${vp} no horizontal scroll`, await noHorizontalScroll(page));
    const stylesheetApplied = await page.evaluate(() => getComputedStyle(document.querySelector('.neo-btn-primary')).borderRadius === '9999px');
    record('1', `${vp} theme stylesheet applied (CTA is a pill)`, stylesheetApplied);
    record('1', `${vp} no console errors / page errors`, errors.length === 0, errors.join(' | '));
    const beforeClick = errors.length;
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.getByRole('button', { name: /Start Talking/ }).click();
    await page.waitForTimeout(2500);
    record('1', `${vp} CTA click issues the anonymous sign-in request`, signUpRequested);
    // Only the deliberately aborted sign-up request may log after the click.
    const afterClick = errors.slice(beforeClick).filter((e) => !/net::ERR_FAILED/.test(e));
    record('1', `${vp} no errors after CTA click besides the aborted sign-up`, afterClick.length === 0, afterClick.join(' | '));
    await ctx.close();
  }
  record('1', `signed-out CTA sign-in ends at /onboarding or /chat (${signIn.live ? 'live this run' : `live at state creation ${signIn.createdAt}`})`,
    signIn.signUpRequested && /^\/(onboarding|chat)/.test(signIn.landedAt), `landed ${signIn.landedAt}`);
}

async function item1b(browser) {
  for (const [vp, size] of Object.entries(VIEWPORTS)) {
    // New tab in a second context that reuses the saved storage (Firebase restores from IndexedDB).
    const ctx = await browser.newContext({ viewport: size, storageState: STATE });
    await ctx.addInitScript(OBSERVER);
    const page = await ctx.newPage();
    const errors = watchErrors(page);
    await page.goto(`${BASE}/about`, { waitUntil: 'load', timeout: 120000 });
    await page.goto(`${BASE}/`, { waitUntil: 'commit' });
    const seen = await page.waitForURL(/\/chat/, { timeout: 30000 }).then(() => true, () => false);
    record('1b', `${vp} signed-in + onboarded at / lands on /chat`, seen, page.url());
    // __koiSeen is per-document; read it from the / document before Next swaps routes client-side.
    const flags = await page.evaluate(() => window.__koiSeen).catch(() => null);
    record('1b', `${vp} landing hero never in the DOM for signed-in visit`, !!flags && !flags.hero, JSON.stringify(flags));
    record('1b', `${vp} spinner shown first`, !!flags && flags.spinnerFirst === true);
    await page.goBack();
    await page.waitForTimeout(3000);
    const back = new URL(page.url()).pathname;
    record('1b', `${vp} Back from /chat returns to the previous page without bouncing`, back === '/about', back);

    await page.goto(`${BASE}/?home=1`, { waitUntil: 'load' });
    await page.waitForSelector('h1.neo-hero-text', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(3000);
    record('1b', `${vp} /?home=1 keeps signed-in user on landing (hero, no redirect)`,
      new URL(page.url()).pathname === '/' && await page.locator('h1.neo-hero-text').isVisible().catch(() => false), page.url());
    const open = page.getByRole('button', { name: 'Open chat' }).first();
    record('1b', `${vp} "Open chat" button present with primary style`, await open.isVisible().catch(() => false)
      && await open.evaluate((el) => el.classList.contains('neo-btn-primary')).catch(() => false));
    record('1b', `${vp} "Get Started" absent for signed-in user`, await page.getByRole('button', { name: /Get Started/ }).count() === 0);
    await open.click().catch(() => {});
    record('1b', `${vp} "Open chat" opens /chat`, await page.waitForURL(/\/chat/, { timeout: 30000 }).then(() => true, () => false));
    const home = page.getByRole('link', { name: 'Home', exact: true });
    record('1b', `${vp} top bar has Home -> /?home=1`, await home.getAttribute('href').catch(() => null) === '/?home=1');
    const logo = page.getByRole('link', { name: 'KOI home' });
    record('1b', `${vp} top bar logo does not bounce (href)`, ['/?home=1'].includes(await logo.getAttribute('href').catch(() => null)));
    record('1b', `${vp} no console errors / page errors`, errors.length === 0, errors.join(' | '));
    await ctx.close();

    // Signed in but not onboarded for this UID: drop the per-UID flag in a copy of the storage.
    const ctx2 = await browser.newContext({ viewport: size, storageState: STATE });
    await ctx2.addInitScript(() => {
      for (const key of Object.keys(localStorage)) if (key.startsWith('koi_onboarding_complete')) localStorage.removeItem(key);
    });
    const page2 = await ctx2.newPage();
    await page2.goto(`${BASE}/`, { waitUntil: 'commit' });
    record('1b', `${vp} signed-in, not onboarded at / goes to /onboarding`,
      await page2.waitForURL(/\/onboarding/, { timeout: 30000 }).then(() => true, () => false), page2.url());
    await ctx2.close();
  }
}

module.exports = { record, watchErrors, boxInfo, noHorizontalScroll, VIEWPORTS, BASE, STATE, OUT };

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const signIn = await ensureSignedInState(browser);
    if (ITEMS.includes('1')) await item1(browser, signIn);
    if (ITEMS.includes('1b')) await item1b(browser);
    for (const item of ['2', '3', '4']) {
      if (!ITEMS.includes(item)) continue;
      const run = ITEM_RUNNERS[item];
      if (run) await run(browser); else record(item, 'assertions defined', false, 'not implemented');
    }
  } finally {
    await browser.close();
  }
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} PASS${failed.length ? `, ${failed.length} FAIL` : ''}`);
  process.exitCode = failed.length ? 1 : 0;
}

const ITEM_RUNNERS = {};

if (require.main === module) main().catch((e) => { console.error('FATAL', e); process.exit(2); });
