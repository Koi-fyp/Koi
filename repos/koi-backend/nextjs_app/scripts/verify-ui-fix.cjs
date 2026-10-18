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
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
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

// Computed look of an existing neo button, measured on the same page with a probe element.
async function neoReference(page, cls) {
  return page.evaluate((c) => {
    const probe = document.createElement('button');
    probe.className = c; probe.textContent = 'probe'; probe.style.position = 'absolute'; probe.style.left = '-9999px';
    document.body.appendChild(probe);
    const cs = getComputedStyle(probe);
    const ref = { bg: cs.backgroundColor, shadow: cs.boxShadow, radius: cs.borderRadius, border: `${cs.borderTopWidth} ${cs.borderTopStyle} ${cs.borderTopColor}` };
    probe.remove();
    return ref;
  }, cls);
}

async function navBottom(page) {
  return page.evaluate(() => { const nav = document.querySelector('nav'); return nav ? nav.getBoundingClientRect().bottom : 0; });
}

async function focusByTab(page, locator) {
  await page.evaluate(() => { document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0); });
  await page.locator('body').click({ position: { x: 2, y: 200 }, force: true }).catch(() => {});
  for (let i = 0; i < 80; i++) {
    await page.keyboard.press('Tab');
    if (await locator.evaluate((el) => el === document.activeElement).catch(() => false)) return true;
  }
  return false;
}

async function checkControls(page, item, label, vp, size, controls) {
  await page.mouse.move(1, size.height - 1);
  const refs = { 'neo-btn-primary': await neoReference(page, 'neo-btn-primary'), 'neo-btn-secondary': await neoReference(page, 'neo-btn-secondary') };
  for (const { name, locator } of controls) {
    const el = locator.first();
    if (!await el.count()) { record(item, `${vp} ${label} "${name}" present`, false, 'not found'); continue; }
    await el.evaluate((node) => node.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(150);
    const look = await el.evaluate((node) => {
      const cs = getComputedStyle(node);
      const cls = ['neo-btn-primary', 'neo-btn-secondary'].find((c) => node.classList.contains(c)) || null;
      const disabled = node.matches(':disabled') || node.getAttribute('aria-disabled') === 'true';
      const r = node.getBoundingClientRect();
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return { cls, bg: cs.backgroundColor, shadow: cs.boxShadow, radius: cs.borderRadius, font: cs.fontFamily, disabled,
        opacity: Number(cs.opacity), unobstructed: !!hit && (hit === node || node.contains(hit)) };
    });
    const ref = look.cls && refs[look.cls];
    record(item, `${vp} ${label} "${name}" uses neo button look`, !!ref && look.bg === ref.bg && look.shadow === ref.shadow && look.radius === ref.radius,
      `${look.cls} bg=${look.bg} shadow=${look.shadow}`);
    const box = await el.boundingBox();
    const top = await navBottom(page);
    const inside = !!box && box.x >= 0 && box.x + box.width <= size.width + 0.5 && box.y >= top - 0.5 && box.y + box.height <= size.height + 0.5;
    record(item, `${vp} ${label} "${name}" inside viewport, below nav, not covered`, inside && look.unobstructed,
      box ? `y=${box.y.toFixed(0)} nav=${top.toFixed(0)} x=${box.x.toFixed(0)} w=${box.width.toFixed(0)} covered=${!look.unobstructed}` : 'no box');
    if (look.disabled) {
      record(item, `${vp} ${label} "${name}" disabled state exposed (disabled/aria-disabled)`, true);
    } else {
      if (look.opacity < 0.9) record(item, `${vp} ${label} "${name}" looks disabled but is not exposed`, false, `opacity ${look.opacity}`);
      const focused = await focusByTab(page, el);
      const ring = focused && await el.evaluate((node) => { const cs = getComputedStyle(node); return cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) >= 2; });
      record(item, `${vp} ${label} "${name}" visible focus outline when tabbed to`, !!ring, focused ? '' : 'never focused by Tab');
    }
  }
  record(item, `${vp} ${label} no horizontal scroll`, await noHorizontalScroll(page));
}

