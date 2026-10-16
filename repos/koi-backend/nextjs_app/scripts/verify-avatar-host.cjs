const assert = require('node:assert/strict');
const { chromium } = require('playwright');

const origin = process.env.KOI_AVATAR_HOST_URL || 'http://127.0.0.1:3010/avatar-host';

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.KOI_AVATAR_BROWSER || undefined,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  try {
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();
    const pageErrors = [];
    const consoleErrors = [];
    const requests = [];
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('request', (request) => requests.push(request.url()));
    await page.addInitScript(() => {
      window.__koiMessages = [];
      window.KoiBridge = { postMessage: (message) => window.__koiMessages.push(message) };
      window.__avatarFrames = new Set();
      const request = window.requestAnimationFrame.bind(window);
      const cancel = window.cancelAnimationFrame.bind(window);
      window.requestAnimationFrame = (callback) => {
        let id;
        id = request((timestamp) => { window.__avatarFrames.delete(id); callback(timestamp); });
        window.__avatarFrames.add(id);
        return id;
      };
      window.cancelAnimationFrame = (id) => { window.__avatarFrames.delete(id); cancel(id); };
    });

    await page.goto(origin, { waitUntil: 'domcontentloaded' });
    try {
      await page.waitForFunction(() => window.AvatarController?.lifecycle === 'not-ready', null, { timeout: 60000 });
    } catch {
      const diagnostic = await page.evaluate(() => ({
        title: document.title,
        body: document.body.innerText,
        controller: window.AvatarController?.lifecycle ?? null,
        avatarState: document.querySelector('[data-avatar-state]')?.getAttribute('data-avatar-state') ?? null,
        canvas: !!document.querySelector('canvas'),
      }));
      throw new Error(`Avatar host did not register its controller: ${JSON.stringify({ diagnostic, pageErrors, consoleErrors, requests })}`);
    }
    await page.evaluate(() => {
      window.AvatarController.setEmotion('joy', 0.7);
      window.AvatarController.setConversationState('listening');
    });
    await page.waitForFunction(() => window.AvatarController?.ready === true, null, { timeout: 120000 });
    await page.waitForTimeout(450);
    const desktop = await page.evaluate(() => ({
      ready: window.AvatarController.ready,
      modelUrl: window.AvatarController.getSnapshot().modelUrl,
      emotion: window.AvatarController.getSnapshot().animation.emotion,
      emotionWeight: window.AvatarController.getSnapshot().animation.weights.happy,
      hasCanvas: !!document.querySelector('canvas'),
      bridgeMessages: [...window.__koiMessages],
      pendingAvatarFrames: window.__avatarFrames.size,
    }));
    assert.equal(desktop.ready, true);
    assert.equal(desktop.modelUrl, '/models/koi-male.vrm');
    assert.equal(desktop.emotion, 'joy');
    assert(desktop.emotionWeight > 0);
    assert(desktop.hasCanvas);
    assert.equal(desktop.pendingAvatarFrames, 1, 'renderer must own one animation loop');
    assert.deepEqual(desktop.bridgeMessages, ['AVATAR_READY']);

    await page.getByLabel('Companion model').selectOption('female');
    await page.waitForFunction(() => window.AvatarController?.ready
      && window.AvatarController.getSnapshot().modelUrl === '/models/koi-female.vrm', null, { timeout: 120000 });
    assert.deepEqual(await page.evaluate(() => window.__koiMessages), ['AVATAR_READY', 'AVATAR_READY']);
    assert.equal(await page.evaluate(() => window.__avatarFrames.size), 1, 'model switching must not duplicate the render loop');

    await page.setViewportSize({ width: 320, height: 280 });
    await page.waitForTimeout(250);
    const mobile = await page.evaluate(() => ({
      width: document.documentElement.scrollWidth,
      viewportWidth: innerWidth,
      height: document.documentElement.scrollHeight,
      viewportHeight: innerHeight,
      canvas: !!document.querySelector('canvas'),
      stageHeight: document.querySelector('[aria-label="KOI companion avatar"]').getBoundingClientRect().height,
    }));
    assert(mobile.canvas && mobile.stageHeight > 0);
    assert(mobile.width <= mobile.viewportWidth, 'host must not overflow horizontally');
    assert(mobile.height <= mobile.viewportHeight, 'host must fit short mobile viewports');

    const serviceRequests = requests.filter((url) => /firebase|\/api\/|voice-api|:3002/.test(url));
    assert.deepEqual(pageErrors, []);
    assert.deepEqual(serviceRequests, []);
    console.log(JSON.stringify({ passed: true, desktop, mobile, pageErrors, serviceRequests }, null, 2));
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
