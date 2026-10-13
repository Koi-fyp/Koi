const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { chromium } = require('playwright');

(async () => {
  const origin = 'http://127.0.0.1:3001';
  const output = path.resolve('dev/avatar-sandbox/.next/verification');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless: true, executablePath: process.env.KOI_AVATAR_BROWSER,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const errors = [], consoleErrors = [], warnings = [], external = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => { if (message.type() === 'warning') warnings.push(message.text()); if (message.type() === 'error' && !/Failed to load resource.*404/.test(message.text())) consoleErrors.push(message.text()); });
    page.on('request', (request) => { if (!request.url().startsWith(origin) && !request.url().startsWith('blob:')) external.push(request.url()); });
    await page.addInitScript(() => {
      window.__avatarAudit = { pending: new Set(), contexts: [], observers: new Set() };
      const request = window.requestAnimationFrame.bind(window);
      const cancel = window.cancelAnimationFrame.bind(window);
      window.requestAnimationFrame = (callback) => {
        const id = request((time) => { window.__avatarAudit.pending.delete(id); callback(time); });
        window.__avatarAudit.pending.add(id); return id;
      };
      window.cancelAnimationFrame = (id) => { window.__avatarAudit.pending.delete(id); cancel(id); };
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (...args) {
        const context = getContext.apply(this, args);
        if (context && args[0] === 'webgl2' && !window.__avatarAudit.contexts.includes(context)) window.__avatarAudit.contexts.push(context);
        return context;
      };
      const Observer = window.ResizeObserver;
      window.ResizeObserver = class extends Observer {
        observe(...args) { window.__avatarAudit.observers.add(this); return super.observe(...args); }
        disconnect() { window.__avatarAudit.observers.delete(this); return super.disconnect(); }
      };
    });
    const asset = await page.request.get(origin + '/models/koi-male.vrm');
    assert.equal(asset.status(), 200);
    assert.deepEqual(await asset.body(), await fs.readFile('public/models/koi-male.vrm'));
    assert.equal((await page.request.get(origin + '/models/fox.glb')).status(), 404);
    assert.equal((await page.request.get(origin + '/api/auth/anonymous')).status(), 404);
    await page.goto(origin + '/companion-scene');
    await page.locator('[data-avatar-state="ready"]').waitFor({ timeout: 120000 });
    assert.equal(await page.locator('canvas').count(), 1);
    await page.screenshot({ path: path.join(output, 'desktop.png') });
    const desktop = await page.locator('canvas').evaluate((canvas) => ({ width: canvas.width, height: canvas.height, clientWidth: canvas.clientWidth, clientHeight: canvas.clientHeight }));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    const mobile = await page.locator('canvas').evaluate((canvas) => ({ width: canvas.width, height: canvas.height, clientWidth: canvas.clientWidth, clientHeight: canvas.clientHeight }));
    assert(mobile.width < desktop.width);
    assert.equal(mobile.width, mobile.clientWidth);
    await page.screenshot({ path: path.join(output, 'mobile.png') });
    await page.getByRole('link', { name: 'Back to sandbox' }).click();
    await page.getByRole('heading', { name: 'KOI development sandbox' }).waitFor();
    await page.waitForTimeout(500);
    assert.equal(await page.locator('canvas').count(), 0);
    const cleanup = await page.evaluate(() => ({ pendingFrames: window.__avatarAudit.pending.size, activeObservers: window.__avatarAudit.observers.size, liveContexts: window.__avatarAudit.contexts.filter((context) => !context.isContextLost()).length }));
    assert.deepEqual(cleanup, { pendingFrames: 0, activeObservers: 0, liveContexts: 0 });
    await page.getByRole('link', { name: 'Open avatar viewer' }).click();
    await page.locator('[data-avatar-state="ready"]').waitFor({ timeout: 120000 });
    await page.reload();
    await page.locator('[data-avatar-state="ready"]').waitFor({ timeout: 120000 });
    // Failure and retry use the real renderer with a simulated missing model response.
    await page.route('**/models/koi-male.vrm', (route) => route.fulfill({ status: 404, body: 'missing' }));
    await page.reload();
    await page.locator('[data-avatar-state] [role=alert]').waitFor();
    assert.match(await page.locator('[data-avatar-state] [role=alert]').innerText(), /404/);
    await page.unroute('**/models/koi-male.vrm');
    await page.getByRole('button', { name: 'Retry' }).click();
    await page.locator('[data-avatar-state="ready"]').waitFor({ timeout: 120000 });
    assert.equal(await page.locator('canvas').count(), 1);
    assert.deepEqual(errors, []);
    assert.deepEqual(consoleErrors, []);
    const productionLauncher = spawnSync(process.execPath, ['scripts/avatar-dev.cjs'], { env: { ...process.env, NODE_ENV: 'production' }, encoding: 'utf8' });
    assert.equal(productionLauncher.status, 1);
    assert.match(productionLauncher.stderr, /only in development/);
    const config = require('../dev/avatar-sandbox/next.config.js');
    assert.throws(() => config(require('next/constants').PHASE_PRODUCTION_BUILD), /cannot be built or served in production/);
    assert.deepEqual(external, []);
    const results = { passed: true, desktop, mobile, cleanup, pageErrors: errors, consoleErrors, productionGuards: 'passed', externalRequests: external, warnings };
    await fs.writeFile(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    console.log(JSON.stringify(results, null, 2));
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