ITEM_RUNNERS['3'] = async (browser) => {
  const CARDS = [
    ['counts', 'section[aria-label="Saved activity counts"]'],
    ['recorded board', 'section[aria-label="Recorded 25-piece board"]'],
    ['check-in (form + chart)', 'section[aria-label="Recorded activities"]'],
    ['activity calendar', 'section[aria-label="Activity calendar"]'],
  ];
  for (const [vp, size] of Object.entries(VIEWPORTS)) {
    const ctx = await browser.newContext({ viewport: size, storageState: STATE });
    const page = await ctx.newPage();
    const errors = watchErrors(page);
    await page.goto(`${BASE}/progress`, { waitUntil: 'load', timeout: 120000 });
    await page.locator(CARDS[3][1]).waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(2500);
    // Reference: the existing "Mood Trends (Preview)" Progress card (inside the previews disclosure).
    const ref = await page.evaluate(() => {
      const details = [...document.querySelectorAll('details')].find((d) => /Design previews/.test(d.querySelector('summary')?.textContent || ''));
      if (!details) return null;
      details.open = true;
      const h = [...details.querySelectorAll('h3')].find((e) => /Mood Trends/.test(e.textContent));
      const card = h && h.parentElement.parentElement;
      const cs = getComputedStyle(card);
      const hs = getComputedStyle(h);
      const out = { radius: cs.borderRadius, border: `${cs.borderTopWidth} ${cs.borderTopStyle} ${cs.borderTopColor}`, shadow: cs.boxShadow, bg: cs.backgroundColor,
        title: `${hs.fontWeight} ${hs.fontSize} ${hs.letterSpacing}`, font: getComputedStyle(document.querySelector('main')).fontFamily };
      details.open = false;
      return out;
    });
    record('3', `${vp} reference Progress card found`, !!ref, JSON.stringify(ref));
    const tops = [];
    for (const [name, selector] of CARDS) {
      const info = await page.evaluate(([sel]) => {
        const card = document.querySelector(sel);
        if (!card) return null;
        const cs = getComputedStyle(card);
        const r = card.getBoundingClientRect();
        const title = card.querySelector('h2');
        const ts = title && getComputedStyle(title);
        // Every rendered descendant must stay inside the card box (scroll containers excepted).
        const overflow = [...card.querySelectorAll('*')].filter((el) => {
          if (el.closest('.overflow-x-auto') || el.closest('[role=dialog]') || el.closest('details:not([open]) > :not(summary)')) return false;
          const b = el.getBoundingClientRect();
          if (!b.width && !b.height) return false;
          return b.left < r.left - 1 || b.right > r.right + 1 || b.top < r.top - 1 || b.bottom > r.bottom + 1;
        }).map((el) => `${el.tagName}.${String(el.className).slice(0, 30)}`);
        const textFonts = [...card.querySelectorAll('h2,h3,p,dt,dd,legend,label,figcaption')].map((el) => getComputedStyle(el).fontFamily);
        return { radius: cs.borderRadius, border: `${cs.borderTopWidth} ${cs.borderTopStyle} ${cs.borderTopColor}`, shadow: cs.boxShadow, bg: cs.backgroundColor,
          title: ts && `${ts.fontWeight} ${ts.fontSize} ${ts.letterSpacing}`, font: cs.fontFamily, textFonts: [...new Set(textFonts)], overflow, top: r.top + window.scrollY,
          left: r.left, right: r.right };
      }, [selector]);
      if (!info) { record('3', `${vp} ${name} card present`, false); continue; }
      tops.push(info.top);
      record('3', `${vp} ${name} card radius/border/shadow/background equal existing card`, !!ref && info.radius === ref.radius && info.border === ref.border && info.shadow === ref.shadow && info.bg === ref.bg,
        `${info.radius} | ${info.border} | ${info.shadow} | ${info.bg}`);
      record('3', `${vp} ${name} heading style equals existing card heading`, !!ref && info.title === ref.title, `${info.title} vs ${ref && ref.title}`);
      record('3', `${vp} ${name} font family equals the page's`, !!ref && info.font === ref.font && info.textFonts.every((f) => f === ref.font), info.textFonts.join(' / '));
      record('3', `${vp} ${name} no element overflows the card`, info.overflow.length === 0, info.overflow.slice(0, 4).join(', '));
      record('3', `${vp} ${name} card inside viewport width`, info.left >= 0 && info.right <= size.width + 0.5, `${info.left.toFixed(0)}..${info.right.toFixed(0)}`);
    }
    const previewsTop = await page.evaluate(() => {
      const d = [...document.querySelectorAll('details')].find((e) => /Design previews/.test(e.querySelector('summary')?.textContent || ''));
      return d ? d.getBoundingClientRect().top + window.scrollY : -1;
    });
    tops.push(previewsTop);
    record('3', `${vp} order: counts, board, check-in, calendar, previews`, tops.length === 5 && tops.every((t, i) => i === 0 || t > tops[i - 1]), tops.map((t) => t.toFixed(0)).join(' < '));
    const form = await page.evaluate(() => {
      const card = document.querySelector('section[aria-label="Recorded activities"]');
      const selects = [...card.querySelectorAll('select')];
      const save = [...card.querySelectorAll('button')].find((b) => /Save check-in|Check-in saved|Saving/.test(b.textContent));
      return { selects: selects.length && selects.every((s) => s.classList.contains('neo-input')), save: !!save && save.classList.contains('neo-btn-primary') };
    });
    record('3', `${vp} check-in selects use .neo-input`, !!form.selects);
    record('3', `${vp} Save check-in uses .neo-btn-primary`, form.save);
    const palette = await page.evaluate(() => {
      const theme = ['#2d63eb', '#ff6b6b', '#2dd36f', '#f4f4f4', '#c7d6fa', '#86a6f3', '#16399a'];
      const fills = [...document.querySelectorAll('section[aria-label="Activity calendar"] svg rect, section[aria-label="Recorded activities"] svg [fill]:not(text)')]
        .map((e) => (e.getAttribute('fill') || '').toLowerCase()).filter((f) => f && f !== 'transparent' && f !== 'none' && f !== '#fff');
      return { fills: [...new Set(fills)], ok: fills.every((f) => theme.includes(f)) };
    });
    record('3', `${vp} chart/calendar colours come from the theme palette (${palette.fills.length ? palette.fills.join(',') : 'no data drawn yet'})`, palette.ok);
    record('3', `${vp} /progress no horizontal scroll`, await noHorizontalScroll(page));
    record('3', `${vp} /progress no console errors / page errors`, errors.length === 0, errors.join(' | '));
    await ctx.close();
  }
};

