// B1 lifecycle verification on the display-only /avatar-host route (no Firebase, no API).
// Per model: load, reload, resize 640x800 -> 360x640 -> 1280x800, client-side model switch away and back
// (renderer effect cleanup = the same release path as unmount), full navigation away and back.
// Usage: KOI_AVATAR_HOST_ORIGIN=http://127.0.0.1:3010 node scripts/verify-avatar-lifecycle.cjs
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');

const ORIGIN = process.env.KOI_AVATAR_HOST_ORIGIN || 'http://127.0.0.1:3010';
const OUT = path.resolve(__dirname, '..', 'artifacts', 'avatar-emotion');
const MODELS = { male: '/models/koi-male.vrm', female: '/models/koi-female.vrm' };
const SIZES = [{ width: 640, height: 800 }, { width: 360, height: 640 }, { width: 1280, height: 800 }];
const HOST_MAX_PIXEL_RATIO = 1.25; // AvatarWebViewHost passes maxPixelRatio={1.25}.
const isLocal = (url) => { try { const parsed = new URL(url); return ['data:', 'blob:', 'about:'].includes(parsed.protocol) || parsed.origin === ORIGIN; } catch { return false; } };

// Observes WebGL/RAF/ResizeObserver lifecycles without touching application code.
function instrument() {
  const audit = window.__lifecycle = { contexts: [], lostEvents: [], loseContextCalls: 0, deletes: 0, creationErrorListenersRemoved: 0,
    rafPending: new Set(), observers: new Set(), koiMessages: [], readyEvents: 0, notReadyEvents: 0, mediaCalls: 0 };
  window.KoiBridge = { postMessage: (message) => audit.koiMessages.push(message) };
  window.addEventListener('AVATAR_READY', () => audit.readyEvents++);
  window.addEventListener('AVATAR_NOT_READY', () => audit.notReadyEvents++);
  if (navigator.mediaDevices?.getUserMedia) navigator.mediaDevices.getUserMedia = async () => { audit.mediaCalls++; throw new Error('media disabled in this harness'); };
  const request = window.requestAnimationFrame.bind(window), cancel = window.cancelAnimationFrame.bind(window);
  window.requestAnimationFrame = (callback) => { const id = request((time) => { audit.rafPending.delete(id); callback(time); }); audit.rafPending.add(id); return id; };
  window.cancelAnimationFrame = (id) => { audit.rafPending.delete(id); cancel(id); };
  const Observer = window.ResizeObserver;
  window.ResizeObserver = class extends Observer {
    observe(...args) { audit.observers.add(this); return super.observe(...args); }
    disconnect() { audit.observers.delete(this); return super.disconnect(); }
  };
  const getContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
    const context = getContext.call(this, type, ...rest);
    if (context && /^(webgl2?|experimental-webgl)$/.test(type) && !audit.contexts.some((entry) => entry.context === context)) {
      const entry = { context, canvas: this, forced: false, created: performance.now() };
      audit.contexts.push(entry);
      this.addEventListener('webglcontextlost', () => audit.lostEvents.push({ index: audit.contexts.indexOf(entry), forced: entry.forced, connected: this.isConnected, at: performance.now() }));
    }
    return context;
  };
  for (const Proto of [window.WebGL2RenderingContext, window.WebGLRenderingContext].filter(Boolean)) {
    const getExtension = Proto.prototype.getExtension;
    Proto.prototype.getExtension = function (name) {
      const extension = getExtension.call(this, name);
      if (name === 'WEBGL_lose_context' && extension && !extension.__wrapped) {
        const lose = extension.loseContext.bind(extension), gl = this;
        extension.loseContext = () => { audit.loseContextCalls++; const entry = audit.contexts.find((item) => item.context === gl); if (entry) entry.forced = true; return lose(); };
        extension.__wrapped = true;
      }
      return extension;
    };
    for (const method of ['deleteTexture', 'deleteBuffer', 'deleteProgram', 'deleteFramebuffer', 'deleteVertexArray']) {
      const original = Proto.prototype[method];
      if (original) Proto.prototype[method] = function (...args) { audit.deletes++; return original.apply(this, args); };
    }
  }
  // WebGLRenderer.dispose() is the only code here that removes a canvas 'webglcontextcreationerror' listener.
  const removeListener = HTMLCanvasElement.prototype.removeEventListener;
  HTMLCanvasElement.prototype.removeEventListener = function (type, ...rest) {
    if (type === 'webglcontextcreationerror') audit.creationErrorListenersRemoved++;
    return removeListener.call(this, type, ...rest);
  };
}