// Reads pixels of a PNG screenshot through a canvas in the page (no image dependency).
async function samplePixels(page, png, points) {
  return page.evaluate(async ([data, pts]) => {
    const img = new Image();
    img.src = `data:image/png;base64,${data}`;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.width; canvas.height = img.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    return pts.map(([x, y]) => [...ctx.getImageData(Math.round(x), Math.round(y), 1, 1).data].slice(0, 3));
  }, [png.toString('base64'), points]);
}
const near = (rgb, target, tol = 8) => rgb.every((v, i) => Math.abs(v - target[i]) <= tol);

async function checkPaper(page, item, label, vp, size, paperSelector) {
  const paper = page.locator(paperSelector).first();
  if (!await paper.count()) { record(item, `${vp} ${label} paper container present`, false); return; }
  record(item, `${vp} ${label} paper container carries .koi-paper`, await paper.evaluate((el) => el.classList.contains('koi-paper')));
  const bg = await paper.evaluate((paperEl) => {
    const white = 'rgb(255, 255, 255)';
    const bad = [];
    const walker = document.createTreeWalker(paperEl, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.textContent.trim()) continue;
      let el = node.parentElement, seen = null;
      // First painted background between the text and the paper (inclusive) must be white.
      while (el) {
        const b = getComputedStyle(el).backgroundColor;
        if (b !== 'rgba(0, 0, 0, 0)' && b !== 'transparent') { seen = b; break; }
        if (el === paperEl) break;
        el = el.parentElement;
      }
      if (seen !== white) bad.push(`${node.parentElement.tagName}:${seen}`);
    }
    return { paper: getComputedStyle(paperEl).backgroundColor, bad };
  });
  record(item, `${vp} ${label} paper background is white and every text run inside sits on white`, bg.paper === 'rgb(255, 255, 255)' && bg.bad.length === 0,
    `${bg.paper}${bg.bad.length ? ` bad: ${bg.bad.slice(0, 3).join(', ')}` : ''}`);
  await paper.evaluate((el) => el.scrollIntoView({ block: 'start', behavior: 'instant' }));
  await page.evaluate(() => window.scrollBy({ top: -100, behavior: 'instant' }));
  await page.waitForTimeout(300);
  const box = await paper.boundingBox();
  const top = Math.max(box.y, await navBottom(page));
  const bottom = Math.min(box.y + box.height, size.height);
  const midY = (top + bottom) / 2;
  const insidePts = [[box.x + 12, midY], [box.x + box.width - 14, midY], [box.x + box.width / 2, Math.max(box.y + 10, top + 2)]];
  if (box.y + box.height < size.height - 12) insidePts.push([box.x + box.width / 2, box.y + box.height - 12]);
  const outside = [Math.max(2, box.x - 8), midY];
  const png = await page.screenshot();
  const px = await samplePixels(page, png, [...insidePts, outside]);
  const inside = px.slice(0, -1);
  record(item, `${vp} ${label} sampled pixels inside the capsule are white`, inside.every((p) => near(p, [255, 255, 255], 3)), JSON.stringify(inside));
  const pageColour = await page.evaluate(() => getComputedStyle(document.body).backgroundColor.match(/\d+/g).map(Number));
  record(item, `${vp} ${label} sampled pixel outside the capsule is the page colour`, box.x >= 10 && near(px[px.length - 1], pageColour), `${JSON.stringify(px[px.length - 1])} vs ${JSON.stringify(pageColour)}`);

  await page.emulateMedia({ media: 'print' });
  await page.waitForTimeout(300);
  const print = await page.evaluate(() => ({
    nav: [...document.querySelectorAll('nav')].every((n) => getComputedStyle(n).display === 'none'),
    controls: [...document.querySelectorAll('.no-print')].every((n) => getComputedStyle(n).display === 'none') && document.querySelectorAll('.no-print').length > 0,
    buttons: [...document.querySelectorAll('button')].filter((b) => b.offsetParent !== null).map((b) => b.textContent.trim()),
    body: getComputedStyle(document.body).backgroundColor,
  }));
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  const printPng = await page.screenshot({ path: path.join(OUT, `4-${label.replace(/\//g, '').replace(/[^a-z-]/gi, '-')}-print-${vp}.png`), fullPage: true });
  const corner = await samplePixels(page, printPng, [[3, 3], [size.width - 4, 40]]);
  record(item, `${vp} ${label} print: nav hidden`, print.nav);
  record(item, `${vp} ${label} print: controls hidden`, print.controls && print.buttons.length === 0, print.buttons.join(', '));
  record(item, `${vp} ${label} print: page background white`, print.body === 'rgb(255, 255, 255)' && corner.every((p) => near(p, [255, 255, 255], 3)), `${print.body} ${JSON.stringify(corner)}`);
  await page.emulateMedia({ media: 'screen' });
}

ITEM_RUNNERS['4'] = async (browser) => {
  for (const [vp, size] of Object.entries(VIEWPORTS)) {
    const ctx = await browser.newContext({ viewport: size, storageState: STATE, acceptDownloads: false });
    const page = await ctx.newPage();
    const errors = watchErrors(page);
    await page.goto(`${BASE}/settings/report`, { waitUntil: 'load', timeout: 120000 });
    await page.locator('article[aria-label^="Report for"]').waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(1500);
    await checkPaper(page, '4', '/settings/report', vp, size, '[data-testid="report-paper"]');
    const optionsAbove = await page.evaluate(() => {
      const form = document.querySelector('form[aria-label="Report options"]');
      const paper = document.querySelector('[data-testid="report-paper"]');
      return !!form && !!paper && form.classList.contains('neo-card') && form.getBoundingClientRect().bottom <= paper.getBoundingClientRect().top;
    });
    record('4', `${vp} /settings/report controls card (range, titles, print) sits above the paper`, optionsAbove);
    record('4', `${vp} /settings/report no horizontal scroll`, await noHorizontalScroll(page));

    await page.goto(`${BASE}/settings/export`, { waitUntil: 'load' });
    await page.getByRole('checkbox', { name: /I understand the metadata/ }).check();
    await page.getByRole('button', { name: 'Prepare data export' }).click();
    await page.locator('[data-testid="export-preview-paper"]').waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(800);
    await checkPaper(page, '4', '/settings/export', vp, size, '[data-testid="export-preview-paper"]');
    const exportAbove = await page.evaluate(() => {
      const card = document.querySelector('section[aria-labelledby="ciphertext-export-title"]');
      const paper = document.querySelector('[data-testid="export-preview-paper"]');
      return !!card && !!paper && card.getBoundingClientRect().bottom <= paper.getBoundingClientRect().top;
    });
    record('4', `${vp} /settings/export controls card (consent, prepare, download) sits above the preview paper`, exportAbove);
    record('4', `${vp} /settings/export no horizontal scroll`, await noHorizontalScroll(page));
    record('4', `${vp} export/report no console errors / page errors`, errors.length === 0, errors.join(' | '));
    await ctx.close();
  }
};