async function main() {
  await fs.mkdir(OUT, { recursive: true });
  const startedAt = Date.now();
  const failures = [];
  const fail = (message) => { failures.push(message); console.error('FAIL', message); };
  const result = { origin: ORIGIN, models: {}, blockedRequests: [] };
  const browser = await chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const context = await browser.newContext({ viewport: SIZES[0], deviceScaleFactor: 1, reducedMotion: 'reduce' });
    await context.route('**/*', (route) => {
      if (isLocal(route.request().url())) return route.continue();
      result.blockedRequests.push(route.request().url()); return route.abort();
    });
    await context.addInitScript(instrument);

    for (const [model, modelUrl] of Object.entries(MODELS)) {
      const other = model === 'male' ? 'female' : 'male';
      const page = await context.newPage();
      page.setDefaultTimeout(180000);
      const pageErrors = [], consoleErrors = [];
      page.on('pageerror', (error) => pageErrors.push(error.message));
      page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
      const cdp = await context.newCDPSession(page);
      await cdp.send('Performance.enable');
      const heapMb = async () => { const { metrics } = await cdp.send('Performance.getMetrics'); return +((metrics.find((m) => m.name === 'JSHeapUsedSize')?.value ?? 0) / 2 ** 20).toFixed(1); };
      const ready = (url) => page.waitForFunction((url) => window.AvatarController?.ready === true && window.AvatarController.getSnapshot().modelUrl === url, url, { timeout: 180000 });
      const state = async (label) => {
        const value = await page.evaluate(() => {
          const audit = window.__lifecycle, canvases = [...document.querySelectorAll('canvas')];
          return {
            canvases: canvases.length,
            contextsCreated: audit.contexts.length,
            contextsLive: audit.contexts.filter((entry) => !entry.context.isContextLost()).length,
            lostEvents: audit.lostEvents.map(({ index, forced, connected }) => ({ index, forced, connected })),
            unexpectedContextLoss: audit.lostEvents.filter((event) => !event.forced).length,
            loseContextCalls: audit.loseContextCalls, glDeletes: audit.deletes, rendererDisposeObserved: audit.creationErrorListenersRemoved,
            rafPending: audit.rafPending.size, resizeObservers: audit.observers.size,
            koiMessages: [...audit.koiMessages], readyEvents: audit.readyEvents, notReadyEvents: audit.notReadyEvents, mediaCalls: audit.mediaCalls,
            canvas: canvases[0] ? { width: canvases[0].width, height: canvases[0].height, clientWidth: canvases[0].clientWidth, clientHeight: canvases[0].clientHeight } : null,
            modelUrl: window.AvatarController?.getSnapshot().modelUrl ?? null, ready: window.AvatarController?.ready ?? false,
          };
        });
        value.jsHeapUsedMb = await heapMb();
        steps.push({ step: label, ...value });
        return value;
      };
      // Dev React StrictMode mounts, cleans up and remounts effects, so a fresh document may create a second
      // context. Every extra context must have been force-lost by our cleanup and detached; exactly one may remain.
      const unreleased = (value) => value.contextsCreated - value.lostEvents.filter((event) => event.forced && !event.connected).length;
      const expectSteady = (value, label) => {
        if (unreleased(value) !== 1) fail(`${model} ${label}: ${unreleased(value)} unreleased WebGL contexts`);
        if (value.canvases !== 1) fail(`${model} ${label}: ${value.canvases} canvases`);
        if (value.contextsLive !== 1) fail(`${model} ${label}: ${value.contextsLive} live WebGL contexts`);
        if (value.rafPending !== 1) fail(`${model} ${label}: ${value.rafPending} pending animation frames`);
        if (value.resizeObservers !== 1) fail(`${model} ${label}: ${value.resizeObservers} ResizeObservers`);
        if (value.unexpectedContextLoss) fail(`${model} ${label}: unexpected WebGL context loss`);
      };
      const steps = [];
      const timings = {};

      let t = Date.now();
      await page.goto(`${ORIGIN}/avatar-host?model=${model}`, { waitUntil: 'domcontentloaded' });
      await ready(modelUrl); timings.loadMs = Date.now() - t;
      const loaded = await state('load');
      expectSteady(loaded, 'load');
      if (JSON.stringify(loaded.koiMessages) !== '["AVATAR_READY"]') fail(`${model} load: KoiBridge messages ${loaded.koiMessages}`);

      t = Date.now();
      await page.reload({ waitUntil: 'domcontentloaded' });
      await ready(modelUrl); timings.reloadMs = Date.now() - t;
      const reloaded = await state('reload');
      expectSteady(reloaded, 'reload');
      if (reloaded.contextsCreated > 2) fail(`${model} reload: ${reloaded.contextsCreated} contexts in the fresh document`);
      result.models[model] = { modelUrl, steps, timings, strictModeExtraContexts: reloaded.contextsCreated - 1 };
      if (JSON.stringify(reloaded.koiMessages) !== '["AVATAR_READY"]') fail(`${model} reload: KoiBridge messages ${reloaded.koiMessages}`);

      timings.resize = [];
      for (const size of SIZES) {
        t = Date.now();
        await page.setViewportSize(size);
        const expected = { width: Math.floor(size.width * Math.min(1, HOST_MAX_PIXEL_RATIO)), height: Math.floor(size.height * Math.min(1, HOST_MAX_PIXEL_RATIO)) };
        try {
          await page.waitForFunction((expected) => { const canvas = document.querySelector('canvas'); return canvas && canvas.width === expected.width && canvas.height === expected.height; }, expected, { timeout: 10000 });
        } catch { fail(`${model} resize ${size.width}x${size.height}: drawing buffer did not reach ${expected.width}x${expected.height}`); }
        await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        timings.resize.push({ ...size, ms: Date.now() - t });
        const resized = await state(`resize ${size.width}x${size.height}`);
        expectSteady(resized, `resize ${size.width}x${size.height}`);
        if (resized.canvas.clientWidth !== size.width || resized.canvas.clientHeight !== size.height) fail(`${model} resize ${size.width}x${size.height}: canvas client size ${resized.canvas.clientWidth}x${resized.canvas.clientHeight}`);
        if (resized.contextsCreated !== reloaded.contextsCreated) fail(`${model} resize: resizing created a new WebGL context`);
        await page.screenshot({ path: path.join(OUT, `lifecycle-${model}-${size.width}x${size.height}.png`) });
      }
      await page.setViewportSize(SIZES[0]);

      // Client-side navigation keeps the document: the renderer effect's cleanup must release the old model's GPU resources.
      const hasRouter = await page.evaluate(() => typeof window.next?.router?.push === 'function');
      result.models[model].clientNavigation = hasRouter ? 'window.next.router.push (Next dev debug handle)' : 'unavailable';
      if (hasRouter) {
        for (const [target, url, label] of [[other, MODELS[other], `switch away to ${other}`], [model, modelUrl, `switch back to ${model}`]]) {
          const before = await state(`before ${label}`);
          t = Date.now();
          await page.evaluate((target) => window.next.router.push(`/avatar-host?model=${target}`), target);
          await ready(url);
          timings[label] = Date.now() - t;
          const after = await state(label);
          expectSteady(after, label);
          if (after.loseContextCalls !== before.loseContextCalls + 1) fail(`${model} ${label}: forceContextLoss calls ${before.loseContextCalls} -> ${after.loseContextCalls}`);
          if (after.rendererDisposeObserved <= before.rendererDisposeObserved) fail(`${model} ${label}: WebGLRenderer.dispose not observed`);
          if (after.glDeletes <= before.glDeletes) fail(`${model} ${label}: no GPU resource deletions observed`);
          if (after.contextsCreated !== before.contextsCreated + 1) fail(`${model} ${label}: expected exactly one new context`);
        }
      } else fail(`${model}: client-side router handle unavailable; teardown not exercised`);

      t = Date.now();
      await page.goto('about:blank');
      await page.goto(`${ORIGIN}/avatar-host?model=${model}`, { waitUntil: 'domcontentloaded' });
      await ready(modelUrl); timings.fullNavigationBackMs = Date.now() - t;
      const back = await state('full navigation away (about:blank) and back');
      expectSteady(back, 'full navigation back');
      if (back.contextsCreated > 2) fail(`${model} full navigation back: ${back.contextsCreated} contexts`);

      result.models[model].pageErrors = pageErrors;
      result.models[model].consoleErrors = consoleErrors;
      if (pageErrors.length) fail(`${model}: page errors ${pageErrors.join(' | ')}`);
      if (consoleErrors.length) fail(`${model}: console errors ${consoleErrors.join(' | ')}`);
      if (steps.some((step) => step.mediaCalls)) fail(`${model}: media permission requested`);
      console.log(`${model}: load ${timings.loadMs} ms, reload ${timings.reloadMs} ms`);
      await page.close();
    }
    if (result.blockedRequests.length) fail(`non-local requests attempted: ${result.blockedRequests.join(', ')}`);
    await context.close();
  } finally {
    await browser.close();
  }
  result.totalMs = Date.now() - startedAt;
  result.failures = failures;
  result.passed = failures.length === 0;
  await fs.writeFile(path.join(OUT, 'lifecycle-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify({ passed: result.passed, failures, totalMs: result.totalMs }, null, 2));
  if (!result.passed) process.exitCode = 1;
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