ITEM_RUNNERS['2'] = async (browser) => {
  for (const [vp, size] of Object.entries(VIEWPORTS)) {
    const ctx = await browser.newContext({ viewport: size, storageState: STATE });
    const page = await ctx.newPage();
    const errors = watchErrors(page);
    const product = [
      { name: 'New Chat', locator: page.getByRole('button', { name: /^New Chat/ }) },
      { name: 'Complete Conversation', locator: page.getByRole('button', { name: 'Complete Conversation' }) },
      { name: 'Change companion', locator: page.getByRole('button', { name: 'Change companion' }) },
    ];
    await page.goto(`${BASE}/chat`, { waitUntil: 'load', timeout: 120000 });
    await page.getByRole('button', { name: 'Change companion' }).waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await checkControls(page, '2', '/chat', vp, size, [...product,
      { name: 'Open avatar conversation', locator: page.getByRole('link', { name: 'Open avatar conversation' }) },
      { name: 'Browse saved history', locator: page.getByRole('link', { name: 'Browse saved history' }) }]);
    await page.getByRole('button', { name: 'Complete Conversation' }).click();
    await checkControls(page, '2', '/chat details', vp, size, [{ name: 'Save completion', locator: page.getByRole('button', { name: /Save completion/ }) }]);
    await page.screenshot({ path: path.join(OUT, `2-chat-details-${vp}-after.png`) });

    await page.goto(`${BASE}/history`, { waitUntil: 'load' });
    await page.getByText('Refresh saved history').waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(1500);
    // "Open conversation" only renders for an archived conversation with messages (none are sent here);
    // its class is asserted in src/__tests__/history-page.test.tsx.
    await checkControls(page, '2', '/history', vp, size, [
      { name: 'Back to current chat', locator: page.getByRole('link', { name: 'Back to current chat' }) },
      { name: 'New Chat', locator: page.getByRole('button', { name: /^New Chat/ }) },
      { name: 'Refresh saved history', locator: page.getByRole('button', { name: 'Refresh saved history' }) },
      { name: 'Read saved conversation', locator: page.getByRole('button', { name: 'Read saved conversation' }) },
      { name: 'Continue current conversation', locator: page.getByRole('link', { name: 'Continue current conversation' }) }]);
    await page.screenshot({ path: path.join(OUT, `2-history-state-${vp}-after.png`), fullPage: true });

    await page.goto(`${BASE}/companion-scene`, { waitUntil: 'load' });
    await page.getByRole('button', { name: 'Change companion' }).waitFor({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(4000);
    await checkControls(page, '2', '/companion-scene', vp, size, product);
    record('2', `${vp} no console errors / page errors on /chat, /history, /companion-scene`, errors.length === 0, errors.join(' | '));
    await ctx.close();
  }
};

if (require.main === module) main().catch((e) => { console.error('FATAL', e); process.exit(2); });
